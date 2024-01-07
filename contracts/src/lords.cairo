#[starknet::contract]
mod lords {
    use castle_hexapolis::erc20::models::{ERC20Allowance, ERC20Balance, ERC20Meta};
    use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};
    use castle_hexapolis::erc20::interface;
    use integer::BoundedInt;
    use starknet::ContractAddress;
    use starknet::{get_caller_address, get_contract_address};
    use zeroable::Zeroable;
    use debug::PrintTrait;

    #[storage]
    struct Storage {
        _world: ContractAddress,
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        Transfer: Transfer,
        Approval: Approval,
    }

    #[derive(Copy, Drop, starknet::Event)]
    struct Transfer {
        from: ContractAddress,
        to: ContractAddress,
        value: u128
    }

    #[derive(Copy, Drop, starknet::Event)]
    struct Approval {
        owner: ContractAddress,
        spender: ContractAddress,
        value: u128
    }

    mod Errors {
        const APPROVE_FROM_ZERO: felt252 = 'Lords: approve from 0';
        const APPROVE_TO_ZERO: felt252 = 'Lords: approve to 0';
        const TRANSFER_FROM_ZERO: felt252 = 'Lords: transfer from 0';
        const TRANSFER_TO_ZERO: felt252 = 'Lords: transfer to 0';
        const BURN_FROM_ZERO: felt252 = 'Lords: burn from 0';
        const MINT_TO_ZERO: felt252 = 'Lords: mint to 0';
    }

    #[external(v0)]
    fn initializer(
        ref self: ContractState,
        world: ContractAddress,
        name: felt252,
        symbol: felt252,
        initial_supply: u128,
        recipient: ContractAddress
    ) {
        self._world.write(world);
        self.initializer(name, symbol);
        self._mint(recipient, initial_supply);
    }

    //
    // External
    //

    #[external(v0)]
    fn faucet(ref self: ContractState) {
        self._transfer(get_contract_address(), get_caller_address(), 1000);
    }

    #[external(v0)]
    impl LordsMetadataImpl of interface::IERC20Metadata<ContractState> {
        fn name(self: @ContractState) -> felt252 {
            self.get_meta().name
        }

        fn symbol(self: @ContractState) -> felt252 {
            self.get_meta().symbol
        }

        fn decimals(self: @ContractState) -> u8 {
            18
        }
    }

    #[external(v0)]
    impl LordsImpl of interface::IERC20<ContractState> {
        fn total_supply(self: @ContractState) -> u128 {
            self.get_meta().total_supply
        }

        fn balance_of(self: @ContractState, account: ContractAddress) -> u128 {
            self.get_balance(account).amount.print();
            self.get_balance(account).amount
        }

        fn allowance(
            self: @ContractState, owner: ContractAddress, spender: ContractAddress
        ) -> u128 {
            self.get_allowance(owner, spender).amount
        }

        fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u128) -> bool {
            let sender = get_caller_address();
            self._transfer(sender, recipient, amount);
            true
        }

        fn transfer_from(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u128
        ) -> bool {
            let caller = get_caller_address();
            self._spend_allowance(sender, caller, amount);
            self._transfer(sender, recipient, amount);
            true
        }

        fn approve(ref self: ContractState, spender: ContractAddress, amount: u128) -> bool {
            let owner = get_caller_address();
            self
                .set_allowance(
                    ERC20Allowance { token: get_contract_address(), owner, spender, amount }
                );
            true
        }
    }

    #[external(v0)]
    impl LordsCamelOnlyImpl of interface::IERC20CamelOnly<ContractState> {
        fn totalSupply(self: @ContractState) -> u128 {
            LordsImpl::total_supply(self)
        }

        fn balanceOf(self: @ContractState, account: ContractAddress) -> u128 {
            LordsImpl::balance_of(self, account)
        }

        fn transferFrom(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u128
        ) -> bool {
            LordsImpl::transfer_from(ref self, sender, recipient, amount)
        }
    }

    #[external(v0)]
    fn increase_allowance(
        ref self: ContractState, spender: ContractAddress, added_value: u128
    ) -> bool {
        self.update_allowance(get_caller_address(), spender, 0, added_value);
        true
    }

    #[external(v0)]
    fn increaseAllowance(
        ref self: ContractState, spender: ContractAddress, addedValue: u128
    ) -> bool {
        increase_allowance(ref self, spender, addedValue)
    }

    #[external(v0)]
    fn decrease_allowance(
        ref self: ContractState, spender: ContractAddress, subtracted_value: u128
    ) -> bool {
        self.update_allowance(get_caller_address(), spender, subtracted_value, 0);
        true
    }

    #[external(v0)]
    fn decreaseAllowance(
        ref self: ContractState, spender: ContractAddress, subtractedValue: u128
    ) -> bool {
        decrease_allowance(ref self, spender, subtractedValue)
    }

    //
    // Internal
    //

    #[generate_trait]
    impl WorldInteractionsImpl of WorldInteractionsTrait {
        fn world(self: @ContractState) -> IWorldDispatcher {
            IWorldDispatcher { contract_address: self._world.read() }
        }

        fn get_meta(self: @ContractState) -> ERC20Meta {
            get!(self.world(), get_contract_address(), ERC20Meta)
        }

        // Helper function to update total_supply model
        fn update_total_supply(ref self: ContractState, subtract: u128, add: u128) {
            let mut meta = self.get_meta();
            // adding and subtracting is fewer steps than if
            meta.total_supply = meta.total_supply - subtract;
            meta.total_supply = meta.total_supply + add;
            set!(self.world(), (meta));
        }

        // Helper function for balance model
        fn get_balance(self: @ContractState, account: ContractAddress) -> ERC20Balance {
            get!(self.world(), (get_contract_address(), account), ERC20Balance)
        }

        fn update_balance(
            ref self: ContractState, account: ContractAddress, subtract: u128, add: u128
        ) {
            let mut balance: ERC20Balance = self.get_balance(account);
            // adding and subtracting is fewer steps than if
            balance.amount = balance.amount - subtract;
            balance.amount = balance.amount + add;
            set!(self.world(), (balance));
        }

        // Helper function for allowance model
        fn get_allowance(
            self: @ContractState, owner: ContractAddress, spender: ContractAddress,
        ) -> ERC20Allowance {
            get!(self.world(), (get_contract_address(), owner, spender), ERC20Allowance)
        }

        fn update_allowance(
            ref self: ContractState,
            owner: ContractAddress,
            spender: ContractAddress,
            subtract: u128,
            add: u128
        ) {
            let mut allowance = self.get_allowance(owner, spender);
            // adding and subtracting is fewer steps than if
            allowance.amount = allowance.amount - subtract;
            allowance.amount = allowance.amount + add;
            self.set_allowance(allowance);
        }

        fn set_allowance(ref self: ContractState, allowance: ERC20Allowance) {
            assert(!allowance.owner.is_zero(), Errors::APPROVE_FROM_ZERO);
            assert(!allowance.spender.is_zero(), Errors::APPROVE_TO_ZERO);
            set!(self.world(), (allowance));
            self
                .emit_event(
                    Approval {
                        owner: allowance.owner, spender: allowance.spender, value: allowance.amount
                    }
                );
        }

        fn emit_event<
            S, impl IntoImp: traits::Into<S, Event>, impl SDrop: Drop<S>, impl SCopy: Copy<S>
        >(
            ref self: ContractState, event: S
        ) {
            self.emit(event);
            emit!(self.world(), event);
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn initializer(ref self: ContractState, name: felt252, symbol: felt252) {
            let meta = ERC20Meta { token: get_contract_address(), name, symbol, total_supply: 0 };
            set!(self.world(), (meta));
        }

        fn _mint(ref self: ContractState, recipient: ContractAddress, amount: u128) {
            assert(!recipient.is_zero(), Errors::MINT_TO_ZERO);
            self.update_total_supply(0, amount);
            self.update_balance(recipient, 0, amount);
            self.emit_event(Transfer { from: Zeroable::zero(), to: recipient, value: amount });
        }

        fn _burn(ref self: ContractState, account: ContractAddress, amount: u128) {
            assert(!account.is_zero(), Errors::BURN_FROM_ZERO);
            self.update_total_supply(amount, 0);
            self.update_balance(account, amount, 0);
            self.emit_event(Transfer { from: account, to: Zeroable::zero(), value: amount });
        }

        fn _approve(
            ref self: ContractState, owner: ContractAddress, spender: ContractAddress, amount: u128
        ) {
            self
                .set_allowance(
                    ERC20Allowance { token: get_contract_address(), owner, spender, amount }
                );
        }

        fn _transfer(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u128
        ) {
            assert(!sender.is_zero(), Errors::TRANSFER_FROM_ZERO);
            assert(!recipient.is_zero(), Errors::TRANSFER_TO_ZERO);
            self.update_balance(sender, amount, 0);
            self.update_balance(recipient, 0, amount);
            self.emit_event(Transfer { from: sender, to: recipient, value: amount });
        }

        fn _spend_allowance(
            ref self: ContractState, owner: ContractAddress, spender: ContractAddress, amount: u128
        ) {
            let current_allowance = self.get_allowance(owner, spender).amount;
            if current_allowance != BoundedInt::max() {
                self.update_allowance(owner, spender, amount, 0);
            }
        }
    }
}
