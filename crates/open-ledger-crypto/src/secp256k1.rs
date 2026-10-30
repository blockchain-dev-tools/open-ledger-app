//! secp256k1 椭圆曲线算法（ECDSA / Schnorr 签名 + 公钥推导）。
//!
//! 封装 k256 crate，供 ETH/BTC/TRX 共用。

use crate::errors::{CryptoError, Result};
use k256::ecdsa::SigningKey;
use k256::elliptic_curve::sec1::ToEncodedPoint;
use k256::elliptic_curve::PrimeField;
use k256::{AffinePoint, ProjectivePoint, Scalar};

/// BIP-340 的 tagged hash：`SHA256(SHA256(tag) ‖ SHA256(tag) ‖ parts…)`。
pub fn tagged_hash(tag: &str, parts: &[&[u8]]) -> [u8; 32] {
    let tag_hash = crate::sha256::hash(tag.as_bytes());
    let mut data = Vec::with_capacity(64 + parts.iter().map(|p| p.len()).sum::<usize>());
    data.extend_from_slice(&tag_hash);
    data.extend_from_slice(&tag_hash);
    for part in parts {
        data.extend_from_slice(part);
    }
    crate::sha256::hash(&data)
}

/// 32 字节大端标量；越界或为零时返回错误。
fn scalar_from_bytes(bytes: &[u8]) -> Result<Scalar> {
    let mut repr = k256::FieldBytes::default();
    if bytes.len() != 32 {
        return Err(CryptoError::InvalidKey(format!(
            "scalar must be 32 bytes, got {}",
            bytes.len()
        )));
    }
    repr.copy_from_slice(bytes);
    Option::from(Scalar::from_repr(repr))
        .ok_or_else(|| CryptoError::InvalidKey("scalar out of range".into()))
}

/// 压缩点编码里的 32 字节 x 坐标。
fn x_bytes(point: &k256::EncodedPoint) -> Result<Vec<u8>> {
    point
        .x()
        .map(|x| x.to_vec())
        .ok_or_else(|| CryptoError::InvalidKey("point at infinity".into()))
}

/// 私钥对应的 x-only 公钥（32 字节，BIP-340）。
pub fn xonly_public_key(private_key: &[u8]) -> Result<Vec<u8>> {
    let signing_key = SigningKey::from_slice(private_key)
        .map_err(|e| CryptoError::InvalidKey(e.to_string()))?;
    x_bytes(&signing_key.verifying_key().to_encoded_point(true))
}

/// BIP-341 的 TapTweak 摘要（无脚本树的 key-path only）。
fn tap_tweak(xonly: &[u8]) -> Result<Scalar> {
    if xonly.len() != 32 {
        return Err(CryptoError::InvalidKey(
            "x-only public key must be 32 bytes".into(),
        ));
    }
    scalar_from_bytes(&tagged_hash("TapTweak", &[xonly]))
}

/// `lift_x`：x-only 公钥还原成偶 y 的完整点。
fn lift_x(xonly: &[u8]) -> Result<ProjectivePoint> {
    if xonly.len() != 32 {
        return Err(CryptoError::InvalidKey(
            "x-only public key must be 32 bytes".into(),
        ));
    }
    let mut compressed = Vec::with_capacity(33);
    compressed.push(0x02);
    compressed.extend_from_slice(xonly);
    let key = k256::PublicKey::from_sec1_bytes(&compressed)
        .map_err(|e| CryptoError::InvalidKey(e.to_string()))?;
    Ok(ProjectivePoint::from(*key.as_affine()))
}

/// BIP-341 key-path only 的输出公钥（x-only，32 字节）：
/// `output = lift_x(internal) + TapTweak(internal)·G`。
pub fn taproot_output_key(xonly: &[u8]) -> Result<Vec<u8>> {
    let internal = lift_x(xonly)?;
    let tweak = tap_tweak(xonly)?;
    let output = internal + ProjectivePoint::GENERATOR * tweak;
    x_bytes(&AffinePoint::from(output).to_encoded_point(true))
}

/// 私钥推导的 Taproot 输出公钥（x-only，32 字节）。
pub fn taproot_output_key_from_private(private_key: &[u8]) -> Result<Vec<u8>> {
    taproot_output_key(&xonly_public_key(private_key)?)
}

/// 用私钥直接做 BIP-340 Schnorr 签名（不做 taproot tweak）。
pub fn schnorr_sign(private_key: &[u8], message: &[u8]) -> Result<Vec<u8>> {
    let scalar = scalar_from_bytes(private_key)?;
    let key = k256::schnorr::SigningKey::from_bytes(&scalar.to_bytes())
        .map_err(|e| CryptoError::InvalidKey(e.to_string()))?;
    // aux_rand 固定为 0：与 RFC6979 一样走确定性签名，同一消息可复现。
    let signature = key
        .sign_raw(message, &[0u8; 32])
        .map_err(|e| CryptoError::InvalidKey(e.to_string()))?;
    Ok(signature.to_bytes().to_vec())
}

