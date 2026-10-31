//! 阶段 3 验收：Bitcoin 四种地址、官方 xpub/主指纹，以及协议口径闸门。
//!
//! 地址与 `open_ledger_biz::btc`（独立代码路径）逐个类型比对；xpub 用独立的
//! BIP-32 序列化重新编码后比对。

use std::sync::{Arc, Mutex};

use chain_app_api::*;
use chain_app_bitcoin::BitcoinFactory;
use chain_app_runtime::{ReviewDecision, Runtime, RuntimeReply};

const MNEMONIC: &str =
    "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";

/// 官方 app-bitcoin 的 `P2_ADDR_FORMAT_*`。
const P2_LEGACY: u8 = 0x00;
const P2_P2SH: u8 = 0x01;
const P2_BECH32: u8 = 0x02;
const P2_BECH32M: u8 = 0x04;

struct CryptoKeys {
    seed: Vec<u8>,
    sign_calls: Mutex<usize>,
}

impl CryptoKeys {
    fn new() -> Self {
        Self {
            seed: open_ledger_crypto::bip39::mnemonic_to_seed(MNEMONIC, "")
                .unwrap()
                .to_vec(),
            sign_calls: Mutex::new(0),
        }
    }

    /// 按模块请求的路径派生；测试替身不能忽略路径，否则默认路径的缺陷会被掩盖。
    fn private_key_at(&self, path: &[u32]) -> Vec<u8> {
        open_ledger_biz::hdkey::derive_secp256k1_private_key(&self.seed, &render_path(path))
            .unwrap()
    }
}

fn render_path(path: &[u32]) -> String {
    let mut text = String::from("m");
    for component in path {
        if *component >= 0x8000_0000 {
            text.push_str(&format!("/{}'", component - 0x8000_0000));
        } else {
            text.push_str(&format!("/{component}"));
        }
    }
    text
}

impl KeyService for CryptoKeys {
    fn public_key(&self, request: &PublicKeyRequest) -> Result<PublicKey, HostError> {
        let compressed = request.output == KeyOutput::CompressedSecp256k1;
        let (private_key, chain_code) =
            open_ledger_biz::hdkey::derive_secp256k1_extended(&self.seed, &render_path(&request.path))
                .map_err(|e| HostError::Unavailable(e.to_string()))?;
        let bytes = open_ledger_crypto::secp256k1::public_key_bytes(&private_key, compressed)
            .map_err(|e| HostError::Unavailable(e.to_string()))?;
        Ok(PublicKey {
            bytes,
            chain_code: request.include_chain_code.then(|| chain_code.to_vec()),
        })
    }

    fn sign(
        &self,
        _auth: &SignAuthorization,
        operation: &SignOperation,
    ) -> Result<Signature, HostError> {
        *self.sign_calls.lock().unwrap() += 1;
        let private_key = self.private_key_at(&operation.path);
        match operation.scheme {
            SignScheme::EcdsaPrehash { .. } => {
                let mut digest = [0u8; 32];
                if operation.input.len() != 32 {
                    return Err(HostError::Denied("btc expects a 32-byte sighash".into()));
                }
                digest.copy_from_slice(&operation.input);
                // 直接签 sighash —— 不再多套一层 keccak。
                let signature = open_ledger_crypto::secp256k1::sign_prehash_recoverable(
                    &private_key,
                    &digest,
                    |v| v,
                )
                .map_err(|e| HostError::Unavailable(e.to_string()))?;
                Ok(Signature {
                    operation_id: operation.operation_id,
                    bytes: signature[1..65].to_vec(),
                    recovery_id: Some(signature[0]),
                })
            }
            SignScheme::SchnorrTaprootKeyPath { hash_type } => {
                let mut message = operation.input.clone();
                if hash_type != 0 {
                    message.push(hash_type);
                }
                let bytes =
                    open_ledger_crypto::secp256k1::schnorr_sign_taproot(&private_key, &message)
                        .map_err(|e| HostError::Unavailable(e.to_string()))?;
                Ok(Signature {
                    operation_id: operation.operation_id,
                    bytes,
                    recovery_id: None,
                })
            }
            SignScheme::Ed25519Message => Err(HostError::Denied("btc has no ed25519".into())),
        }
    }
}

