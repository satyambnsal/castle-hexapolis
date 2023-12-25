//---------------------------------------------------------------------------------------------
// *Actions Contract*
// This contract handles all the actions that can be performed by the user
// Typically you group functions that require similar authentication into a single contract
// For this demo we are keeping all the functions in a single contract
//---------------------------------------------------------------------------------------------

#[dojo::contract]
mod actions {
    use starknet::{ContractAddress, get_caller_address};
    use debug::PrintTrait;
    use cubit::f128::procgen::simplex3;
    use cubit::f128::types::fixed::FixedTrait;
    use cubit::f128::types::vec3::Vec3Trait;

    // import actions
    use emojiman::interface::IActions;

    // import models
    use emojiman::models::{
        GAME_DATA_KEY, GameData, Vec2, Position, PlayerAtPosition, TileType, PlayerID, PlayerAddress
    };

    // import utils
    use emojiman::utils::next_position;

    // import config
    use emojiman::config::{
        INITIAL_MOVES, RENEWED_ENERGY, MOVE_ENERGY_COST, X_RANGE, Y_RANGE, ORIGIN_OFFSET,
        MAP_AMPLITUDE
    };

    // import integer
    use integer::{u128s_from_felt252, U128sFromFelt252Result, u128_safe_divmod};

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
        // Spawns the player on to the map
        fn spawn(self: @ContractState, rps: u8) {
            // world dispatcher
            let world = self.world_dispatcher.read();

            // player address
            let player = get_caller_address();

            // game data
            let mut game_data = get!(world, GAME_DATA_KEY, (GameData));

            game_data.remaining_moves = INITIAL_MOVES;

            // NOTE: save game_data model with the set! macro
            set!(world, (game_data));

            // get player id 
            let mut player_id = get!(world, player, (PlayerID)).id;

            // if player id is 0, assign new id
            if player_id == 0 {
                // Player not already spawned, prepare ID to assign
                player_id = assign_player_id(world, game_data.remaining_moves, player);
            } else {
                // Player already exists, clear old position for new spawn
                let pos = get!(world, player_id, (Position));
                clear_player_at_position(world, pos.x, pos.y);
            }

            // spawn on random position
            let (x, y) = spawn_coords(world, player.into(), player_id.into());

            // set player position
            player_position_and_tile(world, player_id, 0_u8, 0_u8, 4, true, 0_u8, 24_u8);
        }

        // To be done

        // Queues move for player to be processed later
        fn move(self: @ContractState, x: u8, y: u8, tile_type: TileType) {
            // world dispatcher
            let world = self.world_dispatcher.read();

            // player address
            let player = get_caller_address();

            // player id
            let id = get!(world, player, (PlayerID)).id;

            // player position and energy
            let (pos, score) = get!(world, id, (Position, Score));

            // Get new position
            let Position{id, x, y } = next_position(pos, dir);

            // Get max x and y
            let max_x: felt252 = ORIGIN_OFFSET.into() + X_RANGE.into();
            let max_y: felt252 = ORIGIN_OFFSET.into() + Y_RANGE.into();

            // assert max x and y
            assert(
                x <= max_x.try_into().unwrap() && y <= max_y.try_into().unwrap(), 'Out of bounds'
            );

            let tile = tile_at_position(x - ORIGIN_OFFSET.into(), y - ORIGIN_OFFSET.into());
            let mut move_energy_cost = MOVE_ENERGY_COST;
            if tile == 3 {
                // Use more energy to go through ocean tiles
                move_energy_cost = MOVE_ENERGY_COST * 3;
            }

            // assert energy
            assert(energy.amt >= move_energy_cost, 'Not enough energy');

            if 0 == adversary {
                // Empty cell, move
                player_position_and_energy(world, id, x, y, energy.amt - move_energy_cost);
            } else {
                if encounter(world, id, adversary) {
                    // Move the player
                    player_position_and_energy(world, id, x, y, energy.amt + RENEWED_ENERGY);
                }
            }
        }

        // To be done

