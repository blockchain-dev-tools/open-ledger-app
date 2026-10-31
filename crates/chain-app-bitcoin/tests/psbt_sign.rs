//! M2 验收：现行 `E1 04 SIGN_PSBT` 的完整多轮交互。
//!
//! 这里有一台「独立主机」：它自己构造 PSBTv2、自己算 Merkle 树、按官方
//! `client_command` 规范回答 `0xE000`，最后用 k256 + 自己算的 BIP-143 摘要
//! 独立验签。设备侧只拿到 Merkle 化摘要，所有字段都必须反向请求——这条用例
//! 通过才说明协议对齐，而不是自洽。

use std::collections::HashMap;
use std::sync::Arc;

use chain_app_api::*;
use chain_app_bitcoin::BitcoinFactory;
use chain_app_runtime::{ReviewDecision, Runtime, RuntimeReply};
use open_ledger_crypto::{bip39, hash160, secp256k1, sha256, sha256d};

const MNEMONIC: &str =
    "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";

fn seed() -> Vec<u8> {
    bip39::mnemonic_to_seed(MNEMONIC, "").unwrap().to_vec()
}

fn pubkey_at(path: &str) -> Vec<u8> {
    let private = open_ledger_biz::hdkey::derive_secp256k1_private_key(&seed(), path).unwrap();
    secp256k1::public_key_bytes(&private, true).unwrap()
}

fn p2wpkh_script(pubkey: &[u8]) -> Vec<u8> {
    let mut script = vec![0x00, 0x14];
    script.extend_from_slice(&hash160::hash(pubkey));
    script
}

// ── Merkle（官方左完全树） ──────────────────────────────────────────────

fn element_hash(element: &[u8]) -> [u8; 32] {
    let mut buffer = vec![0x00];
    buffer.extend_from_slice(element);
    sha256::hash(&buffer)
}

fn combine(left: &[u8; 32], right: &[u8; 32]) -> [u8; 32] {
    let mut buffer = vec![0x01];
    buffer.extend_from_slice(left);
    buffer.extend_from_slice(right);
    sha256::hash(&buffer)
}

fn largest_power_of_two_less_than(n: usize) -> usize {
    if n.is_power_of_two() {
        n / 2
    } else {
        1 << (usize::BITS as usize - 1 - n.leading_zeros() as usize)
    }
}

fn root_of(leaves: &[[u8; 32]], begin: usize, size: usize) -> [u8; 32] {
    if size == 1 {
        return leaves[begin];
    }
    let left = largest_power_of_two_less_than(size);
    combine(
        &root_of(leaves, begin, left),
        &root_of(leaves, begin + left, size - left),
    )
}

fn proof_of(leaves: &[[u8; 32]], begin: usize, size: usize, index: usize) -> Vec<[u8; 32]> {
    if size == 1 {
        return Vec::new();
    }
    let left = largest_power_of_two_less_than(size);
    if index < left {
        let mut proof = proof_of(leaves, begin, left, index);
        proof.push(root_of(leaves, begin + left, size - left));
        proof
    } else {
        let mut proof = proof_of(leaves, begin + left, size - left, index - left);
        proof.push(root_of(leaves, begin, left));
        proof
    }
}

// ── PSBTv2 构造 ─────────────────────────────────────────────────────────

fn varint(value: u64) -> Vec<u8> {
    let mut out = Vec::new();
    match value {
        0..=0xFC => out.push(value as u8),
        0xFD..=0xFFFF => {
            out.push(0xFD);
            out.extend_from_slice(&(value as u16).to_le_bytes());
        }
        _ => {
            out.push(0xFE);
            out.extend_from_slice(&(value as u32).to_le_bytes());
        }
    }
    out
}

struct MapBuilder(Vec<(Vec<u8>, Vec<u8>)>);

impl MapBuilder {
    fn new() -> Self {
        Self(Vec::new())
    }

    fn put(mut self, key: &[u8], value: Vec<u8>) -> Self {
        self.0.push((key.to_vec(), value));
        self
    }
}

// ── 独立主机 ────────────────────────────────────────────────────────────

struct Host {
    preimages: HashMap<[u8; 32], Vec<u8>>,
    trees: HashMap<[u8; 32], Vec<[u8; 32]>>,
    queue: Vec<Vec<u8>>,
    yielded: Vec<Vec<u8>>,
    requests: usize,
    log: Vec<Vec<u8>>,
}

impl Host {
    fn new() -> Self {
        Self {
            preimages: HashMap::new(),
            trees: HashMap::new(),
            queue: Vec::new(),
            yielded: Vec::new(),
            requests: 0,
            log: Vec::new(),
        }
    }

    fn add_preimage(&mut self, element: &[u8]) {
        self.preimages.insert(sha256::hash(element), element.to_vec());
    }

    fn add_list(&mut self, elements: &[Vec<u8>]) -> [u8; 32] {
        for element in elements {
            let mut prefixed = vec![0x00];
            prefixed.extend_from_slice(element);
            self.preimages.insert(sha256::hash(&prefixed), prefixed);
        }
        let leaves: Vec<[u8; 32]> = elements.iter().map(|el| element_hash(el)).collect();
        let root = root_of(&leaves, 0, leaves.len());
        self.trees.insert(root, leaves);
        root
    }

    /// 返回 `[varint(size)][keys root][values root]`。
    fn add_map(&mut self, map: &MapBuilder) -> Vec<u8> {
        let mut sorted = map.0.clone();
        sorted.sort_by(|a, b| a.0.cmp(&b.0));
        let keys: Vec<Vec<u8>> = sorted.iter().map(|(k, _)| k.clone()).collect();
        let values: Vec<Vec<u8>> = sorted.iter().map(|(_, v)| v.clone()).collect();
        let keys_root = self.add_list(&keys);
        let values_root = self.add_list(&values);
        let mut out = varint(sorted.len() as u64);
        out.extend_from_slice(&keys_root);
        out.extend_from_slice(&values_root);
        out
    }

