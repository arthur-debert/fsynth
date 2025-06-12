#!/usr/bin/env bash
#
# Script: read-version-from-spec.sh
# Purpose: Reads and extracts the semantic version (X.Y.Z format) from a specified
#          rockspec or spec.template file. It specifically targets the 'version = "..."' line
#          and isolates the X.Y.Z part, ignoring any rockspec revision (-R).
#          Outputs the extracted semantic version string (e.g., "1.2.3") to stdout.
#
# Usage: ./read-version-from-spec.sh <spec_file_abs_path>
#   <spec_file_abs_path> : Absolute path to the rockspec or spec.template file.
#
# Output:
#   - To stdout: The extracted semantic version string (X.Y.Z).
#   - To stderr: Error messages if file not found or version cannot be parsed.
#
# Called by: releases/do-release.sh (to get the INITIAL_SEMANTIC_VERSION).
# Assumptions:
#   - The spec file at <spec_file_abs_path> exists and is readable.
#   - The file contains a line like: version = "X.Y.Z-R" or version = "X.Y.Z".
#
set -e

SPEC_FILE_PATH_ARG=$1

# Minimal colors for potential error messages if called directly
RED='\033[0;31m'
NC='\033[0m'

if [ -z "$SPEC_FILE_PATH_ARG" ]; then
    echo -e "${RED}[ERROR]${NC} Spec file path argument not provided." >&2
    exit 1
fi
if [ ! -f "$SPEC_FILE_PATH_ARG" ]; then
    echo -e "${RED}[ERROR]${NC} Spec file not found at [$SPEC_FILE_PATH_ARG]" >&2
    exit 1
fi

# Read version line from spec file
# Example line: version = "0.8.10-1"
VERSION_LINE=$(grep -E '^[[:space:]]*version[[:space:]]*=[[:space:]]*"[0-9]+\.[0-9]+\.[0-9]+-[0-9]+"' "$SPEC_FILE_PATH_ARG")
if [ -z "$VERSION_LINE" ]; then
    # Try to match if rockspec revision is missing, e.g. version = "1.0.0"
    VERSION_LINE=$(grep -E '^[[:space:]]*version[[:space:]]*=[[:space:]]*"[0-9]+\.[0-9]+\.[0-9]+"' "$SPEC_FILE_PATH_ARG")
    if [ -z "$VERSION_LINE" ]; then
        echo -e "${RED}[ERROR]${NC} Could not find valid version line (e.g., version = \"X.Y.Z-R\" or version = \"X.Y.Z\") in $SPEC_FILE_PATH_ARG" >&2
        exit 1
    fi
fi

# Extract the full version string like "0.8.10-1" or "0.8.10"
FULL_VERSION_STRING=$(echo "$VERSION_LINE" | sed -E 's/^[[:space:]]*version[[:space:]]*=[[:space:]]*"([0-9]+\.[0-9]+\.[0-9]+(-[0-9]+)?)".*$/\1/')

# Extract semantic version (X.Y.Z)
SEMANTIC_VERSION=$(echo "$FULL_VERSION_STRING" | sed -E 's/([0-9]+\.[0-9]+\.[0-9]+).*$/\1/')

if [ -z "$SEMANTIC_VERSION" ]; then
    echo -e "${RED}[ERROR]${NC} Could not parse semantic version from '$FULL_VERSION_STRING' in $SPEC_FILE_PATH_ARG" >&2
    exit 1
fi

echo "$SEMANTIC_VERSION"
