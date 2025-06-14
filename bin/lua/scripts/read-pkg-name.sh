#!/usr/bin/env bash
#
# Script: read-pkg-name.sh
# Purpose: Reads the package name directly from a given rockspec or spec.template file.
#          It extracts the value from the 'package = "..."' line.
#          Outputs the extracted package name string to stdout.
# Note:    This script is NOT CURRENTLY USED by the main 'do-release.sh' orchestrator,
#          which now expects PKG_NAME to be set as an environment variable.
#          This script could be useful for other utilities or if direct reading from a file is needed.
#
# Usage: ./read-pkg-name.sh <spec_file_abs_path>
#   <spec_file_abs_path> : Absolute path to the rockspec or spec.template file.
#
# Output:
#   - To stdout: The extracted package name
#   - To stderr: Error messages if the file is not found or the package name cannot be parsed.
#
# Assumptions:
#   - The spec file at <spec_file_abs_path> exists and is readable.
#   - The file contains a line like: package = "actual_package_name" (or with single quotes).
#
set -e

SPEC_TEMPLATE_PATH_ARG=$1

# Minimal colors for potential error messages if called directly
RED='\033[0;31m'
NC='\033[0m'

if [ -z "$SPEC_TEMPLATE_PATH_ARG" ]; then
    echo -e "${RED}[ERROR]${NC} Spec template path argument not provided." >&2
    exit 1
fi
if [ ! -f "$SPEC_TEMPLATE_PATH_ARG" ]; then
    echo -e "${RED}[ERROR]${NC} Spec template not found at [$SPEC_TEMPLATE_PATH_ARG]" >&2
    exit 1
fi

# Find the line with 'package =' and extract the value between quotes (single or double)
PKG_NAME_VALUE=$(grep -E 'package\s*=' "$SPEC_TEMPLATE_PATH_ARG" | awk -F"['\"]" '{print $2}')

if [ -z "$PKG_NAME_VALUE" ]; then
    echo -e "${RED}[ERROR]${NC} Could not find or parse package name from $SPEC_TEMPLATE_PATH_ARG" >&2
    echo -e "${RED}[INFO]${NC} Ensure the file contains a line like 'package = "your_pkg_name"' or 'package = \'your_pkg_name\''" >&2
    exit 1
fi

# Defensive check in case the placeholder was read (though spec.template should have actual name now).
if [ "$PKG_NAME_VALUE" = "@@PACKAGE_NAME@@" ]; then
    echo -e "${RED}[ERROR]${NC} Package name in $SPEC_TEMPLATE_PATH_ARG is still the placeholder '@@PACKAGE_NAME@@'. It should be a defined name." >&2
    exit 1
fi

echo "$PKG_NAME_VALUE"
