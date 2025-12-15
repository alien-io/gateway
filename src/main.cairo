#[starknet::contract]
mod Gateway {
    use core::num::traits::Zero;
    use gateway::errors::Errors;
    use gateway::events::{
        AccountDeactivated, AccountReactivated, UserAddressChanged, UsernameRegistered, WalletAdded,
        WalletRemoved,
    };
    use gateway::interface::IGateway;
    use gateway::types::{UserInfo, Wallet};
    use gateway::utils::hash_username;
    use starknet::storage::{
        Map, MutableVecTrait, StorageMapReadAccess, StorageMapWriteAccess, StoragePathEntry,
        StoragePointerReadAccess, StoragePointerWriteAccess, Vec, VecTrait,
    };
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address};

    #[storage]
    struct Storage {
        usernames: Map<felt252, UserInfo>,
        address_usernames: Map<ContractAddress, ByteArray>,
        user_chain_symbols: Map<felt252, Vec<ByteArray>>,
        // Map from (username_hash, chain_symbol) to Wallet
        user_wallets: Map<(felt252, felt252), Wallet>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        UsernameRegistered: UsernameRegistered,
        WalletAdded: WalletAdded,
        WalletRemoved: WalletRemoved,
        UserAddressChanged: UserAddressChanged,
        AccountDeactivated: AccountDeactivated,
        AccountReactivated: AccountReactivated,
    }


    #[abi(embed_v0)]
    impl GatewayImpl of IGateway<ContractState> {
        /// Change user address - transfers username to a new address
        fn change_user_address(ref self: ContractState, new_address: ContractAddress) {
            assert(new_address.is_non_zero(), Errors::INVALID_ADDRESS);

            let caller = get_caller_address();
            let username = self.address_usernames.read(caller);

            assert(username.len() != 0, Errors::USER_NOT_REGISTERED);

            assert(self.is_account_active(username.clone()), Errors::ACCOUNT_INACTIVE);

            assert(
                self.address_usernames.read(new_address).len() == 0,
                Errors::ADDRESS_ALREADY_HAS_USERNAME,
            );

            let username_hash = hash_username(username.clone());

            let mut user_info = self.usernames.read(username_hash);
            user_info.user_address = new_address;
            self.usernames.write(username_hash, user_info);

            self.address_usernames.write(caller, "");

            self.address_usernames.write(new_address, username.clone());

            self
                .emit(
                    Event::UserAddressChanged(
                        UserAddressChanged {
                            username,
                            old_address: caller,
                            new_address,
                            timestamp: get_block_timestamp(),
                        },
                    ),
                );
        }

        /// Deactivate user account
        fn deactivate_account(ref self: ContractState) {
            let caller = get_caller_address();
            let username = self.address_usernames.read(caller);

            assert(username.len() != 0, Errors::USER_NOT_REGISTERED);

            let username_hash = hash_username(username.clone());
            let mut user_info = self.usernames.read(username_hash);

            assert(user_info.active, Errors::ACCOUNT_ALREADY_INACTIVE);

            user_info.active = false;
            self.usernames.write(username_hash, user_info);

            self
                .emit(
                    Event::AccountDeactivated(
                        AccountDeactivated {
                            username, user_address: caller, timestamp: get_block_timestamp(),
                        },
                    ),
                );
        }

        /// Reactivate user account
        fn reactivate_account(ref self: ContractState) {
            let caller = get_caller_address();
            let username = self.address_usernames.read(caller);

            assert(username.len() != 0, Errors::USER_NOT_REGISTERED);

            let username_hash = hash_username(username.clone());
            let mut user_info = self.usernames.read(username_hash);

            assert(!user_info.active, Errors::ACCOUNT_ALREADY_ACTIVE);

            user_info.active = true;
            self.usernames.write(username_hash, user_info);

            self
                .emit(
                    Event::AccountReactivated(
                        AccountReactivated {
                            username, user_address: caller, timestamp: get_block_timestamp(),
                        },
                    ),
                );
        }

        /// Check if user account is active
        fn is_account_active(self: @ContractState, username: ByteArray) -> bool {
            assert(username.len() != 0, Errors::INVALID_USERNAME);

            let username_hash = hash_username(username);
            let user_info = self.usernames.read(username_hash);
            user_info.active
        }

        /// Register a new username (unique)
        fn register_username(ref self: ContractState, username: ByteArray) {
            assert(username.len() != 0, Errors::INVALID_USERNAME);

            let caller = get_caller_address();
            assert(self.get_username(caller).len() == 0, Errors::CALLER_ALREADY_HAVE_USERNAME);
            assert(!self.check_username_exist(username.clone()), Errors::USERNAME_TAKEN);

            let username_hash = hash_username(username.clone());

            let new_user = UserInfo {
                username: username.clone(), user_address: caller, active: true,
            };

            self.usernames.write(username_hash, new_user);
            self.address_usernames.write(caller, username.clone());

            self
                .emit(
                    Event::UsernameRegistered(
                        UsernameRegistered {
                            username, user_address: caller, timestamp: get_block_timestamp(),
                        },
                    ),
                );
            // AUTOMATICALLY send to L1
        // self._send_user_info_to_l1(username_hash, caller, true);
        }

        /// Add Different wallet address for different chains
        fn add_wallets(
            ref self: ContractState,
            chain_symbol: ByteArray,
            wallet_address: ByteArray,
            memo: Option<u128>,
            tag: Option<u128>,
            metadata: Option<ByteArray>,
        ) {
            assert(chain_symbol.len() > 0, Errors::INVALID_CHAIN_SYMBOL);
            assert(wallet_address.len() > 0, Errors::INVALID_WALLET_ADDRESS);

            let caller = get_caller_address();
            let username = self.get_username(caller);

            assert(username.len() != 0, Errors::USER_NOT_REGISTERED);

            assert(self.is_account_active(username.clone()), Errors::ACCOUNT_INACTIVE);

            let username_hash = hash_username(username);

            // Check if this chain_symbol already exists for this user
            let chain_exists = self._check_chain_exists(username_hash, chain_symbol.clone());

            // If chain doesn't exist, add it to the Vec
            if !chain_exists {
                let mut chain_symbols = self.user_chain_symbols.entry(username_hash);
                chain_symbols.append().write(chain_symbol.clone());
            }

            let new_wallet = Wallet {
                chain_symbol: chain_symbol.clone(),
                address: wallet_address.clone(),
                memo,
                tag,
                metadata,
                updated_at: get_block_timestamp(),
            };
            self
                .user_wallets
                .write((username_hash, hash_username(chain_symbol.clone())), new_wallet);

            self
                .emit(
                    Event::WalletAdded(
                        WalletAdded {
                            user_address: caller,
                            chain_symbol,
                            wallet_address,
                            timestamp: get_block_timestamp(),
                        },
                    ),
                );
            // self
        //     ._send_wallet_to_l1(
        //         username_hash, self.user_wallets.read((username_hash, chain_symbol)),
        //     );
        }

        ///  Remove Wallet from wallet list
        fn remove_wallet(ref self: ContractState, chain_symbol: ByteArray) {
            assert(chain_symbol.len() > 0, Errors::INVALID_CHAIN_SYMBOL);

            let caller = get_caller_address();
            let username = self.get_username(caller);

            assert(username.len() != 0, Errors::USER_NOT_REGISTERED);
            assert(self.check_username_exist(username.clone()), Errors::USER_NOT_REGISTERED);

            assert(self.is_account_active(username.clone()), Errors::ACCOUNT_INACTIVE);

            let username_hash = hash_username(username.clone());

            // Verify the wallet exists for this chain
            let wallet = self
                .user_wallets
                .read((username_hash, hash_username(chain_symbol.clone())));
            assert(wallet.address.len() > 0, Errors::WALLET_NOT_FOUND);

            let empty_wallet = Wallet {
                chain_symbol: "",
                address: "",
                memo: Option::None,
                tag: Option::None,
                metadata: Option::None,
                updated_at: 0,
            };
            self
                .user_wallets
                .write((username_hash, hash_username(chain_symbol.clone())), empty_wallet);

            // Remove chain_symbol from the Vec
            let mut chain_symbols_vec = self.user_chain_symbols.entry(username_hash);
            let len = chain_symbols_vec.len();

            let mut idx: u64 = 0;
            let mut found = false;
            while idx != len {
                if chain_symbols_vec.at(idx).read() == chain_symbol {
                    found = true;
                    break;
                }
                idx += 1;
            }

            assert(found, Errors::chain_symbol_NOT_FOUND);

            if idx != len - 1 {
                let last_chain = chain_symbols_vec.at(len - 1).read();
                chain_symbols_vec.at(idx).write(last_chain);
            }

            chain_symbols_vec.pop();

            self
                .emit(
                    Event::WalletRemoved(
                        WalletRemoved {
                            user_address: caller,
                            username,
                            chain_symbol,
                            timestamp: get_block_timestamp(),
                        },
                    ),
                );
        }

        /// Get wallet for a specific chain
        fn get_wallet(
            self: @ContractState, username: ByteArray, chain_symbol: ByteArray,
        ) -> Wallet {
            assert(username.len() != 0, Errors::INVALID_USERNAME);
            assert(chain_symbol.len() > 0, Errors::INVALID_CHAIN_SYMBOL);

            assert(self.is_account_active(username.clone()), Errors::ACCOUNT_INACTIVE);

            let username_hash = hash_username(username);
            self.user_wallets.read((username_hash, hash_username(chain_symbol)))
        }

        /// Get all chain IDs for a user
        fn get_user_chain_symbols(self: @ContractState, username: ByteArray) -> Array<ByteArray> {
            assert(username.len() != 0, Errors::INVALID_USERNAME);

            assert(self.is_account_active(username.clone()), Errors::ACCOUNT_INACTIVE);

            let username_hash = hash_username(username);
            let chain_symbols_vec = self.user_chain_symbols.entry(username_hash);

            let mut chain_symbols_array = ArrayTrait::new();
            let len = chain_symbols_vec.len();

            let mut i: u64 = 0;
            while i != len {
                chain_symbols_array.append(chain_symbols_vec.at(i).read());
                i += 1;
            }

            chain_symbols_array
        }

        /// Get all wallets for a user
        fn get_all_user_wallets(self: @ContractState, username: ByteArray) -> Array<Wallet> {
            assert(username.len() != 0, Errors::INVALID_USERNAME);

            assert(self.is_account_active(username.clone()), Errors::ACCOUNT_INACTIVE);

            let username_hash = hash_username(username);
            let chain_symbols_vec = self.user_chain_symbols.entry(username_hash);

            let mut wallets = ArrayTrait::new();
            let len = chain_symbols_vec.len();

            let mut i: u64 = 0;
            while i != len {
                let chain_symbol = chain_symbols_vec.at(i).read();
                let wallet = self.user_wallets.read((username_hash, hash_username(chain_symbol)));
                wallets.append(wallet);
                i += 1;
            }

            wallets
        }

        // Check if the username exists on-chain
        fn check_username_exist(self: @ContractState, username: ByteArray) -> bool {
            let hash = hash_username(username);
            let user = self.usernames.read(hash);
            user.user_address.is_non_zero()
        }

        // Get User Info
        fn get_user_info(self: @ContractState, username: ByteArray) -> UserInfo {
            assert(username.len() != 0, Errors::INVALID_USERNAME);
            let hash = hash_username(username);
            let user: UserInfo = self.usernames.read(hash);
            user
        }

        // Get username
        fn get_username(self: @ContractState, address: ContractAddress) -> ByteArray {
            assert(address.is_non_zero(), Errors::INVALID_ADDRESS);
            self.address_usernames.read(address)
        }
    }

    #[generate_trait]
    impl InternalFunctions of InternalFunctionsTrait {
        fn _check_chain_exists(
            self: @ContractState, username_hash: felt252, chain_symbol: ByteArray,
        ) -> bool {
            let chain_symbols = self.user_chain_symbols.entry(username_hash);
            let len = chain_symbols.len();

            let mut i: u64 = 0;
            loop {
                if i >= len {
                    break false;
                }
                if chain_symbols.at(i).read() == chain_symbol {
                    break true;
                }
                i += 1;
            }
        }
        /// Internal function to send user info to L1
    // fn _send_user_info_to_l1(
    //     ref self: ContractState,
    //     username_hash: felt252,
    //     user_address: ContractAddress,
    //     active: bool,
    // ) {
    //     let mut payload: Array<felt252> = ArrayTrait::new();
    //     payload.append(0); // message_type: 0 = user info
    //     payload.append(username_hash);
    //     payload.append(user_address.into());
    //     payload.append(if active {
    //         1
    //     } else {
    //         0
    //     });

        //     let l1_recipient = self.l1_gateway_address.read();
    //     send_message_to_l1_syscall(l1_recipient, payload.span()).unwrap();
    // }

        // /// Internal function to send wallet to L1
    // fn _send_wallet_to_l1(ref self: ContractState, username_hash: felt252, wallet: Wallet) {
    //     let mut payload: Array<felt252> = ArrayTrait::new();
    //     payload.append(1); // message_type: 1 = wallet added/updated
    //     payload.append(username_hash);
    //     payload.append(wallet.chain_symbol);
    //     payload.append(wallet.address);

        //     let memo_val = match wallet.memo {
    //         Option::Some(val) => val.into(),
    //         Option::None => 0,
    //     };
    //     let tag_val = match wallet.tag {
    //         Option::Some(val) => val.into(),
    //         Option::None => 0,
    //     };

        //     payload.append(memo_val);
    //     payload.append(tag_val);
    //     payload.append(wallet.updated_at.into());

        //     let l1_recipient = self.l1_gateway_address.read();
    //     send_message_to_l1_syscall(l1_recipient, payload.span()).unwrap();
    // }

        // /// Internal function to send wallet removal to L1
    // fn _send_wallet_removal_to_l1(
    //     ref self: ContractState, username_hash: felt252, chain_symbol: felt252,
    // ) {
    //     let mut payload: Array<felt252> = ArrayTrait::new();
    //     payload.append(2); // message_type: 2 = wallet removed
    //     payload.append(username_hash);
    //     payload.append(chain_symbol);

        //     let l1_recipient = self.l1_gateway_address.read();
    //     send_message_to_l1_syscall(l1_recipient, payload.span()).unwrap();
    // }
    }
}
