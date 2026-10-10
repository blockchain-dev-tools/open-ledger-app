use thiserror::Error;

pub type Result<T> = std::result::Result<T, CryptoError>;

#[derive(Error, Debug, Clone)]
pub enum CryptoError {
    #[error("invalid key: {0}")]
    InvalidKey(String),
    #[error("invalid data: {0}")]
    InvalidData(String),
    #[error("encryption failed: {0}")]
    EncryptionFailed(String),
    #[error("decryption failed: {0}")]
    DecryptionFailed(String),
    #[error("seed derivation failed: {0}")]
    SeedDerivationFailed(String),
    #[error("invalid mnemonic: {0}")]
    InvalidMnemonic(String),
}
