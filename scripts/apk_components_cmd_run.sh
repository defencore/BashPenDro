#!/bin/bash

# Function to display help manual
display_help() {
  echo "Usage: $0 -f <path_to_file> -d <directory_for_screenshots>"
  echo
  echo "Description:"
  echo "  This script reads a file containing adb commands, executes them one by one,"
  echo "  and allows the user to take screenshots while the commands are being executed."
  echo
  echo "Options:"
  echo "  -f FILE    Specify the path to the file containing commands"
  echo "  -d DIR     Specify the directory to save screenshots"
  echo "  -h         Display this help message"
  echo
  echo "Example usage:"
  echo "  $0 -f /path/to/output/file.adb.commands -d ./screenshots"
  exit 0
}

# Variables to store file path and directory for screenshots
file=""
screenshot_dir=""

# Counters
screenshot_count=0
executed_count=0
skipped_count=0

# Command-line parameter processing
while getopts "f:d:h" opt; do
  case $opt in
    f)
      file=$OPTARG
      ;;
    d)
      screenshot_dir=$OPTARG
      ;;
    h)
      display_help
      ;;
    *)
      display_help
      ;;
  esac
done

# Check if file is specified
if [[ -z $file ]]; then
  echo "Error: Path to file is not specified."
  display_help
fi

# Check if file exists
if [[ ! -f $file ]]; then
  echo "File $file not found."
  exit 1
fi

# Check if screenshot directory is specified
if [[ -z $screenshot_dir ]]; then
  echo "Error: Directory for screenshots is not specified."
  display_help
fi

# Check if screenshot directory exists, if not, create it
if [[ ! -d $screenshot_dir ]]; then
  mkdir -p "$screenshot_dir"
fi

echo "File found. Starting to read commands..."

# Array to store PIDs
pids=()

# Reading the file line by line
while IFS= read -r line; do
  # Skip comments and empty lines
  if [[ $line =~ ^#.* ]] || [[ -z "$line" ]]; then
    continue
  fi

  # Check if the command starts with "adb"
  if [[ $line != adb* ]]; then
    echo "Skipping non-adb command: $line"
    continue
  fi

  # Displaying the command
  echo ""
  echo "Command to be executed:"
  echo "$line"

  while true; do
    # Waiting for Enter key press using /dev/tty
    read -p ">>> Press [Enter] to execute the command, [Space] to take a screenshot, or any other key to skip <<<" -n 1 -r < /dev/tty
    echo
    if [[ $REPLY == "" ]]; then
      echo "[+] Complete: $line"
      # Executing the command in the background
      ( $line > /dev/null 2>&1 & )
      pid=$!
      pids+=($pid)
      executed_count=$((executed_count + 1))
      break
    elif [[ $REPLY == " " ]]; then
        screenshot_file="screenshot_$(date +%Y%m%d_%H%M%S).png"
        local_path="$screenshot_dir/$screenshot_file"
        echo "Taking screenshot and saving to $local_path..."
        adb exec-out screencap -p > "$local_path" || { echo "Failed to take screenshot."; continue; }
        echo "Screenshot saved."
        screenshot_count=$((screenshot_count + 1))
    else
      echo "[-] Skipped: $line"
      skipped_count=$((skipped_count + 1))
      break
    fi
  done

done < "$file"

# Waiting for all background processes to finish
for pid in "${pids[@]}"; do
  wait $pid
done

echo "Total screenshots taken: $screenshot_count"
echo "Total commands executed: $executed_count"
echo " Total commands skipped: $skipped_count"