    fn answer(&mut self, request: &[u8]) -> Vec<u8> {
        self.requests += 1;
        self.log.push(request.to_vec());
        match request[0] {
            0x40 => {
                let hash: [u8; 32] = request[2..34].try_into().unwrap();
                let preimage = self
                    .preimages
                    .get(&hash)
                    .unwrap_or_else(|| panic!("unknown preimage {}", hex::encode(hash)))
                    .clone();
                let len_prefix = varint(preimage.len() as u64);
                let max = 255 - len_prefix.len() - 1;
                let sent = preimage.len().min(max);
                let mut out = len_prefix;
                out.push(sent as u8);
                out.extend_from_slice(&preimage[..sent]);
                if sent < preimage.len() {
                    for byte in &preimage[sent..] {
                        self.queue.push(vec![*byte]);
                    }
                }
                out
            }
            0x41 => {
                let root: [u8; 32] = request[1..33].try_into().unwrap();
                let mut cursor = 33;
                let read = |cursor: &mut usize| -> u64 {
                    let first = request[*cursor];
                    *cursor += 1;
                    match first {
                        0xFD => {
                            let value =
                                u16::from_le_bytes([request[*cursor], request[*cursor + 1]]);
                            *cursor += 2;
                            value as u64
                        }
                        0xFE => {
                            let value =
                                u32::from_le_bytes(request[*cursor..*cursor + 4].try_into().unwrap());
                            *cursor += 4;
                            value as u64
                        }
                        value => value as u64,
                    }
                };
                let size = read(&mut cursor) as usize;
                let index = read(&mut cursor) as usize;
                let leaves = self
                    .trees
                    .get(&root)
                    .unwrap_or_else(|| panic!("unknown tree {}", hex::encode(root)));
                assert_eq!(leaves.len(), size);
                let proof = proof_of(leaves, 0, size, index);
                let mut out = leaves[index].to_vec();
                out.push(proof.len() as u8);
                out.push(proof.len() as u8);
                for node in proof {
                    out.extend_from_slice(&node);
                }
                out
            }
            0xA0 => {
                let element_len = self.queue.first().map(|el| el.len()).unwrap_or(0);
                let mut out = vec![0u8, element_len as u8];
                let mut count = 0u8;
                while !self.queue.is_empty() && out.len() + element_len <= 253 {
                    out.extend_from_slice(&self.queue.remove(0));
                    count += 1;
                }
                out[0] = count;
                out
            }
            0x10 => {
                self.yielded.push(request[1..].to_vec());
                Vec::new()
            }
            other => panic!("unexpected client command 0x{other:02x}"),
        }
    }
}

// ── 运行时夹具 ──────────────────────────────────────────────────────────

struct CryptoKeys {
    seed: Vec<u8>,
}

impl CryptoKeys {
    fn private_key_at(&self, path: &[u32]) -> Vec<u8> {
        let mut text = String::from("m");
        for component in path {
            if *component >= 0x8000_0000 {
                text.push_str(&format!("/{}'", component - 0x8000_0000));
            } else {
                text.push_str(&format!("/{component}"));
            }
        }
        open_ledger_biz::hdkey::derive_secp256k1_private_key(&self.seed, &text).unwrap()
    }
}

impl KeyService for CryptoKeys {
    fn public_key(&self, request: &PublicKeyRequest) -> Result<PublicKey, HostError> {
        let private = self.private_key_at(&request.path);
        let bytes = secp256k1::public_key_bytes(&private, true)
            .map_err(|e| HostError::Unavailable(e.to_string()))?;
        Ok(PublicKey {
            bytes,
            chain_code: None,
        })
    }

    fn sign(
        &self,
        _auth: &SignAuthorization,
        operation: &SignOperation,
    ) -> Result<Signature, HostError> {
        let private = self.private_key_at(&operation.path);
        if operation.input.len() != 32 {
            return Err(HostError::Denied("expected a 32-byte sighash".into()));
        }
        let mut digest = [0u8; 32];
        digest.copy_from_slice(&operation.input);
        let signature = secp256k1::sign_prehash_recoverable(&private, &digest, |v| v)
            .map_err(|e| HostError::Unavailable(e.to_string()))?;
        Ok(Signature {
            operation_id: operation.operation_id,
            bytes: signature[1..65].to_vec(),
            recovery_id: Some(signature[0]),
        })
    }
}

/// taproot key-path：宿主负责 tweak，并在非 DEFAULT 时追加 hash_type。
struct TaprootKeys {
    seed: Vec<u8>,
}

impl KeyService for TaprootKeys {
    fn public_key(&self, request: &PublicKeyRequest) -> Result<PublicKey, HostError> {
        let private = CryptoKeys {
            seed: self.seed.clone(),
        }
        .private_key_at(&request.path);
        Ok(PublicKey {
            bytes: secp256k1::public_key_bytes(&private, true)
                .map_err(|e| HostError::Unavailable(e.to_string()))?,
            chain_code: None,
        })
    }

    fn sign(
        &self,
        _auth: &SignAuthorization,
        operation: &SignOperation,
    ) -> Result<Signature, HostError> {
        let private = CryptoKeys {
            seed: self.seed.clone(),
        }
        .private_key_at(&operation.path);
        match operation.scheme {
            SignScheme::SchnorrTaprootKeyPath { hash_type } => {
                let mut message = operation.input.clone();
                if hash_type != 0 {
                    message.push(hash_type);
                }
                Ok(Signature {
                    operation_id: operation.operation_id,
                    bytes: secp256k1::schnorr_sign_taproot(&private, &message)
                        .map_err(|e| HostError::Unavailable(e.to_string()))?,
                    recovery_id: None,
                })
            }
            SignScheme::EcdsaPrehash { .. } => CryptoKeys {
                seed: self.seed.clone(),
            }
            .sign(_auth, operation),
            _ => Err(HostError::Denied("unexpected scheme".into())),
        }
    }
}

