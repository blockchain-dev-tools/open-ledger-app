//! BIP-32 路径与 Keystone `crypto-keypath` 组件之间的转换。
//!
//! Keystone 的线上表示把路径摊平成一个数组：`[index, hardened, index, ...]`，
//! 不是 `{index, hardened}` 对象数组（2026-10-28 向量核对确认）。

use ciborium::value::{Integer, Value};
use open_ledger_biz::errors::{ChainError, Result};

const HARDENED_BIT: u32 = 0x8000_0000;

pub type Component = (u32, bool);

pub fn parse_path(path: &str) -> Result<Vec<Component>> {
    let mut segments = path.split('/');
    let head = segments.next().unwrap_or_default();
    if head != "m" {
        return Err(ChainError::InvalidPath(format!(
            "path must start with 'm': {path}"
        )));
    }
    let mut components = Vec::new();
    for segment in segments {
        if segment.is_empty() {
            return Err(ChainError::InvalidPath(format!("empty component: {path}")));
        }
        let (digits, hardened) = match segment.strip_suffix('\'') {
            Some(rest) => (rest, true),
            None => (segment, false),
        };
        let index: u32 = digits
            .parse()
            .map_err(|_| ChainError::InvalidPath(format!("invalid component '{segment}'")))?;
        if index & HARDENED_BIT != 0 {
            return Err(ChainError::InvalidPath(format!(
                "component out of range: {segment}"
            )));
        }
        components.push((index, hardened));
    }
    if components.len() > 10 {
        return Err(ChainError::InvalidPath(format!("path too deep: {path}")));
    }
    Ok(components)
}

pub fn render_path(components: &[Component]) -> String {
    let mut out = String::from("m");
    for (index, hardened) in components {
        out.push('/');
        out.push_str(&index.to_string());
        if *hardened {
            out.push('\'');
        }
    }
    out
}

/// `[(44, true), (60, true)]` → CBOR 数组 `[44, true, 60, true]`。
pub fn components_to_cbor(components: &[Component]) -> Value {
    let mut items = Vec::with_capacity(components.len() * 2);
    for (index, hardened) in components {
        items.push(int_value(*index as i128));
        items.push(Value::Bool(*hardened));
    }
    Value::Array(items)
}

pub fn components_from_cbor(value: &Value) -> Result<Vec<Component>> {
    let items = value
        .as_array()
        .ok_or_else(|| ChainError::ParseError("keypath components must be an array".into()))?;
    if items.len() % 2 != 0 {
        return Err(ChainError::ParseError(
            "keypath components must be flat [index, hardened] pairs".into(),
        ));
    }
    let mut components = Vec::with_capacity(items.len() / 2);
    for pair in items.chunks(2) {
        let index = as_i128(&pair[0])?;
        let hardened = pair[1].as_bool().ok_or_else(|| {
            ChainError::ParseError("keypath hardened flag must be a boolean".into())
        })?;
        if index < 0 || index >= HARDENED_BIT as i128 {
            return Err(ChainError::ParseError(format!(
                "keypath index out of range: {index}"
            )));
        }
        components.push((index as u32, hardened));
    }
    if components.len() > 10 {
        return Err(ChainError::ParseError("keypath too deep".into()));
    }
    Ok(components)
}

pub fn int_value(value: i128) -> Value {
    Value::Integer(Integer::try_from(value).expect("integer fits ciborium"))
}

pub fn as_i128(value: &Value) -> Result<i128> {
    value
        .as_integer()
        .map(i128::from)
        .ok_or_else(|| ChainError::ParseError("expected integer".into()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_and_renders_eth_path() {
        let components = parse_path("m/44'/60'/0'/0/0").unwrap();
        assert_eq!(components, vec![(44, true), (60, true), (0, true), (0, false), (0, false)]);
        assert_eq!(render_path(&components), "m/44'/60'/0'/0/0");
    }

    #[test]
    fn master_path_is_empty() {
        assert!(parse_path("m").unwrap().is_empty());
        assert_eq!(render_path(&[]), "m");
    }

    #[test]
    fn rejects_bad_paths() {
        assert!(parse_path("44'/60'").is_err());
        assert!(parse_path("m/44''").is_err());
        assert!(parse_path("m/2147483648").is_err());
    }

    #[test]
    fn cbor_round_trip() {
        let components = parse_path("m/44'/60'/0'/0/3").unwrap();
        let value = components_to_cbor(&components);
        assert_eq!(components_from_cbor(&value).unwrap(), components);
    }

    #[test]
    fn cbor_rejects_odd_length() {
        let value = Value::Array(vec![int_value(44)]);
        assert!(components_from_cbor(&value).is_err());
    }
}
