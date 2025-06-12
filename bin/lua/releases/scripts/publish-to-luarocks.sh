#!/usr/bin/env bash
#
# Script: publish-to-luarocks.sh
# Purpose: Uploads one or more specified rockspec or .src.rock files to LuaRocks.
#          It handles LuaRocks API key logic, checking the LUAROCKS_API_KEY environment variable first,
#          then interactively prompting the user if the key is not found (unless in dry-run mode).
#          On successful upload of a file, it attempts to extract the LuaRocks module URL from the
#          `luarocks upload` command's output and prints this URL to stdout.
#          Other informational messages and prompts are printed to stderr.
#          The full output from `luarocks upload` is only shown (to stderr) if the upload command fails.
#
# Usage: ./publish-to-luarocks.sh [--dry-run] <file_to_upload_1> [file_to_upload_2 ...]
#   [--dry-run]         : Optional. If present, simulates upload actions and API key checks.
#   <file_to_upload_N>  : Filename(s) of the .rockspec or .src.rock file(s) to upload.
#                         Files are expected to be in the Current Working Directory.
#
# Output:
#   - To stdout: The LuaRocks URL of the successfully published module (if extractable, one URL per file if multiple are uploaded and successful).
#   - To stderr: Status messages, warnings, prompts for API key, and error details.
#
# Environment Variables Expected:
#   - LUAROCKS_API_KEY (optional): If set, this API key is used for authentication with LuaRocks,
#                                  bypassing the interactive prompt.
#   - CWD is PROJECT_ROOT : Assumes script is run from the project root where files to upload are located.
#
# Called by: releases/do-release.sh
# Assumptions:
#   - `luarocks` command is available.
#   - Files passed as arguments exist in the Current Working Directory.
#
set -e

# Publishes rockspec files to LuaRocks.
# Assumes CWD is the project root where rockspec files are located.

# Colors
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'
print_status_stderr() { echo -e "${BLUE}[INFO]${NC} $1" >&2; }
print_warning_stderr() { echo -e "${YELLOW}[WARNING]${NC} $1" >&2; }
print_error_stderr() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

DRY_RUN_ARG=""
declare -a rockspecs_to_publish=()

if [ "$1" = "--dry-run" ]; then
    DRY_RUN_ARG="--dry-run"
    shift # Consume --dry-run
fi

# All remaining arguments are rockspec files
for arg in "$@"; do
    if [ -n "$arg" ]; then # Ensure argument is not an empty string
        rockspecs_to_publish+=("$arg")
    fi
done

if [ "${#rockspecs_to_publish[@]}" -eq 0 ]; then
    print_error_stderr "Error: No valid rockspec files were provided for publishing."
fi

for rockspec_file in "${rockspecs_to_publish[@]}"; do
    if [ ! -f "$rockspec_file" ]; then
        print_error_stderr "Rockspec file not found: $rockspec_file (CWD: $(pwd))"
    fi

    print_status_stderr "Preparing to publish ${rockspec_file} to LuaRocks..."

    # Determine API key (scoped per rockspec in case of interactive prompt)
    CURRENT_LUAROCKS_API_KEY=""
    if [ -z "$LUAROCKS_API_KEY" ]; then # Check environment variable
        print_warning_stderr "LUAROCKS_API_KEY environment variable not set for $rockspec_file."
        if [ "$DRY_RUN_ARG" != "--dry-run" ]; then
            read -p "Enter your LuaRocks API key for $rockspec_file (or press Enter to skip this file): " -s API_KEY_INPUT >&2
            echo >&2 # Newline after secret input
            if [ -z "$API_KEY_INPUT" ]; then
                print_warning_stderr "Skipping $rockspec_file due to no API key provided."
                continue # Skip to the next rockspec file
            fi
            CURRENT_LUAROCKS_API_KEY="$API_KEY_INPUT"
        else
            print_warning_stderr "DRY RUN: Would need LUAROCKS_API_KEY for $rockspec_file."
        fi
    else
        CURRENT_LUAROCKS_API_KEY="$LUAROCKS_API_KEY"
    fi

    if [ "$DRY_RUN_ARG" = "--dry-run" ]; then
        print_warning_stderr "DRY RUN: Would upload: luarocks upload $rockspec_file --api-key=***"
    else
        if [ -z "$CURRENT_LUAROCKS_API_KEY" ]; then
            print_warning_stderr "No API key available for $rockspec_file. Skipping upload."
            continue
        fi
        print_status_stderr "Uploading $rockspec_file to LuaRocks..."

        # Capture output of luarocks upload
        UPLOAD_OUTPUT=$(luarocks upload "$rockspec_file" --api-key="$CURRENT_LUAROCKS_API_KEY" 2>&1) # Capture both stdout and stderr from luarocks
        UPLOAD_EXIT_CODE=$?

        # Echo the captured output to stderr only if upload failed
        if [ $UPLOAD_EXIT_CODE -ne 0 ]; then
            echo "--- LuaRocks Upload Output (Error) ---" >&2
            echo "$UPLOAD_OUTPUT" >&2
            echo "--------------------------------------" >&2
        fi

        if [ $UPLOAD_EXIT_CODE -eq 0 ]; then
            print_status_stderr "Successfully published $rockspec_file to LuaRocks!"
            # Extract and print URL to stdout
            # Look for lines like "Done: <url>" or "Uploaded: <url>" or "Module available at: <url>"
            # Common pattern is a line ending with the module URL.
            # Grep for http/https and output only the matching line, then sed to clean it up.
            # Prioritize lines starting with "Done: ", "Uploaded: ", "Module available at: "
            LUAROCKS_URL=$(echo "$UPLOAD_OUTPUT" | grep -Eo '(Done: |Uploaded: |Module available at: |https://luarocks.org/modules/)[^[:space:]]+' | sed -E 's/^(Done: |Uploaded: |Module available at: )//' | head -n 1)

            if [ -n "$LUAROCKS_URL" ]; then
                echo "$LUAROCKS_URL" # Print only the URL to stdout
            else
                # Fallback: if specific prefixes not found, look for any line containing the typical base URL structure. This is less precise.
                FALLBACK_URL=$(echo "$UPLOAD_OUTPUT" | grep -Eo 'https://luarocks.org/modules/[^/]+/[^/]+[^[:space:]]*' | head -n 1)
                if [ -n "$FALLBACK_URL" ]; then
                    echo "$FALLBACK_URL" # Print only the URL to stdout
                else
                    print_warning_stderr "Could not extract LuaRocks URL from upload output for $rockspec_file."
                fi
            fi
        else
            print_error_stderr "Failed to publish $rockspec_file to LuaRocks. See errors above. (Exit code: $UPLOAD_EXIT_CODE)"
        fi
    fi
done