struct NoStorage;

impl StorageService for NoStorage {
    fn read(&mut self, _: &StorageScope, _: &str) -> Result<Option<Vec<u8>>, HostError> {
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
        derivation_rules: vec![DerivationRule {
            derivation_scheme: DerivationScheme::Bip32Secp256k1,
            curve: Curve::Secp256k1,
            depth: 5,
            hardened_positions: vec![0, 1, 2],
            max_index: 1000,
        }],
        allow_chain_code: false,
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
        Arc::new(CryptoKeys { seed: seed() }),
        Box::new(NoStorage),
    );
    runtime
        .register_module(Arc::new(BitcoinFactory), &policy())
        .unwrap();
    let (session, _) = runtime.open_app("openledger.bitcoin").unwrap();
    Fixture { runtime, session }
}

/// 收到 `0xE000` 就按官方格式回答，直到流程给出审阅或终态。
fn pump(fixture: &mut Fixture, host: &mut Host, mut reply: RuntimeReply) -> RuntimeReply {
    loop {
        match reply {
            RuntimeReply::Emit {
                exchange_id,
                payload,
                ..
            } => {
                if !payload.ends_with(&[0xE0, 0x00]) {
                    return RuntimeReply::Emit {
                        wire: Wire::LedgerApdu,
                        exchange_id,
                        payload,
                        state: OperationState::Final,
                    };
                }
                let next = fixture
                    .runtime
                    .delivery_result(fixture.session, exchange_id, DeliveryAck::Acknowledged)
                    .unwrap();
                assert!(
                    matches!(next, RuntimeReply::AwaitInput),
                    "等待主机时必须挂起，实际 {next:?}（payload={}）",
                    hex::encode(&payload)
                );
                let request = &payload[..payload.len() - 2];
                let response = host.answer(request);
                assert!(response.len() < 256, "CONTINUE 数据超过 255 字节");
                let mut apdu = vec![0xF8, 0x01, 0x00, 0x01, response.len() as u8];
                apdu.extend_from_slice(&response);
                reply = fixture
                    .runtime
                    .submit_wire(fixture.session, Wire::LedgerApdu, apdu)
                    .unwrap();
            }
            other => return other,
        }
    }
}

fn path_bytes(path: &[u32]) -> Vec<u8> {
    let mut out = Vec::new();
    for component in path {
        // BIP-174：`bip32_derivation` 里的路径分量是小端。
        out.extend_from_slice(&component.to_le_bytes());
    }
    out
}

fn derivation_value(path: &[u32]) -> Vec<u8> {
    let mut out = vec![0x73, 0xC5, 0xDA, 0x0A];
    out.extend(path_bytes(path));
    out
}

/// 独立实现的 BIP-143 摘要（单输入、SIGHASH_ALL，多输出）。
fn bip143_digest(
    script_code: &[u8],
    amount: u64,
    outputs: &[(u64, Vec<u8>)],
    txid: [u8; 32],
    vout: u32,
    sequence: u32,
    lock_time: u32,
) -> [u8; 32] {
    let mut prevouts = txid.to_vec();
    prevouts.extend(vout.to_le_bytes());
    let sequences = sequence.to_le_bytes().to_vec();
    let mut out_ser = Vec::new();
    for (value, script) in outputs {
        out_ser.extend(value.to_le_bytes());
        out_ser.extend(varint(script.len() as u64));
        out_ser.extend_from_slice(script);
    }
    let mut preimage = 2u32.to_le_bytes().to_vec();
    preimage.extend(sha256d::hash(&prevouts));
    preimage.extend(sha256d::hash(&sequences));
    preimage.extend(prevouts);
    preimage.extend(varint(script_code.len() as u64));
    preimage.extend_from_slice(script_code);
    preimage.extend(amount.to_le_bytes());
    preimage.extend(sequence.to_le_bytes());
    preimage.extend(sha256d::hash(&out_ser));
    preimage.extend(lock_time.to_le_bytes());
    preimage.extend(1u32.to_le_bytes()); // SIGHASH_ALL
    sha256d::hash(&preimage)
}

