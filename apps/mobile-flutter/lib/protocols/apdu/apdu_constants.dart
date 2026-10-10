/// APDU protocol constants — CLA, INS, SW enums matching Ledger APDU spec.
///
/// Ported from open-ledger-mono: `packages/apdu/src/constants.ts`
///
/// CLA byte mapping (per AGENTS.md and mono constants):
///   0xb0 — Ethereum (app-specific)
///   0xe0 — OS commands / Ethereum / Solana / Tron
///   0xe1 — Bitcoin (legacy)
///   0xf8 — Bitcoin (extended)
///   0x14 — Tron (legacy/self-defined alias — see note below)
///   0x07 — Sui
///
/// NOTE on Tron: the real Ledger Tron app (@ledgerhq/hw-app-trx in
/// LedgerHQ/ledger-live) speaks **CLA 0xE0**, the same CLA as the Ethereum
/// and Solana apps — a real device runs only one app at a time, so the OS
/// routes 0xE0 to whichever app is open. Host wallets (TronLink, OKX) send
/// Tron commands on 0xE0, so ApduHandler dispatches 0xE0 by the currently
/// exposed app, exactly like Solana. CLA 0x14 is kept only for backward
/// compatibility with this repo's earlier Tron handler.
library;

/// Class byte (CLA) identifiers — determines which chain/service handles
/// the APDU command.
class Cla {
  Cla._();

  /// OS commands + Ethereum + Solana.
  static const int os = 0xe0;

  /// Global / OS-level commands (GET_APP_AND_VERSION etc.).
  static const int global = 0xb0;

  /// Bitcoin (legacy).
  static const int bitcoin = 0xe1;

  /// Bitcoin (extended protocol).
  static const int bitcoinExt = 0xf8;

  /// Tron.
  static const int tron = 0x14;

  /// Sui.
  static const int sui = 0x07;
}

/// Parameter-1 (P1) flags for the currently open app's INS table.
class P1 {
  P1._();

  /// ETH GET_PUBLIC_KEY (INS 0x02): return the address without confirmation.
  static const int ethNonConfirm = 0x00;

  /// ETH GET_PUBLIC_KEY (INS 0x02): display the address and wait for the user
  /// to confirm before returning it. Mirrors the official `P1_CONFIRM` in
  /// app-ethereum `src/apdu_constants.h:72`.
  static const int ethConfirm = 0x01;
}

/// Parameter-2 (P2) flags for the currently open app's INS table.
class P2 {
  P2._();

  /// ETH GET_PUBLIC_KEY (INS 0x02): do not append the BIP-32 chain code.
  static const int ethNoChainCode = 0x00;

  /// ETH GET_PUBLIC_KEY (INS 0x02): append the 32-byte BIP-32 chain code so
  /// the host can rebuild the extended public key (xpub). Mirrors the official
  /// `P2_CHAINCODE` in app-ethereum `src/apdu_constants.h:74`.
  static const int ethChainCode = 0x01;
}

/// Instruction codes (INS) — the specific operation within a CLA namespace.
///
/// These follow the Ledger APDU specification.
class Ins {
  Ins._();

  // ── App lifecycle (CLA 0xe0, BOLOS) ───────────────────────────────────

  /// OPEN_APP — host selects which Ledger app to run; data is the app name
  /// in ASCII ("Ethereum", "Solana", …). Selects the INS routing table.
  static const int openApp = 0xD8;

  /// QUIT_APP — return to the BOLOS dashboard; resets the app context.
  static const int quitApp = 0xA7;

  // ── OS / common instructions (CLA 0xe0) ────────────────────────────────

  /// Returns the firmware / app version string.
  /// CLA E0 → getVersion, CLA B0 → getAppAndVersion (both INS 0x01).
  static const int getVersion = 0x01;

  /// Get Ethereum address (Ledger standard ETH_GET_ADDRESS).
  /// When CLA is NOT 0xE0, returns the app name string.
  static const int getAppName = 0x02;

  /// Get public key for Ethereum or Solana (chain determined by P1/P2).
  /// NOTE: 0x02 also routes to getPublicKey when CLA=0xE0.
  ///
  /// 0x04 is NOT used for getPublicKey — it maps to ETH_SIGN per the
  /// standard Ledger Ethereum APDU protocol. Use 0x02 for address queries.
  static const int getPublicKey = 0x02;

  // ── Ethereum signing instructions (CLA 0xe0 — Ledger standard) ─────────

  /// Sign an Ethereum transaction (RLP-encoded).
  /// Standard Ledger Ethereum app uses INS 0x04 for ETH_SIGN.
  static const int ethSign = 0x04;

  /// Get Ethereum app configuration and capability flags.
  ///
  /// Standard Ledger Ethereum APDU: CLA=0xE0, INS=0x06, P1=P2=0, no data.
  /// Host wallets send this during connection before transaction or typed-data
  /// signing to read blind-signing support and the app version.
  static const int getAppConfiguration = 0x06;

  /// Sign an Ethereum personal message (EIP-191).
  static const int signEthPersonalMessage = 0x08;

