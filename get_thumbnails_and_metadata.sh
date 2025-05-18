#!/bin/bash
#
# update_youtube_metadata.sh
#
# Add/refresh thumbnails and metadata for videos downloaded with yt-dlp.
#
# Usage:
#   ./update_youtube_metadata.sh [--dry-run] /path/to/video_directory
#
# Typical yt-dlp command used to download the original files:
#   yt-dlp --embed-thumbnail --convert-thumbnails jpg \
#          -f bestvideo+bestaudio --restrict-filenames \
#          -o "~/Desktop/videos/%(uploader)s-%(title)s.%(ext)s" URL
#
# Requires: yt-dlp, jq, curl, ffmpeg
# ---------------------------------------------------------------------

set -euo pipefail
trap 'echo -e "\n🛑  Script interrupted. Exiting."; exit 130' INT

DRY_RUN=false
VIDEO_DIR=""

# Helper to return local timestamp with millisecond precision
timestamp_ms() {
  # Prefer 'gdate' if installed (coreutils on macOS)
  if command -v gdate >/dev/null 2>&1; then
    gdate +"%Y-%m-%d %H:%M:%S.%3N"
  else
    python3 - <<'PY'
import datetime, time, locale, os
locale.setlocale(locale.LC_ALL, '')      # honour locale settings
t = time.time()
dt = datetime.datetime.fromtimestamp(t)
print(dt.strftime('%Y-%m-%d %H:%M:%S.') + f'{int((t-int(t))*1000):03d}')
PY
  fi
}


# ---------- argument parsing ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true ;;
    *)         VIDEO_DIR=$1 ;;
  esac
  shift
done

if [[ -z "$VIDEO_DIR" || ! -d "$VIDEO_DIR" ]]; then
  echo "Usage: $0 [--dry-run] /path/to/video_directory"
  exit 1
fi

# ---------- helper ----------
stat_size () {  # portable file-size helper
  stat -f%z "$1" 2>/dev/null || stat -c%s "$1"
}

# ---------- main loop ----------
find "$VIDEO_DIR" -type f \( -iname '*.mp4' -o -iname '*.mkv' \) | \
while IFS= read -r video; do
  echo "🔍 Processing: $video"
  base_name=$(basename "${video%.*}")

  # ---- build search queries -------------------------------------------------
  queries=()
  if [[ "$base_name" == *_* ]]; then
    channel="${base_name%%_*}"
    title_part="${base_name#*_}"
    queries+=("$channel $title_part")
  fi
  parent_dir=$(basename "$(dirname "$video")")
  grandparent_dir=$(basename "$(dirname "$(dirname "$video")")")
  queries+=("$parent_dir $base_name" "$grandparent_dir $base_name")

  # ---- locate YouTube video -------------------------------------------------
  meta=""
  for q in "${queries[@]}"; do
    echo "🔎 Trying search: $q"
    meta=$(yt-dlp -j "ytsearch:$q" 2>/dev/null | head -n1 || true)
    url=$(echo "$meta" | jq -r '.webpage_url')
    uploader=$(echo "$meta" | jq -r '.uploader')
    video_id=$(echo "$meta" | jq -r '.id')
    [[ $url == https://* && -n $uploader && $video_id != "null" ]] && {
      echo "✅ Match found with: $q"
      break
    }
  done

  if [[ -z ${video_id:-} || $video_id == "null" ]]; then
    echo "❌ No match found for: $base_name"
    continue
  fi

  # ---- extract remaining metadata ------------------------------------------
  title=$(echo "$meta"        | jq -r '.title')
  upload_date=$(echo "$meta"  | jq -r '.upload_date')
  formatted_date=$(date -j -f "%Y%m%d" "$upload_date" +"%Y-%m-%d" 2>/dev/null || echo "$upload_date")
  view_count=$(echo "$meta"   | jq -r '.view_count')
  description=$(echo "$meta"  | jq -r '.description')

  echo "🎯  Title: $title"
  echo "    Uploader: $uploader"
  echo "    ID: $video_id"
  echo "    Views: $view_count"

  $DRY_RUN && { echo "💡 Dry-run — skipping thumbnail/ffmpeg"; continue; }

  # ---- thumbnail download ---------------------------------------------------
  thumb_candidates=(
    "https://img.youtube.com/vi/${video_id}/maxresdefault.jpg"
    "https://img.youtube.com/vi/${video_id}/sddefault.jpg"
    "https://img.youtube.com/vi/${video_id}/hqdefault.jpg"
    "https://img.youtube.com/vi/${video_id}/default.jpg"
  )
  thumb_file="${video%.*}.jpg"
  thumb_ok=false

  MIN_SIZE=2500   # bytes

  for url in "${thumb_candidates[@]}"; do
    echo "🖼️  $(timestamp_ms)  Fetching: $url"

    if curl --fail --silent --location \
            --retry 3 --retry-delay 1 \
            --output "${thumb_file}.part" "$url"; then
      mv "${thumb_file}.part" "$thumb_file"
      size=$(stat_size "$thumb_file")

      echo "🕒  $(timestamp_ms)  Size: ${size} B"

      if (( size > MIN_SIZE )); then
        echo "✅ Saved thumbnail ($((size/1024)) KiB)"
        thumb_ok=true
        break
      else
        echo "ℹ️  Ignoring small file (<${MIN_SIZE} B)"
      fi
    else
      echo "⚠️  $(timestamp_ms)  curl failed (exit $?)"
    fi

    rm -f "${thumb_file}.part"
  done

  if ! $thumb_ok; then
    echo "❌ No usable thumbnail — skipping $video"
    continue
  fi

  # ---- embed metadata & cover art ------------------------------------------
  echo "🎬 Embedding metadata and thumbnail…"
  tmpfile="${video%.*}_tmp.${video##*.}"

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
  echo "✅ Updated $video"

  rm -f "$thumb_file"
done