#[test]
fn sign_psbt_p2wpkh_yields_a_signature_over_the_independently_computed_sighash() {
    let mut fixture = setup();
    let mut host = Host::new();

    let spend_pubkey = pubkey_at("m/84'/0'/0'/0/0");
    let change_pubkey = pubkey_at("m/84'/0'/0'/1/0");

    let mut witness_utxo = 100_000u64.to_le_bytes().to_vec();
    witness_utxo.extend(varint(22));
    witness_utxo.extend_from_slice(&p2wpkh_script(&spend_pubkey));

    let input_map = MapBuilder::new()
        .put(&[0x0E], vec![0x11; 32])
        .put(&[0x0F], 0u32.to_le_bytes().to_vec())
        .put(&[0x10], 0xFFFF_FFFDu32.to_le_bytes().to_vec())
        .put(&[0x01], witness_utxo)
        .put(
            &[&[0x06u8][..], &spend_pubkey[..]].concat(),
            derivation_value(&[0x8000_0000 + 84, 0x8000_0000, 0x8000_0000, 0, 0]),
        );

    let recipient_script = p2wpkh_script(&pubkey_at("m/84'/0'/0'/0/7"));
    let output_paid = MapBuilder::new()
        .put(&[0x03], 60_000u64.to_le_bytes().to_vec())
        .put(&[0x04], recipient_script.clone());
    let output_change = MapBuilder::new()
        .put(&[0x03], 30_000u64.to_le_bytes().to_vec())
        .put(&[0x04], p2wpkh_script(&change_pubkey))
        .put(
            &[&[0x02u8][..], &change_pubkey[..]].concat(),
            derivation_value(&[0x8000_0000 + 84, 0x8000_0000, 0x8000_0000, 1, 0]),
        );

    let global = MapBuilder::new()
        .put(&[0x02], 2u32.to_le_bytes().to_vec())
        .put(&[0x03], 0u32.to_le_bytes().to_vec())
        .put(&[0x04], varint(1))
        .put(&[0x05], varint(2))
        .put(&[0xFB], 2u32.to_le_bytes().to_vec());

    // —— 用主机自己的数据结构拼出 SIGN_PSBT 的摘要 ——
    let global_commitment = host.add_map(&global);
    let input_commitment = host.add_map(&input_map);
    let paid_commitment = host.add_map(&output_paid);
    let change_commitment = host.add_map(&output_change);
    let inputs_root = host.add_list(std::slice::from_ref(&input_commitment));
    let outputs_root = host.add_list(&[paid_commitment, change_commitment]);

    let template = b"wpkh(@0/**)".to_vec();
    host.add_preimage(&template);
    let key_info = b"[73c5da0a/84'/0'/0']xpub6CatWdiZiodmUeTDp8LT5or8nmbKNcuyvz7WyksVFkKB4RHwCD3XyuvPEbvqAQY3rAPshWcMLoP2fMFMKHPJ4ZeZXYVUhLv1VMrjPC7PW6V".to_vec();
    let keys_root = host.add_list(std::slice::from_ref(&key_info));

    let mut policy_bytes = vec![0x02, 0x00];
    policy_bytes.extend(varint(template.len() as u64));
    policy_bytes.extend_from_slice(&sha256::hash(&template));
    policy_bytes.extend(varint(1));
    policy_bytes.extend_from_slice(&keys_root);
    host.add_preimage(&policy_bytes);
    let wallet_id = sha256::hash(&policy_bytes);

    let mut data = global_commitment;
    data.extend(varint(1));
    data.extend_from_slice(&inputs_root);
    data.extend(varint(2));
    data.extend_from_slice(&outputs_root);
    data.extend_from_slice(&wallet_id);
    data.extend_from_slice(&[0u8; 32]);

    let mut apdu = vec![0xE1, 0x04, 0x00, 0x01, data.len() as u8];
    apdu.extend_from_slice(&data);

    let reply = fixture
        .runtime
        .submit_wire(fixture.session, Wire::LedgerApdu, apdu)
        .unwrap();
    let reply = pump(&mut fixture, &mut host, reply);

    let review_id = match reply {
        RuntimeReply::Review { review_id, .. } => review_id,
        other => panic!(
            "expected review, got {other:?} after {} requests: {:?}",
            host.requests,
            host.log
                .iter()
                .map(|request| hex::encode(request))
                .collect::<Vec<_>>()
        ),
    };

    let first = fixture
        .runtime
        .resolve_review(fixture.session, review_id, ReviewDecision::Approve)
        .unwrap();
    match pump(&mut fixture, &mut host, first) {
        RuntimeReply::Emit { payload, .. } => assert_eq!(payload, vec![0x90, 0x00]),
        other => panic!("expected final 9000, got {other:?}"),
    }

    assert_eq!(host.yielded.len(), 1, "只有一个属于本钱包的输入");
    let yielded = &host.yielded[0];
    assert_eq!(yielded[0], 0x00, "input_index = 0");
    assert_eq!(yielded[1], 33);
    assert_eq!(&yielded[2..35], &spend_pubkey[..]);
    assert_eq!(*yielded.last().unwrap(), 0x01, "SIGHASH_ALL");

    let der = &yielded[35..yielded.len() - 1];
    let verifying_key = k256::ecdsa::VerifyingKey::from_sec1_bytes(&spend_pubkey).unwrap();
    let signature = k256::ecdsa::Signature::from_der(der).unwrap();

    // 主机独立算出的 BIP-143 摘要（scriptCode = P2PKH 形态的 P2WPKH）。
    let mut script_code = vec![0x19, 0x76, 0xA9, 0x14];
    script_code.extend_from_slice(&hash160::hash(&spend_pubkey));
    script_code.extend_from_slice(&[0x88, 0xAC]);
    let digest = bip143_digest(
        &script_code[1..],
        100_000,
        &[
            (60_000, recipient_script),
            (30_000, p2wpkh_script(&change_pubkey)),
        ],
        [0x11; 32],
        0,
        0xFFFF_FFFD,
        0,
    );
    use k256::ecdsa::signature::hazmat::PrehashVerifier;
    verifying_key
        .verify_prehash(&digest, &signature)
        .expect("设备签名必须能对独立算出的 BIP-143 摘要验签");
}

// ── taproot key-path ────────────────────────────────────────────────────

fn p2tr_script(pubkey: &[u8]) -> Vec<u8> {
    let output = secp256k1::taproot_output_key(&pubkey[1..]).unwrap();
    let mut script = vec![0x51, 0x20];
    script.extend_from_slice(&output);
    script
}

fn setup_taproot() -> Fixture {
    let mut runtime = Runtime::new(
        "vault-a",
        Default::default(),
        Arc::new(TaprootKeys { seed: seed() }),
        Box::new(NoStorage),
    );
    runtime
        .register_module(Arc::new(BitcoinFactory), &policy())
        .unwrap();
    let (session, _) = runtime.open_app("openledger.bitcoin").unwrap();
    Fixture { runtime, session }
}