struct NoStorage;

impl StorageService for NoStorage {
    fn read(&mut self, _scope: &StorageScope, _key: &str) -> Result<Option<Vec<u8>>, HostError> {
        Ok(None)
    }
    fn write(&mut self, _: &StorageScope, _: &str, _: Vec<u8>) -> Result<(), HostError> {
        Ok(())
    }
    fn delete(&mut self, _: &StorageScope, _: &str) -> Result<(), HostError> {
        Ok(())
    }
}

fn policy() -> CapabilitySet {
    CapabilitySet {
        derivation_rules: vec![
            DerivationRule {
                derivation_scheme: DerivationScheme::Bip32Secp256k1,
                curve: Curve::Secp256k1,
                depth: 0,
                hardened_positions: vec![],
                max_index: 0,
            },
            DerivationRule {
                derivation_scheme: DerivationScheme::Bip32Secp256k1,
                curve: Curve::Secp256k1,
                depth: 2,
                hardened_positions: vec![0, 1],
                max_index: 1000,
            },
            DerivationRule {
                derivation_scheme: DerivationScheme::Bip32Secp256k1,
                curve: Curve::Secp256k1,
                depth: 3,
                hardened_positions: vec![0, 1, 2],
                max_index: 1000,
            },
            DerivationRule {
                derivation_scheme: DerivationScheme::Bip32Secp256k1,
                curve: Curve::Secp256k1,
                depth: 5,
                hardened_positions: vec![0, 1, 2],
                max_index: 1000,
            },
        ],
        allow_chain_code: true,
        allow_signing: true,
        allow_storage: false,
    }
}

struct Fixture {
    runtime: Runtime,
    session: SessionId,
}

fn setup() -> Fixture {
    let mut runtime = Runtime::new(
        "vault-a",
        Default::default(),
        Arc::new(CryptoKeys::new()),
        Box::new(NoStorage),
    );
    runtime
        .register_module(Arc::new(BitcoinFactory), &policy())
        .unwrap();
    let (session, _) = runtime.open_app("openledger.bitcoin").unwrap();
    Fixture { runtime, session }
}

fn purpose_path(purpose: u32) -> Vec<u8> {
    let mut out = vec![5u8];
    for component in [0x8000_0000 + purpose, 0x8000_0000, 0x8000_0000, 0, 0] {
        out.extend_from_slice(&component.to_be_bytes());
    }
    out
}

fn bip84_path() -> Vec<u8> {
    purpose_path(84)
}

fn taproot_path() -> Vec<u8> {
    purpose_path(86)
}

fn apdu(ins: u8, data: &[u8]) -> Vec<u8> {
    apdu_flags(ins, 0, 0, data)
}

fn apdu_flags(ins: u8, p1: u8, p2: u8, data: &[u8]) -> Vec<u8> {
    let mut out = vec![0xE1, ins, p1, p2, data.len() as u8];
    out.extend_from_slice(data);
    out
}
fn submit(fixture: &mut Fixture, bytes: Vec<u8>) -> RuntimeReply {
    fixture
        .runtime
        .submit_wire(fixture.session, Wire::LedgerApdu, bytes)
        .unwrap()
}

fn expect_emit(reply: RuntimeReply) -> Vec<u8> {
    match reply {
        RuntimeReply::Emit { payload, .. } => payload,
        other => panic!("expected emit, got {other:?}"),
    }
}

fn expect_review(reply: RuntimeReply) -> ReviewId {
    match reply {
        RuntimeReply::Review { review_id, .. } => review_id,
        other => panic!("expected review, got {other:?}"),
    }
}

fn approve(fixture: &mut Fixture, review_id: ReviewId) -> Vec<u8> {
    expect_emit(
        fixture
            .runtime
            .resolve_review(fixture.session, review_id, ReviewDecision::Approve)
            .unwrap(),
    )
}

