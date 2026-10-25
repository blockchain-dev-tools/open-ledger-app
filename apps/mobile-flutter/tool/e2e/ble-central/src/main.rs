//! BLE GATT central for the E2E regression suite.
//!
//! Reads one JSON command per stdin line, writes one JSON reply per stdout line.
//! It is deliberately a dumb pipe: fragmentation/reassembly stays in Python
//! (`harness/ble_framing.py`), so the wire format has a single implementation.
//!
//! Commands:
//!   {"cmd":"scan","timeout":25}      → {"address","name","matched_by"}
//!   {"cmd":"connect"}                → {}
//!   {"cmd":"notify"}                 → {}
//!   {"cmd":"write","hex":"..."}      → {}
//!   {"cmd":"recv","timeout":15}      → {"hex":"..."}
//!   {"cmd":"drain"}                  → {"dropped"}
//!   {"cmd":"close"}                  → {}
//!   {"cmd":"quit"}                   → {}
//!
//! btleplug maps to CoreBluetooth on macOS and BlueZ on Linux, so the same
//! binary drives the suite on either host.

use std::io::Write as _;
use std::time::{Duration, Instant};

use anyhow::{anyhow, Context, Result};
use btleplug::api::{Central, Characteristic, Manager as _, Peripheral as _, ScanFilter, WriteType};
use btleplug::platform::{Adapter, Manager, Peripheral};
use futures::StreamExt;
use serde_json::{json, Value};
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::sync::mpsc;
use uuid::Uuid;

const SERVICE_UUID: Uuid = uuid::uuid!("13d63400-2c97-0004-0000-4c6564676572");
const RESP_UUID: Uuid = uuid::uuid!("13d63400-2c97-0004-0001-4c6564676572");
const CMD_UUID: Uuid = uuid::uuid!("13d63400-2c97-0004-0002-4c6564676572");
const WWR_UUID: Uuid = uuid::uuid!("13d63400-2c97-0004-0003-4c6564676572");

/// The 128-bit service UUID rides in the scan response, which some stacks never
/// expose; the local name is the reliable advertisement-side match.
const DEVICE_NAME_PREFIX: &str = "OpenLedgerApp";

struct Session {
    peripheral: Peripheral,
    cmd: Characteristic,
    write_type: WriteType,
    notifications: mpsc::Receiver<Vec<u8>>,
}

#[tokio::main]
async fn main() -> Result<()> {
    let manager = Manager::new().await.context(
        "无法初始化蓝牙（macOS 首次运行需在“系统设置 → 隐私与安全性 → 蓝牙”里允许终端）",
    )?;
    let adapters = manager.adapters().await.context("读取蓝牙适配器失败")?;
    let adapter = adapters.into_iter().next().ok_or_else(|| {
        anyhow!("没有可用的蓝牙适配器（检查蓝牙开关与终端权限）")
    })?;

    let mut discovered: Option<Peripheral> = None;
    let mut session: Option<Session> = None;
    let mut lines = BufReader::new(tokio::io::stdin()).lines();

    while let Some(line) = lines.next_line().await? {
        if line.trim().is_empty() {
            continue;
        }
        let request: Value = match serde_json::from_str(&line) {
            Ok(value) => value,
            Err(err) => {
                reply(json!({"ok": false, "error": format!("bad json: {err}")}));
                continue;
            }
        };
        let command = request["cmd"].as_str().unwrap_or_default().to_string();
        let outcome = handle(&command, &request, &adapter, &mut discovered, &mut session).await;
        match outcome {
            Ok(fields) => {
                let mut out = json!({"ok": true});
                if let Some(map) = fields.as_object() {
                    for (key, value) in map {
                        out[key] = value.clone();
                    }
                }
                reply(out);
            }
            Err(err) => reply(json!({"ok": false, "error": err.to_string()})),
        }
        if command == "quit" {
            break;
        }
    }
    Ok(())
}

fn reply(value: Value) {
    println!("{value}");
    std::io::stdout().flush().ok();
}

