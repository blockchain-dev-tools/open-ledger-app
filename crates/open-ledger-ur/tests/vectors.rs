//! 与 Keystone 官方 JS（`@keystonehq/bc-ur-registry-eth@0.22.1`）生成的真实向量对拍。
//!
//! `vectors.json` 由官方 JS 编码器生成（见 T-023 的 spike），包含单帧、多帧、
//! 以及每个 registry type 的 CBOR 字节。断言的是**逐字节**一致，不是「能解出来」。

use open_ledger_ur::{
    account_address, build_crypto_account, encode_eth_signature, encode_frames, EthSignRequest,
    PartStatus, UrSession,
};
use serde_json::Value as Json;

fn vectors() -> Json {
    serde_json::from_str(include_str!("vectors.json")).expect("vectors.json")
}

fn single_frames(name: &str) -> Vec<String> {
    vectors()[name]["single"]
        .as_array()
        .unwrap()
        .iter()
        .map(|value| value.as_str().unwrap().to_string())
        .collect()
}

fn multipart_frames(name: &str) -> Vec<String> {
    vectors()[name]["multi"]
        .as_array()
        .unwrap()
        .iter()
        .map(|value| value.as_str().unwrap().to_string())
        .collect()
}

fn expected_cbor(name: &str) -> String {
    vectors()[name]["cbor"].as_str().unwrap().to_lowercase()
}

#[test]
fn decodes_every_single_part_vector_byte_identically() {
    for name in ["hdkey", "account", "request", "signature"] {
        let parts = single_frames(name);
        assert_eq!(parts.len(), 1, "{name} should be a single frame");
        let mut session = UrSession::new();
        let state = session.receive(&parts[0]).unwrap();
        assert_eq!(state.status, PartStatus::Complete, "{name}");
        let (_, cbor) = session.result().unwrap();
        assert_eq!(hex::encode(cbor), expected_cbor(name), "{name} CBOR mismatch");
    }
}

#[test]
fn reassembles_multipart_vectors_out_of_order_with_duplicates() {
    for name in ["account", "request"] {
        let parts = multipart_frames(name);
        assert!(parts.len() > 1, "{name} should be multipart");
        let mut order: Vec<&String> = parts.iter().rev().collect();
        order.extend(parts.iter()); // 重复帧不能影响结果
        let mut session = UrSession::new();
        let mut last = PartStatus::Pending;
        for part in order {
            let state = session.receive(part).unwrap();
            if state.status == PartStatus::Complete {
                last = PartStatus::Complete;
                break;
            }
        }
        assert_eq!(last, PartStatus::Complete, "{name} did not complete");
        let (_, cbor) = session.result().unwrap();
        assert_eq!(hex::encode(cbor), expected_cbor(name), "{name} CBOR mismatch");
    }
}

#[test]
fn parses_official_eth_sign_request() {
    let parts = single_frames("request");
    let mut session = UrSession::new();
    session.receive(&parts[0]).unwrap();
    let (_, cbor) = session.result().unwrap();
    let cbor = cbor.to_vec();
    let request = EthSignRequest::from_cbor(&cbor).unwrap();
    assert_eq!(
        hex::encode(request.request_id.unwrap()),
        "9b1deb4d3b7d4bad9bdd2b0d7b3dcb6d"
    );
    assert_eq!(request.data_type, 1);
    assert_eq!(request.chain_id, Some(1));
    assert_eq!(request.path, "m/44'/60'/0'/0/0");
    assert_eq!(hex::encode(request.address.unwrap()), "22".repeat(20));
    assert_eq!(request.origin.as_deref(), Some("MetaMask"));
    // sign-data starts with the EIP-1559 type byte.
    assert_eq!(request.sign_data[0], 0x02);
}

#[test]
fn eth_signature_bytes_match_official_encoder() {
    let signature = vectors();
    let request_id_hex = "9b1deb4d3b7d4bad9bdd2b0d7b3dcb6d";
    let mut request_bytes = [0u8; 16];
    request_bytes.copy_from_slice(&hex::decode(request_id_hex).unwrap());
    let signature_hex = "33".repeat(32) + &"44".repeat(32) + "1b";
    let encoded = encode_eth_signature(
        &request_bytes,
        &hex::decode(signature_hex).unwrap(),
        Some("MetaMask"),
    )
    .unwrap();
    assert_eq!(
        hex::encode(&encoded),
        signature["signature"]["cbor"].as_str().unwrap().to_lowercase()
    );
}

#[test]
fn js_account_cbor_round_trips_canonically() {
    let expected = expected_cbor("account");
    let raw = hex::decode(&expected).unwrap();
    let value: ciborium::value::Value = ciborium::de::from_reader(raw.as_slice()).unwrap();
    let mut out = Vec::new();
    ciborium::ser::into_writer(&value, &mut out).unwrap();
    assert_eq!(hex::encode(out), expected);
}

#[test]
fn our_account_is_well_formed_and_scannable() {
    let phrase =
        "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
    let mnemonic = bip39::Mnemonic::parse(phrase).unwrap();
    let seed = mnemonic.to_seed("");

    let cbor = build_crypto_account(&seed, "m/44'/60'/0'/0/0").unwrap();
    let frames = encode_frames("crypto-account", &cbor, 0).unwrap();
    assert_eq!(frames.len(), 1);

    let mut session = UrSession::new();
    let state = session.receive(&frames[0]).unwrap();
    assert_eq!(state.status, PartStatus::Complete);
    let (ur_type, decoded) = session.result().unwrap();
    assert_eq!(ur_type, "crypto-account");
    assert_eq!(decoded, cbor.as_slice());

    let address = account_address(&seed, "m/44'/60'/0'/0/0").unwrap();
    assert_eq!(
        hex::encode(address),
        "9858effd232b4033e47d90003d41ec34ecaeda94"
    );
}

#[test]
fn multipart_account_frames_are_scannable() {
    let phrase =
        "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
    let mnemonic = bip39::Mnemonic::parse(phrase).unwrap();
    let seed = mnemonic.to_seed("");
    let cbor = build_crypto_account(&seed, "m/44'/60'/0'/0/0").unwrap();
    let frames = encode_frames("crypto-account", &cbor, 40).unwrap();

    let mut session = UrSession::new();
    for frame in &frames {
        session.receive(frame).unwrap();
    }
    let (_, decoded) = session.result().expect("complete");
    assert_eq!(decoded, cbor.as_slice());
}