fn expected_address(purpose: u32) -> String {
    let seed = open_ledger_crypto::bip39::mnemonic_to_seed(MNEMONIC, "").unwrap();
    open_ledger_biz::btc::derive_address(&seed, &format!("m/{purpose}'/0'/0'/0/0")).unwrap()
}

fn address_of(payload: &[u8]) -> String {
    assert_eq!(&payload[payload.len() - 2..], &[0x90, 0x00]);
    String::from_utf8(payload[..payload.len() - 2].to_vec()).unwrap()
}

// ── 地址：四种类型 ────────────────────────────────────────────────────

#[test]
fn each_p2_format_returns_its_own_address_type() {
    let cases = [
        (P2_LEGACY, 44u32, '1'),
        (P2_P2SH, 49, '3'),
        (P2_BECH32, 84, 'b'),
        (P2_BECH32M, 86, 'b'),
    ];
    for (p2, purpose, prefix) in cases {
        let mut fixture = setup();
        let payload = expect_emit(submit(
            &mut fixture,
            apdu_flags(0x40, 0, p2, &purpose_path(purpose)),
        ));
        let address = address_of(&payload);
        assert!(
            address.starts_with(prefix),
            "p2={p2} address={address}"
        );
        assert_eq!(address, expected_address(purpose), "p2={p2}");
    }
}

#[test]
fn taproot_address_is_bech32m_and_differs_from_segwit_v0() {
    let mut taproot_fixture = setup();
    let taproot = address_of(&expect_emit(submit(
        &mut taproot_fixture,
        apdu_flags(0x40, 0, P2_BECH32M, &taproot_path()),
    )));
    let mut segwit_fixture = setup();
    let segwit = address_of(&expect_emit(submit(
        &mut segwit_fixture,
        apdu_flags(0x40, 0, P2_BECH32, &bip84_path()),
    )));
    assert!(taproot.starts_with("bc1p"), "{taproot}");
    assert!(segwit.starts_with("bc1q"), "{segwit}");
}

#[test]
fn empty_data_uses_the_default_bip84_path() {
    let mut fixture = setup();
    let payload = expect_emit(submit(&mut fixture, apdu_flags(0x40, 0, P2_BECH32, &[])));
    assert_eq!(address_of(&payload), expected_address(84));
}

#[test]
fn cashaddr_format_is_rejected_instead_of_returning_a_wrong_address() {
    let mut fixture = setup();
    assert_eq!(
        expect_emit(submit(&mut fixture, apdu_flags(0x40, 0, 0x03, &bip84_path()))),
        vec![0x6A, 0x80]
    );
}

#[test]
fn display_flag_parks_a_review_then_returns_the_address() {
    let mut fixture = setup();
    let review_id = expect_review(submit(
        &mut fixture,
        apdu_flags(0x40, 1, P2_BECH32M, &taproot_path()),
    ));
    let payload = approve(&mut fixture, review_id);
    assert_eq!(address_of(&payload), expected_address(86));
}

#[test]
fn display_flag_rejection_returns_user_denied() {
    let mut fixture = setup();
    let review_id = expect_review(submit(
        &mut fixture,
        apdu_flags(0x40, 1, P2_BECH32, &bip84_path()),
    ));
    let payload = expect_emit(
        fixture
            .runtime
            .resolve_review(fixture.session, review_id, ReviewDecision::Reject)
            .unwrap(),
    );
    assert_eq!(payload, vec![0x69, 0x85]);
}

#[test]
fn unknown_address_format_is_rejected() {
    let mut fixture = setup();
    assert_eq!(
        expect_emit(submit(&mut fixture, apdu_flags(0x40, 0, 0x09, &bip84_path()))),
        vec![0x6A, 0x80]
    );
}

#[test]
fn p1_above_one_is_rejected() {
    let mut fixture = setup();
    assert_eq!(
        expect_emit(submit(&mut fixture, apdu_flags(0x40, 2, P2_BECH32, &bip84_path()))),
        vec![0x6A, 0x86]
    );
}

// ── 签名：ECDSA ──────────────────────────────────────────────────────

