#!/usr/bin/env bash
#
# Script: update-spec-version.sh
# Purpose: Updates the version string in a given .spec, .rockspec, or spec.template file.
#          It reads the existing rockspec revision (e.g., the "-1" in "X.Y.Z-1") from the file
#          and preserves it, only changing the X.Y.Z part to the new semantic version provided.
#          If no rockspec revision is found, it defaults to using "-1".
#          The update is done in-place using `sed`.
#
# Usage: ./update-spec-version.sh <spec_file_abs_path> <new_semantic_version>
#   <spec_file_abs_path>    : Absolute path to the .spec or .rockspec file to update (e.g., releases/spec.template).
#   <new_semantic_version>  : The new semantic version (X.Y.Z format, e.g., "1.2.4") to set.
#
# Output:
#   - To stderr: Status messages about the update process or if no update was needed.
#                Error messages if inputs are invalid or file operations fail.
#   - Modifies the specified file in place.
#
# Called by: releases/do-release.sh (conditionally, to update spec.template if its version is bumped).
# Assumptions:
#   - The spec file exists and is writable.
#   - It contains a version line like: version = "X.Y.Z-R" or version = "X.Y.Z".
#
set -e

SPEC_FILE_TO_UPDATE=$1
NEW_SEMANTIC_VERSION_ARG=$2

RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'
print_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}
print_status_stderr() { echo -e "${BLUE}[INFO]${NC} $1" >&2; }

if [ -z "$SPEC_FILE_TO_UPDATE" ]; then print_error "Spec file path to update not provided."; fi
if [ ! -f "$SPEC_FILE_TO_UPDATE" ]; then print_error "Spec file to update not found at [$SPEC_FILE_TO_UPDATE]"; fi
if [ -z "$NEW_SEMANTIC_VERSION_ARG" ]; then print_error "New semantic version argument not provided."; fi
if ! echo "$NEW_SEMANTIC_VERSION_ARG" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    print_error "New semantic version '$NEW_SEMANTIC_VERSION_ARG' must be X.Y.Z format."
fi

# Find the current version line to get the existing full version string (including rockspec revision)
VERSION_LINE=$(grep -E '^[[:space:]]*version[[:space:]]*=[[:space:]]*"[0-9]+\.[0-9]+\.[0-9]+(-[0-9]+)?"' "$SPEC_FILE_TO_UPDATE")
if [ -z "$VERSION_LINE" ]; then print_error "Could not find version line in $SPEC_FILE_TO_UPDATE to update."; fi

OLD_FULL_VERSION_STRING=$(echo "$VERSION_LINE" | sed -E 's/^[[:space:]]*version[[:space:]]*=[[:space:]]*"([0-9]+\.[0-9]+\.[0-9]+(-[0-9]+)?)".*$/\1/')
ROCKSPEC_REVISION_PART=$(echo "$OLD_FULL_VERSION_STRING" | sed -E 's/[0-9]+\.[0-9]+\.[0-9]+(-[0-9]+)?/\1/')
if [ -z "$ROCKSPEC_REVISION_PART" ]; then ROCKSPEC_REVISION_PART="-1"; fi # Default to -1 if not present

NEW_FULL_VERSION_STRING="${NEW_SEMANTIC_VERSION_ARG}${ROCKSPEC_REVISION_PART}"

if [ "$OLD_FULL_VERSION_STRING" = "$NEW_FULL_VERSION_STRING" ]; then
    print_status_stderr "Version in $SPEC_FILE_TO_UPDATE is already $NEW_FULL_VERSION_STRING. No update needed."
else
    print_status_stderr "Updating version in $SPEC_FILE_TO_UPDATE from '$OLD_FULL_VERSION_STRING' to '$NEW_FULL_VERSION_STRING'..."
    sed -i.bak "s|version = \"${OLD_FULL_VERSION_STRING}\"|version = \"${NEW_FULL_VERSION_STRING}\"|g" "$SPEC_FILE_TO_UPDATE"
    rm -f "${SPEC_FILE_TO_UPDATE}.bak"
    print_status_stderr "Successfully updated version in $SPEC_FILE_TO_UPDATE."
fi
