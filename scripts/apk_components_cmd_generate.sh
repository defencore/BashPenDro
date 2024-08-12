#!/bin/bash

# Function to display debug messages
debug_message() {
    if [ "$debug" = true ]; then
        echo "### =============================== ###"
        echo "$1"
    fi
}

# Function to display the help manual
display_help() {
    debug_message "Entering display_help function"
    echo "Usage: $0 -f <path to the AndroidManifest.xml file> -o <path to the output file> [-d]"
    echo
    echo "Options:"
    echo "  -f <file>       Specify the path to the AndroidManifest.xml file."
    echo "  -o <file>       Specify the output file to save the generated adb commands."
    echo "  -d              Enable debug mode."
    echo
    echo "Description:"
    echo "This script processes the AndroidManifest.xml file to extract components"
    echo "with android:exported=\"true\" attribute and generates appropriate adb"
    echo "commands to interact with these components. It handles activities, services,"
    echo "receivers, and other component types appropriately."
    echo
    echo "Requirements:"
    echo "  - xmlstarlet: XML command line utilities"
    echo
    echo "Example:"
    echo "  $0 -f /path/to/AndroidManifest.xml -o /path/to/output/file.adb.commands -d"
}

# Variable initialization
manifest_file=""
output_file=""
test_value="BashPenDro"
strings_file=""
debug=false

# Command-line argument parsing
while getopts "f:o:dh" opt; do
    case $opt in
        f) manifest_file="$OPTARG" ;;
        o) output_file="$OPTARG" ;;
        d) debug=true ;;
        h) display_help; exit 0 ;;
        *) echo "Invalid argument" >&2; display_help; exit 1 ;;
    esac
done

# Debugging info
debug_message "Debug mode enabled"

# Checking for mandatory arguments
if [ -z "$manifest_file" ] || [ -z "$output_file" ]; then
    echo "Missing mandatory arguments." >&2
    display_help
    exit 1
fi

# Checking for the existence of the AndroidManifest.xml file
if [ ! -f "$manifest_file" ]; then
    echo "File $manifest_file not found."
    exit 1
fi

# Finding and reading the res/values/strings.xml file
strings_file=$(find "$(dirname "$manifest_file")" -type f -name "strings.xml" | grep "res/values/strings.xml")

if [ -z "$strings_file" ]; then
    echo "res/values/strings.xml file not found."
    exit 1
fi

# Debugging info
debug_message "Strings file found: $strings_file"

# Create a temporary file to store key-value pairs
key_value_file=$(mktemp)
trap 'rm -f "$key_value_file"' EXIT

