#!/bin/bash

# Source this script to set up the Lua environment for fsynth
# Usage: source ./bin/luapath.sh

# Get the absolute path to the project root
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script should be sourced, not executed directly."
    echo "Usage: source ./bin/luapath.sh"
    exit 1
fi

# Get the directory where the script is located

# Check if luarocks is installed
if ! command -v luarocks &>/dev/null; then
    echo "luarocks command could not be found. Please ensure it's installed and in your PATH."
    return 1
fi

# 1. Configure LuaRocks to use the local tree and export paths
eval $("$(which luarocks)" --tree "${PROJECT_ROOT}/.luarocks" path)

# 2. Prepend project's directory to LUA_PATH
export LUA_PATH="${PROJECT_ROOT}/?.lua;${PROJECT_ROOT}/${LIB_NAME}/?.lua;${PROJECT_ROOT}/${LIB_NAME}/?/init.lua;$LUA_PATH"

# 3. Add spec directory to LUA_PATH for testing
export LUA_PATH="${PROJECT_ROOT}/spec/?.lua;$LUA_PATH"

# Export the project root for use in other scripts
export FSYNTH_ROOT="${PROJECT_ROOT}"

# Add .luarocks/bin to PATH
export PATH="${PROJECT_ROOT}/.luarocks/bin:$PATH"

# Define a function to run busted tests
run_busted() {
    if command -v busted &>/dev/null; then
        echo "Running tests using global busted installation..."
        busted "$@"
    else
        echo "Error: busted could not be found. Please install it using luarocks."
        return 1
    fi
}

echo "Lua environment for fsynth is now set up:"
echo "- LUA_PATH: $LUA_PATH"
echo "- LUA_CPATH: $LUA_CPATH"
echo "- Local busted is available via the 'run_busted' function"
echo "- Run 'run_busted spec/' to run all tests"
