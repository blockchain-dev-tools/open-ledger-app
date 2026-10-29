//! BC-UR（Uniform Resources）编解码，供 Keystone 兼容的二维码空口使用（D-018）。
//!
//! 只做三件事：把 CBOR 编成 UR 帧、把收到的帧还原成 CBOR、以及 ETH 相关
//! 两个 registry type（`eth-sign-request` / `eth-signature`）与 `crypto-account`
//! 的 dCBOR 结构。密钥派生与签名复用 `open-ledger-biz` / `open-ledger-crypto`。

pub mod account;
pub mod eth;
mod path;
pub mod session;
pub mod ur;

pub use account::{
    account_address, build_crypto_account, build_crypto_account_code, build_crypto_accounts,
    build_multi_accounts, CryptoAccountCode, MAX_ACCOUNTS_PER_CODE, MULTI_ACCOUNTS_ETH_COUNT,
    MULTI_ACCOUNTS_TYPE,
};
pub use eth::{
    encode_eth_signature, EthSignRequest, EthSignatureOut, ETH_SIGN_REQUEST_TYPE,
    ETH_SIGNATURE_TYPE,
};
pub use session::{PartStatus, ReceiveState, UrSession};
pub use ur::{encode_frames, DEFAULT_FRAGMENT_LEN};
