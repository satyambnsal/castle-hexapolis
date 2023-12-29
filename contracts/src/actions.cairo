//---------------------------------------------------------------------------------------------
// *Actions Contract*
// This contract handles all the actions that can be performed by the user
// Typically you group functions that require similar authentication into a single contract
//---------------------------------------------------------------------------------------------

#[dojo::contract]
mod actions {
    use core::option::OptionTrait;
    use core::array::ArrayTrait;
    use core::traits::Into;
    use starknet::{ContractAddress, get_caller_address};
    use debug::PrintTrait;
    use castle_hexapolis::interface::IActions;
    use starknet::{get_block_timestamp};
    use poseidon::PoseidonTrait;
    use hash::HashStateTrait;


    // use integer::{u128s_from_felt252, U128sFromFelt252Result};

    // import models
    use castle_hexapolis::models::{
        GAME_DATA_KEY, TileType, Tile, GameData, Score, RemainingMoves, PlayerAddress, PlayerID,
        Direction
    };

    // import config
    use castle_hexapolis::config::{GRID_SIZE, REMAINING_MOVES_DEFAULT, MIN_TILE_VAL, MAX_TILE_VAL};

    // import integer
    use integer::{u128s_from_felt252, U128sFromFelt252Result, u128_safe_divmod, u128_to_felt252};

    // resource of world
    const DOJO_WORLD_RESOURCE: felt252 = 0;

    // ---------------------------------------------------------------------------------------------
    // ---------------------------------------------------------------------------------------------
    // --------- EXTERNALS -------------------------------------------------------------------------
    // These functions are called by the user and are exposed to the public
    // ---------------------------------------------------------------------------------------------

    // impl: implement functions specified in trait
    #[external(v0)]
    impl ActionsImpl of IActions<ContractState> {
        fn spawn(self: @ContractState) {
            let world = self.world_dispatcher.read();

            // player address
            let player_address = get_caller_address();

            // game data
            let mut game_data = get!(world, GAME_DATA_KEY, (GameData));

            // increment player count
            game_data.number_of_players += 1;

            // NOTE: save game_data model with the set! macro
            set!(world, (game_data));

            let player_id = assign_player_id(world, game_data.number_of_players, player_address);

            assign_score(world, player_id, 0);
            assign_remaining_moves(world, player_id, REMAINING_MOVES_DEFAULT);

            // set default tiles for game.
            set!(
                world,
                (Tile { player_id, row: GRID_SIZE, col: GRID_SIZE, tile_type: TileType::Center })
            )
        }

        fn place_tile(self: @ContractState, tile1: (u8, u8, TileType)) {
            let world = self.world_dispatcher.read();

            let player_address = get_caller_address();
            // Get player ID
            let player_id = get!(world, player_address, (PlayerID)).player_id;

            let mut remaining_moves = get!(world, player_id, (RemainingMoves)).moves;
            assert(remaining_moves > 0, 'no moves left');
            let (row_1, col_1, tile_type_1) = tile1;

            // tile type validation
            assert(
                tile_type_1 == TileType::Grass
                    || tile_type_1 == TileType::Street
                    || tile_type_1 == TileType::WindMill,
                'invalid tile type'
            );

            // check if tile coordinates are within map boundry
            assert(is_tile_in_boundry(row_1, col_1), 'invalid tile position');

            // check if tile is already occupied
            assert(!is_tile_occupied(world, row_1, col_1, player_id), 'tile is already occupied');

            // check if neighbour tile is settled
            let mut new_tile = Tile { row: row_1, col: col_1, player_id, tile_type: tile_type_1, };
            assert(is_neighbor_settled(world, new_tile), 'neighbour is not settled');

            let mut player_score = get!(world, player_id, (Score)).score;
            let mut remaining_moves = get!(world, player_id, (RemainingMoves)).moves;

            set!(world, (new_tile));

            player_score += scoring()
            remaining_moves -= 1;

            scoring()
        }


        // ----- ADMIN FUNCTIONS -----
        // These functions are only callable by the owner of the world
        fn cleanup(self: @ContractState) {}

