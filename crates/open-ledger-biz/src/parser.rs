use crate::errors::{ChainError, Result};
use open_ledger_crypto::rlp as crypto_rlp;

pub fn parse_sign_data(chain: &str, payload_hex: &str) -> Result<String> {
    let payload = hex::decode(payload_hex)
        .map_err(|e| ChainError::ParseError(format!("invalid hex: {e}")))?;
    if payload.is_empty() {
        return Err(ChainError::ParseError("empty payload".into()));
    }
    match chain {
        "ethereum" => parse_eth_tx(&payload),
        "personal_msg" => parse_personal_msg(&payload),
        "eip712" => parse_eip712(&payload),
        "solana" => parse_solana_tx(&payload).or_else(|_| parse_raw(&payload, chain)),
        _ => parse_raw(&payload, chain),
    }
}

fn parse_eth_tx(payload: &[u8]) -> Result<String> {
    use rlp::Rlp;
    let (body, tx_type) = if !payload.is_empty() && payload[0] <= 0x7f {
        (&payload[1..], Some(payload[0]))
    } else {
        (payload, None)
    };
    let rlp = Rlp::new(body);
    let count = rlp.item_count().map_err(|e| ChainError::ParseError(format!("RLP error: {e}")))?;
    if count < 6 {
        return Err(ChainError::ParseError(format!("ETH tx RLP too few fields: {count} (need ≥6)")));
    }
    let (gas_idx, to_idx, value_idx, data_idx) = match tx_type {
        Some(0x02) | Some(0x01) => (4, 5, 6, 7),
        _ => (2, 3, 4, 5),
    };
    if count <= to_idx {
        return Err(ChainError::ParseError(format!("ETH tx RLP too few fields for type: {count} (need at least {})", to_idx + 1)));
    }
    let nonce = crypto_rlp::rlp_val_uint(&rlp.at(0).map_err(|e| ChainError::ParseError(format!("nonce: {e}")))?);
    let gas = crypto_rlp::rlp_val_uint(&rlp.at(gas_idx).map_err(|e| ChainError::ParseError(format!("gas: {e}")))?);
    let to = crypto_rlp::rlp_addr(&rlp.at(to_idx).map_err(|e| ChainError::ParseError(format!("to: {e}")))?);
    let value = crypto_rlp::rlp_val_uint(&rlp.at(value_idx).map_err(|e| ChainError::ParseError(format!("value: {e}")))?);
    let chain_id = match tx_type {
        Some(0x02) | Some(0x01) => crypto_rlp::rlp_val_uint(&rlp.at(0).map_err(|e| ChainError::ParseError(format!("chainId: {e}")))?),
        _ => if count > 6 {
            crypto_rlp::rlp_val_uint(&rlp.at(6).map_err(|e| ChainError::ParseError(format!("chainId: {e}")))?)
        } else { "0".to_string() }
    };
    let gas_price_idx = match tx_type {
        Some(0x02) | Some(0x01) => 3,
        _ => 1,
    };
    let gas_price = if count > gas_price_idx {
        crypto_rlp::rlp_val_uint(&rlp.at(gas_price_idx).map_err(|e| ChainError::ParseError(format!("gasPrice: {e}")))?)
    } else { "0".to_string() };
    let priority_fee = match tx_type {
        Some(0x02) | Some(0x01) => {
            if count > 2 {
                crypto_rlp::rlp_val_uint(&rlp.at(2).map_err(|e| ChainError::ParseError(format!("priorityFee: {e}")))?)
            } else { "0".to_string() }
        }
        _ => String::new(),
    };
    let priority_json = if !priority_fee.is_empty() {
        format!(r#","priorityFee":"{}""#, priority_fee)
    } else { String::new() };
    let data_raw = if count > data_idx {
        rlp.at(data_idx).ok().and_then(|r| r.data().ok()).unwrap_or(&[])
    } else { &[] };
    let data = format_data(data_raw);
    let decoded_action = decode_eth_tx_data(data_raw);
    let tx_type_str = match tx_type {
        Some(2) => "eip1559",
        Some(1) => "eip2930",
        _ => "legacy",
    };
    let action_json = match &decoded_action {
        Some(action) => format!(",\"action\":{}", action),
        None => String::new(),
    };
    Ok(format!(
        r#"{{"type":"eth_tx","to":"{}","value":"{}","gas":"{}","gasPrice":"{}","nonce":"{}","data":"{}","txType":"{}","chainId":"{}"{}{}}}"#,
        to, value, gas, gas_price, nonce, data, tx_type_str, chain_id, priority_json, action_json,
    ))
}

fn format_data(data_raw: &[u8]) -> String {
    if data_raw.is_empty() { "0x".to_string() } else { format!("0x{}", hex::encode(data_raw)) }
}

fn param_json(name: &str, value: &str, type_str: &str) -> String {
    let escaped_value = value.replace('\\', "\\\\").replace('"', "\\\"");
    format!(r#"{{"name":"{}","value":"{}","type":"{}"}}"#, name, escaped_value, type_str)
}

fn decode_eth_tx_data(data: &[u8]) -> Option<String> {
    if data.len() < 4 { return None; }
    let selector = &data[0..4];
    match selector {
        [0xa9, 0x05, 0x9c, 0xbb] => {
            if data.len() < 68 { return None; }
            let to_addr = hex::encode(&data[16..36]);
            let amount = crypto_rlp::bytes_to_decimal(&data[36..68]);
            let params = format!("{},{}",
                param_json("to", &format!("0x{}", to_addr), "address"),
                param_json("amount", &amount, "uint256"));
            Some(format!(r#"{{"method":"transfer","params":[{}]}}"#, params))
        }
        [0x09, 0x5e, 0xa7, 0xb3] => {
            if data.len() < 68 { return None; }
            let spender = hex::encode(&data[16..36]);
            let amount = crypto_rlp::bytes_to_decimal(&data[36..68]);
            let params = format!("{},{}",
                param_json("spender", &format!("0x{}", spender), "address"),
                param_json("amount", &amount, "uint256"));
            Some(format!(r#"{{"method":"approve","params":[{}]}}"#, params))
        }
        [0x23, 0xb8, 0x72, 0xdd] => {
            if data.len() < 100 { return None; }
            let from = hex::encode(&data[16..36]);
            let to_addr = hex::encode(&data[48..68]);
            let amount = crypto_rlp::bytes_to_decimal(&data[68..100]);
            let params = format!("{},{},{}",
                param_json("from", &format!("0x{}", from), "address"),
                param_json("to", &format!("0x{}", to_addr), "address"),
                param_json("amount", &amount, "uint256"));
            Some(format!(r#"{{"method":"transferFrom","params":[{}]}}"#, params))
        }
        _ => None,
    }
}

fn parse_personal_msg(payload: &[u8]) -> Result<String> {
    let message_hex = hex::encode(payload);
    let message = String::from_utf8(payload.to_vec()).unwrap_or_else(|_| format!("0x{}", message_hex));
    let escaped = message.replace('\\', "\\\\").replace('"', "\\\"")
        .replace('\n', "\\n").replace('\r', "\\r").replace('\t', "\\t");
    Ok(format!(r#"{{"type":"personal_msg","message":"{}","messageHex":"{}"}}"#, escaped, message_hex))
}

fn parse_eip712(payload: &[u8]) -> Result<String> {
    if payload.len() < 64 {
        return Err(ChainError::ParseError(format!("EIP-712 payload too short: {}", payload.len())));
    }
    let domain_hash = hex::encode(&payload[..32]);
    let struct_hash = hex::encode(&payload[32..64]);
    Ok(format!(r#"{{"type":"eip712","domainHash":"0x{}","structHash":"0x{}"}}"#, domain_hash, struct_hash))
}

/// Decode a Solana transaction *message* (the bytes the Ledger Solana app
/// hashes/signs) into a human-readable summary.
///
/// Handles legacy messages and versioned (v0) transactions. Versioned
/// messages are prefixed with `0x80 | version`; legacy ones start with
/// `num_required_signatures` (< 0x80). Unknown/unsupported instructions fall
/// back to `"action":"unknown"`; a malformed message returns `Err` so the
/// caller can degrade to [parse_raw].
fn parse_solana_tx(payload: &[u8]) -> Result<String> {
    let (version, msg) = if !payload.is_empty() && payload[0] & 0x80 != 0 {
        (format!("v{}", payload[0] & 0x7f), &payload[1..])
    } else {
        ("legacy".to_string(), payload)
    };

    if msg.len() < 3 {
        return Err(ChainError::ParseError("solana: message too short".into()));
    }
    let num_required_sigs = msg[0] as usize;

    let mut pos = 3usize;
    let (account_count, n) =
        read_compact_u16(msg, pos).ok_or_else(|| ChainError::ParseError("solana: bad account count".into()))?;
    pos += n;
    let account_count = account_count as usize;
    if account_count == 0 || pos + account_count * 32 > msg.len() {
        return Err(ChainError::ParseError("solana: truncated account keys".into()));
    }
    let keys: Vec<&[u8]> = (0..account_count)
        .map(|i| &msg[pos + i * 32..pos + i * 32 + 32])
        .collect();
    pos += account_count * 32;

    // Recent blockhash (32B) is skipped — not surfaced in the summary.
    if pos + 32 > msg.len() {
        return Err(ChainError::ParseError("solana: missing blockhash".into()));
    }
    pos += 32;

    let (ix_count, n) =
        read_compact_u16(msg, pos).ok_or_else(|| ChainError::ParseError("solana: bad instruction count".into()))?;
    pos += n;

    let fee_payer = bs58::encode(keys[0]).into_string();

    let mut program_id: Option<String> = None;
    let mut action = "unknown".to_string();
    let mut to: Option<String> = None;
    let mut lamports: Option<String> = None;

    for _ in 0..ix_count {
        let program_idx = *msg.get(pos).ok_or_else(|| ChainError::ParseError("solana: truncated instruction".into()))? as usize;
        pos += 1;
        let (acct_len, n) =
            read_compact_u16(msg, pos).ok_or_else(|| ChainError::ParseError("solana: bad ix account count".into()))?;
        pos += n;
        let acct_len = acct_len as usize;
        if pos + acct_len > msg.len() {
            return Err(ChainError::ParseError("solana: truncated ix accounts".into()));
        }
        let ix_accounts = &msg[pos..pos + acct_len];
        pos += acct_len;
        let (data_len, n) =
            read_compact_u16(msg, pos).ok_or_else(|| ChainError::ParseError("solana: bad ix data length".into()))?;
        pos += n;
        let data_len = data_len as usize;
        if pos + data_len > msg.len() {
            return Err(ChainError::ParseError("solana: truncated ix data".into()));
        }
        let ix_data = &msg[pos..pos + data_len];
        pos += data_len;

        // Surface only the first instruction.
        if program_id.is_none() {
            if let Some(key) = keys.get(program_idx) {
                program_id = Some(bs58::encode(key).into_string());
                // System Program (32 x 0x00), discriminator 2 = Transfer,
                // data = [u32 le discriminator][u64 le lamports].
                if key.iter().all(|b| *b == 0) && ix_data.len() >= 12 && ix_data[0..4] == [2, 0, 0, 0] {
                    action = "transfer".to_string();
                    if ix_accounts.len() >= 2 {
                        let to_idx = ix_accounts[1] as usize;
                        if let Some(to_key) = keys.get(to_idx) {
                            to = Some(bs58::encode(to_key).into_string());
                        }
                    }
                    let mut buf = [0u8; 8];
                    buf.copy_from_slice(&ix_data[4..12]);
                    lamports = Some(u64::from_le_bytes(buf).to_string());
                }
            }
        }
    }

    let mut out = format!(
        r#"{{"type":"solana_tx","chain":"solana","version":"{}","feePayer":"{}","numSigners":{},"instructionCount":{}"#,
        version, fee_payer, num_required_sigs, ix_count,
    );
    if let Some(pid) = program_id {
        out.push_str(&format!(r#","programId":"{}","action":"{}""#, pid, action));
    }
    if let Some(t) = to {
        out.push_str(&format!(r#","to":"{}""#, t));
    }
    if let Some(l) = lamports {
        out.push_str(&format!(r#","lamports":"{}""#, l));
    }
    out.push('}');
    Ok(out)
}

/// Read a Solana compact-u16 (short_vec) length at [pos], returning the value
/// and the number of bytes consumed.
fn read_compact_u16(data: &[u8], pos: usize) -> Option<(u16, usize)> {
    let b0 = *data.get(pos)?;
    if b0 & 0x80 == 0 {
        return Some((b0 as u16, 1));
    }
    let b1 = *data.get(pos + 1)?;
    if b1 & 0x80 == 0 {
        let v = ((b0 & 0x7f) as u16) | (((b1 & 0x7f) as u16) << 7);
        return Some((v, 2));
    }
    let b2 = *data.get(pos + 2)?;
    if b2 & 0x80 != 0 {
        return None;
    }
    let v = ((b0 & 0x7f) as u16) | (((b1 & 0x7f) as u16) << 7) | ((b2 as u16) << 14);
    Some((v, 3))
}

fn parse_raw(payload: &[u8], chain: &str) -> Result<String> {
    let hex_str = hex::encode(payload);
    Ok(format!(r#"{{"type":"raw","hex":"0x{}","size":{},"chain":"{}"}}"#, hex_str, payload.len(), chain))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn eth_tx_legacy() {
        let rlp_hex = "e8808504a817c800825208948ba1f109551bd432803012645ac136ddd64dba72872386f26fc1000080";
        let payload = hex::decode(rlp_hex).unwrap();
        let result = parse_eth_tx(&payload).unwrap();
        assert!(result.contains(r#""to":"0x8ba1f109551bd432803012645ac136ddd64dba72"#));
        assert!(result.contains(r#""value":"10000000000000000""#));
        assert!(result.contains(r#""gas":"21000""#));
    }

    #[test]
    fn eth_tx_eip1559() {
        let rlp_hex = "02ef01808459682f0085174876e800825208948ba1f109551bd432803012645ac136ddd64dba72872386f26fc1000080c0";
        let payload = hex::decode(rlp_hex).unwrap();
        let result = parse_eth_tx(&payload).unwrap();
        assert!(result.contains(r#""txType":"eip1559""#));
        assert!(result.contains(r#""chainId":"1""#));
        assert!(result.contains(r#""priorityFee":"1500000000""#));
    }

    #[test]
    fn personal_msg_utf8() {
        let result = parse_personal_msg(b"hello world").unwrap();
        assert!(result.contains(r#""message":"hello world""#));
    }

    #[test]
    fn eip712_valid() {
        let mut p = Vec::new();
        p.extend_from_slice(&[0xabu8; 32]);
        p.extend_from_slice(&[0xcdu8; 32]);
        let result = parse_eip712(&p).unwrap();
        assert!(result.contains(r#""domainHash":"0xabababababababababababababababababababababababababababababababab"#));
    }

    #[test]
    fn parse_sign_data_dispatches() {
        let r = parse_sign_data("ethereum", "e8808504a817c800825208948ba1f109551bd432803012645ac136ddd64dba72872386f26fc1000080").unwrap();
        assert!(r.contains(r#""type":"eth_tx""#));
    }

    #[test]
    fn decode_transfer() {
        let mut data = Vec::new();
        data.extend_from_slice(&hex::decode("a9059cbb").unwrap());
        data.extend_from_slice(&hex::decode("0000000000000000000000008ba1f109551bd432803012645ac136ddd64dba72").unwrap());
        data.extend_from_slice(&hex::decode("0000000000000000000000000000000000000000000000000de0b6b3a7640000").unwrap());
        let result = decode_eth_tx_data(&data).unwrap();
        assert!(result.contains(r#""method":"transfer""#));
    }

    #[test]
    fn decode_approve() {
        let mut data = Vec::new();
        data.extend_from_slice(&hex::decode("095ea7b3").unwrap());
        data.extend_from_slice(&hex::decode("0000000000000000000000008ba1f109551bd432803012645ac136ddd64dba72").unwrap());
        data.extend_from_slice(&hex::decode("00000000000000000000000000000000000000000000000000000000000f4240").unwrap());
        let result = decode_eth_tx_data(&data).unwrap();
        assert!(result.contains(r#""method":"approve""#));
    }

    #[test]
    fn decode_transfer_from() {
        let mut data = Vec::new();
        data.extend_from_slice(&hex::decode("23b872dd").unwrap());
        data.extend_from_slice(&hex::decode("0000000000000000000000001111111111111111111111111111111111111111").unwrap());
        data.extend_from_slice(&hex::decode("0000000000000000000000002222222222222222222222222222222222222222").unwrap());
        data.extend_from_slice(&hex::decode("00000000000000000000000000000000000000000000000000000000000001f4").unwrap());
        let result = decode_eth_tx_data(&data).unwrap();
        assert!(result.contains(r#""method":"transferFrom""#));
    }

    /// Real OKX Solana transfer captured from a live BLE session: header
    /// (1 sig, 0 ro-signed, 1 ro-unsigned), 2 accounts, 1 System Program
    /// transfer of 10000 lamports.
    fn solana_transfer_message() -> Vec<u8> {
        hex::decode(concat!(
            "01000102",
            "61595f7b3fd30d7bff605bf6f310935057384cc398d1cdf9fa2f8cfc38558ba3",
            "0000000000000000000000000000000000000000000000000000000000000000",
            "ed32ad46032143d047729fa32aa8cfac5771907972d7ca87c8d012950f3bbc6f",
            "0101",
            "02",
            "0000",
            "0c",
            "02000000",
            "1027000000000000",
        ))
        .unwrap()
    }

    #[test]
    fn solana_tx_legacy_transfer() {
        let result = parse_solana_tx(&solana_transfer_message()).unwrap();
        assert!(result.contains(r#""type":"solana_tx""#));
        assert!(result.contains(r#""version":"legacy""#));
        assert!(result.contains(r#""feePayer":"7Z1b92qmpkuMxqXyYLZgbmTToxzq2jZ7J83oVZ12rPbY""#));
        assert!(result.contains(r#""numSigners":1"#));
        assert!(result.contains(r#""instructionCount":1"#));
        assert!(result.contains(r#""programId":"11111111111111111111111111111111""#));
        assert!(result.contains(r#""action":"transfer""#));
        assert!(result.contains(r#""lamports":"10000""#));
    }

    #[test]
    fn parse_sign_data_solana_dispatches() {
        let hex_msg = hex::encode(solana_transfer_message());
        let r = parse_sign_data("solana", &hex_msg).unwrap();
        assert!(r.contains(r#""type":"solana_tx""#));
    }

    #[test]
    fn solana_tx_malformed_falls_back_to_raw() {
        let r = parse_sign_data("solana", "deadbeef").unwrap();
        assert!(r.contains(r#""type":"raw""#));
    }
}
