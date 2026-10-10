#!/usr/bin/env python3
"""UI regression: BTC/Sui stay hidden after import and cold-start unlock.

Uses a disposable test device: fresh=True clears app data, like signing cases.
Checks the account sections and BLE picker without starting advertising.
"""
from __future__ import annotations

import asyncio
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from harness.session import DeviceSession  # noqa: E402


async def check_entries(app) -> None:
    for chain in ("ethereum", "solana", "tron"):
        assert (await app.find("key", f"chain-header-{chain}")).startswith("size="), chain
    for chain in ("bitcoin", "sui"):
        assert await app.find("key", f"chain-header-{chain}") == "NOT_FOUND", chain

    hit = await app.tap_type("BleFab")
    assert hit.startswith("TAPPED"), hit
    await app.settle(0.8)
    for chain in ("ethereum", "solana", "tron"):
        assert (await app.find("key", f"ble-chain-{chain}")).startswith("size="), chain
    for chain in ("bitcoin", "sui"):
        assert await app.find("key", f"ble-chain-{chain}") == "NOT_FOUND", chain
    hit = await app.tap_key("ble-sheet-close")
    assert hit.startswith("TAPPED"), hit
    await app.settle()


async def run() -> int:
    async with DeviceSession.start(fresh=True, chain_id=None) as session:
        await check_entries(session.app)
    # AttachSession cold-starts the same installed app; persisted accounts
    # should remain hidden after unlocking as well.
    async with DeviceSession.start(fresh=False, chain_id=None) as session:
        await check_entries(session.app)
    print("[OK] BTC/Sui hidden after import and cold-start unlock")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(run()))
