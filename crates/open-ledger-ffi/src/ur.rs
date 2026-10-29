//! Keystone QR 通道的 C 导出（T-026 / D-018）。
//!
//! 与 `chain_host.rs` 同样的约定：入参是十六进制 / UTF-8 字符串，出参是单行
//! JSON；所有错误经 `FfiResult` 返回，跨 FFI 不暴露 Rust 内存布局。
//!
//! 会话句柄是 `Box<UrSession>` 的裸指针，只能由 `ur_session_free` 释放。

use std::ffi::c_void;
use std::os::raw::c_char;

use open_ledger_ur::{
    build_crypto_account_code, build_multi_accounts, encode_eth_signature, encode_frames,
    EthSignRequest, PartStatus, UrSession, MULTI_ACCOUNTS_TYPE,
};
use zeroize::Zeroize;

use crate::types::FfiResult;
use crate::{cstr_to_hex, cstr_to_str};

fn ok_json(json: String) -> *mut FfiResult {
    FfiResult::ok(json).into_ptr()
}

fn err_json(message: &str) -> *mut FfiResult {
    FfiResult::err(99, message.to_string()).into_ptr()
}

/// JSON 字符串转义。origin 来自外部钱包，必须当不可信输入处理。
fn json_string(raw: &str) -> String {
    let mut out = String::with_capacity(raw.len() + 2);
    out.push('"');
    for ch in raw.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

fn frames_json(frames: &[String]) -> String {
    let items: Vec<String> = frames.iter().map(|frame| json_string(frame)).collect();
    format!("[{}]", items.join(","))
}

fn optional_string(value: Option<&str>) -> String {
    match value {
        Some(text) => json_string(text),
        None => "null".to_string(),
    }
}

fn address_hex(address: &[u8; 20]) -> String {
    format!("0x{}", hex::encode(address))
}

/// `fragment_len == 0` → 单帧（`ur:<type>/<data>`，无序号）。
///
/// 多帧要传具体长度（原型用 60）。OKX 插件在多帧上会卡在 fountain 解码的
/// 97–99%，所以单账户导出走单帧路径。
fn resolved_fragment_len(value: u32) -> usize {
    value as usize
}

// ── 会话 ─────────────────────────────────────────────────────────────

#[no_mangle]
pub unsafe extern "C" fn ur_session_new() -> *mut c_void {
    Box::into_raw(Box::new(UrSession::new())) as *mut c_void
}

#[no_mangle]
pub unsafe extern "C" fn ur_session_free(handle: *mut c_void) {
    if !handle.is_null() {
        drop(Box::from_raw(handle as *mut UrSession));
    }
}

/// 收一帧。返回 `{"status":0|1|2,"received":n,"total":m}`。
///
/// `status`：0 缺帧、1 完成、2 重复帧。
#[no_mangle]
pub unsafe extern "C" fn ur_session_receive(
    handle: *mut c_void,
    part_ptr: *const c_char,
) -> *mut FfiResult {
    if handle.is_null() {
        return err_json("null session handle");
    }
    let part = match cstr_to_str(part_ptr) {
        Some(text) => text,
        None => return err_json("null or invalid frame"),
    };
    let session = &mut *(handle as *mut UrSession);
    match session.receive(part) {
        Ok(state) => {
            let status = match state.status {
                PartStatus::Pending => 0,
                PartStatus::Complete => 1,
                PartStatus::Duplicate => 2,
            };
            ok_json(format!(
                "{{\"status\":{status},\"received\":{},\"total\":{}}}",
                state.received, state.total
            ))
        }
        Err(error) => FfiResult::from_chain_error(error).into_ptr(),
    }
}

/// 取结果：完成时 `{"type":...,"cbor":"<hex>"}`，否则 JSON `null`。
#[no_mangle]
pub unsafe extern "C" fn ur_session_result(handle: *mut c_void) -> *mut FfiResult {
    if handle.is_null() {
        return err_json("null session handle");
    }
    let session = &*(handle as *const UrSession);
    match session.result() {
        Some((ur_type, cbor)) => ok_json(format!(
            "{{\"type\":{},\"cbor\":{}}}",
            json_string(ur_type),
            json_string(&hex::encode(cbor))
        )),
        None => ok_json("null".to_string()),
    }
}

// ── ETH 请求 / 签名 ───────────────────────────────────────────────────

fn parse_request(cbor_hex_ptr: *const c_char) -> Result<EthSignRequest, *mut FfiResult> {
    let cbor = unsafe { cstr_to_hex(cbor_hex_ptr) }.ok_or_else(|| err_json("invalid cbor hex"))?;
    EthSignRequest::from_cbor(&cbor).map_err(|error| FfiResult::from_chain_error(error).into_ptr())
}

/// 解析 `eth-sign-request`。
#[no_mangle]
pub unsafe extern "C" fn ur_parse_eth_sign_request(cbor_hex_ptr: *const c_char) -> *mut FfiResult {
    let request = match parse_request(cbor_hex_ptr) {
        Ok(request) => request,
        Err(result) => return result,
    };
    let signing_hash = match request.signing_hash() {
        Ok(hash) => hex::encode(hash),
        Err(error) => return FfiResult::from_chain_error(error).into_ptr(),
    };
    let request_id = request.request_id.map(hex::encode);
    let address = request.address.as_ref().map(address_hex);
    let chain_id = request
        .chain_id
        .map(|id| id.to_string())
        .unwrap_or_else(|| "null".to_string());
    ok_json(format!(
        "{{\"requestId\":{},\"dataType\":{},\"chainId\":{},\"path\":{},\"address\":{},\"origin\":{},\"signDataHex\":{},\"signingHashHex\":{}}}",
        optional_string(request_id.as_deref()),
        request.data_type,
        chain_id,
        json_string(&request.path),
        optional_string(address.as_deref()),
        optional_string(request.origin.as_deref()),
        json_string(&hex::encode(&request.sign_data)),
        json_string(&signing_hash),
    ))
}

/// 用 seed 在请求路径上签名。地址不匹配时返回错误，绝不签名。
#[no_mangle]
pub unsafe extern "C" fn ur_sign_eth_request(
    cbor_hex_ptr: *const c_char,
    seed_hex_ptr: *const c_char,
) -> *mut FfiResult {
    let request = match parse_request(cbor_hex_ptr) {
        Ok(request) => request,
        Err(result) => return result,
    };
    let mut seed = match cstr_to_hex(seed_hex_ptr) {
        Some(seed) => seed,
        None => return err_json("invalid seed hex"),
    };
    let outcome = request.sign(&seed);
    seed.zeroize();
    match outcome {
        Ok(signed) => {
            let request_id = request.request_id.unwrap_or([0u8; 16]);
            ok_json(format!(
                "{{\"requestId\":{},\"signatureHex\":{},\"address\":{},\"addressMatches\":{}}}",
                json_string(&hex::encode(request_id)),
                json_string(&hex::encode(signed.signature)),
                json_string(&address_hex(&signed.address)),
                signed.address_matches,
            ))
        }
        Err(error) => FfiResult::from_chain_error(error).into_ptr(),
    }
}

// ── 回显编码 ─────────────────────────────────────────────────────────

/// 把 65 字节签名包成 `eth-signature` 帧。`fragment_len == 0` → 单帧。
#[no_mangle]
pub unsafe extern "C" fn ur_encode_eth_signature(
    request_id_hex_ptr: *const c_char,
    signature_hex_ptr: *const c_char,
    origin_ptr: *const c_char,
    fragment_len: u32,
) -> *mut FfiResult {
    let mut request_id = [0u8; 16];
    match cstr_to_hex(request_id_hex_ptr) {
        Some(bytes) if bytes.len() == 16 => request_id.copy_from_slice(&bytes),
        _ => return err_json("request id must be 16 bytes"),
    }
    let signature = match cstr_to_hex(signature_hex_ptr) {
        Some(bytes) => bytes,
        None => return err_json("invalid signature hex"),
    };
    let origin = cstr_to_str(origin_ptr).filter(|text| !text.is_empty());
    let cbor = match encode_eth_signature(&request_id, &signature, origin) {
        Ok(cbor) => cbor,
        Err(error) => return FfiResult::from_chain_error(error).into_ptr(),
    };
    match encode_frames("eth-signature", &cbor, resolved_fragment_len(fragment_len)) {
        Ok(frames) => ok_json(format!("{{\"frames\":{}}}", frames_json(&frames))),
        Err(error) => FfiResult::from_chain_error(error).into_ptr(),
    }
}

/// 构造账户码帧，同时回传这一页的地址，界面可在扫码前展示。
///
/// `account_level != 0` 时输出 OKX 插件唯一接受的 `crypto-multi-accounts`
/// **同步码**（4 个账户级 xpub + 10 个 ETH 叶公钥，见 `build_multi_accounts`）；
/// 否则输出 `count` 个叶子地址描述符（MetaMask 一页 5 个）。
/// `fragment_len == 0` → 单帧。
#[no_mangle]
pub unsafe extern "C" fn ur_encode_crypto_account(
    seed_hex_ptr: *const c_char,
    path_ptr: *const c_char,
    count: u32,
    account_level: u32,
    fragment_len: u32,
) -> *mut FfiResult {
    let path = match cstr_to_str(path_ptr) {
        Some(text) => text,
        None => return err_json("null account path"),
    };
    let mut seed = match cstr_to_hex(seed_hex_ptr) {
        Some(seed) => seed,
        None => return err_json("invalid seed hex"),
    };
    let count = if count == 0 { 1 } else { count as usize };
    let multi_accounts = account_level != 0;
    let built = if multi_accounts {
        build_multi_accounts(&seed, "Open Ledger", "1.0.4").map(|cbor| (cbor, Vec::new()))
    } else {
        build_crypto_account_code(&seed, path, count)
            .map(|code| (code.cbor, code.addresses))
    };
    seed.zeroize();
    let (cbor, addresses) = match built {
        Ok(pair) => pair,
        Err(error) => return FfiResult::from_chain_error(error).into_ptr(),
    };
    let ur_type = if multi_accounts {
        MULTI_ACCOUNTS_TYPE
    } else {
        "crypto-account"
    };
    match encode_frames(ur_type, &cbor, resolved_fragment_len(fragment_len)) {
        Ok(frames) => {
            let list: Vec<String> = addresses
                .iter()
                .map(|address| json_string(&address_hex(address)))
                .collect();
            let first = addresses.first().map(|a| json_string(&address_hex(a)));
            ok_json(format!(
                "{{\"frames\":{},\"address\":{},\"addresses\":[{}],\"path\":{}}}",
                frames_json(&frames),
                first.unwrap_or_else(|| "null".into()),
                list.join(","),
                json_string(path),
            ))
        }
        Err(error) => FfiResult::from_chain_error(error).into_ptr(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CString;

    const TEST_PHRASE: &str =
        "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";

    fn text(value: &str) -> CString {
        CString::new(value).unwrap()
    }

    fn take(result: *mut FfiResult) -> String {
        use std::ffi::CStr;
        assert!(!result.is_null());
        let view = unsafe { &*result };
        let error = if view.error_msg.is_null() {
            String::new()
        } else {
            unsafe { CStr::from_ptr(view.error_msg).to_string_lossy().into_owned() }
        };
        assert_eq!(view.error_code, 0, "{error}");
        let data = if view.data.is_null() {
            String::new()
        } else {
            unsafe { CStr::from_ptr(view.data).to_string_lossy().into_owned() }
        };
        unsafe { crate::types::free_ffi_result(result) };
        data
    }

    fn test_seed_hex() -> String {
        let seed = open_ledger_crypto::bip39::mnemonic_to_seed(TEST_PHRASE, "").unwrap();
        hex::encode(seed)
    }

    #[test]
    fn session_reports_progress_and_result() {
        let frames = encode_frames("eth-sign-request", &[0xa1, 0x01, 0x01], 0).unwrap();
        let handle = unsafe { ur_session_new() };
        assert!(!handle.is_null());
        let part = text(&frames[0]);
        let json = take(unsafe { ur_session_receive(handle, part.as_ptr()) });
        assert!(json.contains("\"status\":1"), "{json}");

        let result = take(unsafe { ur_session_result(handle) });
        assert!(result.contains("\"type\":\"eth-sign-request\""), "{result}");
        assert!(result.contains("\"cbor\":\"a10101\""), "{result}");

        let duplicate = text(&frames[0]);
        let json = take(unsafe { ur_session_receive(handle, duplicate.as_ptr()) });
        assert!(json.contains("\"status\":2"), "{json}");
        unsafe { ur_session_free(handle) };
    }

    #[test]
    fn result_is_null_before_completion() {
        let handle = unsafe { ur_session_new() };
        assert_eq!(take(unsafe { ur_session_result(handle) }), "null");
        unsafe { ur_session_free(handle) };
    }

    #[test]
    fn account_export_returns_address_and_frames() {
        let seed = text(&test_seed_hex());
        let path = text("m/44'/60'/0'/0/0");
        let json = take(unsafe { ur_encode_crypto_account(seed.as_ptr(), path.as_ptr(), 5, 0, 60) });
        assert!(
            json.contains("\"address\":\"0x9858effd232b4033e47d90003d41ec34ecaeda94\""),
            "{json}"
        );
        // 一页 5 个地址，MetaMask 才不会在 index 1 上失败。
        let head = "\"addresses\":[";
        let start = json.find(head).expect("addresses array") + head.len();
        let list = &json[start..start + json[start..].find(']').expect("array end")];
        assert_eq!(list.matches("0x").count(), 5, "{json}");
        assert!(json.contains("\"frames\":[\"ur:crypto-account/1-"), "{json}");
    }

    #[test]
    fn multi_accounts_export_uses_the_okx_type() {
        let seed = text(&test_seed_hex());
        let path = text("m/44'/60'/0'");
        let json = take(unsafe { ur_encode_crypto_account(seed.as_ptr(), path.as_ptr(), 1, 1, 60) });
        // OKX 只认 crypto-multi-accounts；其它类型会被判为 UNEXPECTED_QRCODE 并重置扫描。
        assert!(json.contains("\"frames\":[\"ur:crypto-multi-accounts/1-"), "{json}");
        assert!(json.contains("\"addresses\":[]"), "{json}");
        assert!(json.contains("\"address\":null"), "{json}");
        let frames = json.matches("ur:crypto-multi-accounts/").count();
        assert!((15..=60).contains(&frames), "{json}");
    }

    #[test]
    fn single_account_export_is_one_frame() {
        let seed = text(&test_seed_hex());
        let path = text("m/44'/60'/0'/0/0");
        let json = take(unsafe { ur_encode_crypto_account(seed.as_ptr(), path.as_ptr(), 1, 0, 0) });
        assert!(json.contains("\"frames\":[\"ur:crypto-account/"), "{json}");
        // 单帧不带 `/<seq>-<total>/` 头。
        let frames = &json[json.find("\"frames\":[").expect("frames")..];
        assert!(!frames.contains("-1/"), "{json}");
        let head = "\"addresses\":[";
        let start = json.find(head).expect("addresses array") + head.len();
        let list = &json[start..start + json[start..].find(']').expect("array end")];
        assert_eq!(list.matches("0x").count(), 1, "{json}");
    }

    #[test]
    fn signature_encoding_requires_a_16_byte_request_id() {
        let short = text("0011");
        let signature = text(&"22".repeat(65));
        let origin = text("MetaMask");
        let result =
            unsafe { ur_encode_eth_signature(short.as_ptr(), signature.as_ptr(), origin.as_ptr(), 0) };
        let view = unsafe { &*result };
        assert_ne!(view.error_code, 0);
        unsafe { crate::types::free_ffi_result(result) };
    }
}
