#!/usr/bin/env bash
set -euo pipefail

mkdir -p output

if [[ ! -f "$WALLPAPER" ]]; then
  echo "Wallpaper not found: $WALLPAPER" >&2
  exit 1
fi

xcodebuild -version | tee output/xcode-version.txt
xcrun simctl help > output/simctl-help.txt
xcrun simctl list runtimes --json > output/runtimes.json
xcrun simctl list devicetypes --json > output/device-types.json

runtime_id="$({
  jq -r '
    [.runtimes[]
      | select(.isAvailable == true)
      | select(.identifier | contains("iOS"))]
    | sort_by(.version | split(".") | map(tonumber))
    | last
    | .identifier
  ' output/runtimes.json
})"

device_type_id="$({
  jq -r --arg hint "$DEVICE_HINT" '
    [.devicetypes[]
      | select(.name | contains("iPhone"))
      | select(.name | contains($hint))
      | . + {
          model_number: (
            try (.name | capture("iPhone (?<number>[0-9]+)").number | tonumber)
            catch 0
          )
        }]
    | sort_by(.model_number)
    | last
    | .identifier
  ' output/device-types.json
})"

if [[ -z "$runtime_id" || "$runtime_id" == "null" ]]; then
  echo "No available iOS runtime was found." >&2
  exit 1
fi

if [[ -z "$device_type_id" || "$device_type_id" == "null" ]]; then
  device_type_id="$({
    jq -r '
      [.devicetypes[] | select(.name | contains("iPhone"))]
      | last
      | .identifier
    ' output/device-types.json
  })"
fi

udid="$(xcrun simctl create "Morrow Wallpaper Renderer" "$device_type_id" "$runtime_id")"
echo "SIMULATOR_UDID=$udid" >> "$GITHUB_ENV"
echo "Selected runtime: $runtime_id" | tee output/selection.txt
echo "Selected device type: $device_type_id" | tee -a output/selection.txt
echo "Simulator UDID: $udid" | tee -a output/selection.txt

xcrun simctl boot "$udid"
xcrun simctl bootstatus "$udid" -b

# PosterBoard cannot persist a photo poster on some fresh CI simulators when
# its SpringBoard cache directory has not been created yet. The iOS runtime
# does not ship a general-purpose mkdir binary, so create the simulator data
# directory from the macOS host before PosterBoard is launched.
# CoreSimulator maps /private/var/mobile/Library to the host-side data/Library
# directory rather than exposing the device's logical path literally.
springboard_cache="$HOME/Library/Developer/CoreSimulator/Devices/$udid/data/Library/SpringBoard"
mkdir -p "$springboard_cache"
chmod 0777 "$springboard_cache"

# Keep the Simulator GUI process alive so photo posters are rendered by the
# normal Metal-backed presentation path before screenshots are requested.
open -a Simulator --args -CurrentDeviceUDID "$udid" || true
sleep 8

# Match the Chinese screenshots customers see on a mainland China iPhone.
# SpringBoard reads these global preferences when it is restarted.
xcrun simctl spawn "$udid" defaults write NSGlobalDomain AppleLanguages -array "zh-Hans"
xcrun simctl spawn "$udid" defaults write NSGlobalDomain AppleLocale "zh_CN"
xcrun simctl spawn "$udid" killall SpringBoard || true
sleep 6

# Keep system chrome deterministic where the runtime supports this command.
xcrun simctl status_bar "$udid" override \
  --time "9:41" \
  --operatorName "中国移动" \
  --batteryState charged \
  --batteryLevel 100 \
  --wifiBars 3 \
  --cellularBars 4 || true

# Re-encode on macOS to the exact simulated display size. This removes host
# encoder metadata and gives WallpaperKit a conventional sRGB JPEG asset.
sips \
  --setProperty format jpeg \
  --setProperty formatOptions 95 \
  --resampleHeightWidth 2868 1320 \
  "$WALLPAPER" \
  --out output/import-wallpaper.jpg \
  > output/sips.log

xcrun simctl addmedia "$udid" output/import-wallpaper.jpg
# Give Photos/WallpaperKit time to index the freshly imported asset.
sleep 20
xcrun simctl launch "$udid" com.apple.mobileslideshow || true
sleep 4
xcrun simctl io "$udid" screenshot output/photos-after-import.png
