// ---------------------------------------------------------------------
// This file contains the interface of the contract.
// ---------------------------------------------------------------------
use castle_hexapolis::models::TileType;


#[starknet::interface]
trait IActions<TContractState> {
    fn spawn(self: @TContractState);
    fn place_tile(self: @TContractState, tile1: (u8, u8, TileType));
    fn cleanup(self: @TContractState);
    fn produce_random_tiletype(self: @TContractState) -> TileType;
}
