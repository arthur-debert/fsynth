#!/usr/bin/env bash
#
# Script: luarocks-check-version-published.sh
# Purpose: Checks if a specific package version (with -1 rockspec revision) is listed as a rockspec on LuaRocks.
#
# Usage: ./luarocks-check-version-published.sh <package_name> <semantic_version>
#   <package_name>      : The name of the package (e.g., "lual").
#   <semantic_version>  : The semantic version X.Y.Z (e.g., "0.8.22").
#
# Output:
#   Exits with 0 if the version <semantic_version>-1 (rockspec) is found.
#   Exits with 1 if the version is not found.
#   Prints no output to stdout or stderr on its own, designed for scripting.

set -e # Exit on error, though grep -q handles specific search failure.

PACKAGE_NAME_ARG=$1
SEMANTIC_VERSION_ARG=$2

if [ -z "$PACKAGE_NAME_ARG" ] || [ -z "$SEMANTIC_VERSION_ARG" ]; then
    # This error should go to stderr if script is called incorrectly.
    echo "Usage: $0 <package_name> <semantic_version>" >&2
    exit 2 # Different exit code for bad usage
fi

# Assume rockspec revision is always "1" for published rocks we are checking against.
VERSION_REVISION_TO_CHECK="${SEMANTIC_VERSION_ARG}-1"

# Perform the search and store the output
SEARCH_OUTPUT=$(luarocks search "$PACKAGE_NAME_ARG" 2>/dev/null)

# First verify we're looking at the right package section
if ! echo "$SEARCH_OUTPUT" | grep -q "^$PACKAGE_NAME_ARG$"; then
    # Package not found at all
    exit 1
fi

# Look for the version pattern matching the exact format in LuaRocks output within the package section
# We need to check that this version belongs to our package and not some other package with similar name
PACKAGE_SECTION=$(echo "$SEARCH_OUTPUT" | sed -n "/^$PACKAGE_NAME_ARG$/,/^$/p")

# Now check if the version exists in the package section
if echo "$PACKAGE_SECTION" | grep -qE "^[[:space:]]+${VERSION_REVISION_TO_CHECK}[[:space:]]+\(rockspec\)"; then
    exit 0 # Found
else
    exit 1 # Not found
fi