  /// Provide ERC-20 token information (Ledger Ethereum app).
  ///
  /// Host wallets push token metadata (ticker/address/decimals/chainId)
  /// with this INS before signing a token transfer, so the device can
  /// display amount+ticker. The correct response is immediate 9000 —
  /// NOT a sign-confirmation popup.
  ///
  /// ⚠ This byte used to be (incorrectly) mapped to a "Solana sign"
  /// command — real Ledger Solana signs use INS 0x06/0x07, see below.
  /// That collision made every OKX/MetaMask ERC-20 signing flow pop up
  /// a "Solana" confirmation. See docs/decisions/002-apdu-protocol-alignment.md
  static const int ethProvideErc20TokenInfo = 0x0A;

  // ── Solana app instructions (CLA 0xe0 — real Ledger Solana INS table) ──
  //
  // These OVERLAP the Ethereum INS table (0x04/0x06 mean different things
  // per app) and are only valid after OPEN_APP "Solana". Routing is driven
  // by the currentApp state in ApduHandler, not by the raw INS byte.

  /// Solana GET_VERSION (note: 0x04 here vs ETH_SIGN in the Ethereum app).
  static const int solGetVersion = 0x04;

  /// Solana GET_ADDR — returns the 32-byte Ed25519 pubkey.
  static const int solGetAddress = 0x05;

  /// Solana SIGN (on-chain transaction message).
  static const int solSignMessage = 0x06;

  /// Solana SIGN_OFFCHAIN (EIP-191-style off-chain message).
  static const int solSignOffchainMessage = 0x07;

  // ── EIP-712 typed-data signing (CLA 0xe0) ──────────────────────────────

  /// Sign EIP-712 typed data (official `SIGN_EIP_712_MESSAGE`). Only the V0
  /// single-step form is implemented: P1=0x00, P2=0x00, data =
  /// `[path][domain_hash(32)][struct_hash(32)]`. P2=0x01 (V1 streaming) is
  /// reserved and refused with 0x6A86.
  static const int ethSignEip712 = 0x0C;

  // ── Bitcoin instructions (CLA 0xe1 / 0xf8) ─────────────────────────────

  /// Get Bitcoin wallet public key / xpub.
  static const int btcGetWalletPublicKey = 0x40;

  /// Sign a Bitcoin transaction (PSBT or raw TX input).
  static const int btcSignTx = 0x44;

  // ── Tron instructions (CLA 0xE0 real app / CLA 0x14 legacy) ────────────
  //
  // Real Ledger Tron app INS table (@ledgerhq/hw-app-trx, CLA 0xE0):
  //   0x02 GET_ADDRESS · 0x04 SIGN · 0x05 SIGN_HASH · 0x06 VERSION
  //   0x08 SIGN_MESSAGE · 0x0a ECDH_SECRET
  // These overlap the Ethereum INS table and are disambiguated by currentApp.

  /// Get Tron public key / address (CLA 0xE0 Tron app: GET_ADDRESS).
  static const int tronGetPublicKey = 0x02;

  /// Sign a Tron transaction (CLA 0xE0 Tron app: SIGN).
  static const int tronSignTx = 0x04;

  /// Sign a pre-computed Tron transaction hash (CLA 0xE0: SIGN_HASH).
  static const int tronSignHash = 0x05;

  /// Tron app configuration / version (CLA 0xE0: VERSION). Numerically the
  /// same byte as the Ethereum app's GET_APP_CONFIGURATION — the app context
  /// decides which table handles it.
  static const int tronGetAppConfiguration = 0x06;

  /// Sign a Tron personal message (CLA 0xE0: SIGN_MESSAGE).
  static const int tronSignPersonalMessage = 0x08;

  // ── Sui instructions (CLA 0x07) ────────────────────────────────────────

  /// Get Sui public key / address.
  static const int suiGetPublicKey = 0x02;

  /// Sign a Sui transaction.
  static const int suiSignTx = 0x04;
}

/// Status word (SW) — returned as SW1+SW2 in every APDU response.
///
/// Constants represent the combined 16-bit value (sw1 << 8 | sw2).
/// Use [isSuccess] to check for the standard success code.
class Sw {
  Sw._();

  /// Command completed successfully.
  static const int success = 0x9000;

  /// Incorrect P1/P2 parameters.
  static const int incorrectP1P2 = 0x6A86;

  /// Wrong data length (LC mismatch).
  static const int wrongDataLength = 0x6A87;

  /// Instruction code not supported for this CLA.
  static const int insNotSupported = 0x6D00;

  /// Class byte not supported.
  static const int claNotSupported = 0x6E00;

  /// Unknown / generic error.
  static const int unknownError = 0x6F00;

  /// Conditions of use not satisfied (e.g. wallet locked).
  static const int conditionsNotSatisfied = 0x6985;

  /// Security status not satisfied (e.g. PIN not verified).
  static const int securityStatusNotSatisfied = 0x6982;

  /// Wrong data / invalid parameter value.
  static const int wrongData = 0x6A80;

  /// Referenced file or data not found.
  static const int fileNotFound = 0x6A82;

  /// Returns `true` if the status word indicates success.
  static bool isSuccess(int sw) => sw == success;
}
