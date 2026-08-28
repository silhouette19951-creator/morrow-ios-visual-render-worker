#!/usr/bin/env bash
set -euo pipefail

out_dir="output/posterboard-state"
device_root="$HOME/Library/Developer/CoreSimulator/Devices/$SIMULATOR_UDID/data"
mkdir -p "$out_dir"

echo "Simulator UDID: $SIMULATOR_UDID" > "$out_dir/summary.txt"
echo "Device root: $device_root" >> "$out_dir/summary.txt"

poster_data="$(xcrun simctl get_app_container "$SIMULATOR_UDID" com.apple.PosterBoard data 2>/dev/null || true)"

if [[ -z "$poster_data" ]]; then
  while IFS= read -r metadata; do
    identifier="$(plutil -extract MCMMetadataIdentifier raw "$metadata" 2>/dev/null || true)"
    if [[ "$identifier" == "com.apple.PosterBoard" ]]; then
      poster_data="$(dirname "$metadata")"
      break
    fi
  done < <(find "$device_root/Containers/Data/Application" -name '.com.apple.mobile_container_manager.metadata.plist' -type f 2>/dev/null)
fi

echo "PosterBoard data: ${poster_data:-not-found}" >> "$out_dir/summary.txt"

poster_store="$device_root/Library/Application Support/PRBPosterExtensionDataStore"
echo "PosterBoard global store: $poster_store" >> "$out_dir/summary.txt"
if [[ -d "$poster_store" ]]; then
  ditto "$poster_store" "$out_dir/PRBPosterExtensionDataStore"
fi

springboard_dir="$device_root/Library/SpringBoard"
if [[ -d "$springboard_dir" ]]; then
  ditto "$springboard_dir" "$out_dir/SpringBoard"
fi

find "$device_root" -type f \
  \( -iname '*poster*' -o -iname '*wallpaper*' -o -iname '*lockbackground*' \) \
  2>/dev/null | sort > "$out_dir/matching-files.txt" || true

while IFS= read -r file; do
  [[ -f "$file" ]] || continue
  size="$(stat -f '%z' "$file" 2>/dev/null || echo '?')"
  modified="$(stat -f '%Sm' -t '%Y-%m-%dT%H:%M:%S' "$file" 2>/dev/null || echo '?')"
  printf '%s\t%s\t%s\n' "$size" "$modified" "$file"
done < "$out_dir/matching-files.txt" > "$out_dir/matching-files-detailed.txt"

find "$out_dir" -type f -maxdepth 12 -print | sort > "$out_dir/collected-files.txt"
tar -czf output/posterboard-state.tar.gz -C output posterboard-state
