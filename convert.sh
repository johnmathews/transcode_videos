#!/bin/bash

LOG_FILE="conversion.log"
ERROR_LOG="conversion_errors.log"

# Function to log messages with timestamps, headers, and emojis
log_message() {
    local level="$1" # INFO, SUCCESS, ERROR
    local message="$2"
    local log_file="$3"
    local emoji timestamp
    local color reset_color

    case $level in
    SUCCESS)
        emoji=" ✅"
        color=""
        ;; # Green
    ERROR)
        emoji=" 💀"
        color=""
        ;; # Red
    *)
        emoji=""
        color=""
        ;;
    esac
    reset_color="\033[0m"

    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Print colored output to the console
    echo -e "${color}[$timestamp]$emoji $message${reset_color}"

    # Write plain text (no color codes) to the log file
    echo "[$timestamp] $emoji $message" >>"$log_file"
}

# Add a section header to log files
log_header() {
    local header="$1"
    local separator="============================================================================="

    echo -e "\n$separator\n$header\n$separator"
}

# Create log files if they don't exist
touch "$LOG_FILE" "$ERROR_LOG"

# Find video files and process them
find . -maxdepth 1 -type f \( -iname "*.avi" -o -iname "*.mkv" -o -iname "*.mp4" -o -iname "*.mov" -o -iname "*.flv" -o -iname "*.wmv" -o -iname "*.webm" \) -print0 |
while IFS= read -r -d '' f; do
    dir="$(dirname "$f")"
    filename="$(basename "${f%.*}")"
    original_dir="$dir/original"
    converted_dir="$dir/converted"
    input="$original_dir/$(basename "$f")"
    output="$converted_dir/${filename}.mp4"

    # Create necessary directories
    mkdir -p "$original_dir" "$converted_dir"

    # Add a section for the file conversion
    log_header "🔥 Processing File: $filename"

    # Move the file to the original directory if not already moved
    if [ ! -f "$input" ]; then
        mv "$f" "$original_dir/"
        log_message "INFO" "🚚 Moved '$f' to '$original_dir/'" "$LOG_FILE"
    fi

    # Skip conversion if the file has already been processed
    if [ -f "$output" ]; then
        log_message "INFO" "Skipping '$input': already converted." "$LOG_FILE"
        continue
    fi

    # Convert the file
    log_message "INFO" "⚙️  Converting '$input' to '$output'..." "$LOG_FILE"
    if ffmpeg -nostdin -hide_banner -loglevel error -stats -i "$input" -c:v libx264 -preset slow -crf 18 -threads 0 -profile:v high -level 4.2 -pix_fmt yuv420p \
        -c:a aac -b:a 256k "$output"; then
        log_message "SUCCESS" "Successfully converted '$input' to '$output'." "$LOG_FILE"
    else
        log_message "ERROR" "Failed to convert '$input'." "$ERROR_LOG"
    fi
done
