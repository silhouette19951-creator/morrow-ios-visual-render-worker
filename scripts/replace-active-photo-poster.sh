#!/usr/bin/env bash
set -euo pipefail

mkdir -p output

if [[ ! -f "$WALLPAPER" ]]; then
  echo "Wallpaper not found: $WALLPAPER" >&2
  exit 1
fi

device_root="$HOME/Library/Developer/CoreSimulator/Devices/$SIMULATOR_UDID/data"
store_root="$device_root/Library/Application Support/PRBPosterExtensionDataStore"
structure_dir=""
for candidate in "$store_root"/*; do
  [[ -d "$candidate" ]] || continue
  [[ "$(basename "$candidate")" =~ ^[0-9]+$ ]] || continue
  structure_dir="$candidate"
done

if [[ -z "$structure_dir" ]]; then
  echo "PosterBoard store structure was not found." >&2
  exit 1
fi

database="$structure_dir/PBFPosterExtensionDataStoreSQLiteDatabase.sqlite3"
if [[ ! -f "$database" ]]; then
  echo "PosterBoard SQLite database was not found." >&2
  exit 1
fi

active_row="$(sqlite3 "$database" "SELECT p.UUID || '|' || p.providerId FROM poster p JOIN posterRoleMembership m ON m.posterUUID=p.UUID WHERE m.roleId='PRPosterRoleLockScreen' ORDER BY m.roleSortKey DESC LIMIT 1;")"
poster_uuid="${active_row%%|*}"
source_provider="${active_row#*|}"
source_config="$structure_dir/Extensions/$source_provider/configurations/$poster_uuid"

if [[ -z "$poster_uuid" || "$source_provider" == "$active_row" || ! -d "$source_config" ]]; then
  echo "The active lock-screen configuration was not found." >&2
  exit 1
fi

collections_configs="$structure_dir/Extensions/com.apple.WallpaperKit.CollectionsPoster/configurations"
collection_template="$(find "$collections_configs" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1)"

# A fresh simulator may not yet have a CollectionsPoster configuration. A
# native descriptor has the same versioned provider payload and is a valid
# base once Apple's photo configuration styling is copied over it.
if [[ -z "$collection_template" ]]; then
  collection_template="$(find "$structure_dir/Extensions/com.apple.WallpaperKit.CollectionsPoster/descriptors" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1)"
fi

if [[ -z "$collection_template" ]]; then
  echo "A native collection template was not found." >&2
  exit 1
fi

target="$collections_configs/$poster_uuid"
mkdir -p "$collections_configs"
if [[ "$target" != "$source_config" ]]; then
  ditto "$collection_template" "$target"
fi

source_version=""
for candidate in "$source_config/versions"/*; do
  [[ -d "$candidate" ]] || continue
  [[ "$(basename "$candidate")" =~ ^[0-9]+$ ]] || continue
  source_version="$candidate"
done

target_version=""
for candidate in "$target/versions"/*; do
  [[ -d "$candidate" ]] || continue
  [[ "$(basename "$candidate")" =~ ^[0-9]+$ ]] || continue
  target_version="$candidate"
done

if [[ -z "$source_version" || -z "$target_version" ]]; then
  echo "Poster configuration versions were not found." >&2
  exit 1
fi

# Preserve Apple's own clock stretch, color, widgets, and quick-action choices.
if [[ "$source_version" != "$target_version" ]]; then
  for settings_file in \
    com.apple.posterkit.provider.instance.titleStyleConfiguration.plist \
    com.apple.posterkit.provider.instance.complicationLayout.plist \
    com.apple.posterkit.provider.instance.quickActions.plist \
    com.apple.posterkit.provider.instance.renderingConfiguration.plist; do
    if [[ -f "$source_version/$settings_file" ]]; then
      cp "$source_version/$settings_file" "$target_version/$settings_file"
    fi
  done
fi

poster_id="99001"
wallpaper_name="${poster_id}.Morrow-393w-852h@3x~iphone.wallpaper"
contents="$target_version/contents"
rm -rf "$contents"
mkdir -p "$contents/$wallpaper_name/wallpaper.ca/assets"

cp poster-template/com.apple.posterkit.provider.contents.userInfo "$contents/com.apple.posterkit.provider.contents.userInfo"
cp poster-template/Wallpaper.plist "$contents/$wallpaper_name/Wallpaper.plist"
cp poster-template/wallpaper.ca/index.xml "$contents/$wallpaper_name/wallpaper.ca/index.xml"
cp poster-template/wallpaper.ca/assetManifest.caml "$contents/$wallpaper_name/wallpaper.ca/assetManifest.caml"
cp poster-template/wallpaper.ca/main.caml "$contents/$wallpaper_name/wallpaper.ca/main.caml"
cp "$WALLPAPER" "$contents/$wallpaper_name/wallpaper.ca/assets/wallpaper.jpg"

printf '%s' "$poster_id" > "$target/com.apple.posterkit.provider.descriptor.identifier"
plutil -replace wallpaperRepresentingFileName -string "$wallpaper_name" "$contents/com.apple.posterkit.provider.contents.userInfo"
plutil -replace wallpaperRepresentingIdentifier -string "$poster_id" "$contents/com.apple.posterkit.provider.contents.userInfo"
plutil -replace identifier -integer "$poster_id" "$contents/$wallpaper_name/Wallpaper.plist"

# The cloned native configuration may carry a rendered snapshot from the
# source poster. It must not mask the newly supplied CAML background.
find "$target" -type f -name 'RuntimeSnapshotMetadata-*' -delete

xcrun simctl spawn "$SIMULATOR_UDID" killall PosterBoard >/dev/null 2>&1 || true
xcrun simctl spawn "$SIMULATOR_UDID" killall posterboardd >/dev/null 2>&1 || true
sleep 2

sqlite3 "$database" "UPDATE poster SET providerId='com.apple.WallpaperKit.CollectionsPoster' WHERE UUID='$poster_uuid';"
sqlite3 "$database" "SELECT UUID, providerId FROM poster WHERE UUID='$poster_uuid';" > output/replaced-active-poster-db.txt

if [[ "$source_config" != "$target" ]]; then
  rm -rf "$source_config"
fi

gallery_cache="$structure_dir/GalleryCache"
if [[ -d "$gallery_cache" ]]; then
  find "$gallery_cache" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
fi

echo "Device root: $device_root" > output/replaced-active-poster.txt
echo "Store structure: $structure_dir" >> output/replaced-active-poster.txt
echo "Active UUID: $poster_uuid" >> output/replaced-active-poster.txt
echo "Replacement configuration: $target" >> output/replaced-active-poster.txt

xcrun simctl shutdown "$SIMULATOR_UDID"
xcrun simctl boot "$SIMULATOR_UDID"
xcrun simctl bootstatus "$SIMULATOR_UDID" -b
open -a Simulator --args -CurrentDeviceUDID "$SIMULATOR_UDID" || true
xcrun simctl status_bar "$SIMULATOR_UDID" override \
  --time "9:41" \
  --operatorName "中国移动" \
  --batteryState charged \
  --batteryLevel 100 \
  --wifiBars 3 \
  --cellularBars 4 || true
sleep 18
xcrun simctl io "$SIMULATOR_UDID" screenshot output/after-active-poster-replacement.png
