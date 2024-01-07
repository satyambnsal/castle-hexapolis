use starknet::ContractAddress;
use debug::PrintTrait;

// Declaration of an enum named 'Direction' with five variants
#[derive(Serde, Copy, Drop, Introspect, PartialEq)]
enum TileType {
    Empty,
    WatchTower,
    Park,
    Road,
    Castle,
    CityGate
}

// Implementation of a trait to convert TileType enum into felt252 data type
impl TileTypeIntoFelt252 of Into<TileType, felt252> {
    fn into(self: TileType) -> felt252 {
        match self {
            TileType::Empty(()) => 0,
            TileType::WatchTower(()) => 1,
            TileType::Park(()) => 2,
            TileType::Road(()) => 3,
            TileType::Castle(()) => 4,
            TileType::CityGate(()) => 5
        }
    }
}

#[derive(Model, Copy, Drop, Serde)]
struct Tile {
    #[key]
    row: u8,
    #[key]
    col: u8,
    #[key]
    player_id: u128,
    tile_type: TileType,
    counted: bool,
    is_hill: bool
}

#[derive(Model, Copy, Drop, Serde)]
struct PlayerId {
    #[key]
    player_address: ContractAddress,
    player_id: u128
}

#[derive(Model, Copy, Drop, Serde)]
struct PlayerAddress {
    #[key]
    player_id: u128,
    player_address: ContractAddress
}

#[derive(Model, Copy, Drop, Serde)]
struct Score {
    #[key]
    player_id: u128,
    score: u8,
    token_locked: u128,
    rewards: u128
}

#[derive(Model, Copy, Drop, Serde)]
struct RemainingMoves {
    #[key]
    player_id: u128,
    moves: u8
}

#[derive(Model, Copy, Drop, Serde)]
struct GameData {
    #[key]
    game: felt252,
    number_of_players: u128,
    available_ids: u128
}
const GAME_DATA_KEY: felt252 = 'castle_hexapolis_game';


#[derive(Drop, Copy, Serde)]
enum Direction {
    East: (),
    NorthEast: (),
    NorthWest: (),
    West: (),
    SouthWest: (),
    SouthEast: (),
}

impl DirectionIntoFelt252 of Into<Direction, felt252> {
    fn into(self: Direction) -> felt252 {
        match self {
            Direction::East => 0,
            Direction::NorthEast => 1,
            Direction::NorthWest => 2,
            Direction::West => 3,
            Direction::SouthWest => 4,
            Direction::SouthEast => 5,
        }
    }
}

#[derive(Model, Copy, Drop, Serde)]
struct ContractsRegistry {
    #[key]
    id: felt252, // GAME_DATA_KEY
    lords_address: felt252,
}
