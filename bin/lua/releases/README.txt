Release Automation Scripts for Lua Projects

This directory contains a set of scripts to automate the release process for Lua projects,
focusing on LuaRocks and GitHub integration.

--------------------
Main Script: do-release.sh
--------------------

Purpose:
  Orchestrates the entire release lifecycle: version management, rockspec generation,
  Git tagging, LuaRocks publishing, and GitHub release creation.

Common Usage:
  export PKG_NAME="your-package-name" # IMPORTANT: Set this environment variable
  ./releases/do-release.sh [path/to/your.rockspec] --bump <patch|minor|major> [--gh-release <true|false>]

Key Features & Flow:
  1. Setup: Reads PKG_NAME from env. Uses ./releases/spec.template by default or a user-provided .rockspec.
  2. Versioning: Reads initial version. Bumps (patch, minor, major) or uses current version based on flags.
                 Interactive prompt if no versioning flags are given.
  3. Rockspec Generation: Creates a final <PKG_NAME>-<VERSION>-1.rockspec in the project root.
                         Updates package and version fields within the file content.
  4. LuaRocks Pre-flight: Checks if the target version already exists on LuaRocks.
  5. Build Rock: Runs 'luarocks pack' to build the .src.rock (validates spec, output suppressed on success).
  6. Git Integration: Commits the generated rockspec (and updated spec.template if used).
                    Creates and pushes a Git tag (e.g., v1.2.3).
                    (Git command output is minimized on success).
  7. LuaRocks Publishing: Uploads the .rockspec (or .src.rock if --upload-rock specified) to LuaRocks.
                          Attempts to display the LuaRocks module URL.
  8. LuaRocks Verification: Confirms the new version is findable on LuaRocks.
  9. GitHub Release (Optional): If enabled (default) and 'gh' CLI is present, creates a GitHub release
                              for the tag, uploads .rockspec and .src.rock as assets, and generates release notes.
                              Use --gh-release false to disable.
 10. Cleanup: Removes the generated .src.rock if the .rockspec was uploaded.

Key Command-line Flags for do-release.sh:
  [path/to/your.rockspec] : Optional. Use this .rockspec as the version source and generation base.
  --bump <type>             : Bump version by patch, minor, or major.
  --use-version-file        : Use version from source spec/template as is (no bump/prompt).
  --dry-run                 : Simulate most operations.
  --upload-rock             : Upload .src.rock to LuaRocks instead of .rockspec.
  --gh-release <true|false> : Enable/disable GitHub release creation (default: true).

Important:
  - Always set the PKG_NAME environment variable before running do-release.sh.
  - Ensure 'git', 'luarocks', and (if used) 'gh' CLIs are installed and in your PATH.
  - Scripts are designed to be run from the project root.

Sub-scripts (in ./releases/scripts/):
  These are helper scripts called by do-release.sh. Their individual comments provide more detail.
  - manage-version.sh: Handles version calculation (interactive/flag-based).
  - read-version-from-spec.sh: Extracts X.Y.Z version from a spec file.
  - update-spec-version.sh: Updates version in spec.template.
  - gen-rockspecs.sh: Generates the final .rockspec file with correct content.
  - build-rocks.sh: Packs the .src.rock, conditionally showing output.
  - commit-and-tag-release.sh: Handles Git operations (add, commit, tag, push).
  - publish-to-luarocks.sh: Manages LuaRocks upload and API key.
  - luarocks-check-version-published.sh: Checks if a version exists on LuaRocks.
  - create-gh-release.sh: Creates GitHub releases using 'gh' CLI.
  (read-pkg-name.sh exists but is not currently used by do-release.sh).