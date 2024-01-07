// ---------------------------------------------------------------------
// This file contains the interface of the contract.
// ---------------------------------------------------------------------
use castle_hexapolis::models::TileType;
use starknet::ContractAddress;


#[starknet::interface]
trait IActions<TContractState> {
    fn spawn(self: @TContractState, amount: u128);
    fn place_tile(self: @TContractState, tiles: Span<(u8, u8, TileType)>);
    fn cleanup(self: @TContractState);
    fn set_lords_address(ref self: TContractState, lords_address: ContractAddress);
    fn faucet(ref self: TContractState, amount: u128);
}
