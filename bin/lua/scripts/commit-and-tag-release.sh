#!/usr/bin/env bash
#
# Script: commit-and-tag-release.sh
# Purpose: Stages specified release artifact files, commits them with a release message,
#          creates a Git tag for the release version, and pushes the commit and tag
#          to the remote repository (origin). Aims for silent operation on success for git commands.
#
# Usage: ./commit-and-tag-release.sh [--dry-run] <file_to_commit_1> [file_to_commit_2 ...]
#   [--dry-run]            : Optional. If present, simulates actions, printing what would be done
#                            without executing actual Git add, commit, tag, or push operations.
#   <file_to_commit_N>     : Path(s) to file(s) to be staged and committed (e.g., spec.template,
#                            the generated <PKG_NAME>-<FINAL_VERSION>-1.rockspec).
#                            Paths are expected to be relative to the project root (CWD).
#
# Environment Variables Expected (set by caller, e.g., do-release.sh):
#   - FINAL_VERSION          : The semantic version string for the release (e.g., "0.9.0").
#                            Used for the commit message ("Release vX.Y.Z") and tag name ("vX.Y.Z").
#   - CWD is PROJECT_ROOT: Assumes script is run from the project root, which is a Git repository.
#
# Called by: releases/do-release.sh
# Assumptions:
#   - The current working directory is the root of an initialized Git repository.
#   - `git` command is available and configured for the remote 'origin'.
#   - Files specified for commit exist at paths relative to CWD.
#   - The current branch is the one intended for release pushes.
#
set -e

DRY_RUN_ARG=""
# Parse arguments: dry-run is optional first, then list of files.
if [ "$1" = "--dry-run" ]; then
    DRY_RUN_ARG="--dry-run"
    shift # Consume --dry-run argument
fi

# Check for necessary environment variables
if [ -z "$FINAL_VERSION" ]; then
    echo "Error: FINAL_VERSION env var not set." >&2
    exit 1
fi

# Remaining arguments are files to commit.
declare -a FILES_TO_COMMIT_ARGS=()
for arg_file in "$@"; do
    if [ -n "$arg_file" ]; then # Ensure argument is not an empty string
        FILES_TO_COMMIT_ARGS+=("$arg_file")
    fi
done

if [ "${#FILES_TO_COMMIT_ARGS[@]}" -eq 0 ]; then
    echo "Error: No files specified for commit." >&2
    exit 1
fi

# Colors
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'
print_status_stderr() { echo -e "${BLUE}[INFO]${NC} $1" >&2; }
print_warning_stderr() { echo -e "${YELLOW}[WARNING]${NC} $1" >&2; }

if [ -n "$(git status --porcelain)" ]; then
    # This warning means there were pre-existing uncommitted changes OR changes from previous steps
    # that this script is not directly responsible for adding (like spec.template modification).
    # The script will proceed to `git add` the files it *was* explicitly told to add.
    print_warning_stderr "Git working directory has changes. Staging specified files for this release commit..."
fi

print_status_stderr "Adding specified files to git staging area:"
for f in "${FILES_TO_COMMIT_ARGS[@]}"; do
    if [ -z "$f" ]; then # Should be caught by the loop that builds FILES_TO_COMMIT_ARGS
        print_warning_stderr "Skipping empty filename in commit list."
        continue
    fi
    print_status_stderr "  - $f"
    if [ "$DRY_RUN_ARG" != "--dry-run" ]; then git add "$f" >/dev/null; fi
done
echo >&2 # Newline for readability in stderr

COMMIT_MESSAGE="Release v${FINAL_VERSION}"
GIT_TAG="v${FINAL_VERSION}"
CURRENT_BRANCH=$(git branch --show-current)

if [ "$DRY_RUN_ARG" = "--dry-run" ]; then
    print_warning_stderr "DRY RUN: Would commit with message: '$COMMIT_MESSAGE'"
    print_warning_stderr "DRY RUN: Would create tag: '$GIT_TAG'"
    print_warning_stderr "DRY RUN: Would push branch '$CURRENT_BRANCH' and tag '$GIT_TAG'"
else
    if git diff-index --quiet --cached HEAD --; then
        print_status_stderr "No new changes staged for commit by this script. Commit may have already included these changes or files were unchanged."
    else
        print_status_stderr "Committing changes with message: '$COMMIT_MESSAGE'..."
        git commit --quiet -m "$COMMIT_MESSAGE" >/dev/null
    fi

    print_status_stderr "Checking if tag '$GIT_TAG' already exists..."
    if git rev-parse "$GIT_TAG" >/dev/null 2>&1; then
        print_warning_stderr "Tag '$GIT_TAG' already exists. Skipping tag creation."
    else
        print_status_stderr "Creating tag '$GIT_TAG'..."
        git tag "$GIT_TAG" >/dev/null
    fi

    print_status_stderr "Pushing branch '$CURRENT_BRANCH' to origin..."
    git push --no-progress origin "$CURRENT_BRANCH" >/dev/null
    print_status_stderr "Pushing tag '$GIT_TAG' to origin..."
    git push --no-progress origin "$GIT_TAG" >/dev/null

    print_status_stderr "Git commit and tag push complete for v${FINAL_VERSION}."
fi
