use starknet::ContractAddress;

#[derive(Drop, Serde, starknet::Event)]
pub struct UsernameRegistered {
    pub username: ByteArray,
    pub user_address: ContractAddress,
    pub timestamp: u64,
}

#[derive(Drop, Serde, starknet::Event)]
pub struct WalletAdded {
    pub user_address: ContractAddress,
    pub chain_symbol: ByteArray,
    pub wallet_address: ByteArray,
    pub timestamp: u64,
}

#[derive(Drop, starknet::Event)]
pub struct WalletRemoved {
    pub user_address: ContractAddress,
    pub username: ByteArray,
    pub chain_symbol: ByteArray,
    pub timestamp: u64,
}


#[derive(Drop, starknet::Event)]
pub struct UserAddressChanged {
    pub username: ByteArray,
    pub old_address: ContractAddress,
    pub new_address: ContractAddress,
    pub timestamp: u64,
}

#[derive(Drop, starknet::Event)]
pub struct AccountDeactivated {
    pub username: ByteArray,
    pub user_address: ContractAddress,
    pub timestamp: u64,
}

#[derive(Drop, starknet::Event)]
pub struct AccountReactivated {
    pub username: ByteArray,
    pub user_address: ContractAddress,
    pub timestamp: u64,
}
