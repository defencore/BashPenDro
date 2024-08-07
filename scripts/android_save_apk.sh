#!/bin/bash

# Default values for parameters
keyword_filter=""
save_directory="."

# Function to display help message
display_help() {
    echo "Usage: $0 [-f <keyword_filter>] [-d <save_directory>]"
    echo ""
    echo "Options:"
    echo "  -f <keyword_filter>   Filter the list of installed applications by keyword."
    echo "                        Only applications whose package name contains the keyword will be listed."
    echo "  -d <save_directory>   Specify the directory where the APK file should be saved."
    echo "                        If not specified, the current directory is used."
    echo "  -h                    Display this help message and exit."
    exit 0
}

# Parse command line arguments
while getopts "hf:d:" opt; do
  case ${opt} in
    f )
      keyword_filter=$OPTARG
      ;;
    d )
      save_directory=$OPTARG
      mkdir -p $save_directory
      ;;
    h )
      display_help
      exit 0
      ;;
    \? )
      display_help
      exit 1
      ;;
  esac
done

# Check if ADB is installed
if ! command -v adb &> /dev/null
then
    echo "ADB is not installed. Please install it and try again."
    exit
fi

# Connect to the device via ADB
adb start-server
adb devices

# Retrieve the list of installed applications
echo "Retrieving the list of installed applications..."
apps=$(adb shell pm list packages -f | grep -v '/system')

# Display the list of applications, applying the keyword filter if provided
echo "List of installed applications:"
counter=1
app_list=()

while IFS= read -r app; do
    package=$(echo $app | sed 's/.*=//')
    if [ -z "$keyword_filter" ] || [[ $package == *"$keyword_filter"* ]]; then
        app_list+=("$package")
        echo "$counter. $package"
        ((counter++))
    fi
done <<< "$apps"

# Check if any applications were found
if [ $counter -eq 1 ]; then
    echo "No applications found matching the filter '$keyword_filter'."
    exit
fi

# Prompt for application selection
read -p "Enter the number of the application you want to save: " app_number
selected_package=${app_list[$app_number-1]}

if [ -z "$selected_package" ]; then
    echo "Invalid selection. Please try again."
    exit
fi

# Get the paths to the APK files
apk_paths=$(adb shell pm path $selected_package | sed 's/package://')

# Create the save directory if it doesn't exist
mkdir -p "$save_directory"

# Get the version code of the application
#version=$(adb shell dumpsys package $selected_package | grep versionName | sed 's/.*versionName=//' | tr -d '\n' | awk '{print $1}')
version=$(adb shell dumpsys package $selected_package | grep versionName | awk -F= '{print $2}' | sort -rV | head -n 1)


# Iterate over each APK path and pull the files
for apk_path in $apk_paths; do
    # Extract the part of the APK path after the last slash and before the .apk extension
    suffix=$(basename "$apk_path" | sed 's/.*base\|split_//;s/.apk$//')
    file_name="${save_directory}/${selected_package}_${version}_${suffix}.apk"
    echo "Copying $selected_package version code $version, part $suffix..."
    adb pull "$apk_path" "$file_name"
    echo "Part $suffix saved as $file_name"
done

echo "Application $selected_package saved with all parts."
