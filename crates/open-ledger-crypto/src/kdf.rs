//! Versioned PIN → master-key derivation (ADR-007).
//!
//! A PIN is stretched into a 32-byte master key with a **versioned** KDF so a
//! wallet created before the Argon2id switch can still be unlocked, and then
//! upgraded in place:
//!
//! | version | KDF | status |
//! |---|---|---|
//! | 0 | PBKDF2-HMAC-SHA256, 100k rounds | legacy — unlock only |
//! | 1 | Argon2id (memory-hard) | current — all new credentials |
//!
//! The version is stored **next to the verifier it produced** (see
//! `WalletCredential.kdfVersion` in the app): the two must never disagree, and
//! a separate key could be left behind by a crash between writes.
//!
//! Argon2id is memory-hard, so the offline cost per guess no longer scales with
//! GPU-friendliness alone. It does **not** protect against an attacker who can
//! run code on the device — that is the keystore binding's job (see ADR-007).

use argon2::{Algorithm, Argon2, Params, Version};
use zeroize::Zeroize;

use crate::errors::{CryptoError, Result};
use crate::pbkdf2_chacha20::pbkdf2_derive;

/// Legacy PBKDF2-HMAC-SHA256 credential (pre-Argon2id installs).
pub const KDF_VERSION_PBKDF2_LEGACY: u32 = 0;

/// Argon2id credential (current).
pub const KDF_VERSION_ARGON2ID_V1: u32 = 1;

/// Version every **new** credential is written with.
pub const CURRENT_KDF_VERSION: u32 = KDF_VERSION_ARGON2ID_V1;

/// Master key length in bytes (32). Both KDFs produce exactly this.
pub const MASTER_KEY_LEN: usize = 32;

/// Argon2id `m` — 64 MiB, the ADR-007 starting point.
///
/// Memory, not time, is what makes guessing expensive, so this is the parameter
/// that matters. Low-end devices that cannot spare 64 MiB fall back to
/// [`ARGON2_M_COST_KIB_FALLBACK`] (OWASP minimum) — measure on the target
/// device before lowering it.
pub const ARGON2_M_COST_KIB: u32 = 64 * 1024;

/// Argon2id `t` — 3 passes.
pub const ARGON2_T_COST: u32 = 3;

/// Argon2id `p` — 4 lanes.
pub const ARGON2_P_COST: u32 = 4;

/// OWASP minimum memory cost (19 MiB) for devices that cannot allocate 64 MiB.
pub const ARGON2_M_COST_KIB_FALLBACK: u32 = 19 * 1024;

/// Whether [version] is a KDF version this build can derive with.
pub fn is_supported_version(version: u32) -> bool {
    matches!(
        version,
        KDF_VERSION_PBKDF2_LEGACY | KDF_VERSION_ARGON2ID_V1
    )
}

/// Argon2id parameters for [version] (`m` in KiB, `t` passes, `p` lanes).
///
/// Returns `None` for a non-Argon2 version.
pub fn argon2_params(version: u32) -> Option<(u32, u32, u32)> {
    match version {
        KDF_VERSION_ARGON2ID_V1 => Some((ARGON2_M_COST_KIB, ARGON2_T_COST, ARGON2_P_COST)),
        _ => None,
    }
}

