//! Event / Effect 的版本化二进制编码，以及「整条链路真的走了一遍字节」的夹具。
//!
//! 现在宿主与模块同进程，编码不参与运行；它的用途是先把边界固化成协议：
//! 换成动态库或 WASM 沙箱后，同一份字节就是跨边界载荷，不需要重做 DTO。
//!
//! ## 兼容性
//!
//! 枚举的**变体顺序就是线格式**。新增变体只能追加在末尾，并递增
//! [`WIRE_VERSION`]；删除、重排或在已有变体中间插入都会让 `golden_*` 测试
//! 失败——那是预期行为，不要放宽断言。

use serde::{de::DeserializeOwned, Serialize};

use crate::app::{ChainApp, ModuleFactory, SessionConfig};
use crate::error::AppError;
use crate::event::{CancelReason, Effect, Event};
use crate::manifest::AppDescriptor;

/// 当前线格式版本。任何破坏兼容的改动都必须递增它。
pub const WIRE_VERSION: u16 = 1;

/// 编码/解码失败。宿主据此拒绝该模块，而不是猜测字段含义。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum WireError {
    /// 载荷版本与宿主不一致。
    UnknownVersion { found: u16, expected: u16 },
    /// 载荷被截断或结构不符。
    Codec(String),
}

impl std::fmt::Display for WireError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            WireError::UnknownVersion { found, expected } => {
                write!(f, "wire version {found} != {expected}")
            }
            WireError::Codec(reason) => write!(f, "wire codec error: {reason}"),
        }
    }
}

impl std::error::Error for WireError {}

/// 编码成 `[版本][postcard 载荷]`。版本在最前面，便于在不解析载荷的情况下拒绝。
pub fn encode<T: Serialize>(body: &T) -> Vec<u8> {
    postcard::to_allocvec(&(WIRE_VERSION, body)).expect("owned DTOs always serialise")
}

/// 解码并校验版本。版本不符时不尝试兼容旧载荷：未知字段必须显式处理。
pub fn decode<T: DeserializeOwned>(bytes: &[u8]) -> Result<T, WireError> {
    let (version, body): (u16, T) =
        postcard::from_bytes(bytes).map_err(|e| WireError::Codec(e.to_string()))?;
    if version != WIRE_VERSION {
        return Err(WireError::UnknownVersion {
            found: version,
            expected: WIRE_VERSION,
        });
    }
    Ok(body)
}

/// 编码后再解码。失败说明某个 DTO 无法完整跨边界，属于线上契约的 bug。
fn round_trip<T: Serialize + DeserializeOwned>(value: &T) -> T {
    let bytes = encode(value);
    decode(&bytes).expect("chain-app DTO must round-trip through its wire encoding")
}

/// 把任意模块包一层「编码 → 解码 → 调用」，让真实流量完整走一遍字节。
///
/// 它不改变宿主行为，只把边界上的隐式拷贝变成显式编码；等到换载体
/// （动态库 / WASM）时，替换的是这里的实现，而不是每个链模块。
pub struct EncodedFactory<F> {
    inner: F,
}

impl<F> EncodedFactory<F> {
    pub fn new(inner: F) -> Self {
        Self { inner }
    }
}

impl<F: ModuleFactory> ModuleFactory for EncodedFactory<F> {
    fn describe(&self) -> AppDescriptor {
        round_trip(&self.inner.describe())
    }

    fn create(&self) -> Box<dyn ChainApp> {
        Box::new(EncodedApp {
            inner: self.inner.create(),
        })
    }
}

/// [`EncodedFactory`] 创建的会话：每个事件与效果都真的经过 [`encode`] / [`decode`]。
struct EncodedApp {
    inner: Box<dyn ChainApp>,
}

impl ChainApp for EncodedApp {
    fn open(&mut self, config: SessionConfig) -> Result<(), AppError> {
        self.inner.open(round_trip(&config))
    }

    fn step(&mut self, event: Event) -> Result<Effect, AppError> {
        round_trip(&self.inner.step(round_trip(&event)))
    }