async fn handle(
    command: &str,
    request: &Value,
    adapter: &Adapter,
    discovered: &mut Option<Peripheral>,
    session: &mut Option<Session>,
) -> Result<Value> {
    match command {
        "scan" => {
            let timeout = request["timeout"].as_f64().unwrap_or(25.0);
            let (peripheral, name, matched_by) = scan(adapter, timeout).await?;
            let address = peripheral.id().to_string();
            *discovered = Some(peripheral);
            Ok(json!({
                "address": address,
                "name": name,
                "matched_by": matched_by,
            }))
        }
        "connect" => {
            let peripheral = discovered.take().ok_or_else(|| anyhow!("先 scan"))?;
            *session = Some(connect(peripheral).await?);
            Ok(json!({}))
        }
        "notify" => {
            // `connect` already subscribes and starts the notification pump.
            if session.is_none() {
                return Err(anyhow!("先 connect"));
            }
            Ok(json!({}))
        }
        "write" => {
            let current = session.as_mut().ok_or_else(|| anyhow!("先 connect"))?;
            let data = decode_hex(request["hex"].as_str().unwrap_or_default())?;
            current
                .peripheral
                .write(&current.cmd, &data, current.write_type)
                .await
                .context("写入特征失败")?;
            Ok(json!({}))
        }
        "recv" => {
            let current = session.as_mut().ok_or_else(|| anyhow!("先 connect"))?;
            let timeout = request["timeout"].as_f64().unwrap_or(15.0);
            match tokio::time::timeout(
                Duration::from_secs_f64(timeout),
                current.notifications.recv(),
            )
            .await
            {
                Ok(Some(value)) => Ok(json!({"hex": encode_hex(&value)})),
                Ok(None) => Err(anyhow!("通知流已关闭")),
                Err(_) => Err(anyhow!("等待通知超时（{timeout}s）")),
            }
        }
        "drain" => {
            let current = session.as_mut().ok_or_else(|| anyhow!("先 connect"))?;
            let mut dropped = 0;
            while current.notifications.try_recv().is_ok() {
                dropped += 1;
            }
            Ok(json!({"dropped": dropped}))
        }
        "close" => {
            if let Some(current) = session.take() {
                current.peripheral.disconnect().await.ok();
            }
            *discovered = None;
            Ok(json!({}))
        }
        "quit" => {
            if let Some(current) = session.take() {
                current.peripheral.disconnect().await.ok();
            }
            *discovered = None;
            Ok(json!({}))
        }
        other => Err(anyhow!("unknown command: {other}")),
    }
}

async fn scan(adapter: &Adapter, timeout: f64) -> Result<(Peripheral, String, String)> {
    adapter
        .start_scan(ScanFilter::default())
        .await
        .context("开始扫描失败（检查终端蓝牙权限）")?;
    let deadline = Instant::now() + Duration::from_secs_f64(timeout);

    let found = 'scan: loop {
        for peripheral in adapter.peripherals().await? {
            let props = match peripheral.properties().await? {
                Some(properties) => properties,
                None => continue,
            };
            let name = props.local_name.clone().unwrap_or_default();
            if name.starts_with(DEVICE_NAME_PREFIX) {
                break 'scan Some((peripheral, name, "device-name".to_string()));
            }
            if props.services.contains(&SERVICE_UUID) {
                break 'scan Some((peripheral, name, "service-uuid".to_string()));
            }
        }
        if Instant::now() >= deadline {
            break 'scan None;
        }
        tokio::time::sleep(Duration::from_millis(250)).await;
    };
    adapter.stop_scan().await.ok();

    found.ok_or_else(|| anyhow!("扫描未发现 Open Ledger App 外设"))
}

async fn connect(peripheral: Peripheral) -> Result<Session> {
    peripheral.connect().await.context("连接失败")?;
    peripheral
        .discover_services()
        .await
        .context("GATT 服务发现失败")?;

    let characteristics = peripheral.characteristics();
    let resp = characteristics
        .iter()
        .find(|characteristic| characteristic.uuid == RESP_UUID)
        .cloned()
        .ok_or_else(|| anyhow!("未找到响应特征（0001）"))?;
    let (cmd, write_type) = match characteristics.iter().find(|c| c.uuid == CMD_UUID) {
        Some(characteristic) => (characteristic.clone(), WriteType::WithResponse),
        None => (
            characteristics
                .iter()
                .find(|c| c.uuid == WWR_UUID)
                .cloned()
                .ok_or_else(|| anyhow!("未找到命令特征（0002/0003）"))?,
            WriteType::WithoutResponse,
        ),
    };

    peripheral
        .subscribe(&resp)
        .await
        .context("订阅响应特征失败")?;
    let mut stream = peripheral
        .notifications()
        .await
        .context("打开通知流失败")?;
    let (sender, receiver) = mpsc::channel(64);
    tokio::spawn(async move {
        while let Some(notification) = stream.next().await {
            if notification.uuid == RESP_UUID {
                if sender.send(notification.value).await.is_err() {
                    break;
                }
            }
        }
    });

    Ok(Session {
        peripheral,
        cmd,
        write_type,
        notifications: receiver,
    })
}

fn decode_hex(text: &str) -> Result<Vec<u8>> {
    let cleaned: String = text.chars().filter(|c| !c.is_whitespace()).collect();
    if cleaned.len() % 2 != 0 {
        return Err(anyhow!("hex 长度必须为偶数"));
    }
    (0..cleaned.len())
        .step_by(2)
        .map(|index| {
            u8::from_str_radix(&cleaned[index..index + 2], 16)
                .map_err(|_| anyhow!("非法 hex: {text}"))
        })
        .collect()
}

fn encode_hex(bytes: &[u8]) -> String {
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}