// ── 签名：Taproot ────────────────────────────────────────────────────

// ── 本机账户派生 ─────────────────────────────────────────────────────

fn derive_local_payload(fixture: &mut Fixture, profile: u16, index: u32) -> Vec<u8> {
    let reply = fixture
        .runtime
        .submit_local(
            fixture.session,
            1,
            LocalCommand::DeriveAccount {
                account_profile_index: profile,
                address_index: index,
            },
        )
        .unwrap();
    match reply {
        RuntimeReply::LocalReply { payload, .. } => payload,
        other => panic!("expected local reply, got {other:?}"),
    }
}

fn derive_local(fixture: &mut Fixture, profile: u16, index: u32) -> String {
    let payload = derive_local_payload(fixture, profile, index);
    let text = String::from_utf8(payload).unwrap();
    text.split("\"address\":\"")
        .nth(1)
        .and_then(|rest| rest.split('"').next())
        .expect("address")
        .to_string()
}

#[test]
fn local_derivation_offers_all_four_types_and_keeps_profile_zero_unchanged() {
    // profile 0 必须是升级前的 P2WPKH，否则老账户地址会变。
    let expected = [84u32, 44, 49, 86];
    for (profile, purpose) in expected.iter().enumerate() {
        let mut fixture = setup();
        let address = derive_local(&mut fixture, profile as u16, 0);
        assert_eq!(address, expected_address(*purpose), "profile {profile}");
    }
}

#[test]
fn local_derivation_uses_the_address_index_segment() {
    let mut fixture = setup();
    let address = derive_local(&mut fixture, 0, 3);
    let seed = open_ledger_crypto::bip39::mnemonic_to_seed(MNEMONIC, "").unwrap();
    let expected = open_ledger_biz::btc::derive_address(&seed, "m/84'/0'/0'/0/3").unwrap();
    assert_eq!(address, expected);
}

#[test]
fn unknown_account_profile_is_rejected() {
    let mut fixture = setup();
    assert!(derive_local_payload(&mut fixture, 9, 0).is_empty());
}

// ── 其它 ─────────────────────────────────────────────────────────────

#[test]
fn unknown_ins_is_rejected() {
    let mut fixture = setup();
    assert_eq!(
        expect_emit(submit(&mut fixture, apdu(0x99, &[]))),
        vec![0x6D, 0x00]
    );
}

// ── 网络：P2 高 4 位 ──────────────────────────────────────────────────

/// 高 4 位网络 / 低 4 位地址格式，见 ADR-020 的落地修订。
const NET_MAINNET: u8 = 0x00;
const NET_TESTNET: u8 = 0x10;
const NET_REGTEST: u8 = 0x20;

fn address_for_network(p2: u8, path: &[u8]) -> String {
    let mut fixture = setup();
    address_of(&expect_emit(submit(
        &mut fixture,
        apdu_flags(0x40, 0, p2, path),
    )))
}

/// 同一把密钥、同一条路径，只换网络位：三段 bech32 的 witness program 必须一致。
#[test]
fn network_nibble_only_changes_the_bech32_hrp() {
    let mainnet = address_for_network(NET_MAINNET | P2_BECH32, &bip84_path());
    let testnet = address_for_network(NET_TESTNET | P2_BECH32, &bip84_path());
    let regtest = address_for_network(NET_REGTEST | P2_BECH32, &bip84_path());

    assert!(mainnet.starts_with("bc1q"), "{mainnet}");
    assert!(testnet.starts_with("tb1q"), "{testnet}");
    assert!(regtest.starts_with("bcrt1q"), "{regtest}");

    // 去掉 hrp 与 6 字符校验和（校验和本身依赖 hrp），剩下的 witness program 必须一致。
    let program = |address: &str| {
        let start = address.find('1').unwrap() + 1;
        address[start..address.len() - 6].to_string()
    };
    assert_eq!(program(&mainnet), program(&testnet));
    assert_eq!(program(&mainnet), program(&regtest));
}

