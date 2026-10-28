//! 审批绑定的确定性编码。
//!
//! 不使用 JSON map 顺序、不依赖可变字符串拼接；所有字段长度前缀 + 类型标签，
//! 任何一项（模块、版本、epoch、金库、线协议、审阅、计划）变化都会改变摘要。

use chain_app_api::review::{Field, FieldValue, ReviewDocument};
use chain_app_api::sign::{SignOperation, SignPlan, SignScheme};
use sha2::{Digest as Sha2Digest, Sha256};

pub type Digest = [u8; 32];

const DOMAIN: &[u8] = b"openledger/chain-app/approval/v1";

struct Encoder {
    buf: Vec<u8>,
}

impl Encoder {
    fn new() -> Self {
        Self { buf: Vec::new() }
    }

    fn tag(&mut self, tag: &str) {
        self.bytes(tag.as_bytes());
    }

    fn bytes(&mut self, data: &[u8]) {
        self.buf.extend_from_slice(&(data.len() as u64).to_be_bytes());
        self.buf.extend_from_slice(data);
    }

    fn u64(&mut self, value: u64) {
        self.buf.extend_from_slice(&value.to_be_bytes());
    }

    fn finish(self) -> Digest {
        let mut hasher = Sha256::new();
        hasher.update(DOMAIN);
        hasher.update(&self.buf);
        hasher.finalize().into()
    }
}

fn encode_field(enc: &mut Encoder, field: &Field) {
    enc.tag("field");
    enc.bytes(field.label_key.as_bytes());
    match &field.value {
        FieldValue::Address {
            value,
            network,
            role,
        } => {
            enc.tag("address");
            enc.bytes(value.as_bytes());
            enc.bytes(network.as_bytes());
            enc.bytes(role.as_bytes());
        }
        FieldValue::Amount {
            raw,
            decimals,
            asset,
            ticker,
        } => {
            enc.tag("amount");
            enc.bytes(raw.as_bytes());
            enc.u64(u64::from(*decimals));
            enc.bytes(asset.as_bytes());
            match ticker {
                Some(t) => {
                    enc.tag("ticker");
                    enc.bytes(t.as_bytes());
                }
                None => enc.tag("no-ticker"),
            }
        }
        FieldValue::Fee {
            kind,
            raw,
            decimals,
            asset,
        } => {
            enc.tag("fee");
            enc.tag(match kind {
                chain_app_api::review::FeeKind::Known => "known",
                chain_app_api::review::FeeKind::UpperBound => "upper-bound",
                chain_app_api::review::FeeKind::Estimated => "estimated",
                chain_app_api::review::FeeKind::Unknown => "unknown",
            });
            match raw {
                Some(r) => {
                    enc.tag("value");
                    enc.bytes(r.as_bytes());
                }
                None => enc.tag("no-value"),
            }
            enc.u64(u64::from(*decimals));
            enc.bytes(asset.as_bytes());
        }
        FieldValue::Text { value } => {
            enc.tag("text");
            enc.bytes(value.as_bytes());
        }
        FieldValue::Bytes { value } => {
            enc.tag("bytes");
            enc.bytes(value);
        }
        FieldValue::Structured { entries } => {
            enc.tag("structured");
            enc.u64(entries.len() as u64);
            for entry in entries {
                encode_field(enc, entry);
            }
        }
        FieldValue::Boolean(value) => {
            enc.tag("bool");
            enc.u64(u64::from(*value));
        }
    }
}

fn encode_document(enc: &mut Encoder, document: &ReviewDocument) {
    enc.tag("review");
    enc.tag(match document.operation {
        chain_app_api::review::OperationKind::Transaction => "transaction",
        chain_app_api::review::OperationKind::Message => "message",
        chain_app_api::review::OperationKind::AddressConfirmation => "address",
        chain_app_api::review::OperationKind::SettingsChange => "settings",
    });
    enc.bytes(document.network.name.as_bytes());
    enc.u64(document.network.chain_id.unwrap_or(0));
    match &document.account {
        Some(a) => {
            enc.tag("account");
            enc.bytes(a.as_bytes());
        }
        None => enc.tag("no-account"),
    }
    enc.tag(match document.parse_status {
        chain_app_api::review::ParseStatus::Complete => "complete",
        chain_app_api::review::ParseStatus::Partial => "partial",
        chain_app_api::review::ParseStatus::Opaque => "opaque",
    });
    enc.u64(document.sections.len() as u64);
    for section in &document.sections {
        enc.tag("section");
        enc.bytes(section.title_key.as_bytes());
        enc.u64(section.fields.len() as u64);
        for field in &section.fields {
            encode_field(enc, field);
        }
    }
    enc.u64(document.risks.len() as u64);
    for risk in &document.risks {
        enc.tag("risk");
        enc.bytes(risk.code.as_bytes());
        enc.u64(risk.severity as u64);
        enc.u64(risk.parameters.len() as u64);
        for (k, v) in &risk.parameters {
            enc.bytes(k.as_bytes());
            enc.bytes(v.as_bytes());
        }
    }
}

