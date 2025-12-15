use core::pedersen::pedersen;

pub fn hash_username(username: ByteArray) -> felt252 {
    let mut hash_accumulator = 0;
    let username_len = username.len();
    let mut i = 0;
    while i != username_len {
        hash_accumulator = pedersen(hash_accumulator, username[i].into());
        i += 1;
    }

    hash_accumulator
}
