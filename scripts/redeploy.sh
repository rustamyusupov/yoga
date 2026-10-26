#!/bin/zsh
# Rebuilds Yoga with a fresh 7-day provisioning profile and reinstalls it
# on the iPhone over Wi-Fi (USB also works). Run by launchd every 6 days,
# see scripts/me.rstm.yoga.redeploy.plist.
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

PROJECT_DIR="${0:A:h:h}"
UDID="00008110-001A1CA61E30401E"
DERIVED="$PROJECT_DIR/build"
APP="$DERIVED/Build/Products/Debug-iphoneos/Yoga.app"
LOG_DIR="$HOME/Library/Logs/Yoga"
mkdir -p "$LOG_DIR"
exec >>"$LOG_DIR/redeploy.log" 2>&1

echo "=== $(date '+%Y-%m-%d %H:%M:%S') start"

cd "$PROJECT_DIR"
xcodebuild build -quiet \
    -project Yoga.xcodeproj -scheme Yoga \
    -destination 'generic/platform=iOS' \
    -allowProvisioningUpdates \
    -derivedDataPath "$DERIVED"

security cms -D -i "$APP/embedded.mobileprovision" | grep -A1 ExpirationDate | tail -1

if idevice_id -l | grep -q "$UDID"; then
    MODE=()
elif idevice_id -n | grep -q "$UDID"; then
    MODE=(-n)
else
    echo "device not reachable"
    exit 1
fi

ideviceinstaller "${MODE[@]}" -u "$UDID" install "$APP"
echo "=== $(date '+%Y-%m-%d %H:%M:%S') done"