#[test]
fn network_nibble_changes_the_base58_prefixes_too() {
    let mainnet = address_for_network(NET_MAINNET | P2_LEGACY, &bip84_path());
    let testnet = address_for_network(NET_TESTNET | P2_LEGACY, &bip84_path());
    assert!(mainnet.starts_with('1'), "{mainnet}");
    assert!(
        testnet.starts_with('m') || testnet.starts_with('n'),
        "{testnet}"
    );

    let mainnet_nested = address_for_network(NET_MAINNET | P2_P2SH, &bip84_path());
    let testnet_nested = address_for_network(NET_TESTNET | P2_P2SH, &bip84_path());
    assert!(mainnet_nested.starts_with('3'), "{mainnet_nested}");
    assert!(testnet_nested.starts_with('2'), "{testnet_nested}");
}

#[test]
fn default_path_uses_the_network_coin_type() {
    // 空数据 + regtest 必须落在 m/84'/1'/0'/0/0，而不是主网的 0'。
    let mut implicit = setup();
    let implicit = address_of(&expect_emit(submit(
        &mut implicit,
        apdu_flags(0x40, 0, NET_REGTEST | P2_BECH32, &[]),
    )));
    let mut explicit = setup();
    let mut path = vec![5u8];
    for component in [0x8000_0054u32, 0x8000_0001, 0x8000_0000, 0, 0] {
        path.extend_from_slice(&component.to_be_bytes());
    }
    let explicit = address_of(&expect_emit(submit(
        &mut explicit,
        apdu_flags(0x40, 0, NET_REGTEST | P2_BECH32, &path),
    )));
    assert_eq!(implicit, explicit);
}

#[test]
fn unknown_network_bits_are_rejected() {
    let mut fixture = setup();
    assert_eq!(
        expect_emit(submit(
            &mut fixture,
            apdu_flags(0x40, 0, 0x42, &bip84_path())
        )),
        vec![0x6A, 0x86]
    );
}

#[test]
fn review_document_names_the_selected_network() {
    let mut fixture = setup();
    let reply = submit(
        &mut fixture,
        apdu_flags(0x40, 1, NET_REGTEST | P2_BECH32, &bip84_path()),
    );
    let document = match reply {
        RuntimeReply::Review { document, .. } => document,
        other => panic!("expected review, got {other:?}"),
    };
    assert_eq!(document.network.name, "Bitcoin Regtest");
    match &document.sections[0].fields[0].value {
        FieldValue::Address { network, .. } => assert_eq!(network, "Bitcoin Regtest"),
        other => panic!("expected address field, got {other:?}"),
    }
}

// ── 官方 2.1.0+ 的 xpub / 主指纹 ──────────────────────────────────────

fn derive_extended(path: &str) -> (Vec<u8>, [u8; 32]) {
    open_ledger_biz::hdkey::derive_secp256k1_extended(&CryptoKeys::new().seed, path).unwrap()
}

#[test]
fn master_fingerprint_matches_the_independent_derivation() {
    let mut fixture = setup();
    let payload = expect_emit(submit(&mut fixture, apdu_flags(0x05, 0, 1, &[])));
    let (private_key, _) = derive_extended("m");
    let pubkey = open_ledger_crypto::secp256k1::public_key_bytes(&private_key, true).unwrap();
    let mut expected = open_ledger_crypto::hash160::hash(&pubkey)[..4].to_vec();
    expected.extend_from_slice(&[0x90, 0x00]);
    assert_eq!(payload, expected, "payload={payload:02x?} expected={expected:02x?}");

    // 非空数据不是合法的 GET_MASTER_FINGERPRINT。
    let mut fixture = setup();
    assert_eq!(
        expect_emit(submit(&mut fixture, apdu_flags(0x05, 0, 1, &[0u8]))),
        vec![0x6A, 0x86]
    );
}