/// Stretch [pin] with [salt] into a 32-byte master key using [version].
///
/// `salt` must be at least 8 bytes (Argon2id's minimum); the app uses the
/// 16-byte device salt. Unknown versions are rejected rather than silently
/// falling back — a wrong KDF would produce a key that silently fails to open
/// anything, which looks exactly like a wrong PIN.
pub fn derive_master_key(pin: &str, salt: &[u8], version: u32) -> Result<Vec<u8>> {
    match version {
        KDF_VERSION_PBKDF2_LEGACY => Ok(pbkdf2_derive(pin, salt, MASTER_KEY_LEN)),
        KDF_VERSION_ARGON2ID_V1 => {
            if salt.len() < 8 {
                return Err(CryptoError::InvalidData(format!(
                    "Argon2id salt must be at least 8 bytes, got {}",
                    salt.len()
                )));
            }
            let (m_cost, t_cost, p_cost) = argon2_params(version)
                .expect("argon2_params covers every Argon2 branch here");
            let params = Params::new(m_cost, t_cost, p_cost, Some(MASTER_KEY_LEN))
                .map_err(|e| CryptoError::InvalidData(format!("invalid Argon2id params: {e}")))?;
            let argon2 = Argon2::new(Algorithm::Argon2id, Version::V0x13, params);

            let mut out = vec![0u8; MASTER_KEY_LEN];
            argon2
                .hash_password_into(pin.as_bytes(), salt, &mut out)
                .map_err(|e| CryptoError::SeedDerivationFailed(format!("Argon2id failed: {e}")))?;
            Ok(out)
        }
        other => Err(CryptoError::InvalidData(format!(
            "unsupported KDF version: {other}"
        ))),
    }
}

/// Zeroise a derived key in place. Keys cross the FFI boundary as hex strings,
/// so callers that hold raw bytes must wipe them explicitly.
pub fn wipe_key(key: &mut [u8]) {
    key.zeroize();
}

#[cfg(test)]
mod tests {
    use super::*;

    const SALT: &[u8] = b"0123456789abcdef";

    #[test]
    fn master_key_is_32_bytes_for_every_version() {
        for v in [KDF_VERSION_PBKDF2_LEGACY, KDF_VERSION_ARGON2ID_V1] {
            assert_eq!(derive_master_key("123456", SALT, v).unwrap().len(), MASTER_KEY_LEN);
        }
    }

    #[test]
    fn derivation_is_deterministic() {
        for v in [KDF_VERSION_PBKDF2_LEGACY, KDF_VERSION_ARGON2ID_V1] {
            assert_eq!(
                derive_master_key("123456", SALT, v).unwrap(),
                derive_master_key("123456", SALT, v).unwrap(),
            );
        }
    }

    #[test]
    fn different_pin_or_salt_yields_different_key() {
        let base = derive_master_key("123456", SALT, KDF_VERSION_ARGON2ID_V1).unwrap();
        assert_ne!(
            base,
            derive_master_key("123457", SALT, KDF_VERSION_ARGON2ID_V1).unwrap()
        );
        assert_ne!(
            base,
            derive_master_key("123456", b"fedcba9876543210", KDF_VERSION_ARGON2ID_V1).unwrap()
        );
    }

    /// An upgraded credential must never accidentally produce the legacy key:
    /// that would let a legacy verifier be satisfied by an Argon2id credential.
    #[test]
    fn versions_do_not_collide() {
        assert_ne!(
            derive_master_key("123456", SALT, KDF_VERSION_PBKDF2_LEGACY).unwrap(),
            derive_master_key("123456", SALT, KDF_VERSION_ARGON2ID_V1).unwrap(),
        );
    }

    /// Pin the legacy path to the historical constant: a change here would lock
    /// out every pre-upgrade install.
    #[test]
    fn legacy_version_matches_plain_pbkdf2() {
        assert_eq!(
            derive_master_key("123456", SALT, KDF_VERSION_PBKDF2_LEGACY).unwrap(),
            pbkdf2_derive("123456", SALT, MASTER_KEY_LEN),
        );
    }

    #[test]
    fn unknown_version_is_rejected() {
        assert!(derive_master_key("123456", SALT, 99).is_err());
        assert!(!is_supported_version(99));
    }

    #[test]
    fn short_salt_is_rejected_for_argon2() {
        assert!(derive_master_key("123456", b"short", KDF_VERSION_ARGON2ID_V1).is_err());
    }

    #[test]
    fn current_version_is_argon2id() {
        assert_eq!(CURRENT_KDF_VERSION, KDF_VERSION_ARGON2ID_V1);
        assert_eq!(
            argon2_params(CURRENT_KDF_VERSION),
            Some((ARGON2_M_COST_KIB, ARGON2_T_COST, ARGON2_P_COST)),
        );
        assert!(ARGON2_M_COST_KIB_FALLBACK < ARGON2_M_COST_KIB);
    }
}