fn encode_scheme(enc: &mut Encoder, scheme: &SignScheme) {
    match scheme {
        SignScheme::EcdsaPrehash { digest_len, low_s } => {
            enc.tag("ecdsa-prehash");
            enc.u64(u64::from(*digest_len));
            enc.u64(u64::from(*low_s));
        }
        SignScheme::Ed25519Message => enc.tag("ed25519-message"),
    }
}

fn encode_operation(enc: &mut Encoder, op: &SignOperation) {
    enc.tag("op");
    enc.u64(u64::from(op.operation_id));
    enc.u64(op.derivation_scheme as u64);
    enc.u64(op.curve as u64);
    enc.u64(op.path.len() as u64);
    for component in &op.path {
        enc.u64(u64::from(*component));
    }
    encode_scheme(enc, &op.scheme);
    enc.bytes(&op.input);
    enc.u64(op.public_parameters.len() as u64);
    for (k, v) in &op.public_parameters {
        enc.bytes(k.as_bytes());
        enc.bytes(v);
    }
}

fn encode_plan(enc: &mut Encoder, plan: &SignPlan) {
    enc.tag("plan");
    enc.u64(plan.operations.len() as u64);
    for op in &plan.operations {
        encode_operation(enc, op);
    }
}

/// 模块静态指纹：ID、版本、接口版本与能力声明。用于版本回退限制与审计。
pub fn descriptor_digest(descriptor: &chain_app_api::manifest::AppDescriptor) -> Digest {
    let mut enc = Encoder::new();
    enc.tag("descriptor");
    enc.bytes(descriptor.module_id.as_bytes());
    enc.bytes(descriptor.module_version.as_bytes());
    enc.u64(u64::from(descriptor.api_version));
    enc.u64(u64::from(descriptor.review_schema_version));
    enc.u64(u64::from(descriptor.storage_schema_version));
    enc.u64(descriptor.protocol_profiles.len() as u64);
    for profile in &descriptor.protocol_profiles {
        enc.bytes(profile.name.as_bytes());
        enc.bytes(profile.version.as_bytes());
        enc.bytes(profile.wire.as_str().as_bytes());
        enc.u64(profile.supported.len() as u64);
        for item in &profile.supported {
            enc.bytes(item.as_bytes());
        }
        enc.u64(profile.unsupported.len() as u64);
        for item in &profile.unsupported {
            enc.bytes(item.as_bytes());
        }
    }
    enc.u64(descriptor.account_profiles.len() as u64);
    for account in &descriptor.account_profiles {
        enc.bytes(account.network.as_bytes());
        enc.bytes(account.account_type.as_bytes());
        enc.bytes(account.default_path.as_bytes());
        enc.u64(account.derivation_scheme as u64);
        enc.u64(account.curve as u64);
    }
    let capabilities = &descriptor.requested_capabilities;
    enc.u64(capabilities.derivation_rules.len() as u64);
    for rule in &capabilities.derivation_rules {
        enc.u64(rule.derivation_scheme as u64);
        enc.u64(rule.curve as u64);
        enc.u64(u64::from(rule.depth));
        enc.u64(rule.hardened_positions.len() as u64);
        for position in &rule.hardened_positions {
            enc.u64(u64::from(*position));
        }
        enc.u64(u64::from(rule.max_index));
    }
    enc.u64(u64::from(capabilities.allow_chain_code));
    enc.u64(u64::from(capabilities.allow_signing));
    enc.u64(u64::from(capabilities.allow_storage));
    enc.finish()
}

/// 冻结审批时写入绑定记录的摘要。
pub struct BindingInputs<'a> {
    pub module_id: &'a str,
    pub module_version: &'a str,
    pub epoch: u64,
    pub vault: &'a str,
    pub wire: chain_app_api::manifest::Wire,
    pub request: &'a chain_app_api::review::ReviewRequest,
}

pub fn binding_digest(inputs: &BindingInputs<'_>) -> Digest {
    let mut enc = Encoder::new();
    enc.tag("binding");
    enc.bytes(inputs.module_id.as_bytes());
    enc.bytes(inputs.module_version.as_bytes());
    enc.u64(inputs.epoch);
    enc.bytes(inputs.vault.as_bytes());
    enc.bytes(inputs.wire.as_str().as_bytes());
    encode_document(&mut enc, &inputs.request.document);
    match &inputs.request.action {
        chain_app_api::review::ReviewAction::DisplayAddress {
            derivation_scheme,
            curve,
            path,
        } => {
            enc.tag("action-address");
            enc.u64(*derivation_scheme as u64);
            enc.u64(*curve as u64);
            enc.u64(path.len() as u64);
            for component in path {
                enc.u64(u64::from(*component));
            }
        }
        chain_app_api::review::ReviewAction::ChangeSetting { key, value } => {
            enc.tag("action-setting");
            enc.bytes(key.as_bytes());
            enc.bytes(value);
        }
        chain_app_api::review::ReviewAction::Sign(plan) => {
            enc.tag("action-sign");
            encode_plan(&mut enc, plan);
        }
    }
    enc.finish()
}
