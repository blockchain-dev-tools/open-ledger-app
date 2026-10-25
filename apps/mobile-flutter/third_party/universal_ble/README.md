# universal_ble (vendored fork)

Upstream: [Navideck/universal_ble](https://github.com/Navideck/universal_ble) 2.3.0, MIT (see `LICENSE`).
Vendored so the Android peripheral can survive a Bluetooth off/on toggle; only the Android
sources under `android/` differ from upstream, plus this file and `pubspec.yaml` (the unused
Windows implementation was dropped). `lib/` and `darwin/` are unchanged.

## Why this fork exists

`UniversalBlePeripheralPlugin` caches its `BluetoothGattServer` and `BluetoothLeAdvertiser`
forever (`ensurePeripheralInitialized()` returns early once both exist). When the user or the
system toggles Bluetooth, the framework Bluetooth process dies with the adapter: the cached
server's binder becomes dead, `addService()` / `clearServices()` swallow the
`DeadObjectException`, and `onServiceAdded` never fires. Advertising can then never restart
without killing the app process, while `getAdvertisingState()` still reports stale state.

## Patch

- `UniversalBlePeripheralPlugin.onAdapterStateChanged()` — drops and closes the cached
  `gattServer` / `bluetoothLeAdvertiser`, clears per-device caches, and pushes advertising
  state `IDLE` to Dart.
- `UniversalBlePlugin`'s `ACTION_STATE_CHANGED` receiver calls it for every adapter state
  change, before forwarding availability to Dart.

Consequence: the next peripheral call (for example the app's rebuilt `startAdvertising()`)
opens a fresh GATT server against the live Bluetooth process.

Do not regenerate the pigeon sources; they match upstream 2.3.0.
