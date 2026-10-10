use thiserror::Error;
use open_ledger_crypto::errors::CryptoError;

pub type Result<T> = std::result::Result<T, ChainError>;

#[derive(Error, Debug)]
pub enum ChainError {
    #[error("invalid derivation path: {0}")]
    InvalidPath(String),
    #[error("key derivation failed: {0}")]
    DerivationFailed(String),
    #[error("invalid mnemonic: {0}")]
    InvalidMnemonic(String),
    #[error("enigma error: {0}")]
    EnigmaError(String),
    #[error("parse error: {0}")]
    ParseError(String),
    #[error("invalid private key: {0}")]
    InvalidPrivateKey(String),
    #[error("address derivation failed: {0}")]
    AddressError(String),
    #[error("crypto error: {0}")]
    CryptoError(#[from] CryptoError),
}
