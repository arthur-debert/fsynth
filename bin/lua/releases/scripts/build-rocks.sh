#!/usr/bin/env bash
#
# Script: build-rocks.sh
# Purpose: Packs one or more rockspec files into .rock (source rock) files using `luarocks pack`.
#          This step also serves as a validation that the rockspec is buildable.
#          The script aims to be silent on success, but if `luarocks pack` fails,
#          it will display the full output from `luarocks pack` for diagnostics.
#          Outputs a space-separated list of successfully packed .src.rock filenames to stdout.
#
# Usage: ./build-rocks.sh <rockspec_file1> [rockspec_file2 ...]
#   <rockspec_fileN> : Filename(s) of the rockspec(s) to pack (expected to be in CWD).
#
# Environment Variables Expected (set by caller, e.g., do-release.sh):
#   - PKG_NAME          : The definitive package name (e.g., "lual"). Used to predict the output .src.rock filename.
#   - FINAL_VERSION     : The definitive semantic version (X.Y.Z, e.g., "0.9.0"). Used to predict output filename.
#   - CWD should be PROJECT_ROOT, where rockspec files are located and .rock files will be created.
#
# Called by: releases/do-release.sh
# Assumptions:
#   - `luarocks` command is available.
#   - Rockspec files passed as arguments exist in the Current Working Directory.
#   - The output .src.rock filename will follow the pattern: ${PKG_NAME}-${FINAL_VERSION}-1.src.rock
#     (assumes a rockspec revision of 1 for the packed rock).
#
set -e

# Assumes CWD is the project root where rockspec files are located.

# Colors (optional, for stderr messages if any)
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'
print_status_stderr() { echo -e "${BLUE}[INFO]${NC} $1" >&2; }
print_error_stderr() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

if [ -z "$PKG_NAME" ] || [ -z "$FINAL_VERSION" ]; then
    print_error_stderr "PKG_NAME and FINAL_VERSION environment variables must be set."
fi

ROCKSPEC_REVISION="1" # Assuming rockspec revision is always 1 for packed rocks

PACKED_ROCK_FILENAMES=()

for rockspec_file_arg in "$@"; do
    if [ -z "$rockspec_file_arg" ]; then
        print_error_stderr "Empty rockspec file argument provided."
    fi
    if [ ! -f "$rockspec_file_arg" ]; then
        print_error_stderr "Rockspec file not found: $rockspec_file_arg (CWD: $(pwd))"
    fi

    print_status_stderr "Packing ${rockspec_file_arg}..."

    # Predict the output filename
    # This assumes the rockspec file itself might have a different name pattern than the final rock,
    # but the final .src.rock will follow PKG_NAME-FINAL_VERSION-ROCKSPEC_REVISION.src.rock
    PREDICTED_PACKED_ROCK_NAME="${PKG_NAME}-${FINAL_VERSION}-${ROCKSPEC_REVISION}.src.rock"

    # Create a temporary file to capture all output from luarocks pack
    TMP_OUTPUT_FILE=$(mktemp)
    # Ensure TMP_OUTPUT_FILE is removed on script exit, in any case (success, error, interrupt)
    trap 'rm -f "$TMP_OUTPUT_FILE"' EXIT

    PACK_EXIT_CODE=0
    # Run luarocks pack, redirecting all its output (stdout & stderr) to the temporary file
    if ! luarocks pack "$rockspec_file_arg" >"$TMP_OUTPUT_FILE" 2>&1; then
        PACK_EXIT_CODE=$? # Capture the actual exit code
    fi

    if [ $PACK_EXIT_CODE -ne 0 ]; then
        print_error_stderr "'luarocks pack ${rockspec_file_arg}' failed with exit code $PACK_EXIT_CODE."
        if [ -s "$TMP_OUTPUT_FILE" ]; then # Check if file is not empty
            echo -e "${RED}--- Output from 'luarocks pack' ---${NC}" >&2
            cat "$TMP_OUTPUT_FILE" >&2
            echo -e "${RED}----------------------------------${NC}" >&2
        fi
        # Error already printed by print_error_stderr, which also exits
        # Trap will clean up TMP_OUTPUT_FILE
        exit $PACK_EXIT_CODE # Ensure we exit with the pack exit code
    fi

    # If successful, TMP_OUTPUT_FILE can be removed by the trap on normal exit.
    # We don't need its contents if pack succeeded.

    # Check if the predicted file was created
    if [ -f "$PREDICTED_PACKED_ROCK_NAME" ]; then
        print_status_stderr "  Packed rock verified: $PREDICTED_PACKED_ROCK_NAME"
        PACKED_ROCK_FILENAMES+=("$PREDICTED_PACKED_ROCK_NAME")
    else
        # This might happen if luarocks pack failed silently or conventions changed
        # Or if the rockspec_file_arg was for an 'extras' package with a different PKG_NAME
        # For now, we assume PKG_NAME and FINAL_VERSION apply to all rockspecs passed.
        print_error_stderr "Packed rock file $PREDICTED_PACKED_ROCK_NAME not found after packing $rockspec_file_arg. Build failed or filename convention mismatch."
    fi
done

if [ ${#PACKED_ROCK_FILENAMES[@]} -eq 0 ]; then
    print_error_stderr "No rock files were successfully packed."
fi

echo "${PACKED_ROCK_FILENAMES[@]}" # Print the list of packed rock filenames to stdout