        fn produce_random_tiletype(self: @ContractState) -> TileType {
            let seed: u64 = get_block_timestamp();
            let mut seed_u256: u256 = seed.into();

            let val: u128 = randomize_range_usize(ref seed_u256, MIN_TILE_VAL, MAX_TILE_VAL);

            let val1: felt252 = u128_to_felt252(val);

            if (val1 == 1) {
                return TileType::WindMill(());
            } else if (val1 == 2) {
                return TileType::Grass(());
            } else if (val1 == 3) {
                return TileType::Street(());
            } else if (val1 == 4) {
                return TileType::Center(());
            } else {
                return TileType::Port(());
            }
        }
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
            (PlayerID { player_address, player_id }, PlayerAddress { player_address, player_id })
        );
        player_id
    }

    fn scoring(world: IWorldDispatcher, tile1: Tile, tile2: Tile) -> u8 {
        let flag1: bool = is_close(tile1, tile2);
        let flag2: bool = is_tile_occupied(world, tile2.row, tile2.col, tile2.player_id);
        let tile1_type_value: u8 = tile1.tile_type.into();
        let tile2_type_value: u8 = tile2.tile_type.into();
        if (flag1 && flag2) {
            if (tile1_type_value == 3 && tile2_type_value == 4)
                || (tile1_type_value == 4 && tile2_type_value == 3) {
                return 1;
            } // Street connected to Street
            else if tile1_type_value == 3 && tile2_type_value == 3 {
                return 3;
            } // Windturbine near non-Windturbine
            else if tile1_type_value == 1 && tile2_type_value != 1 {
                return 1;
            } // Windturbine near Windturbine
            else if tile1_type_value == 1 && tile2_type_value == 1 {
                return 3;
            } // Park near Park
            else if tile1_type_value == 2 && tile2_type_value == 2 {
                return 5;
            } // Park near non-Park
            else if tile1_type_value == 2 {
                return 1;
            }
        }
        0
    }


    fn assign_score(world: IWorldDispatcher, player_id: u128, score: u8) {
        set!(world, (Score { player_id, score }))
    }

    fn assign_remaining_moves(world: IWorldDispatcher, player_id: u128, moves: u8) {
        set!(world, (RemainingMoves { player_id, moves }));
    }

    // @dev: Returns player id at tile
    // fn player_at_tile(world: IWorldDispatcher, x: u8, y: u8) -> u128 {
    //     get!(world, (x, y), (Tile)).player_id
    // }

    // @dev: Sets player score and remaining moves
    fn player_score_and_remaining_moves(
        world: IWorldDispatcher, player_id: u128, score: u8, moves: u8
    ) {
        set!(world, (Score { player_id, score }, RemainingMoves { player_id, moves }));
    }

    fn is_tile_in_boundry(row: u8, col: u8) -> bool {
        (row >= 0 && row <= 2 * GRID_SIZE + 1) && (col >= 0 && col <= 2 * GRID_SIZE + 1)
    }

    fn is_tile_occupied(world: IWorldDispatcher, row: u8, col: u8, player_id: u128) -> bool {
        let tile = get!(world, (row, col, player_id), (Tile));
        // 'tile'.print();
        // tile.player_id.print();
        // tile.row.print();
        // let t: TileType = tile.tile_type;
        // let t1: felt252 = t.into();
        // t1.print();

        tile.tile_type != TileType::Empty
    }

    fn distance(self: Tile, b: Tile) -> u8 {
        let mut dx: u8 = 0;
        if self.row > b.col {
            dx = self.row - b.row;
        } else {
            dx = b.row - self.row;
        };

        let mut dy: u8 = 0;
        if self.col > b.col {
            dy = self.col - b.col;
        } else {
            dy = b.col - self.col;
        };
        dx * dx + dy * dy
    }

    fn is_close(self: Tile, b: Tile) -> bool {
        distance(self, b) <= 1
    }

    fn _rnd_rnd_(rnd: u256) -> u256 {
        let value: u128 = hash_u128(rnd.high, rnd.low);
        u256 { high: rnd.high, low: value, }
    }

    // randomizes a value lower than max (exclusive)
    // returns the new rnd and the value

    fn randomize_value(ref rnd: u256, max: u128) -> u128 {
        rnd = _rnd_rnd_(rnd);
        (rnd.low % max)
    }

    fn randomize_range(ref rnd: u256, min: u128, max: u128) -> u128 {
        rnd = _rnd_rnd_(rnd);
        (min + rnd.low % (max - min + 1))
    }

    fn randomize_range_usize(ref rnd: u256, min: u128, max: u128) -> u128 {
        randomize_range(ref rnd, min, max).try_into().unwrap()
    }
    fn hash_felt(seed: felt252, offset: felt252) -> felt252 {
        pedersen::pedersen(seed, offset)
    }

    fn hash_u128(seed: u128, offset: u128) -> u128 {
        let hash = hash_felt(seed.into(), offset.into());
        felt_to_u128(hash)
    }

    fn felt_to_u128(value: felt252) -> u128 {
        match u128s_from_felt252(value) {
            U128sFromFelt252Result::Narrow(x) => x,
            U128sFromFelt252Result::Wide((_, x)) => x,
        }
    }

    // upgrade a u128 hash to u256
    fn hash_u128_to_u256(value: u128) -> u256 {
        u256 { low: value, high: hash_u128(value, value) }
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

    fn neighbors(world: IWorldDispatcher, tile: Tile) -> Array<Tile> {
        array![
            neighbor(world, tile, Direction::East(())),
            neighbor(world, tile, Direction::NorthEast(())),
            neighbor(world, tile, Direction::NorthWest(())),
            neighbor(world, tile, Direction::West(())),
            neighbor(world, tile, Direction::SouthWest(())),
            neighbor(world, tile, Direction::SouthEast(()))
        ]
    }

    fn is_neighbor(world: IWorldDispatcher, tile: Tile, other: Tile) -> bool {
        let mut neighbors = neighbors(world, tile);
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
        let mut neighbors = neighbors(world, tile);
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
                && current_neighbour.tile_type != TileType::Port) {
                break true;
            }
        }
    }
}