#[test]
fn extended_pubkey_serializes_the_account_key_and_chain_code() {
    // `[display=0][count=3][84'/1'/0']`
    let mut data = vec![0u8, 3];
    for component in [0x8000_0054u32, 0x8000_0001, 0x8000_0000] {
        data.extend_from_slice(&component.to_be_bytes());
    }
    let mut fixture = setup();
    let payload = expect_emit(submit(&mut fixture, apdu_flags(0x00, 0, 1, &data)));
    let text = std::str::from_utf8(&payload[..payload.len() - 2]).unwrap();

    let (private_key, chain_code) = derive_extended("m/84'/1'/0'");
    let pubkey = open_ledger_crypto::secp256k1::public_key_bytes(&private_key, true).unwrap();
    let (parent_key, _) = derive_extended("m/84'/1'");
    let parent = open_ledger_crypto::secp256k1::public_key_bytes(&parent_key, true).unwrap();

    let mut body = 0x0435_87CFu32.to_be_bytes().to_vec(); // tpub
    body.push(3);
    body.extend_from_slice(&open_ledger_crypto::hash160::hash(&parent)[..4]);
    body.extend_from_slice(&0x8000_0000u32.to_be_bytes());
    body.extend_from_slice(&chain_code);
    body.extend_from_slice(&pubkey);
    assert_eq!(text, open_ledger_crypto::base58::encode_check(&body), "device={text} expected={}", open_ledger_crypto::base58::encode_check(&body));

    // 主网账户（coin type 0'）必须是 xpub 版本。
    let mut data = vec![0u8, 3];
    for component in [0x8000_0054u32, 0x8000_0000, 0x8000_0000] {
        data.extend_from_slice(&component.to_be_bytes());
    }
    let mut fixture = setup();
    let payload = expect_emit(submit(&mut fixture, apdu_flags(0x00, 0, 1, &data)));
    let text = std::str::from_utf8(&payload[..payload.len() - 2]).unwrap();
    assert!(text.starts_with("xpub"), "{text}");

    // 结构不合法：长度与 count 不符。
    let mut fixture = setup();
    assert_eq!(
        expect_emit(submit(&mut fixture, apdu_flags(0x00, 0, 1, &[0u8, 2, 0, 0, 0, 0]))),
        vec![0x6A, 0x80]
    );
}

// ── 协议口径：非标准实现必须是「显式的非标准」 ────────────────────────

/// 官方现行 app（`LedgerHQ/app-bitcoin` 2.1.0+，CLA `0xE1`）的命令编号：
/// `0x00` GET_EXTENDED_PUBKEY、`0x02` REGISTER_WALLET、`0x03` GET_WALLET_ADDRESS、
/// `0x04` SIGN_PSBT、`0x05` GET_MASTER_FINGERPRINT、`0x10` SIGN_MESSAGE。
///
/// 这些编号**不得**被赋予别的语义。实现某条官方命令时，把它从「必须拒绝」
/// 的名单里移走并补上官方语义的用例 —— 这就是防协议漂移的闸门。
#[test]
fn official_bitcoin_commands_are_not_silently_reinterpreted() {
    // `0x04 SIGN_PSBT` / `0x00 GET_EXTENDED_PUBKEY` / `0x05 GET_MASTER_FINGERPRINT`
    // 已按官方语义实现；其余官方编号仍必须拒绝。`0x44` 在 legacy app 里是
    // `HASH_INPUT_START`，现行 app 未分配——无论哪种，都不得被我们的实现接管。
    for ins in [0x02u8, 0x03, 0x10, 0x44] {
        let mut fixture = setup();
        assert_eq!(
            expect_emit(submit(&mut fixture, apdu(ins, &[]))),
            vec![0x6D, 0x00],
            "INS 0x{ins:02X} 属于官方 2.1.0+ 协议，不能被我们的实现接管"
        );
    }
    // `0x04` 只接受协议版本 1，且数据必须能解析；否则 6A80/6A86，而不是 6D00。
    let mut fixture = setup();
    assert_eq!(
        expect_emit(submit(&mut fixture, apdu_flags(0x04, 0, 0, &[]))),
        vec![0x6A, 0x86]
    );
    let mut fixture = setup();
    assert_eq!(
        expect_emit(submit(&mut fixture, apdu_flags(0x04, 0, 1, &[]))),
        vec![0x6A, 0x80]
    );
}
