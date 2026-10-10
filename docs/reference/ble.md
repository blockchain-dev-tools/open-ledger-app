# Device BLE transport and APDU interface

This document describes the Flutter device transport, not a web simulator transport. The [device implementation](../../apps/mobile-flutter/lib/infrastructure/ble/ble_peripheral_universal.dart) and [APDU constants](../../apps/mobile-flutter/lib/protocols/apdu/apdu_constants.dart) are authoritative.

## GATT profile

| Role | UUID |
|---|---|
| Service | `13d63400-2c97-0004-0000-4c6564676572` |
| Notify, responses from device | `13d63400-2c97-0004-0001-4c6564676572` |
| Write, requests to device | `13d63400-2c97-0004-0002-4c6564676572` |

The host subscribes to Notify and sends requests to Write. Default advertising name is `OpenLedger`; identify live advertisements primarily by service UUID rather than a personal device MAC.

## Tag-first framing

The device does **not** prepend a `0x0101` channel. Header integers are big-endian.

```text
First fragment (sequence 0):
byte 0     tag 05
bytes 1–2  sequence 0000
bytes 3–4  complete APDU byte length
bytes 5+   payload

Continuation:
byte 0     tag 05
bytes 1–2  sequence
bytes 3+   payload
```

At a 20-byte fragment size the first fragment has 15 payload bytes and subsequent fragments have 17. Use the negotiated transport limits and implementation checks; never mix this with a channel-prefixed framing codec. The response length likewise starts at bytes 3–4 of the first fragment.

## APDU and dispatch

Commands are `CLA INS P1 P2 Lc [data]`; responses are `[payload] [SW high] [SW low]`. Path encodings and payload validation depend on the active chain command.

| Dispatch | Context |
|---|---|
| `B0` | Global identity/OS commands |
| `E0` | OS commands or INS table selected by currently open Ethereum/Solana/Tron app |
| `E1` / `F8` | Bitcoin |
| `14` | Legacy Tron alias |
| `07` | Sui |

CLA `E0` app-specific commands without an open app return `6D00`. One active app is identified by [LedgerApp](../../apps/mobile-flutter/lib/core/models/chain.dart). `GET_APP_AND_VERSION` returns format `01` when an app is open, and format `00` with BOLOS on dashboard. App versions reported for protocol compatibility are not the Open Ledger App release version.

| Status | Meaning |
|---|---|
| `9000` | Successful response |
| `6985` | User rejected/conditions not satisfied |
| `6400` | Signing confirmation timed out |
| `6982` | Security status not satisfied |
| `6A80` | Invalid data |
| `6D00` | Unsupported instruction |
| `6E00` | Unsupported class |

Signing commands must pass the device confirmation gate. Queries do not release private material. See the [product contract](../product/contract.md) for locked-state and terminal-decision requirements.

## Discovery and verification

Subscribe to live BlueZ `InterfacesAdded` and `PropertiesChanged` signals while discovering. Reading `GetManagedObjects()` after scanning can omit transient UUID/RSSI properties and is not reliable advertisement evidence. A scan-response service UUID is not inherently undiscoverable; distinguish stale-cache readings and platform delivery failures from actual advertising data. Random LE addresses may differ from the phone's classic Bluetooth MAC.

The APDU corpus in [spec/apdu/](../../spec/apdu/) declares command coverage, vectors and known gaps. `regression` vectors capture implementation behavior; only independently captured firmware vectors establish byte-level conformance for their measured cases. Passing vectors does not establish compatibility with every host wallet or instruction.

[APDU handler](../../apps/mobile-flutter/lib/biz/apdu_handler.dart), [sign approval](../../apps/mobile-flutter/lib/biz/sign_confirmation.dart), [real-device harness](../../apps/mobile-flutter/tool/e2e/README.md).
