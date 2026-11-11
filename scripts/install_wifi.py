#!/usr/bin/env python3
"""Install a .app on the iPhone over Wi-Fi via plain IPv4 lockdownd.

Apple's usbmuxd/CoreDevice reach a Wi-Fi device over IPv6 link-local, which
Cisco AnyConnect drops ("IPv6: Drop All Traffic"). The IPv4 LAN is outside the
tunnel, so we talk to lockdownd on <host>:62078 directly, reusing the pairing
record that usbmuxd already holds for <udid>. A locked iPhone puts Wi-Fi to
sleep for minutes at a time, so we keep retrying until --wait seconds pass.

usage: install_wifi.py [--wait SECONDS] <udid> <host> <path/to/App.app>
"""
import argparse
import asyncio
import socket
import sys
import time
from pathlib import Path

from pymobiledevice3.exceptions import PyMobileDevice3Exception
from pymobiledevice3.lockdown import TcpLockdownClient, create_using_tcp
from pymobiledevice3.pair_records import get_usbmux_pairing_record
from pymobiledevice3.services.installation_proxy import InstallationProxyService

LOCKDOWN_PORT = 62078
RETRY_DELAY = 15


def resolve_ipv4(host: str) -> str:
    """Resolve host (e.g. bluish.local) to an IPv4 address; mDNS via getaddrinfo."""
    infos = socket.getaddrinfo(host, LOCKDOWN_PORT, socket.AF_INET, socket.SOCK_STREAM)
    return infos[0][4][0]


async def connect(udid: str, host: str, record: dict) -> TcpLockdownClient:
    ip = resolve_ipv4(host)
    lockdown = await create_using_tcp(
        hostname=ip, identifier=udid, autopair=False, pair_record=record, keep_alive=True
    )
    if not lockdown.paired:
        await lockdown.close()
        sys.exit("pairing record rejected by device")
    print(f"connected to {lockdown.all_values.get('DeviceName')} ({ip}) iOS {lockdown.product_version}", flush=True)
    return lockdown


async def install_once(udid: str, host: str, record: dict, app: Path) -> None:
    lockdown = await connect(udid, host, record)
    try:
        last = -1

        def progress(percent: int) -> None:
            nonlocal last
            if percent != last:
                last = percent
                print(f"install: {percent}%", flush=True)

        installer = InstallationProxyService(lockdown=lockdown)
        await installer.install_from_local(app, cmd="Install", developer=True, handler=progress)
    finally:
        try:
            await lockdown.close()
        except Exception:
            pass


async def main(udid: str, host: str, app: Path, wait: float) -> None:
    record = await get_usbmux_pairing_record(identifier=udid)
    if record is None:
        sys.exit(f"no usbmuxd pairing record for {udid}")
    # A locked iPhone wakes Wi-Fi only briefly: the connection may succeed and
    # then drop mid-transfer, so retry the whole connect+install, not just the
    # connect, until the deadline.
    deadline = time.monotonic() + wait
    attempt = 0
    while True:
        attempt += 1
        try:
            await install_once(udid, host, record, app)
        except (OSError, asyncio.TimeoutError, PyMobileDevice3Exception) as error:
            if time.monotonic() >= deadline:
                sys.exit(f"gave up after {attempt} attempts / {int(wait)}s: {error.__class__.__name__}: {error}")
            print(f"attempt {attempt} failed ({error.__class__.__name__}), retrying in {RETRY_DELAY}s", flush=True)
            await asyncio.sleep(RETRY_DELAY)
            continue
        print("install: done")
        return


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--wait", type=float, default=600, help="seconds to keep retrying while the device sleeps")
    parser.add_argument("udid")
    parser.add_argument("host")
    parser.add_argument("app", type=Path)
    args = parser.parse_args()
    asyncio.run(main(args.udid, args.host, args.app, args.wait))
