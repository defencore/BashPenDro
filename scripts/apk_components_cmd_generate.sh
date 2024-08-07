#!/bin/bash

# Function to display the help manual
display_help() {
    echo "Usage: $0 -f <path to the AndroidManifest.xml file> -o <path to the output file>"
    echo
    echo "Options:"
    echo "  -f <file>       Specify the path to the AndroidManifest.xml file."
    echo "  -o <file>       Specify the output file to save the generated adb commands."
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
    echo "  $0 -f /path/to/AndroidManifest.xml -o /path/to/output/file.adb.commands"
}

# Variable initialization
manifest_file=""
output_file=""
test_value="BashPenDro"

# Command-line argument parsing
while getopts "f:o:h" opt; do
    case $opt in
        f) manifest_file="$OPTARG" ;;
        o) output_file="$OPTARG" ;;
        h) display_help; exit 0 ;;
        *) echo "Invalid argument" >&2; display_help; exit 1 ;;
    esac
done

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

# Retrieving the app package
package=$(xmlstarlet sel -t -v '/manifest/@package' "$manifest_file")

# Create a temporary file
tmp_file=$(mktemp)
trap 'rm -f "$tmp_file"' EXIT

# Looping through each component and outputting adb commands
IFS=$'\n'
for component in $components; do
    # Getting the component type (activity, service, receiver, provider, activity-alias) and its name
    comp_type=$(echo "$component" | cut -d':' -f1)
    comp_name=$(echo "$component" | cut -d':' -f2-)
    
    # Adding the full path to the component
    full_component="$package/$comp_name"
    
    # Retrieving actions for this component
    actions=$(xmlstarlet sel -t -m "//${comp_type}[@android:name='$comp_name']//intent-filter//action" -v '@android:name' -n "$manifest_file")
    # Retrieving schemes for this component
    schemes=$(xmlstarlet sel -t -m "//${comp_type}[@android:name='$comp_name']//intent-filter//data" -v '@android:scheme' -n "$manifest_file")

    if [ -z "$actions" ] && [[ "$comp_type" != "provider" && "$comp_type" != "activity-alias" ]]; then
        # Generate command without actions
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
    else
        for action in $actions; do
            if [ -z "$schemes" ]; then
                scheme_option=""
                case "$comp_type" in
                    activity | activity-alias)
                        echo "adb shell su -c \"am start -n $full_component$scheme_option\"" >> "$tmp_file"
                        ;;
                    service)
                        echo "adb shell su -c \"am startservice -n $full_component$scheme_option\"" >> "$tmp_file"
                        ;;
                    receiver)
                        echo "adb shell su -c \"am broadcast -n $full_component$scheme_option\"" >> "$tmp_file"
                        ;;
                    provider)
                        echo "# Component $comp_name is a provider and cannot be invoked via am start/broadcast." >> "$tmp_file"
                        ;;
                    *)
                        echo "# Unknown component type $comp_type for component $comp_name." >> "$tmp_file"
                        ;;
                esac
            else
                for scheme in $schemes; do
                    scheme_option=" -d $scheme://$test_value"
                    case "$comp_type" in
                        activity | activity-alias)
                            echo "adb shell su -c \"am start -n $full_component$scheme_option\"" >> "$tmp_file"
                            ;;
                        service)
                            echo "adb shell su -c \"am startservice -n $full_component$scheme_option\"" >> "$tmp_file"
                            ;;
                        receiver)
                            echo "adb shell su -c \"am broadcast -n $full_component$scheme_option\"" >> "$tmp_file"
                            ;;
                        provider)
                            echo "# Component $comp_name is a provider and cannot be invoked via am start/broadcast." >> "$tmp_file"
                            ;;
                        *)
                            echo "# Unknown component type $comp_type for component $comp_name." >> "$tmp_file"
                            ;;
                    esac
                done
            fi
        done
    fi
done

# Check the number of components found
component_count=$(wc -l < "$tmp_file")

if [ "$component_count" -gt 0 ]; then
    # Remove duplicates and save to the output file
    sort -u "$tmp_file" > "$output_file"
    echo "Found $component_count exported components. Commands saved to $output_file."
else
    echo "No exported components found."
fi
