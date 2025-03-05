#!/bin/bash
###############################################################################
# Video Conversion Script
#
# Searches the current folder for video files (avi, mkv, mp4, mov, flv, wmv, webm),
# moves each file to an "original" subfolder, and converts it to MP4 (using ffmpeg)
# saved in a "converted" subfolder.
#
# Duplicate basenames are resolved by appending a counter.
#
# Usage:
#   ./transcode.sh         # Normal mode: moves & converts files
#   ./transcode.sh -d      # Dry run mode: list files to be processed without conversion
#   ./transcode.sh -h      # Show this help message
#
# Requirements: ffmpeg must be installed.
###############################################################################

# Variables
LOG_FILE="conversion.log"
ERROR_LOG="conversion_errors.log"
DRY_RUN=false

# Display help message and exit
display_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -d         Dry run mode: list files to convert without converting"
    echo "  -h, --help Show this help message and exit"
    exit 0
}

# Parse command-line options
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -d) DRY_RUN=true ;;
        -h|--help) display_help ;;
        *) echo "Unknown option: $1" ; display_help ;;
    esac
    shift
done

# Check for ffmpeg
if ! command -v ffmpeg &> /dev/null; then
    echo "❌  ffmpeg not found. Please install ffmpeg and try again."
    exit 1
fi

# Create log files if they don't exist
touch "$LOG_FILE" "$ERROR_LOG"

# Logging function: prints colored messages to console and plain text to a log file.
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
            color="\033[0;32m"  # Green
            ;;
        ERROR)
            emoji="💀"
            color="\033[0;31m"  # Red
            ;;
        INFO)
            emoji="ℹ️"
            color="\033[0;34m"  # Blue
            ;;
        *)
            emoji=""
            color=""
            ;;
    esac

    echo -e "${color}[$timestamp] $emoji $message${reset_color}"
    echo "[$timestamp] $emoji $message" >> "$log_file"
}

# Log header function: prints a visual separator with a header.
log_header() {
    local header="$1"
    local separator="============================================================================="
    echo -e "\n$separator\n$header\n$separator"
    echo -e "\n$separator\n$header\n$separator" >> "$LOG_FILE"
}

# Function to generate a unique output filename to avoid duplicate basename conflicts.
unique_output_filename() {
    local base_dir="$1"   # e.g., converted directory
    local name="$2"       # base name without extension
    local ext="$3"        # file extension (e.g., mp4)
    local output_file="${base_dir}/${name}.${ext}"
    local counter=1
    while [[ -e "$output_file" ]]; do
        output_file="${base_dir}/${name} (${counter}).${ext}"
        ((counter++))
    done
    echo "$output_file"
}

# Count total files to process in the current directory (matching video file extensions)
TOTAL_FILES=$(find . -maxdepth 1 -type f \( -iname "*.avi" -o -iname "*.mkv" -o -iname "*.mp4" -o -iname "*.mov" -o -iname "*.flv" -o -iname "*.wmv" -o -iname "*.webm" \) -print0 | tr '\0' '\n' | wc -l | xargs)
COUNTER=0

# Process each video file using process substitution to avoid subshell issues
while IFS= read -r -d '' f; do
    COUNTER=$((COUNTER+1))
    # Get the file's directory and names
    dir="$(dirname "$f")"
    base_filename="$(basename "$f")"
    filename="$(basename "${f%.*}")"

    # Define directories and paths
    original_dir="${dir}/original"
    converted_dir="${dir}/converted"
    input="${original_dir}/${base_filename}"
    output=$(unique_output_filename "$converted_dir" "$filename" "mp4")
    temp_output="${output%.mp4}.temp.mp4"

    # Dry run: list the intended conversion and skip actual processing.
    if $DRY_RUN; then
        echo "📂  Would process file ${COUNTER}/${TOTAL_FILES}: $f -> $output"
        continue
    fi

    # Create necessary directories
    mkdir -p "$original_dir" "$converted_dir"

    # Log the start of processing for this file with numbering.
    log_header "🔥  Processing file ${COUNTER}/${TOTAL_FILES}: $filename"

    # Move file to the original directory if not already moved.
    if [ ! -f "$input" ]; then
        if mv "$f" "$original_dir/"; then
            log_message "INFO" " Moved '$f' to '$original_dir/'" "$LOG_FILE"
        else
            log_message "ERROR" " Failed to move '$f' to '$original_dir/'" "$ERROR_LOG"
            continue
        fi
    fi

    # If the final output already exists, skip conversion.
    if [ -f "$output" ]; then
        log_message "INFO" " Skipping '$input': already converted." "$LOG_FILE"
        continue
    fi

    # Remove any leftover temporary file from a previous incomplete run.
    if [ -f "$temp_output" ]; then
        rm -f "$temp_output"
    fi

    # Convert the file using ffmpeg to a temporary file.
    log_message "INFO" " Converting '$input' to temporary file '$temp_output'..." "$LOG_FILE"
    if script -q /dev/null ffmpeg -nostdin -hide_banner -loglevel warning -stats -i "$input" \
        -c:v libx264 -preset slow -crf 18 -threads 0 -profile:v high -level 4.2 -pix_fmt yuv420p \
        -c:a aac -b:a 256k "$temp_output"
    then
        # Rename temp file to final output upon success.
        mv "$temp_output" "$output"
        log_message "SUCCESS" " Successfully converted '$input' to '$output'." "$LOG_FILE"
    else
        log_message "ERROR" "Failed to convert '$input'." "$ERROR_LOG"
        rm -f "$temp_output"
    fi
done < <(find . -maxdepth 1 -type f \( -iname "*.avi" -o -iname "*.mkv" -o -iname "*.mp4" -o -iname "*.mov" -o -iname "*.flv" -o -iname "*.wmv" -o -iname "*.webm" \) -print0)
