# Lua Project Setup: Isolated Dependencies with LuaRocks

This guide details how to manage Lua project dependencies in an isolated manner
using LuaRocks. This approach keeps your project's libraries separate from other
projects and your system-wide LuaRocks installation, while still sharing the
main Lua runtime. This leads to more reproducible builds and avoids version
conflicts.

## Assumed Project Structure

We'll assume the following project structure:

```
my_lua_project/  
├── .luarocks/         # Local, isolated LuaRocks tree for dependencies  
├── fsynth-0.1.0-1.rockspec   # Rockspec file defining dependencies
├── bin/               # Directory for utility scripts
│   ├── luapath.sh     # Script to set up the Lua environment
│   └── run-tests      # Script to run tests with the correct environment
└── spec/              # Test specifications
```

## Prerequisites

- Lua: Ensure Lua is installed on your system.
- LuaRocks: Ensure LuaRocks, the Lua package manager, is installed.

## Step 1: Initial Project Setup and Local Rocktree

1. Create Project Directories:  
   Navigate to where you want to create your project and set up the basic
   structure:  
   ```bash
   mkdir my_lua_project  
   cd my_lua_project  
   mkdir spec
   mkdir bin
   touch myproject.rockspec  # We'll edit this in the next step
   ```

2. Create the Local Rocktree:  
   This directory will store all dependencies specific to this project.  
   ```bash
   mkdir .luarocks
   ```

   Using .luarocks makes it a hidden directory by convention.

## Step 2: Defining Dependencies with a Rockspec

A rockspec file (.rockspec) describes a Lua package (a "rock"). Even if you're
not publishing your project as a rock, a rockspec is an excellent way to declare
its dependencies.

Create or edit myproject.rockspec in your project root:

```lua
-- myproject.rockspec

package = "myproject"  
version = "0.1.0-1"  -- Use "dev-1" or similar if it's just for tracking deps

source = {  
   -- For local development, a placeholder URL is fine
   url = "."
}

description = {  
   summary = "My Awesome Lua Project using isolated dependencies.",  
   detailed = [[
      This project demonstrates how to set up an isolated LuaRocks  
      environment for managing dependencies.  
   ]],  
   homepage = "https://your_project_homepage.com",  -- Optional  
   license = "MIT"  -- Or your chosen license  
}

-- Define your project's dependencies here  
dependencies = {  
   "lua >= 5.1",  -- Specify Lua version compatibility  
   "penlight >= 1.5.0",  -- Example: Penlight library
   "log.lua >= 0.1.0",   -- Example: Logging library
}

-- For test dependencies
test_dependencies = {
   "busted >= 2.0.0"  -- Testing framework
}

-- Build instructions  
build = {  
   type = "builtin",  -- Common type for Lua modules  
   modules = {  
      -- Example: if you have my_lua_project/myproject/core.lua  
      ["myproject.core"] = "myproject/core.lua",
      -- Add all your modules here
   }  
}
```

Key part: The dependencies table lists all external Lua libraries your project
needs, while test_dependencies lists libraries needed only for testing.

## Step 3: Installing Dependencies into the Local Tree

With your .luarocks directory and rockspec ready, you can install the
defined dependencies.

1. From the Rockspec:

   - Installing the dependencies listed in the rockspec:  
     ```bash
     luarocks --tree ./.luarocks install --only-deps rockspec_file.rockspec
     ```

   - Installing the project itself along with its dependencies (useful during development):  
     ```bash
     luarocks --tree ./.luarocks make rockspec_file.rockspec
     ```

   The `--tree ./.luarocks` flag tells LuaRocks to use your project-local directory
   for installation, keeping dependencies isolated from the system-wide installation.

2. Installing Individual Rocks (Ad-hoc):  
   If you need to add a dependency not yet in your rockspec:  
   ```bash
   luarocks --tree ./.luarocks install <rockname>
   ```

   Example:  
   ```bash
   luarocks --tree ./.luarocks install penlight
   ```

   Remember to add it to your rockspec file later for reproducibility.

## Step 4: Configuring the Lua Environment (LUA_PATH and LUA_CPATH)

For Lua to find your project's own modules and the dependencies in
.luarocks/, you need to correctly set the LUA_PATH and LUA_CPATH
environment variables.

The recommended way is to create a helper script in your bin directory.
Here's an example of what that script should do:

1. Generate Paths from Local Rocktree:  
   LuaRocks can tell you the paths needed for your local tree:  
   ```bash
   eval $(luarocks --tree ./.luarocks path)
   ```

   This command executes the output of luarocks path, which exports
   LUA_PATH and LUA_CPATH pointing to your ./.luarocks tree.

