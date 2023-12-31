// ---------------------------------------------------------------------
// This file contains the interface of the contract.
// ---------------------------------------------------------------------
use castle_hexapolis::models::TileType;


#[starknet::interface]
trait IActions<TContractState> {
    fn spawn(self: @TContractState);
    fn place_tile(self: @TContractState, tiles: Span<(u8, u8, TileType)>);
    fn cleanup(self: @TContractState);
}
