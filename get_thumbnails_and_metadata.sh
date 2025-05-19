#!/usr/bin/env bash
#
# update_youtube_metadata.sh
#
# Refresh thumbnails and metadata for videos downloaded with yt-dlp.
#
# Usage:
#   ./update_youtube_metadata.sh [--dry-run] /path/to/video_directory
#
# Requires: yt-dlp, jq, curl, ffmpeg

set -euo pipefail
trap 'echo "Script interrupted. Exiting."; exit 130' INT

DRY_RUN=false
VIDEO_DIR=""

# Return timestamp with millisecond precision
timestamp_ms() {
  if command -v gdate >/dev/null 2>&1; then
    gdate +"%Y-%m-%d %H:%M:%S.%3N"
  else
    python3 - "$@" <<'PY'
import datetime, time
t = time.time()
print(datetime.datetime.fromtimestamp(t).strftime('%Y-%m-%d %H:%M:%S.') + f'{int((t-int(t))*1000):03d}')
PY
  fi
}

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true ;;
    *) VIDEO_DIR=$1 ;;
  esac
  shift
done

echo "VIDEO_DIR=[$VIDEO_DIR]"
if [[ -d "$VIDEO_DIR" ]]; then
  echo "DEBUG: directory test passes"
else
  echo "DEBUG: directory test fails"
fi
if [[ -z "$VIDEO_DIR" || ! -d "$VIDEO_DIR" ]]; then
  echo "Usage: $0 [--dry-run] /path/to/video_directory"
  exit 1
fi

# Portable file-size helper
stat_size() {
  stat -f%z "$1" 2>/dev/null || stat -c%s "$1"
}

# Main loop
find "$VIDEO_DIR" -type f \( -iname '*.mp4' -o -iname '*.mkv' \) -print0 |
while IFS= read -r -d '' video; do

  # ensure absolute path
  [[ "$video" != /* ]] && video="/$video"

  echo ""
  echo ">> Processing: $video"
  base_name=$(basename "${video%.*}")

  # Build search queries from filename and parent dirs
  queries=()
  if [[ "$base_name" == *_* ]]; then
    channel="${base_name%%_*}"
    title_part="${base_name#*_}"
    queries+=("$channel $title_part")
  fi
  parent_dir=$(basename "$(dirname "$video")")
  grandparent_dir=$(basename "$(dirname "$(dirname "$video")")")
  queries+=("$parent_dir $base_name" "$grandparent_dir $base_name")

  # Lookup YouTube metadata
  meta=""
  for q in "${queries[@]}"; do
    echo "Trying search: $q"
    meta=$(yt-dlp -j "ytsearch:$q" 2>/dev/null | head -n1 || true)
    url=$(echo "$meta" | jq -r '.webpage_url')
    uploader=$(echo "$meta" | jq -r '.uploader')
    video_id=$(echo "$meta" | jq -r '.id')
    if [[ $url == https://* && -n $uploader && $video_id != "null" ]]; then
      echo "Match found with: $q"
      break
    fi
  done

  if [[ -z ${video_id:-} || $video_id == "null" ]]; then
    echo "No match found for: $base_name"
    continue
  fi

  # Extract metadata fields
  title=$(echo "$meta" | jq -r '.title')
  upload_date=$(echo "$meta" | jq -r '.upload_date')
  formatted_date=$(python3 - "$upload_date" <<'PY'
import sys, datetime
d = datetime.datetime.strptime(sys.argv[1], "%Y%m%d")
print(d.strftime("%Y-%m-%d"))
PY
)
  view_count=$(echo "$meta" | jq -r '.view_count')
  description=$(echo "$meta" | jq -r '.description')

  echo "Title: $title"
  echo "Uploader: $uploader"
  echo "ID: $video_id"
  # echo "Views: $view_count"

  if $DRY_RUN; then
    echo "Dry-run: skipping thumbnail and metadata embedding"
    continue
  fi

  # Thumbnail candidates (highest quality first)
  thumb_candidates=(
    "https://img.youtube.com/vi/${video_id}/maxresdefault.jpg"
    "https://img.youtube.com/vi/${video_id}/sddefault.jpg"
    "https://img.youtube.com/vi/${video_id}/hqdefault.jpg"
    "https://img.youtube.com/vi/${video_id}/default.jpg"
  )
  thumb_file="${video%.*}.jpg"
  thumb_ok=false
  MIN_SIZE=10240  # 10 KiB

  for thumb_url in "${thumb_candidates[@]}"; do
    # echo "$(timestamp_ms) thumb_file: $thumb_file"
    # echo "Downloading: $thumb_url"

    mkdir -p "$(dirname "$thumb_file")"
    if curl -4 -sS --noproxy '*' --location  \
            --retry 3 --retry-delay 1 \
            -A "Mozilla/5.0" \
            --output "${thumb_file}.part" \
            "$thumb_url"; then

      mv -- "${thumb_file}.part" "$thumb_file"
      size=$(stat_size "$thumb_file")
      # echo "$(timestamp_ms) Size: ${size} B"

      if (( size > MIN_SIZE )); then
        # echo "!! Saved thumbnail ($((${size}/1024)) KiB)"
        thumb_ok=true
        break
      # else
      #   echo "Ignoring too-small file (<${MIN_SIZE} B)"
      fi

    else
      echo "Download error (exit $?) for $thumb_url"
    fi

    rm -f -- "${thumb_file}" "${thumb_file}.part"
  done

  if ! $thumb_ok; then
    echo "No usable thumbnail – skipping $video"
    continue
  fi

  # Embed metadata and cover art
  echo "Embedding metadata and thumbnail"
  tmpfile="${video%.*}_tmp.${video##*.}"
  # echo "tmpfile: $tmpfile"

  ffmpeg -hide_banner -loglevel error \
    -i "$video" -i "$thumb_file" \
    -map 0 -map 1 -c copy \
    -metadata title="$title" \
    -metadata artist="$uploader" \
    -metadata comment="$description" \
    -metadata date="$formatted_date" \
    -metadata publisher="$url" \
    -metadata description="Views: $view_count" \
    -disposition:v:1 attached_pic \
    "$tmpfile"

  mv "$tmpfile" "$video"
  rm -f "$thumb_file"
  echo "Updated $video"
done
