use crate::errors::{ChainError, Result};
use open_ledger_crypto::{keccak256, secp256k1};

pub fn sign_transaction(private_key: &[u8], rlp: &[u8]) -> Result<Vec<u8>> {
    let hash = keccak256::hash(rlp);
    secp256k1::sign_prehash_recoverable(private_key, &hash, |recovery_bit| {
        let is_typed = !rlp.is_empty() && rlp[0] <= 0x7f;
        if is_typed { recovery_bit } else { 27 + recovery_bit }
    }).map_err(|e| ChainError::InvalidPrivateKey(e.to_string()))
}

pub fn sign_personal_message(private_key: &[u8], message: &[u8]) -> Result<Vec<u8>> {
    let prefix = format!("\x19Ethereum Signed Message:\n{}", message.len());
    let mut payload = Vec::with_capacity(prefix.len() + message.len());
    payload.extend_from_slice(prefix.as_bytes());
    payload.extend_from_slice(message);
    let hash = keccak256::hash(&payload);
    secp256k1::sign_prehash_recoverable(private_key, &hash, |recovery_bit| 27 + recovery_bit)
        .map_err(|e| ChainError::InvalidPrivateKey(e.to_string()))
}

pub fn sign_eip712(private_key: &[u8], domain_hash: &[u8], struct_hash: &[u8]) -> Result<Vec<u8>> {
    let mut payload = Vec::with_capacity(2 + 32 + 32);
    payload.push(0x19);
    payload.push(0x01);
    payload.extend_from_slice(domain_hash);
    payload.extend_from_slice(struct_hash);
    let hash = keccak256::hash(&payload);
    secp256k1::sign_prehash_recoverable(private_key, &hash, |recovery_bit| 27 + recovery_bit)
        .map_err(|e| ChainError::InvalidPrivateKey(e.to_string()))
}

pub fn derive_address(seed: &[u8], path: &str) -> Result<String> {
    let privkey = crate::hdkey::derive_secp256k1_private_key(seed, path)?;
    address_from_private_key(&privkey)
}

pub fn address_from_private_key(private_key: &[u8]) -> Result<String> {
    let pubkey_bytes = secp256k1::public_key_bytes(private_key, false)?;
    let hash = keccak256::hash(&pubkey_bytes[1..]);
    let raw_addr = &hash[12..];
    let addr_hex = hex::encode(raw_addr);
    let checksummed = eip55_checksum(&addr_hex);
    Ok(format!("0x{checksummed}"))
}

fn eip55_checksum(addr_hex_lower: &str) -> String {
    let hash = keccak256::hash(addr_hex_lower.as_bytes());
    addr_hex_lower.chars().enumerate().map(|(i, c)| {
        let hash_byte = hash[i / 2];
        let nibble = if i % 2 == 0 { hash_byte >> 4 } else { hash_byte & 0x0f };
        if !c.is_ascii_alphabetic() { c }
        else if nibble >= 8 { c.to_ascii_uppercase() }
        else { c }
    }).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_privkey() -> Vec<u8> {
        let phrase = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
        let mnemonic = bip39::Mnemonic::parse(phrase).unwrap();
        let seed = mnemonic.to_seed("");
        crate::hdkey::derive_secp256k1_private_key(&seed, "m/44'/60'/0'/0/0").unwrap()
    }

    #[test]
    fn address_valid_format() {
        let key = test_privkey();
        let addr = address_from_private_key(&key).unwrap();
        assert!(addr.starts_with("0x"));
        assert_eq!(addr.len(), 42);
    }

    #[test]
    fn address_deterministic() {
        let key = test_privkey();
        let a1 = address_from_private_key(&key).unwrap();
        let a2 = address_from_private_key(&key).unwrap();
        assert_eq!(a1, a2);
    }

    #[test]
    fn sign_personal_message_returns_65_bytes() {
        let key = test_privkey();
        let sig = sign_personal_message(&key, b"hello world").unwrap();
        assert_eq!(sig.len(), 65);
        assert!(sig[0] == 27 || sig[0] == 28);
    }

    #[test]
    fn sign_eip712_returns_65_bytes() {
        let key = test_privkey();
        let domain_hash = [0xabu8; 32];
        let struct_hash = [0xcdu8; 32];
        let sig = sign_eip712(&key, &domain_hash, &struct_hash).unwrap();
        assert_eq!(sig.len(), 65);
        assert!(sig[0] == 27 || sig[0] == 28);
    }

    #[test]
    fn sign_transaction_returns_65_bytes() {
        let key = test_privkey();
        let sig = sign_transaction(&key, &[0x01, 0x02, 0x03]).unwrap();
        assert_eq!(sig.len(), 65);
    }

    #[test]
    fn sign_deterministic() {
        let key = test_privkey();
        let sig1 = sign_personal_message(&key, b"test").unwrap();
        let sig2 = sign_personal_message(&key, b"test").unwrap();
        assert_eq!(sig1, sig2);
    }

    #[test]
    fn derive_address_from_seed() {
        let phrase = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
        let mnemonic = bip39::Mnemonic::parse(phrase).unwrap();
        let seed = mnemonic.to_seed("");
        let addr = derive_address(&seed, "m/44'/60'/0'/0/0").unwrap();
        assert_eq!(addr.len(), 42);
    }

    #[test]
    fn address_has_eip55_checksum() {
        let key = test_privkey();
        let addr = address_from_private_key(&key).unwrap();
        let hex_part = &addr[2..];
        assert!(hex_part.chars().any(|c| c.is_ascii_uppercase()));
        assert!(hex_part.chars().any(|c| c.is_ascii_lowercase()));
    }
}