/// 独立实现的 BIP-341 key-path 摘要（单输入、DEFAULT / ALL）。
fn bip341_digest(
    prevout: (u64, Vec<u8>),
    outputs: &[(u64, Vec<u8>)],
    txid: [u8; 32],
    vout: u32,
    sequence: u32,
    hash_type: u8,
) -> [u8; 32] {
    let mut prevout_bytes = txid.to_vec();
    prevout_bytes.extend(vout.to_le_bytes());
    let amounts = prevout.0.to_le_bytes().to_vec();
    let mut scripts = varint(prevout.1.len() as u64);
    scripts.extend_from_slice(&prevout.1);
    let sequences = sequence.to_le_bytes().to_vec();
    let mut out_ser = Vec::new();
    for (value, script) in outputs {
        out_ser.extend(value.to_le_bytes());
        out_ser.extend(varint(script.len() as u64));
        out_ser.extend_from_slice(script);
    }
    let body = [
        vec![hash_type],
        2u32.to_le_bytes().to_vec(),
        0u32.to_le_bytes().to_vec(),
        sha256::hash(&prevout_bytes).to_vec(),
        sha256::hash(&amounts).to_vec(),
        sha256::hash(&scripts).to_vec(),
        sha256::hash(&sequences).to_vec(),
        sha256::hash(&out_ser).to_vec(),
        vec![0x00],
        0u32.to_le_bytes().to_vec(),
    ]
    .concat();
    secp256k1::tagged_hash("TapSighash", &[&[0x00], &body])
}

#[test]
fn sign_psbt_taproot_yields_a_bip340_signature() {
    let mut fixture = setup_taproot();
    let mut host = Host::new();

    let spend_pubkey = pubkey_at("m/86'/0'/0'/0/0");
    let change_pubkey = pubkey_at("m/86'/0'/0'/1/0");
    let spend_script = p2tr_script(&spend_pubkey);

    let mut witness_utxo = 120_000u64.to_le_bytes().to_vec();
    witness_utxo.extend(varint(spend_script.len() as u64));
    witness_utxo.extend_from_slice(&spend_script);

    let input_map = MapBuilder::new()
        .put(&[0x0E], vec![0x22; 32])
        .put(&[0x0F], 1u32.to_le_bytes().to_vec())
        .put(&[0x10], 0xFFFF_FFFDu32.to_le_bytes().to_vec())
        .put(&[0x01], witness_utxo)
        .put(
            &[&[0x06u8][..], &spend_pubkey[..]].concat(),
            derivation_value(&[0x8000_0000 + 86, 0x8000_0000, 0x8000_0000, 0, 0]),
        );

    let recipient_script = p2wpkh_script(&pubkey_at("m/84'/0'/0'/0/9"));
    let output_paid = MapBuilder::new()
        .put(&[0x03], 70_000u64.to_le_bytes().to_vec())
        .put(&[0x04], recipient_script.clone());
    let change_script = p2tr_script(&change_pubkey);
    let output_change = MapBuilder::new()
        .put(&[0x03], 40_000u64.to_le_bytes().to_vec())
        .put(&[0x04], change_script.clone())
        .put(
            &[&[0x02u8][..], &change_pubkey[..]].concat(),
            derivation_value(&[0x8000_0000 + 86, 0x8000_0000, 0x8000_0000, 1, 0]),
        );

    let global = MapBuilder::new()
        .put(&[0x02], 2u32.to_le_bytes().to_vec())
        .put(&[0x03], 0u32.to_le_bytes().to_vec())
        .put(&[0x04], varint(1))
        .put(&[0x05], varint(2))
        .put(&[0xFB], 2u32.to_le_bytes().to_vec());

    let global_commitment = host.add_map(&global);
    let input_commitment = host.add_map(&input_map);
    let paid_commitment = host.add_map(&output_paid);
    let change_commitment = host.add_map(&output_change);
    let inputs_root = host.add_list(std::slice::from_ref(&input_commitment));
    let outputs_root = host.add_list(&[paid_commitment, change_commitment]);

    let template = b"tr(@0/**)".to_vec();
    host.add_preimage(&template);
    let key_info = b"[73c5da0a/86'/0'/0']xpub6CatWdiZiodmUeTDp8LT5or8nmbKNcuyvz7WyksVFkKB4RHwCD3XyuvPEbvqAQY3rAPshWcMLoP2fMFMKHPJ4ZeZXYVUhLv1VMrjPC7PW6V".to_vec();
    let keys_root = host.add_list(std::slice::from_ref(&key_info));

    let mut policy_bytes = vec![0x02, 0x00];
    policy_bytes.extend(varint(template.len() as u64));
    policy_bytes.extend_from_slice(&sha256::hash(&template));
    policy_bytes.extend(varint(1));
    policy_bytes.extend_from_slice(&keys_root);
    host.add_preimage(&policy_bytes);
    let wallet_id = sha256::hash(&policy_bytes);

    let mut data = global_commitment;
    data.extend(varint(1));
    data.extend_from_slice(&inputs_root);
    data.extend(varint(2));
    data.extend_from_slice(&outputs_root);
    data.extend_from_slice(&wallet_id);
    data.extend_from_slice(&[0u8; 32]);

    let mut apdu = vec![0xE1, 0x04, 0x00, 0x01, data.len() as u8];
    apdu.extend_from_slice(&data);

    let reply = fixture
        .runtime
        .submit_wire(fixture.session, Wire::LedgerApdu, apdu)
        .unwrap();
    let review_id = match pump(&mut fixture, &mut host, reply) {
        RuntimeReply::Review { review_id, .. } => review_id,
        other => panic!("expected review, got {other:?}"),
    };
    let first = fixture
        .runtime
        .resolve_review(fixture.session, review_id, ReviewDecision::Approve)
        .unwrap();
    match pump(&mut fixture, &mut host, first) {
        RuntimeReply::Emit { payload, .. } => assert_eq!(payload, vec![0x90, 0x00]),
        other => panic!("expected final 9000, got {other:?}"),
    }

    let yielded = &host.yielded[0];
    assert_eq!(yielded[0], 0x00);
    assert_eq!(yielded[1], 32, "taproot 是 32 字节 x-only 公钥");
    assert_eq!(&yielded[2..34], &spend_pubkey[1..]);
    let signature = &yielded[34..];
    assert_eq!(signature.len(), 64, "SIGHASH_DEFAULT 不带 sighash 字节");

    let digest = bip341_digest(
        (120_000, spend_script.clone()),
        &[(70_000, recipient_script.clone()), (40_000, change_script.clone())],
        [0x22; 32],
        1,
        0xFFFF_FFFD,
        0x00,
    );
    // 先确认我们自己的实现与测试里的独立实现得到同一个摘要
    let tx = chain_app_bitcoin::psbt::Tx {
        version: 2,
        inputs: vec![chain_app_bitcoin::psbt::TxIn {
            previous_output: chain_app_bitcoin::psbt::OutPoint { txid: [0x22; 32], vout: 1 },
            script_sig: Vec::new(),
            sequence: 0xFFFF_FFFD,
        }],
        outputs: vec![
            chain_app_bitcoin::psbt::TxOut { value: 70_000, script_pubkey: recipient_script.clone() },
            chain_app_bitcoin::psbt::TxOut { value: 40_000, script_pubkey: change_script.clone() },
        ],
        lock_time: 0,
    };
    let ours = chain_app_bitcoin::psbt::bip341_sighash(
        &tx,
        0,
        &[chain_app_bitcoin::psbt::TxOut { value: 120_000, script_pubkey: spend_script.clone() }],
        0,
    )
    .unwrap();
    assert_eq!(ours, digest, "设备侧与测试侧的 BIP-341 摘要必须一致");

    // 同一摘要、同一私钥再签一次：必须与设备给出的字节完全一致。
    let private = open_ledger_biz::hdkey::derive_secp256k1_private_key(
        &seed(),
        "m/86'/0'/0'/0/0",
    )
    .unwrap();
    let local = secp256k1::schnorr_sign_taproot(&private, &digest).unwrap();
    assert_eq!(local, signature, "设备签名应与本地同摘要签名一致");

    let output_key = secp256k1::taproot_output_key(&spend_pubkey[1..]).unwrap();
    let verifying_key = k256::schnorr::VerifyingKey::from_bytes(&output_key).unwrap();
    let signature = k256::schnorr::Signature::try_from(signature).unwrap();
    verifying_key
        .verify_raw(&digest, &signature)
        .expect("taproot 签名必须能对独立的 BIP-341 摘要验签");
}

