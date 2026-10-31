//! Sui BCS 交易解析（只覆盖「原生 SUI / Token 转账」这一族）。
//!
//! 官方 `app-sui` 解析完整 BCS 交易，识别出「收款方 + 金额 + gas」后展示；
//! 识别不了就拒绝（未开盲签时回 `SW_NOT_SUPPORTED`）。这里按同样的原则做
//! **一个更窄的子集**：
//!
//! ```text
//! Intent(0,0,0) || TransactionData::V1(TransactionKind::ProgrammableTransaction{
//!     inputs, commands
//! }, sender, gas_data, expiration)
//!
//! commands == [
//!     SplitCoins(<GasCoin | Input(coin-object)>, [Input(amount)…]),
//!     TransferObjects([Result(0)], Input(recipient)),
//! ]
//! ```
//!
//! 形状不匹配（MoveCall / MergeCoins / send-max / 多收款方 / SIP-58 余额支付 …）
//! 一律返回 [`Parsed::Unsupported`]，由调用方回 `0x6808`，绝不猜测字段。

pub const SUI_DECIMALS: u8 = 9;

const MAX_INPUTS: usize = 16;
const MAX_COMMANDS: usize = 16;
const MAX_PURE_LEN: usize = 256;
const MAX_GAS_COINS: usize = 32;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Asset {
    /// 直接用 `GasCoin` 拆分出的原生 SUI。
    Native,
    /// 从某个 coin object 拆出的代币；币种取决于对象数据，这里只能给 base units。
    Token,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Transfer {
    pub asset: Asset,
    pub sender: [u8; 32],
    pub recipient: [u8; 32],
    pub amount: u64,
    pub gas_price: u64,
    pub gas_budget: u64,
    /// `gas_data.payment` 的条数；0 表示 SIP-58 用地址余额付 gas。
    pub gas_payments: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Parsed {
    Transfer(Transfer),
    Unsupported,
}

#[derive(Clone, Copy)]
enum Argument {
    GasCoin,
    Input(u16),
    Result(u16),
    /// 只用于把字节流读干净；我们的形状校验不会接受它。
    NestedResult,
}

enum Input {
    Amount(u64),
    Address([u8; 32]),
    Object,
    Other,
}

enum Command {
    SplitCoins(Argument, Vec<Argument>),
    TransferObjects(Vec<Argument>, Argument),
}

struct Reader<'a> {
    buf: &'a [u8],
    pos: usize,
}

impl<'a> Reader<'a> {
    fn new(buf: &'a [u8]) -> Self {
        Self { buf, pos: 0 }
    }

    fn take(&mut self, len: usize) -> Option<&'a [u8]> {
        let end = self.pos.checked_add(len)?;
        if end > self.buf.len() {
            return None;
        }
        let slice = &self.buf[self.pos..end];
        self.pos = end;
        Some(slice)
    }

    fn u8(&mut self) -> Option<u8> {
        self.take(1).map(|b| b[0])
    }

    fn u16le(&mut self) -> Option<u16> {
        self.take(2).map(|b| u16::from_le_bytes([b[0], b[1]]))
    }

    fn u32le(&mut self) -> Option<u32> {
        self.take(4).map(|b| u32::from_le_bytes([b[0], b[1], b[2], b[3]]))
    }

    fn u64le(&mut self) -> Option<u64> {
        self.take(8).map(|b| {
            let mut raw = [0u8; 8];
            raw.copy_from_slice(b);
            u64::from_le_bytes(raw)
        })
    }

    fn address(&mut self) -> Option<[u8; 32]> {
        self.take(32).map(|b| {
            let mut out = [0u8; 32];
            out.copy_from_slice(b);
            out
        })
    }

    /// BCS 的变长整数（仅用于长度与枚举标签，值域按 u32 限制）。
    fn uleb(&mut self) -> Option<u32> {
        let mut value: u64 = 0;
        for shift in 0..5 {
            let byte = self.u8()?;
            value |= ((byte & 0x7F) as u64) << (7 * shift);
            if byte & 0x80 == 0 {
                return u32::try_from(value).ok();
            }
        }
        None
    }

    fn done(&self) -> bool {
        self.pos == self.buf.len()
    }
}

fn parse_object_ref(reader: &mut Reader<'_>) -> Option<()> {
    reader.address()?; // object id
    reader.u64le()?; // version
    reader.address()?; // digest
    Some(())
}

fn parse_input(reader: &mut Reader<'_>) -> Option<Input> {
    match reader.u8()? {
        0x00 => {
            let len = reader.uleb()? as usize;
            if len == 0 || len > MAX_PURE_LEN {
                return None;
            }
            let raw = reader.take(len)?;
            Some(match len {
                8 => {
                    let mut value = [0u8; 8];
                    value.copy_from_slice(raw);
                    Input::Amount(u64::from_le_bytes(value))
                }
                32 => {
                    let mut value = [0u8; 32];
                    value.copy_from_slice(raw);
                    Input::Address(value)
                }
                _ => Input::Other,
            })
        }
        0x01 => match reader.u8()? {
            // ImmOrOwnedObject / Receiving：两种都是完整 ObjectRef。
            0x00 | 0x02 => parse_object_ref(reader).map(|_| Input::Object),
            // SharedObject：id + initial_shared_version + mutable。
            0x01 => {
                reader.address()?;
                reader.u64le()?;
                reader.u8()?;
                Some(Input::Object)
            }
            _ => None,
        },
        // SIP-58 FundsWithdrawal：本期不展示，直接判为不可识别。
        _ => None,
    }
}

