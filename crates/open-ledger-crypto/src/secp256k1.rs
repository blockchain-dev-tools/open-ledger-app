//! secp256k1 椭圆曲线算法（ECDSA 签名 + 公钥推导）。
//!
//! 封装 k256 crate，供 ETH/BTC/TRX 共用。

use crate::errors::{CryptoError, Result};
use k256::ecdsa::SigningKey;

pub fn sign_prehash_recoverable<F>(
    private_key: &[u8],
    hash: &[u8; 32],
    v_fn: F,
) -> Result<Vec<u8>>
where
    F: FnOnce(u8) -> u8,
{
    let signing_key = SigningKey::from_slice(private_key)
        .map_err(|e| CryptoError::InvalidKey(e.to_string()))?;
    let (sig, recid) = signing_key
        .sign_prehash_recoverable(hash)
        .map_err(|e| CryptoError::InvalidKey(e.to_string()))?;
    // EIP-2 low-s 归一化：k256 的 `sign_prehash_recoverable` 默认不归一化 s，
    // 约 50% 的签名 s 会落在曲线阶高半区，被 OpenZeppelin ECDSA 等链上验证器
    // 以 "invalid signature 's' value" 拒绝。当 s 翻转为 n - s 时，recovery id
    // 的 y-parity 位必须同步翻转，否则 ecrecover 还原出的地址错误。
    let (sig, recid_byte) = match sig.normalize_s() {
        Some(normalized) => (normalized, recid.to_byte() ^ 1),
        None => (sig, recid.to_byte()),
    };
    let r = sig.r().to_bytes();
    let s = sig.s().to_bytes();
    let v = v_fn(recid_byte);
    let mut result = Vec::with_capacity(65);
    result.push(v);
    result.extend_from_slice(&r);
    result.extend_from_slice(&s);
    Ok(result)
}

pub fn public_key_bytes(private_key: &[u8], compressed: bool) -> Result<Vec<u8>> {
    let signing_key = SigningKey::from_slice(private_key)
        .map_err(|e| CryptoError::InvalidKey(e.to_string()))?;
    let verifying_key = signing_key.verifying_key();
    let encoded = verifying_key.to_encoded_point(compressed);
    Ok(encoded.as_bytes().to_vec())
}

/// ECDH：`peer_public_key * private_key`，返回未压缩点（`0x04 || X || Y`，65 字节）。
///
/// 与 Ledger app-tron 的 `cx_ecdh(CX_ECDH_POINT)` 输出一致；不是只取 X 坐标。
pub fn ecdh_shared_point(private_key: &[u8], peer_public_key: &[u8]) -> Result<Vec<u8>> {
    use k256::elliptic_curve::sec1::ToEncodedPoint;

    let secret = k256::SecretKey::from_slice(private_key)
        .map_err(|e| CryptoError::InvalidKey(e.to_string()))?;
    let peer = k256::PublicKey::from_sec1_bytes(peer_public_key)
        .map_err(|e| CryptoError::InvalidKey(e.to_string()))?;
    let shared = k256::ProjectivePoint::from(*peer.as_affine()) * *secret.to_nonzero_scalar();
    let point = k256::AffinePoint::from(shared);
    Ok(point.to_encoded_point(false).as_bytes().to_vec())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::keccak256;

    fn test_privkey() -> Vec<u8> {
        let phrase = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
        let mnemonic = bip39::Mnemonic::parse(phrase).unwrap();
        let seed = mnemonic.to_seed("");
        // Use bip32 crate to derive
        let path: bip32::DerivationPath = "m/44'/60'/0'/0/0".parse().unwrap();
        let xprv = bip32::XPrv::derive_from_path(seed, &path).unwrap();
        xprv.private_key().to_bytes().to_vec()
    }

    #[test]
    fn public_key_uncompressed_65_bytes() {
        let pk = test_privkey();
        let pubkey = public_key_bytes(&pk, false).unwrap();
        assert_eq!(pubkey.len(), 65);
        assert_eq!(pubkey[0], 0x04);
    }

    #[test]
    fn public_key_compressed_33_bytes() {
        let pk = test_privkey();
        let pubkey = public_key_bytes(&pk, true).unwrap();
        assert_eq!(pubkey.len(), 33);
        assert!(pubkey[0] == 0x02 || pubkey[0] == 0x03);
    }

    #[test]
    fn sign_and_recover() {
        let pk = test_privkey();
        let hash = keccak256::hash(b"hello world");
        let sig = sign_prehash_recoverable(&pk, &hash, |v| 27 + v).unwrap();
        assert_eq!(sig.len(), 65);
        assert!(sig[0] == 27 || sig[0] == 28);
    }

    #[test]
    fn sign_deterministic() {
        let pk = test_privkey();
        let hash = keccak256::hash(b"test message");
        let sig1 = sign_prehash_recoverable(&pk, &hash, |v| v).unwrap();
        let sig2 = sign_prehash_recoverable(&pk, &hash, |v| v).unwrap();
        assert_eq!(sig1, sig2);
    }

    #[test]
    fn signature_is_low_s_and_recovers_original_key() {
        use k256::ecdsa::{RecoveryId, Signature, VerifyingKey};
        // 尝试足够多不同的 hash，覆盖 recovery id = 0/1 以及 s 高/低半区两种情况。
        for i in 0..20u8 {
            let pk = test_privkey();
            let hash = keccak256::hash(&[i; 32]);
            let sig = sign_prehash_recoverable(&pk, &hash, |v| v).unwrap();
            assert_eq!(sig.len(), 65);

            let sig_part = Signature::from_slice(&sig[1..65]).unwrap();
            let recid = RecoveryId::from_byte(sig[0]).unwrap();

            // EIP-2：s 必须已在低半区（若仍为 high-s，说明归一化缺失）。
            assert!(
                sig_part.normalize_s().is_none(),
                "s is in the high half — EIP-2 low-s normalization is missing"
            );

            // recovery id 必须与归一化后的签名匹配，还原出原公钥。
            let recovered = VerifyingKey::recover_from_prehash(&hash, &sig_part, recid).unwrap();
            let exp_key = SigningKey::from_slice(&pk).unwrap();
            let expected = exp_key.verifying_key();
            assert_eq!(recovered.to_sec1_bytes(), expected.to_sec1_bytes());
        }
    }
}