        // ----- ADMIN FUNCTIONS -----
        // These functions are only callable by the owner of the world
        fn cleanup(self: @ContractState) {
            let world = self.world_dispatcher.read();
            let player = get_caller_address();

            assert(
                world.is_owner(get_caller_address(), DOJO_WORLD_RESOURCE), 'only owner can call'
            );

            // reset player count
            let mut game_data = get!(world, GAME_DATA_KEY, (GameData));
            game_data.number_of_players = 0;
            set!(world, (game_data));

            // Kill off all players
            let mut i = 1;
            loop {
                if i > 20 {
                    break;
                }
                player_dead(world, i);
                i += 1;
            };
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
    fn assign_player_id(world: IWorldDispatcher, num_players: u8, player: ContractAddress) -> u8 {
        let id = num_players;
        set!(world, (PlayerID { player, id }, PlayerAddress { player, id }));
        id
    }

    // // @dev: Sets no player at position
    // fn clear_player_at_position(world: IWorldDispatcher, x: u8, y: u8) {
    //     set!(world, (PlayerAtPosition { x, y, id: 0 }));
    // }

    // @dev: Returns player id at position
    fn player_occupied_position(world: IWorldDispatcher, id: u8, x: u8, y: u8, id: u8) -> bool {
        get!(world, (id, x, y), (PlayerAtPosition)).occupied
    }

    // @dev: Sets player position and energy
    fn player_position_and_score(
        world: IWorldDispatcher,
        id: u8,
        x: u8,
        y: u8,
        tile_type: TileType,
        occupied: bool,
        points: u8,
        remaining_moves: u8
    ) {
        set!(
            world,
            (Position { id, x, y, tile_type, occupied }, Score { id, points, remaining_moves })
        );
    }

    // // @dev: Game over part
    // fn player_dead(world: IWorldDispatcher, id: u8) {
    //     let pos = get!(world, id, (Position));
    //     let empty_player = starknet::contract_address_const::<0>();

    //     let id_felt: felt252 = id.into();
    //     let entity_keys = array![id_felt].span();
    //     let player = get!(world, id, (PlayerAddress)).player;
    //     let player_felt: felt252 = player.into();
    //     // Remove player address and ID mappings

    //     let mut layout = array![];

    //     world.delete_entity('PlayerID', array![player_felt].span(), layout.span());
    //     world.delete_entity('PlayerAddress', entity_keys, layout.span());

    //     set!(world, (PlayerID { player, id: 0 }));
    //     set!(world, (Position { id, x: 0, y: 0 }, RPSType { id, rps: 0 }));

    //     // Remove player components
    //     world.delete_entity('Position', entity_keys, layout.span());
    //     world.delete_entity('Score', entity_keys, layout.span());
    // }

    // @dev: Returns true if player wins
    //If the remaining tile is 0 then he wins
    // fn encounter_win(ply_type: u8, adv_type: u8) -> bool {
    //     assert(adv_type != ply_type, 'occupied by same type');
    //     if (ply_type == 'r' && adv_type == 's')
    //         || (ply_type == 'p' && adv_type == 'r')
    //         || (ply_type == 's' && adv_type == 'p') {
    //         return true;
    //     }
    //     false
    // }

    // @dev: Returns random spawn coordinates
    fn spawn_tile_type(world: IWorldDispatcher, player: felt252, mut salt: felt252) -> (u8, u8) {
        let mut x = 10;
        let mut y = 10;
        let mut z = 10;
        loop {
            let hash = pedersen::pedersen(player, salt);
            let rnd_seed = match u128s_from_felt252(hash) {
                U128sFromFelt252Result::Narrow(low) => low,
                U128sFromFelt252Result::Wide((high, low)) => low,
            };
            let (rnd_seed, x_) = u128_safe_divmod(rnd_seed, X_RANGE.try_into().unwrap());
            let (rnd_seed, y_) = u128_safe_divmod(rnd_seed, Y_RANGE.try_into().unwrap());
            let (rnd_seed, z_) = u128_safe_divmod(rnd_seed, Z_RANGE.try_into().unwrap());
            let x_: felt252 = x_.into();
            let y_: felt252 = y_.into();
            let z_: felt252 = z_.into();

            x = ORIGIN_OFFSET + x_.try_into().unwrap();
            y = ORIGIN_OFFSET + y_.try_into().unwrap();
            z = ORIGIN_OFFSET + z_.try_into().unwrap();
            let occupied = TileAtPosition(world, x, y);
            if occupied == 0 {
                break;
            } else {
                salt += 1; // Try new salt
            }
        };
        (x, y)
    }
}
