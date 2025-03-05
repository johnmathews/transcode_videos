# Transcode Script 🚀

A Bash script that automates video conversion using FFmpeg. It searches the
current directory for common video files, moves them into an `original` folder,
and converts them to MP4 format (saved in a `converted` folder). The script uses
temporary files during conversion to safely handle mid-run cancellations and is
idempotent—re-running it skips already processed files.

## Features

- **Automatic File Organization:** 📁  
  Moves original video files to an `original` directory before conversion.

- **Real-Time, Single-Line Conversion Progress:** ⏱️  
  Uses FFmpeg’s `-progress -` option and an AWK script to display conversion
  progress (frame count, fps, elapsed time, speed) on a single, continuously
  updated line in the console.

- **Video Conversion:**  
  Converts videos to MP4 using FFmpeg with H.264 (libx264) and AAC encoding.

- **Duplicate Handling:**  
  Resolves duplicate basenames by appending a counter to the output filename.

- **Dry Run Mode:** 👀  
  Use the `-d` flag to list files that would be processed without converting them.

- **Robust Error Handling:** ⚠️  
  Uses temporary output files to ensure that incomplete conversions do not
  register as successful. Logs conversion progress and errors to separate log files.

- **Optional Real-Time Buffering:**  
  If available, the script uses `unbuffer` (from the expect package) to improve
  the real-time display of conversion progress.

- **Idempotency:** 🔄  
  Safe to re-run—the script skips files that have already been moved and converted.

## Requirements

- **Bash** (tested on Linux/macOS)
- **FFmpeg** (must be installed and available in your PATH)
- **FFprobe** (part of FFmpeg)
- *Optional:* **unbuffer** (from the expect package) for enhanced real-time progress output

## Installation 📥

1. **Clone the repository:**

   ```bash
   git clone https://github.com/yourusername/transcode-script.git

1. **Clone the repository:**

   ```bash
   git clone https://github.com/yourusername/transcode-script.git
   ```

2. Navigate to the repository directory:

```bash
cd transcode-script
```

3. Make the script executable:

```bash
chmod +x transcode.sh
```

## Usage ▶️

Run the script from the directory containing your video files.

- Normal Mode (Convert Files):
  ```bash
  ./transcode.sh
  ```
- Dry Run Mode (List Files Only):
  ```bash
  ./transcode.sh -d
  ```
- Help:
  ```
  ./transcode.sh -h
  ```

## How It Works 🔧

1. File Discovery:

   - Searches for video files (e.g., .avi, .mkv, .mp4, .mov, .flv, .wmv, .webm)
     in the current directory.

2. Organization:

   - Moves each file to an original subfolder (if not already moved).

3. Conversion:

   - Converts the file to MP4 format using FFmpeg.
   - A temporary file is used during conversion; upon success, it is renamed to
     the final output name.
   - This prevents incomplete conversions from being misinterpreted as complete.

4. Logging:

   - Conversion logs are written to conversion.log and errors to
     conversion_errors.log.

## Contributing

Contributions are welcome! If you have suggestions or improvements, please open
an issue or submit a pull request.