2. Add Your Project's Main Directories:  
   You also need to tell Lua where to find your project's own modules:
   
   ```bash
   # Prepend your project's module directories to LUA_PATH
   export LUA_PATH="$(pwd)/?.lua;$(pwd)/your_module/?.lua;$(pwd)/your_module/?/init.lua;$LUA_PATH"
   
   # Add the spec directory for testing
   export LUA_PATH="$(pwd)/spec/?.lua;$LUA_PATH"
   
   # Add .luarocks/bin to PATH for tools installed by LuaRocks
   export PATH="$(pwd)/.luarocks/bin:$PATH"
   ```

Path Order Importance:  
The resulting search order for require() will be roughly:

1. Your project's main module directories.
2. Your project's spec directory (if added).
3. Your project's local .luarocks/ tree.
4. System-wide Lua/LuaRocks paths.

## Step 5: Running Your Project and Tests

Once the environment variables LUA_PATH and LUA_CPATH are correctly set (as per
Step 4), you can run your application and tests.

1. Running Your Main Application File:  
   Assuming main.lua is in your project root:  
   ```bash
   # Ensure environment is set up first!
   source ./bin/luapath.sh
   lua main.lua
   ```

2. Running Busted Tests:

   - Add busted to your rockspec's test_dependencies.
   - Install it with:  
     ```bash
     luarocks --tree ./.luarocks install --only-deps rockspec_file.rockspec
     ```
   - Run tests using the helper script:
     ```bash
     ./bin/run-tests
     ```
     
   - Or manually:
     ```bash
     # First source the environment setup
     source ./bin/luapath.sh
     
     # Then run busted (using the function defined in luapath.sh)
     run_busted
     ```

## Step 6: Helper Scripts for Environment Setup

To avoid manually setting environment variables every time, create helper scripts
in your project's bin directory.

### Environment Setup Script (bin/luapath.sh)

```bash
#!/bin/bash

# Source this script to set up the Lua environment for your project
# Usage: source ./bin/luapath.sh

# Get the absolute path to the project root
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script should be sourced, not executed directly."
    echo "Usage: source ./bin/luapath.sh"
    exit 1
fi

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "${SCRIPT_DIR}/.." && pwd )"
PACKAGE_NAME="your_package_name"

# Check if luarocks is installed
if ! command -v luarocks &>/dev/null; then
    echo "luarocks command could not be found. Please ensure it's installed"
    echo "and in your PATH."
    return 1
fi

# Configure LuaRocks to use the local tree and export paths
eval $("$(which luarocks)" --tree "${PROJECT_ROOT}/.luarocks" path)

# Prepend project's module directories to LUA_PATH
export LUA_PATH="${PROJECT_ROOT}/?.lua;${PROJECT_ROOT}/${PACKAGE_NAME}/?.lua;${PROJECT_ROOT}/${PACKAGE_NAME}/?/init.lua;$LUA_PATH"

# Add spec directory to LUA_PATH for testing
export LUA_PATH="${PROJECT_ROOT}/spec/?.lua;$LUA_PATH"

# Add .luarocks/bin to PATH
export PATH="${PROJECT_ROOT}/.luarocks/bin:$PATH"

# Define a function to run busted tests
run_busted() {
    local busted_path="${PROJECT_ROOT}/.luarocks/bin/busted"
    if [ -x "$busted_path" ]; then
        echo "Running tests using local busted installation..."
        "${busted_path}" "$@"
    elif command -v busted &>/dev/null; then
        echo "Running tests using global busted installation..."
        busted "$@"
    else
        echo "Error: busted could not be found. Please install it using luarocks."
        return 1
    fi
}

echo "Lua environment for ${PACKAGE_NAME} is now set up:"
echo "- LUA_PATH: $LUA_PATH"
echo "- LUA_CPATH: $LUA_CPATH"
echo "- Local busted is available via the 'run_busted' function"
```

### Test Runner Script (bin/run-tests)

```bash
#!/bin/bash

# Run tests for your project using the local LuaRocks installation

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "${SCRIPT_DIR}/.." && pwd )"

# Source the environment setup script
source "${SCRIPT_DIR}/luapath.sh"

# Set test mode environment variable if needed
export PROJECT_TEST_MODE=1

# Run the tests
echo "Running tests..."
run_busted "$@"
```

Make these scripts executable:

```bash
chmod +x bin/luapath.sh bin/run-tests
```

### Usage

1. To set up the environment for development:
   ```bash
   source ./bin/luapath.sh
   ```

2. To run tests:
   ```bash
   ./bin/run-tests
   ```

## Conclusion

By following this setup, you create a robust and isolated environment for your
Lua project. Each project has its own set of dependency versions managed in its
local .luarocks tree, preventing conflicts and making your project more portable
and easier to set up.

Key points:

1. Install project dependencies in a local `.luarocks` directory
2. Use helper scripts (`bin/luapath.sh` and `bin/run-tests`) to set up the environment and run tests
3. Configure `.busted` file for test settings
4. Add test dependencies to the rockspec file

This approach ensures that your development environment is consistent and
reproducible, making it easier to collaborate with others and maintain your
project over time.
