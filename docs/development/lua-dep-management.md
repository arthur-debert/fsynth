# Lua Project Setup: Isolated Dependencies with LuaRocks

This guide details how to manage Lua project dependencies in an isolated manner
using LuaRocks with direnv for automatic environment setup. This approach keeps
your project's libraries separate from other projects and your system-wide
LuaRocks installation, while still sharing the main Lua runtime. This leads to
more reproducible builds and avoids version conflicts.

## Assumed Project Structure

We'll assume the following project structure:

```plaintext
my_lua_project/
├── .luarocks/         # Local, isolated LuaRocks tree for dependencies
├── .envrc             # direnv configuration for automatic environment setup
├── fsynth-0.1.0-1.rockspec   # Rockspec file defining dependencies
└── spec/              # Test specifications
```

## Prerequisites

- Lua: Ensure Lua is installed on your system.
- LuaRocks: Ensure LuaRocks, the Lua package manager, is installed.
- direnv: For automatic environment setup when entering the project directory.

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

With your .luarocks directory and rockspec ready, you can install the defined
dependencies.

1. From the Rockspec:

   - Installing the dependencies listed in the rockspec:

     ```bash
     luarocks --tree ./.luarocks install --only-deps rockspec_file.rockspec
     ```

   - Installing the project itself along with its dependencies (useful during
     development):

     ```bash
     luarocks --tree ./.luarocks make rockspec_file.rockspec
     ```

   The `--tree ./.luarocks` flag tells LuaRocks to use your project-local
   directory for installation, keeping dependencies isolated from the
   system-wide installation.

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

## Step 4: Configuring the Lua Environment with direnv

For Lua to find your project's own modules and the dependencies in .luarocks/,
you need to correctly set the LUA_PATH and LUA_CPATH environment variables.
Using direnv automates this process.

### Setting up direnv

1. Install direnv if you haven't already:

   - On macOS: `brew install direnv`
   - On Ubuntu/Debian: `apt-get install direnv`
   - Other platforms: See
     [direnv installation instructions](https://direnv.net/docs/installation.html)

2. Add direnv hook to your shell's RC file:
   - For bash: `echo 'eval "$(direnv hook bash)"' >> ~/.bashrc`
   - For zsh: `echo 'eval "$(direnv hook zsh)"' >> ~/.zshrc`
   - Reload your shell or source the RC file

### Creating a .envrc file

Create a `.envrc` file in your project root with the following content:

```bash
#! /usr/bin/env bash

# Define project structure
PROJECT_ROOT="$(pwd)"
LIB_NAME="your_lib_name"  # Replace with your library name
LIB_ROOT="${PROJECT_ROOT}/${LIB_NAME}"
export LIB_NAME
export PROJECT_ROOT
export LIB_ROOT

# Set up LuaRocks paths if .luarocks directory exists
if [[ -d ".luarocks" ]]; then
    # Check if luarocks is installed
    LUAROCKS_BIN=$(command -v luarocks)
    if [[ -z "${LUAROCKS_BIN}" ]]; then
        echo "LuaRocks is not installed. Please install it to use this" \
          "project." >&2
        exit 1
    fi

    # Set up the local LuaRocks tree paths
    LUAROCKS_PATH_RESULT=$("${LUAROCKS_BIN}" --tree \
      "${PROJECT_ROOT}/.luarocks" path) && eval "${LUAROCKS_PATH_RESULT}"
fi
```

After creating the file, allow it with direnv:

```bash
direnv allow
```

When you enter the project directory, direnv will automatically load this
configuration. The environment will be set up correctly without having to
manually source any scripts.

## Step 5: Running Your Project and Tests

With direnv automatically setting up your environment when you enter the project
directory, running your application and tests becomes much simpler.

1. Running Your Main Application File:  
   Assuming main.lua is in your project root:

   ```bash
   # Environment is already set up by direnv
   lua main.lua
   ```

2. Running Busted Tests:

   - Add busted to your rockspec's test_dependencies.
   - Install it with:

     ```bash
     luarocks --tree ./.luarocks install --only-deps rockspec_file.rockspec
     ```

   - Run tests directly:

     ```bash
     # Environment is already set up by direnv
     busted
     ```

## Conclusion

By following this setup, you create a robust and isolated environment for your
Lua project. Each project has its own set of dependency versions managed in its
local .luarocks tree, preventing conflicts and making your project more portable
and easier to set up.

Key points:

1. Install project dependencies in a local `.luarocks` directory
2. Use direnv with a `.envrc` file for automatic environment setup
3. Run busted tests directly without helper scripts
4. Add test dependencies to the rockspec file

This approach ensures that your development environment is consistent and
reproducible, making it easier to collaborate with others and maintain your
project over time. Using direnv significantly simplifies the workflow by
automating environment setup when entering the project directory.