fn parse_argument(reader: &mut Reader<'_>) -> Option<Argument> {
    // 官方 `ArgumentSchema`：枚举标签是 ULEB128，索引是 **u16 little-endian**。
    Some(match reader.uleb()? {
        0 => Argument::GasCoin,
        1 => Argument::Input(reader.u16le()?),
        2 => Argument::Result(reader.u16le()?),
        3 => {
            reader.u16le()?;
            reader.u16le()?;
            Argument::NestedResult
        }
        _ => return None,
    })
}

fn parse_arguments(reader: &mut Reader<'_>) -> Option<Vec<Argument>> {
    let count = reader.uleb()? as usize;
    if count > MAX_COMMANDS {
        return None;
    }
    (0..count).map(|_| parse_argument(reader)).collect()
}

fn parse_command(reader: &mut Reader<'_>) -> Option<Command> {
    match reader.uleb()? {
        // MoveCall：质押 / DeFi / 部分钱包的代币转账，本期不解析。
        0 => None,
        1 => {
            let objects = parse_arguments(reader)?;
            let recipient = parse_argument(reader)?;
            Some(Command::TransferObjects(objects, recipient))
        }
        2 => {
            let coin = parse_argument(reader)?;
            let amounts = parse_arguments(reader)?;
            Some(Command::SplitCoins(coin, amounts))
        }
        _ => None,
    }
}

fn parse_expiration(reader: &mut Reader<'_>) -> Option<()> {
    match reader.u8()? {
        0 => Some(()),
        1 => reader.u64le().map(|_| ()),
        // SIP-58 ValidDuring：4 个 Option<u64> + 长度前缀的 chain + u32 nonce。
        2 => {
            for _ in 0..4 {
                if reader.u8()? == 1 {
                    reader.u64le()?;
                }
            }
            let len = reader.uleb()? as usize;
            reader.take(len)?;
            reader.u32le()?;
            Some(())
        }
        _ => None,
    }
}

/// 解析宿主交来的交易字节；任何形状不符都返回 [`Parsed::Unsupported`]。
pub fn parse_transaction(tx: &[u8]) -> Parsed {
    match try_parse(tx) {
        Some(transfer) => Parsed::Transfer(transfer),
        None => Parsed::Unsupported,
    }
}

fn try_parse(tx: &[u8]) -> Option<Transfer> {
    let mut reader = Reader::new(tx);
    // Intent：version / scope / app_id 必须都是 0（TransactionData）。
    if reader.u8()? != 0 || reader.u8()? != 0 || reader.u8()? != 0 {
        return None;
    }
    // TransactionData::V1 与 TransactionKind::ProgrammableTransaction。
    if reader.u8()? != 0 || reader.u8()? != 0 {
        return None;
    }

    let input_count = reader.uleb()? as usize;
    if input_count > MAX_INPUTS {
        return None;
    }
    let mut inputs = Vec::with_capacity(input_count);
    for _ in 0..input_count {
        inputs.push(parse_input(&mut reader)?);
    }

    let command_count = reader.uleb()? as usize;
    if command_count > MAX_COMMANDS {
        return None;
    }
    let mut commands = Vec::with_capacity(command_count);
    for _ in 0..command_count {
        commands.push(parse_command(&mut reader)?);
    }

    let sender = reader.address()?;

    let gas_payments = reader.uleb()? as usize;
    if gas_payments > MAX_GAS_COINS {
        return None;
    }
    for _ in 0..gas_payments {
        parse_object_ref(&mut reader)?;
    }
    reader.address()?; // gas owner
    let gas_price = reader.u64le()?;
    let gas_budget = reader.u64le()?;
    parse_expiration(&mut reader)?;
    // 解析必须刚好吃掉宿主声明的整段字节，否则展示与签名可能不一致。
    if !reader.done() {
        return None;
    }

    if commands.len() != 2 {
        return None;
    }
    let mut iter = commands.into_iter();
    let split = iter.next()?;
    let transfer = iter.next()?;
    let (source, amounts) = match split {
        Command::SplitCoins(source, amounts) => (source, amounts),
        _ => return None,
    };
    let (objects, recipient) = match transfer {
        Command::TransferObjects(objects, recipient) => (objects, recipient),
        _ => return None,
    };

    if objects.len() != 1 || !matches!(objects[0], Argument::Result(0)) {
        return None;
    }
    let Argument::Input(recipient_index) = recipient else {
        return None;
    };
    let recipient = match inputs.get(recipient_index as usize)? {
        Input::Address(address) => *address,
        _ => return None,
    };

    let asset = match source {
        Argument::GasCoin => Asset::Native,
        Argument::Input(index) => match inputs.get(index as usize)? {
            Input::Object => Asset::Token,
            _ => return None,
        },
        _ => return None,
    };

    // send-max（直接转整个 GasCoin）与「按对象余额拆分」都拿不到确定金额：拒绝。
    if amounts.is_empty() {
        return None;
    }
    let mut total: u64 = 0;
    for argument in amounts {
        let Argument::Input(index) = argument else {
            return None;
        };
        let amount = match inputs.get(index as usize)? {
            Input::Amount(value) => *value,
            _ => return None,
        };
        total = total.checked_add(amount)?;
    }
    if total == 0 {
        return None;
    }

    Some(Transfer {
        asset,
        sender,
        recipient,
        amount: total,
        gas_price,
        gas_budget,
        gas_payments: gas_payments as u64,
    })
}
