#!/bin/zsh
# Rebuilds Yoga with a fresh 7-day provisioning profile and reinstalls it on
# the iPhone (scripts/install_app.py): over USB when plugged in, otherwise over
# Wi-Fi via plain IPv4 lockdownd, which keeps working while Cisco VPN is
# connected — usbmuxd/CoreDevice would go over IPv6 link-local, which the VPN
# drops. Run by launchd every couple of hours, see
# scripts/me.rstm.yoga.redeploy.plist. Xcode keeps signing with its cached
# profile until that one expires, so the cached profile is set aside before the
# build to make Xcode issue a fresh one. Does nothing while the profile last
# installed ON THE DEVICE still has more than MIN_DAYS_LEFT days to live, and
# does not install while the app is running on the device (even suspended in
# the background) — the next run tries again. Pass --force to rebuild and
# reinstall regardless of both.
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

PROJECT_DIR="${0:A:h:h}"
UDID="00008110-001A1CA61E30401E"
HOST="bluish.local"
DERIVED="$PROJECT_DIR/build"
APP="$DERIVED/Build/Products/Debug-iphoneos/Yoga.app"
VENV="$DERIVED/pmd3-venv"                      # recreated below if build/ was wiped
PYMOBILEDEVICE3_VERSION="11.52.1"
BUNDLE_ID="me.rstm.Yoga"
PROFILES_DIR="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
PROFILES_ASIDE="$DERIVED/profiles-aside"       # cached profiles, kept until the build succeeds
LOG_DIR="$HOME/Library/Logs/Yoga"
INSTALLED_UNTIL="$LOG_DIR/installed_until"   # profile expiry of the build on the device
WIFI_WAIT=600                                # seconds to wait for a sleeping iPhone
MIN_DAYS_LEFT=2
APP_RUNNING_STATUS=3                         # install_app.py: app is running on the device

mkdir -p "$LOG_DIR"
exec >>"$LOG_DIR/redeploy.log" 2>&1

profile_expiry() {
    security cms -D -i "$APP/embedded.mobileprovision" 2>/dev/null \
        | grep -A1 ExpirationDate | sed -n 's:.*<date>\(.*\)</date>.*:\1:p'
}

to_ts() { date -ju -f '%Y-%m-%dT%H:%M:%SZ' "$1" '+%s'; }

set_cached_profiles_aside() {
    local profile
    rm -rf "$PROFILES_ASIDE"
    mkdir -p "$PROFILES_ASIDE"
    for profile in "$PROFILES_DIR"/*.mobileprovision(N); do
        if security cms -D -i "$profile" 2>/dev/null | grep -qF ".$BUNDLE_ID</string>"; then
            mv "$profile" "$PROFILES_ASIDE/"
        fi
    done
}

restore_cached_profiles() {
    local profile
    for profile in "$PROFILES_ASIDE"/*.mobileprovision(N); do
        mv "$profile" "$PROFILES_DIR/"
    done
}

echo "=== $(date '+%Y-%m-%d %H:%M:%S') start"

if [[ "${1:-}" != "--force" && -s "$INSTALLED_UNTIL" ]]; then
    installed="$(<"$INSTALLED_UNTIL")"
    if (( $(to_ts "$installed") - $(date '+%s') > MIN_DAYS_LEFT * 86400 )); then
        echo "device profile valid until $installed, skip"
        exit 0
    fi
fi

cd "$PROJECT_DIR"
set_cached_profiles_aside
if ! xcodebuild build -quiet \
    -project Yoga.xcodeproj -scheme Yoga \
    -destination 'generic/platform=iOS' \
    -allowProvisioningUpdates \
    -derivedDataPath "$DERIVED"; then
    # e.g. no Apple account in Xcode: keep the old profile usable
    restore_cached_profiles
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') build failed"
    exit 1
fi
rm -rf "$PROFILES_ASIDE"

expiry="$(profile_expiry)"
echo "new profile valid until $expiry"

if [[ ! -x "$VENV/bin/python" ]]; then
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install -q "pymobiledevice3==$PYMOBILEDEVICE3_VERSION"
fi

install_args=()
if [[ "${1:-}" == "--force" ]]; then install_args+=(--allow-running); fi
if idevice_id -l | grep -q "$UDID"; then
    echo "installing over USB"
else
    echo "installing over Wi-Fi ($HOST)"
    install_args+=(--host "$HOST" --wait "$WIFI_WAIT")
fi

rc=0
"$VENV/bin/python" "$PROJECT_DIR/scripts/install_app.py" "${install_args[@]}" "$UDID" "$APP" || rc=$?
if (( rc == APP_RUNNING_STATUS )); then
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') app is running, postponed"
    exit 0
fi
(( rc == 0 )) || exit "$rc"

echo "$expiry" >"$INSTALLED_UNTIL"
echo "=== $(date '+%Y-%m-%d %H:%M:%S') done"
