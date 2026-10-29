#!/usr/bin/env python3
"""UI regression: the Vault's default chains, the BLE app picker, and Manage chains.

Uses a disposable test device: fresh=True clears app data, like signing cases.
Checks the account sections and BLE picker without starting advertising.
"""
from __future__ import annotations

import asyncio
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from harness.session import DeviceSession  # noqa: E402

DEFAULT_CHAINS = ("bitcoin", "ethereum", "solana", "tron")
ADDABLE_CHAINS = ("ton", "sui", "near")


async def wait_for_key(app, key: str, timeout: float = 10.0) -> str:
    """轮询直到按 ValueKey 找到节点；解锁后首帧还没构出账户卡片是正常时序。"""
    deadline = asyncio.get_event_loop().time() + timeout
    geom = ""
    while asyncio.get_event_loop().time() < deadline:
        geom = await app.find("key", key)
        if geom.startswith("size="):
            return geom
        await asyncio.sleep(0.3)
    return geom


async def wait_for_key_gone(app, key: str, timeout: float = 10.0) -> bool:
    """轮询直到按 ValueKey 找不到节点。"""
    deadline = asyncio.get_event_loop().time() + timeout
    while asyncio.get_event_loop().time() < deadline:
        if await app.find("key", key) == "NOT_FOUND":
            return True
        await asyncio.sleep(0.3)
    return False


async def check_entries(app) -> None:
    for chain in DEFAULT_CHAINS:
        assert (await wait_for_key(app, f"chain-header-{chain}")).startswith("size="), chain
    for chain in ADDABLE_CHAINS:
        assert await app.find("key", f"chain-header-{chain}") == "NOT_FOUND", chain

    hit = await app.tap_type("BleFab")
    assert hit.startswith("TAPPED"), hit
    await app.settle(0.8)
    # The picker mirrors the Vault: only the chains the user actually has.
    for chain in DEFAULT_CHAINS:
        assert (await app.find("key", f"ble-chain-{chain}")).startswith("size="), chain
    for chain in ADDABLE_CHAINS:
        assert await app.find("key", f"ble-chain-{chain}") == "NOT_FOUND", chain
    hit = await app.tap_key("ble-sheet-close")
    assert hit.startswith("TAPPED"), hit
    await app.settle()


async def check_manage_chains(app) -> None:
    """Turning chains off/on in "Manage chains"; the BLE picker follows."""
    hit = await app.tap_key("manage-chains-tile")
    assert hit.startswith("TAPPED"), hit
    await app.settle(0.8)
    for chain in DEFAULT_CHAINS + ADDABLE_CHAINS:
        assert (await app.find("key", f"chain-toggle-{chain}")).startswith("size="), chain

    # Turning NEAR on derives account 0 and reveals its section.
    hit = await app.tap_key("chain-toggle-near")
    assert hit.startswith("TAPPED"), hit
    assert (await wait_for_key(app, "chain-header-near", timeout=20)).startswith("size=")

    # Turning Ethereum off hides its section.
    hit = await app.tap_key("chain-toggle-ethereum")
    assert hit.startswith("TAPPED"), hit
    assert await wait_for_key_gone(app, "chain-header-ethereum")

    hit = await app.tap_key("manage-chains-close")
    assert hit.startswith("TAPPED"), hit
    await app.settle()

    # The BLE picker mirrors the managed set: NEAR in, Ethereum out.
    hit = await app.tap_type("BleFab")
    assert hit.startswith("TAPPED"), hit
    await app.settle(0.8)
    assert (await app.find("key", "ble-chain-near")).startswith("size=")
    assert await app.find("key", "ble-chain-ethereum") == "NOT_FOUND"
    for chain in ("ton", "sui"):
        assert await app.find("key", f"ble-chain-{chain}") == "NOT_FOUND", chain
    hit = await app.tap_key("ble-sheet-close")
    assert hit.startswith("TAPPED"), hit
    await app.settle()

    # Restore Ethereum so later sessions start from the default set again.
    hit = await app.tap_key("manage-chains-tile")
    assert hit.startswith("TAPPED"), hit
    await app.settle(0.8)
    hit = await app.tap_key("chain-toggle-ethereum")
    assert hit.startswith("TAPPED"), hit
    assert (await wait_for_key(app, "chain-header-ethereum", timeout=20)).startswith("size=")
    hit = await app.tap_key("manage-chains-close")
    assert hit.startswith("TAPPED"), hit
    await app.settle()


async def run() -> int:
    async with DeviceSession.start(fresh=True, chain_id=None) as session:
        await check_entries(session.app)
    # AttachSession cold-starts the same installed app; persisted accounts
    # should remain hidden after unlocking as well.
    async with DeviceSession.start(fresh=False, chain_id=None) as session:
        await check_entries(session.app)
        await check_manage_chains(session.app)
    # A cold restart keeps the derived NEAR account and the restored Ethereum —
    # i.e. the manage state survives alongside the accounts.
    async with DeviceSession.start(fresh=False, chain_id=None) as session:
        for chain in ("ethereum", "near"):
            assert (await wait_for_key(
                session.app, f"chain-header-{chain}", timeout=20)).startswith("size="), chain
    print("[OK] default chains, BLE picker and Manage chains behave as expected")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(run()))