/// Taproot key-path 签名：先把私钥按 BIP-341 调整（`d' = d + TapTweak(x)`，
/// 内部公钥为奇 y 时先取反），再对 `message`（32 字节 sighash，必要时已含
/// 1 字节 hash_type）做 BIP-340 Schnorr 签名。
pub fn schnorr_sign_taproot(private_key: &[u8], message: &[u8]) -> Result<Vec<u8>> {
    let mut scalar = scalar_from_bytes(private_key)?;
    let point = (ProjectivePoint::GENERATOR * scalar).to_affine();
    // 内部公钥必须是偶 y（BIP-341 的 lift_x 约定）。
    if point.to_encoded_point(false).as_bytes()[64] & 1 == 1 {
        scalar = -scalar;
    }
    let internal_x = x_bytes(&point.to_encoded_point(true))?;
    let tweak = tap_tweak(&internal_x)?;
    let tweaked = scalar + tweak;
    schnorr_sign(&tweaked.to_bytes(), message)
}

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

    // ── BIP-340 / BIP-341 ────────────────────────────────────────────

    fn scalar_bytes(value: u32) -> Vec<u8> {
        let mut out = vec![0u8; 32];
        out[28..].copy_from_slice(&value.to_be_bytes());
        out
    }

    /// BIP-340 官方测试向量 0：私钥 3、aux 全零、消息全零。
    #[test]
    fn schnorr_matches_bip340_vector_zero() {
        let private_key = scalar_bytes(3);
        assert_eq!(
            hex::encode(xonly_public_key(&private_key).unwrap()),
            "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"
        );
        let signature = schnorr_sign(&private_key, &[0u8; 32]).unwrap();
        assert_eq!(
            hex::encode(&signature),
            "e907831f80848d1069a5371b402410364bdf1c5f8307b0084c55f1ce2dca821525f66a4a85ea8b71e482a74f382d2ce5ebeee8fdb2172f477df4900d310536c0"
        );
    }

    /// 手写 BIP-340 验签方程 `s·G == R + e·P`，不复用 k256 的 schnorr 实现。
    fn verify_bip340(xonly: &[u8], message: &[u8], signature: &[u8]) -> bool {
        let point = |x: &[u8]| -> ProjectivePoint {
            let mut compressed = vec![0x02];
            compressed.extend_from_slice(x);
            ProjectivePoint::from(*k256::PublicKey::from_sec1_bytes(&compressed).unwrap().as_affine())
        };
        let scalar = |bytes: &[u8]| -> Scalar {
            let mut repr = k256::FieldBytes::default();
            repr.copy_from_slice(bytes);
            Option::from(Scalar::from_repr(repr)).unwrap()
        };
        let r_point = point(&signature[..32]);
        let s = scalar(&signature[32..]);
        let e = scalar(&tagged_hash(
            "BIP0340/challenge",
            &[&signature[..32], xonly, message],
        ));
        (ProjectivePoint::GENERATOR * s) == (r_point + point(xonly) * e)
    }

    #[test]
    fn schnorr_signatures_satisfy_the_verification_equation() {
        let private_key = test_privkey();
        let xonly = xonly_public_key(&private_key).unwrap();
        for i in 0..5u8 {
            let message = crate::sha256::hash(&[i; 7]);
            let signature = schnorr_sign(&private_key, &message).unwrap();
            assert!(verify_bip340(&xonly, &message, &signature), "case {i}");
        }
    }

    #[test]
    fn taproot_output_key_is_tweaked_not_the_internal_key() {
        let private_key = test_privkey();
        let internal = xonly_public_key(&private_key).unwrap();
        let output = taproot_output_key_from_private(&private_key).unwrap();
        assert_eq!(output.len(), 32);
        assert_ne!(output, internal, "输出公钥必须带 TapTweak");
        // 同一内部公钥重复计算必须稳定。
        assert_eq!(output, taproot_output_key(&internal).unwrap());
    }

    #[test]
    fn taproot_signature_verifies_against_the_output_key() {
        let private_key = test_privkey();
        let output = taproot_output_key_from_private(&private_key).unwrap();
        let message = crate::sha256::hash(b"taproot key path");
        let signature = schnorr_sign_taproot(&private_key, &message).unwrap();
        assert_eq!(signature.len(), 64);
        let verifying = k256::schnorr::VerifyingKey::from_bytes(&output).unwrap();
        let parsed = k256::schnorr::Signature::try_from(signature.as_slice()).unwrap();
        verifying.verify_raw(&message, &parsed).unwrap();
    }
}
