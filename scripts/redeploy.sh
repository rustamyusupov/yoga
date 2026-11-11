#!/bin/zsh
# Rebuilds Yoga with a fresh 7-day provisioning profile and reinstalls it on
# the iPhone: over USB when plugged in, otherwise over Wi-Fi via plain IPv4
# lockdownd (scripts/install_wifi.py), which keeps working while Cisco VPN is
# connected — usbmuxd/CoreDevice would go over IPv6 link-local, which the VPN
# drops. Run by launchd every couple of hours, see
# scripts/me.rstm.yoga.redeploy.plist. Does nothing while the profile last
# installed ON THE DEVICE still has more than MIN_DAYS_LEFT days to live;
# pass --force to rebuild and reinstall anyway.
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

PROJECT_DIR="${0:A:h:h}"
UDID="00008110-001A1CA61E30401E"
HOST="bluish.local"
DERIVED="$PROJECT_DIR/build"
APP="$DERIVED/Build/Products/Debug-iphoneos/Yoga.app"
VENV="$DERIVED/pmd3-venv"                      # recreated below if build/ was wiped
PYMOBILEDEVICE3_VERSION="11.52.1"
LOG_DIR="$HOME/Library/Logs/Yoga"
INSTALLED_UNTIL="$LOG_DIR/installed_until"   # profile expiry of the build on the device
WIFI_WAIT=600                                # seconds to wait for a sleeping iPhone
MIN_DAYS_LEFT=2

mkdir -p "$LOG_DIR"
exec >>"$LOG_DIR/redeploy.log" 2>&1

profile_expiry() {
    security cms -D -i "$APP/embedded.mobileprovision" 2>/dev/null \
        | grep -A1 ExpirationDate | sed -n 's:.*<date>\(.*\)</date>.*:\1:p'
}

to_ts() { date -ju -f '%Y-%m-%dT%H:%M:%SZ' "$1" '+%s'; }

echo "=== $(date '+%Y-%m-%d %H:%M:%S') start"

if [[ "${1:-}" != "--force" && -s "$INSTALLED_UNTIL" ]]; then
    installed="$(<"$INSTALLED_UNTIL")"
    if (( $(to_ts "$installed") - $(date '+%s') > MIN_DAYS_LEFT * 86400 )); then
        echo "device profile valid until $installed, skip"
        exit 0
    fi
fi

cd "$PROJECT_DIR"
xcodebuild build -quiet \
    -project Yoga.xcodeproj -scheme Yoga \
    -destination 'generic/platform=iOS' \
    -allowProvisioningUpdates \
    -derivedDataPath "$DERIVED"

expiry="$(profile_expiry)"
echo "new profile valid until $expiry"

if idevice_id -l | grep -q "$UDID"; then
    echo "installing over USB"
    ideviceinstaller -u "$UDID" install "$APP"
else
    echo "installing over Wi-Fi ($HOST)"
    if [[ ! -x "$VENV/bin/python" ]]; then
        python3 -m venv "$VENV"
        "$VENV/bin/pip" install -q "pymobiledevice3==$PYMOBILEDEVICE3_VERSION"
    fi
    "$VENV/bin/python" "$PROJECT_DIR/scripts/install_wifi.py" --wait "$WIFI_WAIT" "$UDID" "$HOST" "$APP"
fi

echo "$expiry" >"$INSTALLED_UNTIL"
echo "=== $(date '+%Y-%m-%d %H:%M:%S') done"
