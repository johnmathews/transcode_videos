#!/bin/bash
###############################################################################
# Video Conversion Script
#
# Searches the current folder for video files (avi, mkv, mp4, mov, flv, wmv, webm),
# prints a numbered list of identified files, moves each file to an "original" subfolder,
# prints the video's total duration, and converts it to MP4 (using ffmpeg) saved in a 
# "converted" subfolder.
#
# Duplicate basenames are resolved by appending a counter.
#
# Usage:
#   ./convert.sh         # Normal mode: moves & converts files
#   ./convert.sh -d      # Dry run mode: list files to convert without converting
#   ./convert.sh -h      # Show this help message
#
# Requirements: ffmpeg and ffprobe must be installed.
###############################################################################

set -o pipefail

# Variables
LOG_FILE="conversion.log"
ERROR_LOG="conversion_errors.log"
DRY_RUN=false
MAX_JOBS=4

# Display help message and exit
display_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -d         Dry run mode: list files to convert without converting"
    echo "  -j N       Run up to N conversions in parallel (default: 4)"
    echo "  -h, --help Show this help message and exit"
    exit 0
}

# Parse command-line options
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -d) DRY_RUN=true ;;
        -j|--jobs)
            shift
            MAX_JOBS="$1"
            if ! [[ "$MAX_JOBS" =~ ^[0-9]+$ ]]; then
                echo "Invalid job count: $MAX_JOBS"
                exit 1
            fi
            ;;
        -h|--help) display_help ;;
        *) echo "Unknown option: $1" ; display_help ;;
    esac
    shift
done

# Check for ffmpeg and ffprobe
if ! command -v ffmpeg &> /dev/null; then
    echo "❌  ffmpeg not found. Please install ffmpeg and try again."
    exit 1
fi

if ! command -v ffprobe &> /dev/null; then
    echo "❌  ffprobe not found. Please install ffmpeg (which includes ffprobe) and try again."
    exit 1
fi

# Create log files if they don't exist
touch "$LOG_FILE" "$ERROR_LOG"

# Logging function: prints colored messages to console and logs plain text.
log_message() {
    local level="$1"   # INFO, SUCCESS, or ERROR
    local message="$2"
    local log_file="$3"
    local emoji color reset_color timestamp
    reset_color="\033[0m"
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    case "$level" in
        SUCCESS)
            emoji="✅"
            color="\033[0;32m"
            ;;
        ERROR)
            emoji="💀"
            color="\033[0;31m"
            ;;
        INFO)
            emoji=""
            color="\033[0;34m"
            ;;
        INFO2)
            emoji=""
            color="\033[0;95m"
            ;;
        *)
            emoji=""
            color=""
            ;;
    esac
    echo -e "${color}[$timestamp] $emoji $message${reset_color}"
    echo "[$timestamp] $emoji $message" >> "$log_file"
}

# Log header function.
log_header() {
    local header="$1"
    local separator="============================================================================="
    echo -e "\n$separator\n$header\n$separator"
    echo -e "\n$separator\n$header\n$separator" >> "$LOG_FILE"
}

# Generate unique output filename.
unique_output_filename() {
    local base_dir="$1"
    local name="$2"
    local ext="$3"
    local output_file="${base_dir}/${name}.${ext}"
    local counter=1
    while [[ -e "$output_file" ]]; do
        output_file="${base_dir}/${name} (${counter}).${ext}"
        ((counter++))
    done
    echo "$output_file"
}

# Build an array of video files (zsh-compatible method).
files=()
while IFS= read -r -d $'\0' file; do
    files+=("$file")
done < <(find . -maxdepth 1 -type f \( -iname "*.avi" -o -iname "*.mkv" -o -iname "*.mp4" -o -iname "*.mov" -o -iname "*.flv" -o -iname "*.wmv" -o -iname "*.webm" \) -print0)