// ── P2SH-P2WPKH（BIP-49）与 P2PKH（BIP-44）────────────────────────────

fn p2pkh_script(pubkey: &[u8]) -> Vec<u8> {
    let mut script = vec![0x76, 0xA9, 0x14];
    script.extend_from_slice(&hash160::hash(pubkey));
    script.extend_from_slice(&[0x88, 0xAC]);
    script
}

fn p2sh_p2wpkh_script(pubkey: &[u8]) -> Vec<u8> {
    let mut redeem = vec![0x00, 0x14];
    redeem.extend_from_slice(&hash160::hash(pubkey));
    let mut script = vec![0xA9, 0x14];
    script.extend_from_slice(&hash160::hash(&redeem));
    script.push(0x87);
    script
}

/// 造一笔 `non_witness_utxo` 用的原始交易，返回 (序列化, 内部字节序 txid)。
fn raw_prev_tx(value: u64, script: &[u8]) -> (Vec<u8>, [u8; 32]) {
    let mut tx = Vec::new();
    tx.extend_from_slice(&2u32.to_le_bytes());
    tx.extend(varint(1));
    tx.extend_from_slice(&[0x33u8; 32]);
    tx.extend_from_slice(&0u32.to_le_bytes());
    tx.extend(varint(0)); // scriptSig 空
    tx.extend_from_slice(&0xFFFF_FFFDu32.to_le_bytes());
    tx.extend(varint(1));
    tx.extend_from_slice(&value.to_le_bytes());
    tx.extend(varint(script.len() as u64));
    tx.extend_from_slice(script);
    tx.extend_from_slice(&0u32.to_le_bytes());
    (tx.clone(), sha256d::hash(&tx))
}

/// 独立实现的 legacy（BIP-143 之前）摘要：单输入、SIGHASH_ALL。
fn legacy_digest(
    script_code: &[u8],
    outputs: &[(u64, Vec<u8>)],
    txid: [u8; 32],
    vout: u32,
    sequence: u32,
) -> [u8; 32] {
    let mut preimage = 2u32.to_le_bytes().to_vec();
    preimage.extend(varint(1));
    preimage.extend_from_slice(&txid);
    preimage.extend_from_slice(&vout.to_le_bytes());
    preimage.extend(varint(script_code.len() as u64));
    preimage.extend_from_slice(script_code);
    preimage.extend_from_slice(&sequence.to_le_bytes());
    preimage.extend(varint(outputs.len() as u64));
    for (value, script) in outputs {
        preimage.extend_from_slice(&value.to_le_bytes());
        preimage.extend(varint(script.len() as u64));
        preimage.extend_from_slice(script);
    }
    preimage.extend_from_slice(&0u32.to_le_bytes()); // nLockTime
    preimage.extend_from_slice(&1u32.to_le_bytes()); // SIGHASH_ALL
    sha256d::hash(&preimage)
}

/// 审阅字段的 label 列表（用来断言费率 / RBF / locktime 确实进了确认页）。
fn review_labels(document: &ReviewDocument) -> Vec<String> {
    document
        .sections
        .iter()
        .flat_map(|section| section.fields.iter())
        .map(|field| field.label_key.clone())
        .collect()
}

