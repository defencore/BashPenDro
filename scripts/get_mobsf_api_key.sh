#!/bin/bash

# Function to display help manual
display_help() {
    echo "Usage: $0 -c <config_file>"
    echo
    echo "Options:"
    echo "  -c <config_file>  Specify the path to the mobsf.config file."
    echo "  -h                Display this help message."
    echo
    echo "Description:"
    echo "This script logs in to the MobSF instance, retrieves the API Key,"
    echo "and updates the mobsf.config file with the new API Key."
    echo
    echo "The config file should contain the following entries:"
    echo "  mobsfhost=<host:port>"
    echo "  username=<username>"
    echo "  password=<password>"
    echo "  API_KEY=<existing_api_key_or_blank>"
    exit 1
}

# Default config file path
config_file="mobsf.config"

# Parse command-line options
while getopts ":c:h" opt; do
    case $opt in
        c)
            config_file="$OPTARG"
            ;;
        h)
            display_help
            ;;
        \?)
            echo "Error: Invalid option -$OPTARG" >&2
            display_help
            ;;
        :)
            echo "Error: Option -$OPTARG requires an argument." >&2
            display_help
            ;;
    esac
done

# Check if config file exists
if [ ! -f "$config_file" ]; then
    echo "Error: Config file not found: $config_file"
    display_help
    exit 1
fi

# Extract mobsfhost, username, and password from the config file
mobsfhost=$(grep 'mobsfhost=' "$config_file" | cut -d '=' -f2)
username=$(grep 'username=' "$config_file" | cut -d '=' -f2)
password=$(grep 'password=' "$config_file" | cut -d '=' -f2)

# Get CSRF token
csrf_token=$(curl -s http://$mobsfhost/login/ | grep 'csrfmiddlewaretoken' | sed 's/.*value="\([^"]*\)".*/\1/')

# Perform POST request to login and store cookies in a variable
cookies=$(curl -s -X POST http://$mobsfhost/login/ \
-H "Content-Type: application/x-www-form-urlencoded" \
--data "csrfmiddlewaretoken=$csrf_token&username=$username&password=$password" \
-D - | grep 'Set-Cookie' | sed 's/Set-Cookie: \([^;]*\).*/\1/' | tr '\n' ';')

# Retrieve API Key
api_key=$(curl -s -X GET http://$mobsfhost/api_docs -H "Cookie: $cookies" | grep "API Key:" | sed -E 's/.*API Key: <strong><code>([^<]+)<\/code><\/strong>.*/\1/')

# Update API_KEY in the config file
if [ -n "$api_key" ]; then
    # Remove the old API_KEY entry and add the new one
    sed -i '' "s/^API_KEY=.*/API_KEY=$api_key/" "$config_file"
    echo "API Key updated in $config_file"
else
    echo "Failed to retrieve API Key"
fi
