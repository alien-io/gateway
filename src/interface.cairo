use gateway::types::{UserInfo, Wallet};
use starknet::ContractAddress;

#[starknet::interface]
pub trait IGateway<TContractState> {
    fn change_user_address(ref self: TContractState, new_address: ContractAddress);
    fn deactivate_account(ref self: TContractState);
    fn reactivate_account(ref self: TContractState);
    fn is_account_active(self: @TContractState, username: ByteArray) -> bool;

    fn register_username(ref self: TContractState, username: ByteArray);
    fn check_username_exist(self: @TContractState, username: ByteArray) -> bool;
    fn add_wallets(
        ref self: TContractState,
        chain_symbol: ByteArray,
        wallet_address: ByteArray,
        memo: Option<u128>,
        tag: Option<u128>,
        metadata: Option<ByteArray>,
    );
    fn remove_wallet(ref self: TContractState, chain_symbol: ByteArray);

    fn get_user_info(self: @TContractState, username: ByteArray) -> UserInfo;
    fn get_username(self: @TContractState, address: ContractAddress) -> ByteArray;
    fn get_wallet(self: @TContractState, username: ByteArray, chain_symbol: ByteArray) -> Wallet;
    fn get_user_chain_symbols(self: @TContractState, username: ByteArray) -> Array<ByteArray>;
    fn get_all_user_wallets(self: @TContractState, username: ByteArray) -> Array<Wallet>;
}