# Parse the strings.xml file and store the values in the temporary file
while IFS= read -r line; do
    debug_message "Parsing strings.xml line: $line"
    if [[ $line =~ \<string\ name=\"(.*)\"\>(.*)\</string\> ]]; then
        echo "${BASH_REMATCH[1]}=${BASH_REMATCH[2]}" >> "$key_value_file"
    fi
done < "$strings_file"

# Check for xmlstarlet
if ! command -v xmlstarlet &> /dev/null; then
    echo "xmlstarlet could not be found, please install it."
    exit 1
fi

# Check for adb
if ! command -v adb &> /dev/null; then
    echo "adb could not be found, please install it."
    exit 1
fi

# Using xmlstarlet to select components with android:exported="true"
components=$(xmlstarlet sel -t -m '//*[@android:exported="true"]' -v 'concat(name(), ":", @android:name)' -n "$manifest_file")

# Additional error handling when processing XML components
if [ -z "$components" ]; then
    echo "No components with android:exported=\"true\" found in $manifest_file."
    exit 0
fi

# Debugging info
debug_message "Found components: $components"

# Retrieving the app package
package=$(xmlstarlet sel -t -v '/manifest/@package' "$manifest_file")

# Create a temporary file for processing commands
debug_message "Creating temporary file for processing commands..."
tmp_file=$(mktemp)
trap 'debug_message "Cleaning up temporary file..."; rm -f "$tmp_file"' EXIT

# Function to replace @string values with actual values using the temporary file
replace_string_reference() {
    local value="$1"
    if [[ $value == @string/* ]]; then
        local key=${value#@string/}
        local new_value=$(grep "^$key=" "$key_value_file" | cut -d'=' -f2)
        
        if [ -n "$new_value" ]; then
            value="$new_value"
        fi
    fi
    echo "$value"
}

# Looping through each component and outputting adb commands
IFS=$'\n'
for component in $components; do
    debug_message "Processing component: $component"
    
    comp_type=$(echo "$component" | cut -d':' -f1)
    comp_name=$(echo "$component" | cut -d':' -f2-)
    
    if [ -z "$comp_name" ]; then
        echo "# Component name missing for component type $comp_type." >> "$tmp_file"
        continue
    fi

    if [ -z "$comp_type" ];then
        echo "# Component type is missing for $comp_name." >> "$tmp_file"
        continue
    elif ! [[ "$comp_type" =~ ^(activity|service|receiver|provider|activity-alias)$ ]]; then
        echo "# Unsupported component type $comp_type for component $comp_name." >> "$tmp_file"
        continue
    fi

    full_component="$package/$comp_name"
    actions=$(xmlstarlet sel -t -m "//${comp_type}[@android:name='$comp_name']//intent-filter//action" -v '@android:name' -n "$manifest_file")
    schemes=$(xmlstarlet sel -t -m "//${comp_type}[@android:name='$comp_name']//intent-filter//data" -v '@android:scheme' -n "$manifest_file")
    hosts=$(xmlstarlet sel -t -m "//${comp_type}[@android:name='$comp_name']//intent-filter//data" -v '@android:host' -n "$manifest_file")

    if [ -z "$actions" ] && [[ "$comp_type" != "provider" && "$comp_type" != "activity-alias" ]]; then
        if [ -n "$schemes" ] && [ -n "$hosts" ];then
            for scheme in $schemes; do
                for host in $hosts; do
                    host=$(replace_string_reference "$host")
                    echo "adb shell su -c \"am start -n $full_component -d $scheme://$host/$test_value\"" >> "$tmp_file"
                done
            done
        else
            case "$comp_type" in
                activity | activity-alias)
                    echo "adb shell su -c \"am start -n $full_component\"" >> "$tmp_file"
                    ;;
                service)
                    echo "adb shell su -c \"am startservice -n $full_component\"" >> "$tmp_file"
                    ;;
                receiver)
                    echo "adb shell su -c \"am broadcast -n $full_component\"" >> "$tmp_file"
                    ;;
                provider)
                    echo "# Component $comp_name is a provider and cannot be invoked via am start/broadcast." >> "$tmp_file"
                    ;;
                *)
                    echo "# Unknown component type $comp_type for component $comp_name." >> "$tmp_file"
                    ;;
            esac
        fi
    else
        for action in $actions; do
            if [ -z "$schemes" ]; then
                scheme_option=""
                case "$comp_type" in
                    activity | activity-alias)
                        echo "adb shell su -c \"am start -n $full_component -a $action$scheme_option\"" >> "$tmp_file"
                        ;;
                    service)
                        echo "adb shell su -c \"am startservice -n $full_component -a $action$scheme_option\"" >> "$tmp_file"
                        ;;
                    receiver)
                        echo "adb shell su -c \"am broadcast -n $full_component -a $action$scheme_option\"" >> "$tmp_file"
                        ;;
                    provider)
                        echo "# Component $comp_name is a provider and cannot be invoked via am start/broadcast." >> "$tmp_file"
                        ;;
                esac
            else
                for scheme in $schemes; do
                    scheme=$(replace_string_reference "$scheme")
                    for host in $hosts; do
                        host=$(replace_string_reference "$host")
                        scheme_option=" -d $scheme://$host/$test_value"
                        case "$comp_type" in
                            activity | activity-alias)
                                echo "adb shell su -c \"am start -n $full_component -a $action$scheme_option\"" >> "$tmp_file"
                                ;;
                            service)
                                echo "adb shell su -c \"am startservice -n $full_component -a $action$scheme_option\"" >> "$tmp_file"
                                ;;
                            receiver)
                                echo "adb shell su -c \"am broadcast -n $full_component -a $action$scheme_option\"" >> "$tmp_file"
                                ;;
                            provider)
                                echo "# Component $comp_name is a provider and cannot be invoked via am start/broadcast." >> "$tmp_file"
                                ;;
                        esac
                    done
                done
            fi
        done
    fi
done

component_count=$(wc -l < "$tmp_file")

if [ "$component_count" -gt 0 ]; then
    sort -u "$tmp_file" > "$output_file"
    echo "Found $component_count exported components. Commands saved to $output_file"
else
    echo "No exported components found."
fi

# Debugging info
debug_message "Contents of key-value file:"
debug_message "$(cat "$key_value_file")"
