use starknet::ContractAddress;
use debug::PrintTrait;


// Declaration of an enum named 'TileType' with three variants
#[derive(Serde, Copy, Drop, Introspect)]
enum TileType {
    Road,
    Tower,
    Agri,
    TownHall,
}

// Implementation of a trait to convert TileType enum into felt252 data type
impl TileTypeIntoFelt252 of Into<TileType, felt252> {
    fn into(self: Direction) -> felt252 {
        match self {
            TileType::Road(()) => 1,
            TileType::Tower(()) => 2,
            TileType::Agri(()) => 3,
            TileType::TownHall(()) => 4,
        }
    }
}


// Constant definition for a game data key. This allows us to fetch this model using the key.
const GAME_DATA_KEY: felt252 = 'game';

// Structure definition for a 2D vector with x and y as unsigned 32-bit integers
#[derive(Copy, Drop, Serde, Introspect)]
struct Vec2 {
    x: u32,
    y: u32
}


// Structure representing a position with an ID, and x, y coordinates
#[derive(Model, Copy, Drop, Serde)]
struct Position {
    #[key]
    id: u8,
    #[key]
    x: u8,
    #[key]
    y: u8,
    tile_type: TileType,
    occupied: bool,
}


// Structure representing a player's ID with a ContractAddress
#[derive(Model, Copy, Drop, Serde)]
struct PlayerID {
    #[key]
    player: ContractAddress,
    id: u8,
}

// Structure linking a player's ID to their ContractAddress
#[derive(Model, Copy, Drop, Serde)]
struct PlayerAddress {
    #[key]
    id: u8,
    player: ContractAddress,
}

// Structure for storing game data with a key, number of players, and available IDs
#[derive(Model, Copy, Drop, Serde)]
struct GameData {
    #[key]
    game: felt252, // Always 'game'
    remaining_moves: u8, // Packed u8s?
}

#[derive(Model, Copy, Drop, Serde)]
struct Score {
    #[key]
    id: u8,
    points: u8,
    remaining_moves: u8
}