#[test]
fn sign_psbt_nested_segwit_yields_a_bip143_signature() {
    let mut fixture = setup();
    let mut host = Host::new();

    let spend_pubkey = pubkey_at("m/49'/0'/0'/0/0");
    let change_pubkey = pubkey_at("m/49'/0'/0'/1/0");
    let spend_script = p2sh_p2wpkh_script(&spend_pubkey);

    let mut witness_utxo = 140_000u64.to_le_bytes().to_vec();
    witness_utxo.extend(varint(spend_script.len() as u64));
    witness_utxo.extend_from_slice(&spend_script);

    let input_map = MapBuilder::new()
        .put(&[0x0E], vec![0x44; 32])
        .put(&[0x0F], 2u32.to_le_bytes().to_vec())
        .put(&[0x10], 0xFFFF_FFFDu32.to_le_bytes().to_vec())
        .put(&[0x01], witness_utxo)
        .put(
            &[&[0x06u8][..], &spend_pubkey[..]].concat(),
            derivation_value(&[0x8000_0000 + 49, 0x8000_0000, 0x8000_0000, 0, 0]),
        );

    let recipient_script = p2wpkh_script(&pubkey_at("m/84'/0'/0'/0/3"));
    let change_script = p2sh_p2wpkh_script(&change_pubkey);
    let output_paid = MapBuilder::new()
        .put(&[0x03], 80_000u64.to_le_bytes().to_vec())
        .put(&[0x04], recipient_script.clone());
    let output_change = MapBuilder::new()
        .put(&[0x03], 50_000u64.to_le_bytes().to_vec())
        .put(&[0x04], change_script.clone())
        .put(
            &[&[0x02u8][..], &change_pubkey[..]].concat(),
            derivation_value(&[0x8000_0000 + 49, 0x8000_0000, 0x8000_0000, 1, 0]),
        );

    // locktime = 1、sequence 可 RBF：确认页要能显示这两项。
    let global = MapBuilder::new()
        .put(&[0x02], 2u32.to_le_bytes().to_vec())
        .put(&[0x03], 1u32.to_le_bytes().to_vec())
        .put(&[0x04], varint(1))
        .put(&[0x05], varint(2))
        .put(&[0xFB], 2u32.to_le_bytes().to_vec());

    let global_commitment = host.add_map(&global);
    let input_commitment = host.add_map(&input_map);
    let paid_commitment = host.add_map(&output_paid);
    let change_commitment = host.add_map(&output_change);
    let inputs_root = host.add_list(&[input_commitment]);
    let outputs_root = host.add_list(&[paid_commitment, change_commitment]);

    let template = b"sh(wpkh(@0/**))".to_vec();
    host.add_preimage(&template);
    let key_info = b"[73c5da0a/49'/0'/0']xpub6CatWdiZiodmUeTDp8LT5or8nmbKNcuyvz7WyksVFkKB4RHwCD3XyuvPEbvqAQY3rAPshWcMLoP2fMFMKHPJ4ZeZXYVUhLv1VMrjPC7PW6V".to_vec();
    let keys_root = host.add_list(std::slice::from_ref(&key_info));

    let mut policy_bytes = vec![0x02, 0x00];
    policy_bytes.extend(varint(template.len() as u64));
    policy_bytes.extend_from_slice(&sha256::hash(&template));
    policy_bytes.extend(varint(1));
    policy_bytes.extend_from_slice(&keys_root);
    host.add_preimage(&policy_bytes);
    let wallet_id = sha256::hash(&policy_bytes);

    let mut data = global_commitment;
    data.extend(varint(1));
    data.extend_from_slice(&inputs_root);
    data.extend(varint(2));
    data.extend_from_slice(&outputs_root);
    data.extend_from_slice(&wallet_id);
    data.extend_from_slice(&[0u8; 32]);

    let mut apdu = vec![0xE1, 0x04, 0x00, 0x01, data.len() as u8];
    apdu.extend_from_slice(&data);

    let reply = fixture
        .runtime
        .submit_wire(fixture.session, Wire::LedgerApdu, apdu)
        .unwrap();
    let (review_id, document) = match pump(&mut fixture, &mut host, reply) {
        RuntimeReply::Review {
            review_id,
            document,
            ..
        } => (review_id, document),
        other => panic!("expected review, got {other:?}"),
    };

    let labels = review_labels(&document);
    assert_eq!(document.sections[0].title_key, "review.section.bitcoin");
    assert!(labels.contains(&"review.field.fee_rate".to_string()), "{labels:?}");
    assert!(labels.contains(&"review.field.rbf".to_string()), "{labels:?}");
    assert!(labels.contains(&"review.field.locktime".to_string()), "{labels:?}");
    assert!(labels.contains(&"review.field.change".to_string()), "{labels:?}");

    let first = fixture
        .runtime
        .resolve_review(fixture.session, review_id, ReviewDecision::Approve)
        .unwrap();
    match pump(&mut fixture, &mut host, first) {
        RuntimeReply::Emit { payload, .. } => assert_eq!(payload, vec![0x90, 0x00]),
        other => panic!("expected final 9000, got {other:?}"),
    }

    assert_eq!(host.yielded.len(), 1);
    let yielded = &host.yielded[0];
    assert_eq!(yielded[0], 0x00);
    assert_eq!(yielded[1], 33);
    assert_eq!(&yielded[2..35], &spend_pubkey[..]);
    assert_eq!(*yielded.last().unwrap(), 0x01);

    let der = &yielded[35..yielded.len() - 1];
    let verifying_key = k256::ecdsa::VerifyingKey::from_sec1_bytes(&spend_pubkey).unwrap();
    let signature = k256::ecdsa::Signature::from_der(der).unwrap();
    // 嵌套 SegWit 的 scriptCode 与 P2WPKH 相同：P2PKH 形态的哈希公钥脚本。
    let digest = bip143_digest(
        &p2pkh_script(&spend_pubkey),
        140_000,
        &[(80_000, recipient_script.clone()), (50_000, change_script.clone())],
        [0x44; 32],
        2,
        0xFFFF_FFFD,
        1,
    );
    use k256::ecdsa::signature::hazmat::PrehashVerifier;
    verifying_key
        .verify_prehash(&digest, &signature)
        .expect("P2SH-P2WPKH 签名必须能对独立算出的 BIP-143 摘要验签");
}

