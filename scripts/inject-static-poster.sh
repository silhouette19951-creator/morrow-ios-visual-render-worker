#!/usr/bin/env bash
set -euo pipefail

mkdir -p output

if [[ ! -f "$WALLPAPER" ]]; then
  echo "Wallpaper not found: $WALLPAPER" >&2
  exit 1
fi

poster_data="$(xcrun simctl get_app_container "$SIMULATOR_UDID" com.apple.PosterBoard data 2>/dev/null || true)"
if [[ -z "$poster_data" ]]; then
  echo "PosterBoard data container was not found." >&2
  exit 1
fi

store_root="$poster_data/Library/Application Support/PRBPosterExtensionDataStore"
structure_dir=""
for candidate in "$store_root"/*; do
  [[ -d "$candidate" ]] || continue
  [[ "$(basename "$candidate")" =~ ^[0-9]+$ ]] || continue
  structure_dir="$candidate"
done

if [[ -z "$structure_dir" ]]; then
  xcrun simctl launch "$SIMULATOR_UDID" com.apple.PosterBoard >/dev/null 2>&1 || true
  sleep 8
  for candidate in "$store_root"/*; do
    [[ -d "$candidate" ]] || continue
    [[ "$(basename "$candidate")" =~ ^[0-9]+$ ]] || continue
    structure_dir="$candidate"
  done
fi

if [[ -z "$structure_dir" ]]; then
  echo "PosterBoard store structure was not initialized." >&2
  exit 1
fi

descriptors="$structure_dir/Extensions/com.apple.WallpaperKit.CollectionsPoster/descriptors"
template="$(find "$descriptors" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1)"
if [[ -z "$template" ]]; then
  echo "No native CollectionsPoster descriptor was available to clone." >&2
  exit 1
fi

poster_uuid="$(uuidgen)"
poster_id="99001"
wallpaper_name="${poster_id}.Morrow-393w-852h@3x~iphone.wallpaper"
target="$descriptors/$poster_uuid"
ditto "$template" "$target"

printf '%s' "$poster_id" > "$target/com.apple.posterkit.provider.descriptor.identifier"
version_dir=""
for candidate in "$target/versions"/*; do
  [[ -d "$candidate" ]] || continue
  [[ "$(basename "$candidate")" =~ ^[0-9]+$ ]] || continue
  version_dir="$candidate"
done
if [[ -z "$version_dir" ]]; then
  echo "The cloned descriptor has no numeric version directory." >&2
  exit 1
fi
contents="$version_dir/contents"
rm -rf "$contents"
mkdir -p "$contents/$wallpaper_name/wallpaper.ca/assets"

cp poster-template/com.apple.posterkit.provider.contents.userInfo "$contents/com.apple.posterkit.provider.contents.userInfo"
cp poster-template/Wallpaper.plist "$contents/$wallpaper_name/Wallpaper.plist"
cp poster-template/wallpaper.ca/index.xml "$contents/$wallpaper_name/wallpaper.ca/index.xml"
cp poster-template/wallpaper.ca/assetManifest.caml "$contents/$wallpaper_name/wallpaper.ca/assetManifest.caml"
cp poster-template/wallpaper.ca/main.caml "$contents/$wallpaper_name/wallpaper.ca/main.caml"
cp "$WALLPAPER" "$contents/$wallpaper_name/wallpaper.ca/assets/wallpaper.jpg"

plutil -replace wallpaperRepresentingFileName -string "$wallpaper_name" "$contents/com.apple.posterkit.provider.contents.userInfo"
plutil -replace wallpaperRepresentingIdentifier -string "$poster_id" "$contents/com.apple.posterkit.provider.contents.userInfo"
plutil -replace identifier -integer "$poster_id" "$contents/$wallpaper_name/Wallpaper.plist"

gallery_cache="$structure_dir/GalleryCache"
if [[ -d "$gallery_cache" ]]; then
  find "$gallery_cache" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
fi

echo "PosterBoard data: $poster_data" > output/injected-poster.txt
echo "Store structure: $structure_dir" >> output/injected-poster.txt
echo "Descriptor UUID: $poster_uuid" >> output/injected-poster.txt

xcrun simctl spawn "$SIMULATOR_UDID" killall PosterBoard >/dev/null 2>&1 || true
xcrun simctl spawn "$SIMULATOR_UDID" killall posterboardd >/dev/null 2>&1 || true
xcrun simctl spawn "$SIMULATOR_UDID" killall SpringBoard >/dev/null 2>&1 || true
sleep 8

xcrun simctl launch "$SIMULATOR_UDID" com.apple.PosterBoard >/dev/null 2>&1 || true
sleep 12
xcrun simctl io "$SIMULATOR_UDID" screenshot output/posterboard-gallery.png
