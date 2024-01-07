//---------------------------------------------------------------------------------------------
// *Actions Contract*
// This contract handles all the actions that can be performed by the user
//---------------------------------------------------------------------------------------------

#[dojo::contract]
mod actions {
    use core::clone::Clone;
    use core::array::SpanTrait;
    use core::option::OptionTrait;
    use core::array::ArrayTrait;
    use core::traits::Into;
    use starknet::{ContractAddress, get_caller_address, get_contract_address};
    use debug::PrintTrait;
    use castle_hexapolis::interface::IActions;
    use castle_hexapolis::queue::{Queue, QueueTrait};
    use core::dict::Felt252Dict;
    // import models
    use castle_hexapolis::models::{
        GAME_DATA_KEY, TileType, Tile, ContractsRegistry, GameData, Score, RemainingMoves,
        PlayerAddress, PlayerId, Direction
    };
    // import erc20trait
    use castle_hexapolis::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};

    // import config
    use castle_hexapolis::config::{GRID_SIZE, REMAINING_MOVES_DEFAULT};

    // import integer
    use integer::{u128s_from_felt252, U128sFromFelt252Result, u128_safe_divmod};

    // resource of world
    const DOJO_WORLD_RESOURCE: felt252 = 0;

    // contract storage
    struct Storage {
        erc20_contract_address: ContractAddress,
        has_claimed: LegacyMap::<ContractAddress, bool>,
    }

    // ---------------------------------------------------------------------------------------------
    // ---------------------------------------------------------------------------------------------
    // --------- EXTERNALS -------------------------------------------------------------------------
    // These functions are called by the user and are exposed to the public
    // ---------------------------------------------------------------------------------------------

    // impl: implement functions specified in trait
    #[external(v0)]
    impl ActionsImpl of IActions<ContractState> {
        fn set_lords_address(ref self: ContractState, lords_address: ContractAddress) {
            self.erc20_contract_address.write(lords_address);
            let world = self.world_dispatcher.read();
            let mut contracts: ContractsRegistry = get!(
                world, 'castle_hexapolis', ContractsRegistry
            );
            contracts.lords_address = lords_address.into();
            set!(world, (contracts));
        }
        fn faucet(ref self: ContractState, amount: u128) {
            let world = self.world_dispatcher.read();
            let from: ContractAddress = get_contract_address();
            let to: ContractAddress = get_caller_address();
            let has_claimed = self.has_claimed.read(to);
            assert(amount >= 5, 'Amount exceeded');
            assert(has_claimed == false, 'Has already claimed');
            let lordsDispatcher = IERC20Dispatcher {
                contract_address: self.erc20_contract_address.read()
            };
            lordsDispatcher.transfer_from(from, to, amount);
        }
        fn spawn(self: @ContractState, amount: u128) {
            let world = self.world_dispatcher.read();
            let player_address = get_caller_address();

            let mut game_data = get!(world, GAME_DATA_KEY, (GameData));

            // increment player count
            game_data.number_of_players += 1;

            // NOTE: save game_data model with the set! macro
            set!(world, (game_data));

            let player_id = assign_player_id(world, game_data.number_of_players, player_address);

            //Minimum amount should be 5
            assert(amount >= 5, 'Entry cost is minimum 5');

            // Transfering the token to the game contract
            let lordsDispatcher = IERC20Dispatcher {
                contract_address: self.erc20_contract_address.read()
            };
            let from: ContractAddress = get_caller_address();
            let to: ContractAddress = get_contract_address();
            let finalAmount: u128 = amount;
            lordsDispatcher.transfer_from(from, to, finalAmount);

            //getting token_locked

            assign_score(world, player_id, 0, amount, 0);
            assign_remaining_moves(world, player_id, REMAINING_MOVES_DEFAULT);

            place_default_tiles(world, player_id);
        }

        fn place_tile(self: @ContractState, tiles: Span<(u8, u8, TileType)>) {
            let world = self.world_dispatcher.read();
            let player_address = get_caller_address();
            let lordsDispatcher = IERC20Dispatcher {
                contract_address: self.erc20_contract_address.read()
            };

            let from: ContractAddress = get_contract_address();
            // Get player ID
            let player_id = get!(world, player_address, (PlayerId)).player_id;

            assert(player_id > 0, 'player does not exist');

            let mut remaining_moves = get!(world, player_id, (RemainingMoves)).moves;
            assert(remaining_moves > 0, 'no moves left');
            assert(tiles.len() == 3, 'only three tiles can be placed');

            let tile1 = *tiles.at(0);
            let tile2 = *tiles.at(1);
            let tile3 = *tiles.at(2);
            let (row_1, col_1, tile_type_1) = tile1;
            let (row_2, col_2, tile_type_2) = tile2;
            let (row_3, col_3, tile_type_3) = tile3;
            'tiles coords'.print();
            row_1.print();
            col_1.print();
            row_2.print();
            col_2.print();
            row_3.print();
            col_3.print();
            '------'.print();
            // NOTE: We can refactor this code by using loop. for now lets keep it simple though.

            assert(!(row_1 == row_2 && col_1 == col_2), 'duplicate tiles not allowed');
            assert(!((row_2 == row_3) && (col_2 == col_3)), 'duplicate tiles not allowed');
            assert(!((row_1 == row_3) && (col_1 == col_3)), 'duplicate tiles not allowed');

            assert(validate_tile_type(tile_type_1), 'invalid tile1 type');
            assert(validate_tile_type(tile_type_2), 'invalid tile2 type');
            assert(validate_tile_type(tile_type_3), 'invalid tile3 type');

            // check if tile coordinates are within map boundry
            assert(is_tile_in_boundry(row_1, col_1), 'invalid tile1 position');
            assert(is_tile_in_boundry(row_2, col_2), 'invalid tile2 position');
            assert(is_tile_in_boundry(row_3, col_3), 'invalid tile3 position');

            // check if tile is already occupied
            assert(!is_tile_occupied(world, row_1, col_1, player_id), 'tile1 is already occupied');
            assert(!is_tile_occupied(world, row_2, col_2, player_id), 'tile2 is already occupied');
            assert(!is_tile_occupied(world, row_3, col_3, player_id), 'tile3 is already occupied');

            // check if neighbour tile is settled
            let mut new_tile_1 = Tile {
                row: row_1,
                col: col_1,
                player_id,
                tile_type: tile_type_1,
                counted: false,
                is_hill: false
            };

            let mut new_tile_2 = Tile {
                row: row_2,
                col: col_2,
                player_id,
                tile_type: tile_type_2,
                counted: false,
                is_hill: false
            };

            let mut new_tile_3 = Tile {
                row: row_3,
                col: col_3,
                player_id,
                tile_type: tile_type_3,
                counted: false,
                is_hill: false
            };

            // Check if at least one tile is close to a settled tile.

            let is_settled_1 = is_neighbor_settled(world, new_tile_1);

            let is_settled_2 = is_neighbor_settled(world, new_tile_2);

            let is_settled_3 = is_neighbor_settled(world, new_tile_3);

            assert(is_settled_1 || is_settled_2 || is_settled_3, 'neighbour is not settled');

            let mut player_score = get!(world, player_id, (Score)).score;
            let mut remaining_moves = get!(world, player_id, (RemainingMoves)).moves;

            // Set all three tiles
            set!(world, (new_tile_1));
            set!(world, (new_tile_2));
            set!(world, (new_tile_3));

            player_score += calculate_score_for_tile(world, new_tile_1);
            player_score += calculate_score_for_tile(world, new_tile_2);
            player_score += calculate_score_for_tile(world, new_tile_3);

            remaining_moves -= 1;

            let token_locked = get!(world, player_id, (Score)).token_locked;

            set_player_score_and_remaining_moves(
                world, player_id, player_score, remaining_moves, token_locked, 0
            );

            let mut remaining_moves = get!(world, player_id, (RemainingMoves)).moves;
            let total_score = get!(world, player_id, (Score)).score;

            if (remaining_moves <= 1) {
                if (total_score >= 60) {
                    lordsDispatcher.transfer_from(from, player_address, 1);
                    set_player_score_and_remaining_moves(
                        world, player_id, player_score, remaining_moves, token_locked, 1
                    );
                } else if (total_score >= 85) {
                    lordsDispatcher.transfer_from(from, player_address, 2);
                    set_player_score_and_remaining_moves(
                        world, player_id, player_score, remaining_moves, token_locked, 2
                    );
                } else if (total_score >= 100) {
                    lordsDispatcher.transfer_from(from, player_address, 4);
                    set_player_score_and_remaining_moves(
                        world, player_id, player_score, remaining_moves, token_locked, 4
                    );
                }
            }
        }

        // ----- ADMIN FUNCTIONS -----
        // These functions are only callable by the owner of the world
        fn cleanup(self: @ContractState) {}
    }

    // ---------------------------------------------------------------------------------------------
    // ---------------------------------------------------------------------------------------------
    // --------- INTERNALS -------------------------------------------------------------------------
    // These functions are called by the contract and are not exposed to the public
    // ---------------------------------------------------------------------------------------------

    // @dev: 
    // 1. Assigns player id
    // 2. Sets player address
    // 3. Sets player id
    fn assign_player_id(
        world: IWorldDispatcher, num_players: u128, player_address: ContractAddress
    ) -> u128 {
        let player_id: u128 = num_players;
        set!(
            world,
            (PlayerId { player_address, player_id }, PlayerAddress { player_address, player_id })
        );
        player_id
    }

    fn assign_score(
        world: IWorldDispatcher, player_id: u128, score: u8, token_locked: u128, rewards: u128
    ) {
        set!(world, (Score { player_id, score, token_locked, rewards }))
    }

    fn assign_remaining_moves(world: IWorldDispatcher, player_id: u128, moves: u8) {
        set!(world, (RemainingMoves { player_id, moves }));
    }


    // @dev: Returns player id at tile
    // fn player_at_tile(world: IWorldDispatcher, x: u8, y: u8) -> u128 {
    //     get!(world, (x, y), (Tile)).player_id
    // }

    // @dev: Sets player score and remaining moves
    fn set_player_score_and_remaining_moves(
        world: IWorldDispatcher,
        player_id: u128,
        score: u8,
        moves: u8,
        token_locked: u128,
        rewards: u128
    ) {
        set!(
            world,
            (Score { player_id, score, token_locked, rewards }, RemainingMoves { player_id, moves })
        );
    }


    fn is_tile_in_boundry(row: u8, col: u8) -> bool {
        (row >= 0 && row <= 2 * GRID_SIZE + 1) && (col >= 0 && col <= 2 * GRID_SIZE + 1)
    }

    fn is_tile_occupied(world: IWorldDispatcher, row: u8, col: u8, player_id: u128) -> bool {
        let tile = get!(world, (row, col, player_id), (Tile));

        tile.tile_type != TileType::Empty
    }

    fn neighbor(world: IWorldDispatcher, tile: Tile, direction: Direction) -> Tile {
        match direction {
            Direction::East(()) => get!(world, (tile.row, tile.col + 1, tile.player_id), (Tile)),
            Direction::NorthEast(()) => get!(
                world, (tile.row - 1, tile.col + 1, tile.player_id), (Tile)
            ),
            Direction::NorthWest(()) => get!(
                world, (tile.row - 1, tile.col, tile.player_id), (Tile)
            ),
            Direction::West(()) => get!(world, (tile.row, tile.col - 1, tile.player_id), (Tile)),
            Direction::SouthWest(()) => get!(
                world, (tile.row + 1, tile.col, tile.player_id), (Tile)
            ),
            Direction::SouthEast(()) => get!(
                world, (tile.row + 1, tile.col + 1, tile.player_id), (Tile)
            ),
        }
    }

    fn get_neighbors(world: IWorldDispatcher, tile: Tile) -> Array<Tile> {
        let mut result = ArrayTrait::<Tile>::new();

        let mut all_neighbours = array![
            neighbor(world, tile, Direction::East(())),
            neighbor(world, tile, Direction::NorthEast(())),
            neighbor(world, tile, Direction::NorthWest(())),
            neighbor(world, tile, Direction::West(())),
            neighbor(world, tile, Direction::SouthWest(())),
            neighbor(world, tile, Direction::SouthEast(()))
        ];

        loop {
            if (all_neighbours.len() == 0) {
                break;
            }

            let current = all_neighbours.pop_front().unwrap();
            if (is_tile_in_boundry(current.row, current.col)) {
                result.append(current);
            }
        };
        // 'neighbours len'.print();
        // result.len().print();

        result
    }


    fn is_neighbor(world: IWorldDispatcher, tile: Tile, other: Tile) -> bool {
        let mut neighbors = get_neighbors(world, tile);
        loop {
            if (neighbors.len() == 0) {
                break false;
            }

            let curent_neighbor = neighbors.pop_front().unwrap();

            if (curent_neighbor.col == other.col) {
                if (curent_neighbor.row == other.row) {
                    break true;
                }
            };
        }
    }

    fn is_neighbor_settled(world: IWorldDispatcher, tile: Tile) -> bool {
        let mut neighbors = get_neighbors(world, tile);
        // 'neightbour len'.print();
        // neighbors.len().print();
        loop {
            if (neighbors.len() == 0) {
                break false;
            }
            let current_neighbour = neighbors.pop_front().unwrap();
            // 'neightbour x'.print();
            // current_neighbour.row.print();
            // 'neighbour y'.print();
            // current_neighbour.col.print();
            if ((current_neighbour.tile_type != TileType::Empty)
                && current_neighbour.tile_type != TileType::CityGate) {
                break true;
            }
        }
    }

    fn place_default_tiles(world: IWorldDispatcher, player_id: u128) {
        set!(
            world,
            (Tile {
                player_id,
                row: GRID_SIZE,
                col: GRID_SIZE,
                tile_type: TileType::Castle,
                counted: false,
                is_hill: false
            })
        );
        set!(
            world,
            (Tile {
                player_id,
                row: 0,
                col: GRID_SIZE,
                tile_type: TileType::CityGate,
                counted: false,
                is_hill: false
            })
        );
        set!(
            world,
            (Tile {
                player_id,
                row: 0,
                col: GRID_SIZE * 2,
                tile_type: TileType::CityGate,
                counted: false,
                is_hill: false
            })
        );
        set!(
            world,
            (Tile {
                player_id,
                row: GRID_SIZE,
                col: 0,
                tile_type: TileType::CityGate,
                counted: false,
                is_hill: false
            })
        );
        set!(
            world,
            (Tile {
                player_id,
                row: GRID_SIZE,
                col: GRID_SIZE * 2,
                tile_type: TileType::CityGate,
                counted: false,
                is_hill: false
            })
        );
        set!(
            world,
            (Tile {
                player_id,
                row: GRID_SIZE * 2,
                col: 0,
                tile_type: TileType::CityGate,
                counted: false,
                is_hill: false
            })
        );
        set!(
            world,
            (Tile {
                player_id,
                row: GRID_SIZE * 2,
                col: GRID_SIZE,
                tile_type: TileType::CityGate,
                counted: false,
                is_hill: false
            })
        );
    }

    fn get_connected(world: IWorldDispatcher, tile: Tile) -> Array<Tile> {
        let mut connected_tiles: Array<Tile> = ArrayTrait::new();
        let mut visited_map: Felt252Dict<bool> = Default::default();
        let mut queue = QueueTrait::<Tile>::new();
        queue.enqueue(tile);

        loop {
            if (queue.len() == 0) {
                break;
            }
            let t = queue.dequeue().unwrap();
            let tilePos: felt252 = (t.row + t.col).into();
            if (visited_map.get(tilePos) != true) {
                connected_tiles.append(t);
            }
            visited_map.insert(tilePos, true);

            let mut neighbors = get_neighbors(world, t);
            loop {
                if (neighbors.len() == 0) {
                    break;
                }
                let current_neighbour = neighbors.pop_front().unwrap();
                let current_neighbour_pos: felt252 = (current_neighbour.row + current_neighbour.col)
                    .into();

                if (visited_map.get(current_neighbour_pos) != true
                    && (current_neighbour.tile_type == t.tile_type
                        || (t.tile_type == TileType::Road
                            && current_neighbour.tile_type == TileType::CityGate))) {
                    queue.enqueue(current_neighbour);
                }
            };
        };
        connected_tiles
    }

    impl QueueTileDrop of Drop<Queue<Tile>>;

    fn calculate_score_for_tile(world: IWorldDispatcher, tile: Tile) -> u8 {
        let mut score = 0;
        if (tile.counted) {
            return score;
        }
        if (tile.tile_type == TileType::WatchTower) {
            let mut isolated = true;
            let mut neighbors = get_neighbors(world, tile);

            loop {
                if (neighbors.len() == 0) {
                    break;
                }

                let current_neighbour = neighbors.pop_front().unwrap();
                if (current_neighbour.tile_type == TileType::WatchTower) {
                    isolated = false;
                    if (current_neighbour.counted) {
                        set!(
                            world,
                            Tile {
                                row: current_neighbour.row,
                                col: current_neighbour.col,
                                player_id: current_neighbour.player_id,
                                is_hill: current_neighbour.is_hill,
                                tile_type: current_neighbour.tile_type,
                                counted: false
                            }
                        );
                        if (current_neighbour.is_hill) {
                            score -= 3;
                        } else {
                            score -= 1;
                        }
                    }
                }
            };

            if (isolated) {
                if (tile.is_hill) {
                    score += 3;
                } else {
                    score += 1;
                }
            }

            return score;
        } else if (tile.tile_type == TileType::Park) {
            let mut group = get_connected(world, tile);
            let mut unaccounted_trees: Array<Tile> = ArrayTrait::new();
            // unaccounted_trees.len().print();
            loop {
                if (group.len() == 0) {
                    break;
                }
                let g = group.pop_front().unwrap();
                if (g.counted == false) {
                    unaccounted_trees.append(g);
                }
            };

            loop {
                if (unaccounted_trees.len() < 3) {
                    break;
                }
                let first_tree = unaccounted_trees.pop_front().unwrap();
                let second_tree = unaccounted_trees.pop_front().unwrap();
                let third_tree = unaccounted_trees.pop_front().unwrap();
                set!(
                    world,
                    (
                        Tile {
                            row: first_tree.row,
                            col: first_tree.col,
                            player_id: first_tree.player_id,
                            is_hill: first_tree.is_hill,
                            tile_type: first_tree.tile_type,
                            counted: true
                        },
                        Tile {
                            row: second_tree.row,
                            col: second_tree.col,
                            player_id: second_tree.player_id,
                            is_hill: second_tree.is_hill,
                            tile_type: second_tree.tile_type,
                            counted: true
                        },
                        Tile {
                            row: third_tree.row,
                            col: third_tree.col,
                            player_id: third_tree.player_id,
                            is_hill: third_tree.is_hill,
                            tile_type: third_tree.tile_type,
                            counted: true
                        }
                    )
                );
                score += 5;
            }
        } else if (tile.tile_type == TileType::Road) {
            let mut neighbours = get_neighbors(world, tile);
            loop {
                if (neighbours.len() == 0) {
                    break;
                }
                let current_neighbour = neighbours.pop_front().unwrap();
                if (current_neighbour.tile_type == TileType::Castle && !tile.counted) {
                    score += 1;
                    set!(
                        world,
                        (Tile {
                            row: tile.row,
                            col: tile.col,
                            player_id: tile.player_id,
                            is_hill: tile.is_hill,
                            tile_type: tile.tile_type,
                            counted: true
                        })
                    );
                }
            };
            let mut group = get_connected(world, tile);
            let mut group_copy = group.clone();
            let mut connected_to_castle = false;
            let mut i = group.len() - 1;
            loop {
                if (group_copy.len() == 0) {
                    break;
                }
                let t = group_copy.pop_front().unwrap();
                if (t.tile_type == TileType::Road && t.counted) {
                    connected_to_castle = true;
                    break;
                }
            };
            // 'connected to castle'.print();
            // connected_to_castle.print();
            if (connected_to_castle) {
                loop {
                    if (group.len() == 0) {
                        break;
                    }

                    let current_neighbour = group.pop_front().unwrap();
                    if (!current_neighbour.counted) {
                        if (current_neighbour.tile_type == TileType::CityGate) {
                            score += 3;
                        } else {
                            score += 1;
                        }
                        set!(
                            world,
                            Tile {
                                row: current_neighbour.row,
                                col: current_neighbour.col,
                                player_id: current_neighbour.player_id,
                                is_hill: current_neighbour.is_hill,
                                tile_type: current_neighbour.tile_type,
                                counted: true
                            }
                        );
                    }
                }
            }
        }
        'final score'.print();
        score.print();
        score
    }

    fn validate_tile_type(tile_type: TileType) -> bool {
        tile_type == TileType::Park
            || tile_type == TileType::Road
            || tile_type == TileType::WatchTower
    }
}