#[test]
fn sign_psbt_legacy_yields_a_signature_over_the_legacy_digest() {
    let mut fixture = setup();
    let mut host = Host::new();

    let spend_pubkey = pubkey_at("m/44'/0'/0'/0/0");
    let change_pubkey = pubkey_at("m/44'/0'/0'/1/0");
    let spend_script = p2pkh_script(&spend_pubkey);

    let (prev_tx, prev_txid) = raw_prev_tx(150_000, &spend_script);

    let input_map = MapBuilder::new()
        .put(&[0x0E], prev_txid.to_vec())
        .put(&[0x0F], 0u32.to_le_bytes().to_vec())
        .put(&[0x10], 0xFFFF_FFFDu32.to_le_bytes().to_vec())
        // legacy 输入没有 witness，只能靠完整 prev tx 让设备自己校验金额。
        .put(&[0x00], prev_tx)
        .put(
            &[&[0x06u8][..], &spend_pubkey[..]].concat(),
            derivation_value(&[0x8000_0000 + 44, 0x8000_0000, 0x8000_0000, 0, 0]),
        );

    let recipient_script = p2pkh_script(&pubkey_at("m/44'/0'/0'/0/5"));
    let change_script = p2pkh_script(&change_pubkey);
    let output_paid = MapBuilder::new()
        .put(&[0x03], 90_000u64.to_le_bytes().to_vec())
        .put(&[0x04], recipient_script.clone());
    let output_change = MapBuilder::new()
        .put(&[0x03], 50_000u64.to_le_bytes().to_vec())
        .put(&[0x04], change_script.clone())
        .put(
            &[&[0x02u8][..], &change_pubkey[..]].concat(),
            derivation_value(&[0x8000_0000 + 44, 0x8000_0000, 0x8000_0000, 1, 0]),
        );

    let global = MapBuilder::new()
        .put(&[0x02], 2u32.to_le_bytes().to_vec())
        .put(&[0x03], 0u32.to_le_bytes().to_vec())
        .put(&[0x04], varint(1))
        .put(&[0x05], varint(2))
        .put(&[0xFB], 2u32.to_le_bytes().to_vec());

    let global_commitment = host.add_map(&global);
    let input_commitment = host.add_map(&input_map);
    let paid_commitment = host.add_map(&output_paid);
    let change_commitment = host.add_map(&output_change);
    let inputs_root = host.add_list(&[input_commitment]);
    let outputs_root = host.add_list(&[paid_commitment, change_commitment]);

    let template = b"pkh(@0/**)".to_vec();
    host.add_preimage(&template);
    let key_info = b"[73c5da0a/44'/0'/0']xpub6CatWdiZiodmUeTDp8LT5or8nmbKNcuyvz7WyksVFkKB4RHwCD3XyuvPEbvqAQY3rAPshWcMLoP2fMFMKHPJ4ZeZXYVUhLv1VMrjPC7PW6V".to_vec();
    let keys_root = host.add_list(std::slice::from_ref(&key_info));

    let mut policy_bytes = vec![0x02, 0x00];
    policy_bytes.extend(varint(template.len() as u64));
    policy_bytes.extend_from_slice(&sha256::hash(&template));
    policy_bytes.extend(varint(1));
    policy_bytes.extend_from_slice(&keys_root);
    host.add_preimage(&policy_bytes);
    let wallet_id = sha256::hash(&policy_bytes);

    let mut data = global_commitment;
    data.extend(varint(1));
    data.extend_from_slice(&inputs_root);
    data.extend(varint(2));
    data.extend_from_slice(&outputs_root);
    data.extend_from_slice(&wallet_id);
    data.extend_from_slice(&[0u8; 32]);

    let mut apdu = vec![0xE1, 0x04, 0x00, 0x01, data.len() as u8];
    apdu.extend_from_slice(&data);

    let reply = fixture
        .runtime
        .submit_wire(fixture.session, Wire::LedgerApdu, apdu)
        .unwrap();
    let review_id = match pump(&mut fixture, &mut host, reply) {
        RuntimeReply::Review { review_id, .. } => review_id,
        other => panic!("expected review, got {other:?}"),
    };
    let first = fixture
        .runtime
        .resolve_review(fixture.session, review_id, ReviewDecision::Approve)
        .unwrap();
    match pump(&mut fixture, &mut host, first) {
        RuntimeReply::Emit { payload, .. } => assert_eq!(payload, vec![0x90, 0x00]),
        other => panic!("expected final 9000, got {other:?}"),
    }

    assert_eq!(host.yielded.len(), 1);
    let yielded = &host.yielded[0];
    assert_eq!(&yielded[2..35], &spend_pubkey[..]);

    let der = &yielded[35..yielded.len() - 1];
    let verifying_key = k256::ecdsa::VerifyingKey::from_sec1_bytes(&spend_pubkey).unwrap();
    let signature = k256::ecdsa::Signature::from_der(der).unwrap();
    let digest = legacy_digest(
        &spend_script,
        &[(90_000, recipient_script.clone()), (50_000, change_script.clone())],
        prev_txid,
        0,
        0xFFFF_FFFD,
    );
    use k256::ecdsa::signature::hazmat::PrehashVerifier;
    verifying_key
        .verify_prehash(&digest, &signature)
        .expect("legacy 签名必须能对独立算出的传统摘要验签");
}