    fn close(&mut self, reason: CancelReason) {
        self.inner.close(round_trip(&reason));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::event::{
        DeliveryAck, FinishStatus, LocalCommand, OperationState, ReviewOutcome, ServiceResult,
        StorageOp,
    };
    use crate::manifest::Wire;
    use crate::review::{
        FeeKind, Field, FieldValue, NetworkId, OperationKind, ParseStatus, ReviewAction,
        ReviewDocument, ReviewRequest, ReviewSection, Risk, RiskLevel, RiskSource,
    };
    use crate::sign::{
        Curve, DerivationScheme, KeyOutput, PublicKey, PublicKeyRequest, SignOperation, SignPlan,
        SignScheme, Signature,
    };

    fn document() -> ReviewDocument {
        ReviewDocument {
            operation: OperationKind::Transaction,
            network: NetworkId {
                name: "Ethereum".into(),
                chain_id: Some(56),
            },
            account: Some("0x9858effd232b4033e47d90003d41ec34ecaeda94".into()),
            sections: vec![ReviewSection {
                title_key: "review.summary".into(),
                fields: vec![
                    Field {
                        label_key: "review.to".into(),
                        value: FieldValue::Address {
                            value: "0x25b243".into(),
                            network: "bsc".into(),
                            role: "to".into(),
                        },
                    },
                    Field {
                        label_key: "review.amount".into(),
                        value: FieldValue::Amount {
                            raw: "1000000000000000000".into(),
                            decimals: 18,
                            asset: "BNB".into(),
                            ticker: Some("BNB".into()),
                        },
                    },
                    Field {
                        label_key: "review.calldata".into(),
                        value: FieldValue::Structured {
                            entries: vec![Field {
                                label_key: "review.selector".into(),
                                value: FieldValue::Bytes {
                                    value: vec![0xa9, 0x05, 0x9c, 0xbb],
                                },
                            }],
                        },
                    },
                    Field {
                        label_key: "review.fee".into(),
                        value: FieldValue::Fee {
                            kind: FeeKind::UpperBound,
                            raw: Some("21000".into()),
                            decimals: 18,
                            asset: "BNB".into(),
                        },
                    },
                    Field {
                        label_key: "review.blind".into(),
                        value: FieldValue::Boolean(false),
                    },
                    Field {
                        label_key: "review.memo".into(),
                        value: FieldValue::Text {
                            value: "你好 🧾".into(),
                        },
                    },
                ],
            }],
            risks: vec![Risk {
                code: "blind-signing".into(),
                severity: RiskLevel::Warning,
                parameters: vec![("selector".into(), "0xdeadbeef".into())],
                source: RiskSource::External {
                    provider: "server".into(),
                    verified: false,
                },
            }],
            parse_status: ParseStatus::Partial,
        }
    }

    #[test]
    fn event_round_trips_every_variant() {
        let events = vec![
            Event::Wire {
                exchange_id: 7,
                wire: Wire::Ur,
                payload: vec![0, 1, 2, 255],
            },
            Event::Local {
                request_id: 3,
                command: LocalCommand::DeriveAccount {
                    account_profile_index: 0,
                    address_index: 42,
                },
            },
            Event::Local {
                request_id: 4,
                command: LocalCommand::SettingsChange {
                    key: "network".into(),
                    value: b"mainnet".to_vec(),
                },
            },
            Event::ServiceResult {
                service_id: 1,
                result: ServiceResult::PublicKey(PublicKey {
                    bytes: vec![0x02; 33],
                    chain_code: Some(vec![0xaa; 32]),
                }),
            },
            Event::ServiceResult {
                service_id: 2,
                result: ServiceResult::Storage(Some(vec![9, 8, 7])),
            },
            Event::ServiceResult {
                service_id: 3,
                result: ServiceResult::SharedSecret(vec![0x04; 65]),
            },
            Event::ServiceResult {
                service_id: 4,
                result: ServiceResult::Failed("denied".into()),
            },
            Event::ReviewResult {
                review_id: 9,
                outcome: ReviewOutcome::Approved {
                    signatures: vec![Signature {
                        operation_id: 7,
                        bytes: vec![0x11; 64],
                        recovery_id: Some(1),
                    }],
                },
            },
            Event::ReviewResult {
                review_id: 10,
                outcome: ReviewOutcome::TimedOut,
            },
            Event::Delivered {
                exchange_id: 5,
                ack: DeliveryAck::BestEffort,
            },
            Event::Cancel {
                reason: CancelReason::Locked,
            },
        ];

        for event in events {
            assert_eq!(round_trip(&event), event);
        }
    }

    #[test]
    fn effect_round_trips_every_variant() {
        let effects = vec![
            Effect::Emit {
                wire: Wire::LedgerApdu,
                exchange_id: 1,
                payload: vec![0x90, 0x00],
                state: OperationState::Collecting,
            },
            Effect::LocalReply {
                request_id: 2,
                payload: b"{\"address\":\"0x0\"}".to_vec(),
            },
            Effect::NeedPublicKey {
                service_id: 3,
                request: PublicKeyRequest {
                    derivation_scheme: DerivationScheme::Bip32Secp256k1,
                    curve: Curve::Secp256k1,
                    path: vec![0x8000_002c, 0x8000_003c, 0x8000_0000, 0, 0],
                    output: KeyOutput::ExtendedPublicKey,
                    include_chain_code: true,
                },
            },
            Effect::NeedEcdh {
                service_id: 4,
                request: crate::sign::EcdhRequest {
                    derivation_scheme: DerivationScheme::Slip10Ed25519,
                    curve: Curve::Ed25519,
                    path: vec![0x8000_002c],
                    peer_public_key: vec![0x05; 33],
                },
            },
            Effect::NeedReview {
                service_id: 5,
                request: Box::new(ReviewRequest {
                    document: document(),
                    action: ReviewAction::Sign(SignPlan {
                        operations: vec![SignOperation {
                            operation_id: 7,
                            derivation_scheme: DerivationScheme::Bip32Secp256k1,
                            curve: Curve::Secp256k1,
                            path: vec![0x8000_002c, 0x8000_003c, 0x8000_0000, 0, 0],
                            scheme: SignScheme::EcdsaPrehash {
                                digest_len: 32,
                                low_s: true,
                            },
                            input: vec![0x22; 32],
                            public_parameters: vec![("domain".into(), b"bsc".to_vec())],
                        }],
                    }),
                }),
            },
            Effect::NeedReview {
                service_id: 6,
                request: Box::new(ReviewRequest {
                    document: document(),
                    action: ReviewAction::DisplayAddress {
                        derivation_scheme: DerivationScheme::Bip32Secp256k1,
                        curve: Curve::Secp256k1,
                        path: vec![0x8000_002c],
                    },
                }),
            },
            Effect::NeedReview {
                service_id: 7,
                request: Box::new(ReviewRequest {
                    document: document(),
                    action: ReviewAction::ChangeSetting {
                        key: "network".into(),
                        value: b"testnet".to_vec(),
                    },
                }),
            },
            Effect::NeedStore {
                service_id: 8,
                operation: StorageOp::Write {
                    key: "cursor".into(),
                    value: vec![1, 2, 3],
                },
            },
            Effect::AwaitInput,
            Effect::Finished {
                status: FinishStatus::Failed,
            },
        ];

        for effect in effects {
            assert_eq!(round_trip(&effect), effect);
        }
    }

    #[test]
    fn descriptor_and_session_config_round_trip() {
        let descriptor = AppDescriptor {
            module_id: "openledger.ethereum".into(),
            module_version: "0.1.0".into(),
            api_version: crate::manifest::API_VERSION,
            review_schema_version: 1,
            storage_schema_version: 1,
            protocol_profiles: Vec::new(),
            account_profiles: Vec::new(),
            requested_capabilities: crate::manifest::CapabilitySet::default(),
        };
        assert_eq!(round_trip(&descriptor), descriptor);

        let config = SessionConfig {
            session_id: 1,
            epoch: 2,
            granted: crate::manifest::CapabilitySet::default(),
            public_config: vec![("network".into(), "mainnet".into())],
        };
        assert_eq!(round_trip(&config), config);
    }

    /// 变体顺序就是线格式：编码一旦变化，说明有人重排了枚举。
    #[test]
    fn golden_vectors_pin_variant_order() {
        assert_eq!(
            encode(&Event::Cancel {
                reason: CancelReason::Locked
            }),
            vec![0x01, 0x05, 0x01]
        );
        assert_eq!(
            encode(&Effect::Finished {
                status: FinishStatus::Delivered
            }),
            vec![0x01, 0x07, 0x00]
        );
    }

    #[test]
    fn unknown_version_is_rejected() {
        let mut bytes = encode(&Effect::AwaitInput);
        bytes[0] = WIRE_VERSION as u8 + 1;
        assert_eq!(
            decode::<Effect>(&bytes),
            Err(WireError::UnknownVersion {
                found: WIRE_VERSION + 1,
                expected: WIRE_VERSION
            })
        );
    }

    #[test]
    fn truncated_payload_is_rejected() {
        let bytes = encode(&Effect::Emit {
            wire: Wire::LedgerApdu,
            exchange_id: 1,
            payload: vec![1, 2, 3, 4],
            state: OperationState::Final,
        });
        assert!(matches!(
            decode::<Effect>(&bytes[..bytes.len() - 1]),
            Err(WireError::Codec(_))
        ));
    }

    #[test]
    fn app_error_round_trips() {
        let error = AppError::BadRequest("chunk too large".into());
        assert_eq!(round_trip(&error), error);
    }
}
