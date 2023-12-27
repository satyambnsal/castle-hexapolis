// ---------------------------------------------------------------------
// This file contains the interface of the contract.
// ---------------------------------------------------------------------

#[starknet::interface]
trait IActions<TContractState> {
    fn spawn(self: @TContractState);
    fn move(self: @TContractState, dir: emojiman::models::Direction, props: emojiman::models::Tile);
    fn cleanup(self: @TContractState);
}