TOTAL_FILES=${#files[@]}
COUNTER=0

if [[ "$TOTAL_FILES" -eq 0 ]]; then
    echo "There are no files to convert."
    exit 0
fi

# Print numbered list of identified files.
echo ""
echo "Identified files for conversion:"
for i in "${!files[@]}"; do
    printf "%d. %s\n" $((i+1)) "${files[i]}"
done

process_video() {
    local f="$1"
    COUNTER=$((COUNTER+1))
    dir="$(dirname "$f")"
    base_filename="$(basename "$f")"
    filename="$(basename "${f%.*}")"
    original_dir="${dir}/original"
    converted_dir="${dir}/converted"
    input="${original_dir}/${base_filename}"
    output=$(unique_output_filename "$converted_dir" "$filename" "mp4")
    temp_output="${output%.mp4}.temp.mp4"

    if $DRY_RUN; then
        echo "📂  Would process file ${COUNTER}/${TOTAL_FILES}: $f -> $output"
        return
    fi

    mkdir -p "$original_dir" "$converted_dir"
    log_header "🔥  Processing file ${COUNTER}/${TOTAL_FILES}: $filename"

    if [ ! -f "$input" ]; then
        if mv "$f" "$original_dir/"; then
            log_message "INFO" "Moved '$f' to '$original_dir/'" "$LOG_FILE"
        else
            log_message "ERROR" " Failed to move '$f' to '$original_dir/'" "$ERROR_LOG"
            return
        fi
    fi

    if [ -f "$output" ]; then
        log_message "INFO" "Skipping '$input': already converted." "$LOG_FILE"
        return
    fi

    log_message "INFO" "Converting '$input' to temporary file '$temp_output'..." "$LOG_FILE"

    duration=$(ffprobe -v error -select_streams v:0 -show_entries format=duration \
        -of default=noprint_wrappers=1:nokey=1 "$input")
    if [ -n "$duration" ]; then
        duration_int=${duration%.*}
        hours=$((duration_int/3600))
        minutes=$(((duration_int % 3600)/60))
        seconds=$((duration_int % 60))
        log_message "INFO2" "Duration: ${hours}h ${minutes}m ${seconds}s" "$LOG_FILE"
    fi

    # Use H.264 hardware acceleration for best compatibility with QuickLook
    CONVERT_CMD=(nice -n 10 ffmpeg -nostdin -hide_banner -loglevel error -progress - -i "$input" \
        -c:v h264_videotoolbox -b:v 6000k -pix_fmt yuv420p \
        -c:a aac -b:a 256k "$temp_output")

    "${CONVERT_CMD[@]}" 2>&1 | awk '
    BEGIN {
      frame=""; fps=""; out_time=""; speed="";
    }
    {
      split($0, a, "=");
      key = a[1]; value = a[2];
      if(key=="frame") { frame = value; }
      else if(key=="fps") { fps = value; }
      else if(key=="out_time") { out_time = value; }
      else if(key=="speed") { speed = value; }
      else if(key=="progress" && value=="continue") {
          printf("\rframe=%s, fps=%s, time=%s, speed=%s", frame, fps, out_time, speed);
          fflush(stdout);
      }
      else if(key=="progress" && value=="end") {
          printf("\rframe=%s, fps=%s, time=%s, speed=%s\n", frame, fps, out_time, speed);
          fflush(stdout);
          exit;
      }
    }'
    ffmpeg_ec=${PIPESTATUS[0]}

    echo ""  # newline after progress

    if [ $ffmpeg_ec -eq 0 ]; then
        mv "$temp_output" "$output"
        log_message "SUCCESS" "Successfully converted '$input' to '$output'." "$LOG_FILE"
    else
        log_message "ERROR" "Failed to convert '$input'." "$ERROR_LOG"
        rm -f "$temp_output"
    fi
}



# Process each video file.
CURRENT_JOBS=0

for f in "${files[@]}"; do
    (
        process_video "$f"
    ) &

    ((CURRENT_JOBS++))
    if (( CURRENT_JOBS >= MAX_JOBS )); then
        wait -n
        ((CURRENT_JOBS--))
    fi
done

wait  # wait for any remaining jobs
