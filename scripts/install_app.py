#!/usr/bin/env python3
"""Install a .app on the iPhone unless the app is running there.

Installing kills the running app, so first ask the device for its process list
(os_trace_relay) and exit with code 3 if the app's executable is in it — a
suspended app in the background counts as running too. --allow-running skips
the check.

Without --host the device is reached over USB via usbmuxd. With --host it is
reached over Wi-Fi via plain IPv4 lockdownd: Apple's usbmuxd/CoreDevice reach a
Wi-Fi device over IPv6 link-local, which Cisco AnyConnect drops ("IPv6: Drop
All Traffic"). The IPv4 LAN is outside the tunnel, so we talk to lockdownd on
<host>:62078 directly, reusing the pairing record that usbmuxd already holds
for <udid>. A locked iPhone puts Wi-Fi to sleep for minutes at a time, so we
keep retrying until --wait seconds pass.

usage: install_app.py [--host HOST] [--wait SECONDS] [--allow-running] <udid> <path/to/App.app>
"""
import argparse
import asyncio
import plistlib
import socket
import sys
import time
from pathlib import Path
from typing import Optional

from pymobiledevice3.exceptions import PyMobileDevice3Exception
from pymobiledevice3.lockdown import LockdownClient, create_using_tcp, create_using_usbmux
from pymobiledevice3.pair_records import get_usbmux_pairing_record
from pymobiledevice3.services.installation_proxy import InstallationProxyService
from pymobiledevice3.services.os_trace import OsTraceService

LOCKDOWN_PORT = 62078
RETRY_DELAY = 15
EXIT_APP_RUNNING = 3


def resolve_ipv4(host: str) -> str:
    """Resolve host (e.g. bluish.local) to an IPv4 address; mDNS via getaddrinfo."""
    infos = socket.getaddrinfo(host, LOCKDOWN_PORT, socket.AF_INET, socket.SOCK_STREAM)
    return infos[0][4][0]


def executable_name(app: Path) -> str:
    with open(app / "Info.plist", "rb") as file:
        return plistlib.load(file)["CFBundleExecutable"]


async def connect(udid: str, host: Optional[str]) -> LockdownClient:
    if host is None:
        where = "USB"
        lockdown = await create_using_usbmux(serial=udid, autopair=False, connection_type="USB")
    else:
        record = await get_usbmux_pairing_record(identifier=udid)
        if record is None:
            sys.exit(f"no usbmuxd pairing record for {udid}")
        where = resolve_ipv4(host)
        lockdown = await create_using_tcp(
            hostname=where, identifier=udid, autopair=False, pair_record=record, keep_alive=True
        )
    if not lockdown.paired:
        await lockdown.close()
        sys.exit("pairing record rejected by device")
    print(f"connected to {lockdown.all_values.get('DeviceName')} ({where}) iOS {lockdown.product_version}", flush=True)
    return lockdown


async def is_running(lockdown: LockdownClient, executable: str) -> bool:
    async with OsTraceService(lockdown=lockdown) as os_trace:
        processes = (await os_trace.get_pid_list()).get("Payload") or {}
    return any(info.get("ProcessName") == executable for info in processes.values())


async def install_once(udid: str, host: Optional[str], app: Path, allow_running: bool) -> None:
    lockdown = await connect(udid, host)
    try:
        executable = executable_name(app)
        if not allow_running and await is_running(lockdown, executable):
            print(f"{executable} is running on the device, not installing", flush=True)
            sys.exit(EXIT_APP_RUNNING)

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


async def main(udid: str, host: Optional[str], app: Path, wait: float, allow_running: bool) -> None:
    # A locked iPhone wakes Wi-Fi only briefly: the connection may succeed and
    # then drop mid-transfer, so retry the whole connect+check+install, not
    # just the connect, until the deadline.
    deadline = time.monotonic() + wait
    attempt = 0
    while True:
        attempt += 1
        try:
            await install_once(udid, host, app, allow_running)
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
    parser.add_argument("--host", help="reach the device over Wi-Fi at this host instead of USB")
    parser.add_argument("--wait", type=float, default=0, help="seconds to keep retrying while the device sleeps")
    parser.add_argument("--allow-running", action="store_true", help="install even if the app is running")
    parser.add_argument("udid")
    parser.add_argument("app", type=Path)
    args = parser.parse_args()
    asyncio.run(main(args.udid, args.host, args.app, args.wait, args.allow_running))
