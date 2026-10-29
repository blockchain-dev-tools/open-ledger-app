//! 密钥与签名计划：模块能声明的密码学需求，以及宿主返还的结果。
//!
//! 这里只放拥有所有权的数据；模块永远拿不到 seed / 私钥，也拿不到宿主的缓冲区。

/// 派生体系。与曲线分开枚举，避免「一条曲线字符串」掩盖 SLIP-10 与 BIP-32 的差异。
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum DerivationScheme {
    Bip32Secp256k1,
    Slip10Ed25519,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum Curve {
    Secp256k1,
    Ed25519,
}

impl Curve {
    pub fn matches(self, scheme: DerivationScheme) -> bool {
        matches!(
            (self, scheme),
            (Curve::Secp256k1, DerivationScheme::Bip32Secp256k1)
                | (Curve::Ed25519, DerivationScheme::Slip10Ed25519)
        )
    }
}

/// 公钥的输出编码。`ExtendedPublicKey` 只在宿主授予 chain code 能力时可用。
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum KeyOutput {
    CompressedSecp256k1,
    UncompressedSecp256k1,
    Ed25519,
    ExtendedPublicKey,
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct PublicKeyRequest {
    pub derivation_scheme: DerivationScheme,
    pub curve: Curve,
    pub path: Vec<u32>,
    pub output: KeyOutput,
    pub include_chain_code: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct PublicKey {
    pub bytes: Vec<u8>,
    pub chain_code: Option<Vec<u8>>,
}

/// ECDH：宿主用派生私钥与对端公钥计算共享点（返回未压缩点，65 字节）。
/// 只用于 Tron `0x0A GET_ECDH_SECRET` 这类不产生签名的私钥运算。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct EcdhRequest {
    pub derivation_scheme: DerivationScheme,
    pub curve: Curve,
    pub path: Vec<u32>,
    pub peer_public_key: Vec<u8>,
}

/// 签名输入的语义。Ed25519 直接对原始消息签名，不能默认先哈希。
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum SignScheme {
    EcdsaPrehash { digest_len: u8, low_s: bool },
    Ed25519Message,
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct SignOperation {
    pub operation_id: u32,
    pub derivation_scheme: DerivationScheme,
    pub curve: Curve,
    pub path: Vec<u32>,
    pub scheme: SignScheme,
    /// 待签输入。ECDSA 为摘要，Ed25519 为原始消息；长度由 `scheme` 校验。
    pub input: Vec<u8>,
    /// 协议需要的公开参数（例如域分隔标签）。不允许放私钥材料。
    pub public_parameters: Vec<(String, Vec<u8>)>,
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct Signature {
    pub operation_id: u32,
    pub bytes: Vec<u8>,
    /// ECDSA 恢复位；Ed25519 为 `None`。
    pub recovery_id: Option<u8>,
}

/// 一次批准覆盖的有序、有限操作集合。批准后顺序与集合冻结。
#[derive(Debug, Clone, PartialEq, Eq, Default, serde::Serialize, serde::Deserialize)]
pub struct SignPlan {
    pub operations: Vec<SignOperation>,
}

impl SignPlan {
    pub fn single(op: SignOperation) -> Self {
        Self {
            operations: vec![op],
        }
    }

    pub fn operation_ids(&self) -> Vec<u32> {
        self.operations.iter().map(|o| o.operation_id).collect()
    }
}
