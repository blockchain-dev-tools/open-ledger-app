use crate::errors::{ChainError, Result};
use hmac::{Hmac, Mac};
use sha2::Sha512;

const SLIP10_SEED_KEY: &[u8] = b"ed25519 seed";
type HmacSha512 = Hmac<Sha512>;

fn be32(value: u32) -> [u8; 4] {
    value.to_be_bytes()
}

/// Derive a secp256k1 private key **and** its BIP-32 chain code at `path`.
///
/// The chain code is a first-class output of BIP-32 CKDpriv
/// (`I = HMAC-SHA512(chain_code_parent, serP || i)`, child chain code = `I[32..]`)
/// and is *not* recoverable from the private key alone. A Ledger host asks for
/// it explicitly (`GET_PUBLIC_KEY`, `P2 = 0x01`) so it can rebuild an xpub, so it
/// must come from the same derivation that produced the key.
///
/// Returns `(private_key[32], chain_code[32])`.
pub fn derive_secp256k1_extended(seed: &[u8], path: &str) -> Result<(Vec<u8>, [u8; 32])> {
    let p: bip32::DerivationPath = path
        .parse()
        .map_err(|e| ChainError::InvalidPath(format!("invalid BIP-32 path '{path}': {e}")))?;
    let xprv = bip32::XPrv::derive_from_path(seed, &p)
        .map_err(|e| ChainError::DerivationFailed(e.to_string()))?;
    Ok((xprv.private_key().to_bytes().to_vec(), xprv.attrs().chain_code))
}

pub fn derive_secp256k1_private_key(seed: &[u8], path: &str) -> Result<Vec<u8>> {
    Ok(derive_secp256k1_extended(seed, path)?.0)
}

pub fn derive_ed25519_private_key(seed: &[u8], path: &str) -> Result<Vec<u8>> {
    let components = parse_slip10_components(path)?;
    let mut mac = HmacSha512::new_from_slice(SLIP10_SEED_KEY)
        .map_err(|e| ChainError::DerivationFailed(e.to_string()))?;
    mac.update(seed);
    let i = mac.finalize().into_bytes();
    let mut kl = i[..32].to_vec();
    let mut kr = i[32..].to_vec();
    for component in &components {
        let index_bytes = be32(*component);
        let mut data = [0u8; 37];
        data[0] = 0x00;
        data[1..33].copy_from_slice(&kl);
        data[33..37].copy_from_slice(&index_bytes);
        let mut child_mac = HmacSha512::new_from_slice(&kr)
            .map_err(|e| ChainError::DerivationFailed(e.to_string()))?;
        child_mac.update(&data);
        let child_i = child_mac.finalize().into_bytes();
        kl = child_i[..32].to_vec();
        kr = child_i[32..].to_vec();
    }
    Ok(kl)
}

fn parse_slip10_components(path: &str) -> Result<Vec<u32>> {
    let segments: Vec<&str> = path.split('/').collect();
    if segments.is_empty() || segments[0] != "m" {
        return Err(ChainError::InvalidPath(format!("SLIP-10 path must start with 'm': {path}")));
    }
    let mut components = Vec::with_capacity(segments.len() - 1);
    for seg in &segments[1..] {
        if !seg.ends_with('\'') {
            return Err(ChainError::InvalidPath(format!(
                "SLIP-10 Ed25519 requires all-hardened paths, got non-hardened component '{seg}' in '{path}'"
            )));
        }
        let num_str = &seg[..seg.len() - 1];
        let num: u32 = num_str
            .parse()
            .map_err(|_| ChainError::InvalidPath(format!("invalid SLIP-10 path component: {seg}")))?;
        components.push(num | 0x80000000);
    }
    Ok(components)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_seed() -> Vec<u8> {
        let phrase = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
        let mnemonic = bip39::Mnemonic::parse(phrase).unwrap();
        mnemonic.to_seed("").to_vec()
    }

    #[test]
    fn derive_secp256k1_basic() {
        let seed = test_seed();
        let key = derive_secp256k1_private_key(&seed, "m/44'/60'/0'/0/0").unwrap();
        assert_eq!(key.len(), 32);
    }

    #[test]
    fn derive_secp256k1_different_paths() {
        let seed = test_seed();
        let a = derive_secp256k1_private_key(&seed, "m/44'/60'/0'/0/0").unwrap();
        let b = derive_secp256k1_private_key(&seed, "m/44'/60'/0'/0/1").unwrap();
        assert_ne!(a, b);
    }

    #[test]
    fn derive_ed25519_basic() {
        let seed = test_seed();
        let key = derive_ed25519_private_key(&seed, "m/44'/501'/0'/0'").unwrap();
        assert_eq!(key.len(), 32);
    }

    #[test]
    fn derive_ed25519_different_paths() {
        let seed = test_seed();
        let a = derive_ed25519_private_key(&seed, "m/44'/501'/0'/0'").unwrap();
        let b = derive_ed25519_private_key(&seed, "m/44'/501'/1'/0'").unwrap();
        assert_ne!(a, b);
    }

    #[test]
    fn ed25519_rejects_non_hardened() {
        let seed = test_seed();
        let result = derive_ed25519_private_key(&seed, "m/44'/501'/0'/0");
        assert!(result.is_err());
    }

    #[test]
    fn secp256k1_accepts_non_hardened() {
        let seed = test_seed();
        let result = derive_secp256k1_private_key(&seed, "m/44'/60'/0'/0/0");
        assert!(result.is_ok());
    }

    #[test]
    fn deterministic_derivation() {
        let seed = test_seed();
        let a1 = derive_ed25519_private_key(&seed, "m/44'/501'/0'/0'").unwrap();
        let a2 = derive_ed25519_private_key(&seed, "m/44'/501'/0'/0'").unwrap();
        assert_eq!(a1, a2);
    }

    #[test]
    fn derive_secp256k1_extended_exposes_real_chain_code() {
        let seed = test_seed();
        let (key, chain_code) = derive_secp256k1_extended(&seed, "m/44'/60'/0'/0/0").unwrap();
        assert_eq!(key.len(), 32);
        assert_eq!(chain_code.len(), 32);
        assert_ne!(chain_code, [0u8; 32], "chain code must be derived, not zero-filled");
        // Refactor equivalence: the plain entry point returns the key half.
        assert_eq!(key, derive_secp256k1_private_key(&seed, "m/44'/60'/0'/0/0").unwrap());
        // The chain code varies with the derivation path.
        let (_, sibling) = derive_secp256k1_extended(&seed, "m/44'/60'/0'/0/1").unwrap();
        assert_ne!(chain_code, sibling);
        // Deterministic.
        let (_, again) = derive_secp256k1_extended(&seed, "m/44'/60'/0'/0/0").unwrap();
        assert_eq!(chain_code, again);
    }
}
