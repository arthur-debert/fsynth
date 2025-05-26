# Lua Project Setup: Isolated Dependencies with LuaRocks

This guide details how to manage Lua project dependencies in an isolated manner
using LuaRocks. This approach keeps your project's libraries separate from other
projects and your system-wide LuaRocks installation, while still sharing the
main Lua runtime. This leads to more reproducible builds and avoids version
conflicts.

Assumed Project Structure:

We'll assume the following project structure:

my_lua_project/  
├── lib/ \# Your project's own Lua modules  
├── specs/ \# Busted test specifications (or any test suite)  
├── .luarocks/ \# Local, isolated LuaRocks tree for dependencies  
├── myproject.rockspec \# Rockspec file defining dependencies (and optionally
the project itself)  
└── main.lua \# Example main application file

Prerequisites:

- Lua: Ensure Lua is installed on your system.
- LuaRocks: Ensure LuaRocks, the Lua package manager, is installed.

## Step 1: Initial Project Setup and Local Rocktree

1. Create Project Directories:  
   Navigate to where you want to create your project and set up the basic
   structure:  
   mkdir my_lua_project  
   cd my_lua_project  
   mkdir lib  
   mkdir specs  
   touch main.lua  
   touch myproject.rockspec \# We'll edit this in the next step

2. Create the Local Rocktree:  
   This directory will store all dependencies specific to this project.  
   mkdir .luarocks

   Using .luarocks makes it a hidden directory by convention.

## Step 2: Defining Dependencies with a Rockspec

A rockspec file (.rockspec) describes a Lua package (a "rock"). Even if you're
not publishing your project as a rock, a rockspec is an excellent way to declare
its dependencies.

Create or edit myproject.rockspec in your project root:

\-- myproject.rockspec

package \= "myproject"  
version \= "0.1.0-1" \-- Use "dev-1" or similar if it's just for tracking deps

source \= {  
 \-- If you were building this project as a rock to be installed:  
 \-- url \= "git://github.com/yourusername/my_lua_project.git",  
 \-- dir \= "my_lua_project"  
 \-- For local development, especially if just managing dependencies,  
 \-- a dummy URL is fine if 'build.type' is 'none' or if you only use '--only-deps'.

url \= "/dev/null", \-- Placeholder  
}

description \= {  
 summary \= "My Awesome Lua Project using isolated dependencies.",  
 detailed \= \[\[  
 This project demonstrates how to set up an isolated LuaRocks  
 environment for managing dependencies.  
 \]\],  
 homepage \= "https_your_project_homepage_com", \-- Optional  
 license \= "MIT" \-- Or your chosen license  
}

\-- Define your project's dependencies here  
dependencies \= {  
 "lua \>= 5.1", \-- Specify Lua version compatibility  
 "penlight \>= 1.13.0", \-- Example: Penlight library  
 "lua-cjson \>= 2.1.0", \-- Example: Lua CJSON library  
 "busted \>= 2.0" \-- Example: Busted testing framework (if you want it
project-local)  
}

\-- Build instructions  
\-- If this rockspec is \*only\* for listing dependencies and not for building
'myproject' itself as a rock:  
\-- build \= {  
\-- type \= "none"  
\-- }

\-- If you intend for this rockspec to also define how 'myproject' itself could
be installed (e.g., its modules from \`lib/\`):  
build \= {  
 type \= "builtin", \-- Common type for Lua modules  
 modules \= {  
 \-- Example: if you have my_lua_project/lib/core.lua  
 \-- \["myproject.core"\] \= "lib/core.lua",  
 \-- Example: if you have my_lua_project/lib/utils/init.lua for a module 'utils'

\-- \["myproject.utils"\] \= "lib/utils/init.lua"  
 }  
}

Key part: The dependencies table lists all external Lua libraries your project
needs.

## Step 3: Installing Dependencies into the Local Tree

With your .luarocks directory and myproject.rockspec ready, you can install the
defined dependencies.

1. From the Rockspec:

   - If your rockspec also defines your project and you want to "install" it
     locally (useful if it has build.modules defined) along with its
     dependencies:  
     luarocks \--tree ./.luarocks make myproject.rockspec

   - If you _only_ want to install the dependencies listed in the rockspec and
     not build/install the main package described by the rockspec itself:  
     luarocks \--tree ./.luarocks install \--only-deps myproject.rockspec

The \--tree ./.luarocks flag tells LuaRocks to use your project-local directory
for installation.

2. Installing Individual Rocks (Ad-hoc):  
   If you need to add a dependency not yet in your rockspec, or just want to
   install one quickly:  
   luarocks \--tree ./.luarocks install \<rockname\>  
   \# Example:  
   \# luarocks \--tree ./.luarocks install middleclass

   Remember to add it to your myproject.rockspec later for reproducibility.

## Step 4: Configuring the Lua Environment (LUA_PATH and LUA_CPATH)

For Lua to find your project's own modules (in lib/) and the dependencies in
.luarocks/, you need to correctly set the LUA_PATH (for Lua modules) and
LUA_CPATH (for C modules) environment variables.

The recommended way is to create a helper script or set these in your shell
before running your project.

1. Generate Paths from Local Rocktree:  
   LuaRocks can tell you the paths needed for your local tree:  
   eval $(luarocks \--tree ./.luarocks path)

   This command executes the output of luarocks path, which typically exports
   LUA_PATH and LUA_CPATH pointing to your ./.luarocks tree. These paths are
   usually prepended, giving them priority over system paths.

2. Add Your Project's lib Directory:  
   You also need to tell Lua where to find your project's own modules (e.g.,
   those in the lib/ directory). You should prepend these paths to LUA_PATH so
   they are checked before the rocktree dependencies or system paths.  
   Combined approach (recommended for a script):  
   First, set up paths for the local rocktree, then prepend your project's lib
   path.  
   \# In your project root, or use absolute paths in scripts

   \# 1\. Set up paths for .luarocks  
   eval $(luarocks \--tree "$(pwd)/.luarocks" path)

   \# 2\. Prepend your project's 'lib' directory to LUA_PATH  
   \# \`?.lua\` finds files like \`lib/foo.lua\` for \`require('foo')\`  
   \# \`?/init.lua\` finds modules structured as directories like
   \`lib/bar/init.lua\` for \`require('bar')\`  
   export LUA_PATH="$(pwd)/lib/?.lua;$(pwd)/lib/?/init.lua;$LUA_PATH"

   \# LUA_CPATH is usually handled correctly by \`luarocks path\` for C modules
   in .luarocks.  
   \# If your \`lib/\` directory also contained self-compiled C modules not
   managed by LuaRocks,  
   \# you'd prepend to LUA_CPATH similarly:  
   \# export LUA_CPATH="$(pwd)/lib/?.so;$LUA_CPATH" \# (.so for Linux, .dylib
   for macOS, .dll for Windows)

Path Order Importance:  
The resulting search order for require() will be roughly:

1. Your project's lib/ directory.
2. Your project's local .luarocks/ tree.
3. System-wide Lua/LuaRocks paths.

## Step 5: Running Your Project and Tests

Once the environment variables LUA_PATH and LUA_CPATH are correctly set (as per
Step 4):

1. Running Your Main Application File (main.lua):  
   Assuming main.lua is in your project root and requires modules from lib/ or
   your installed dependencies:  
   \# Ensure environment is set up first\!  
   lua main.lua

2. Running Busted Tests:

   - Ensure Busted is installed: It could be global, or you could have installed
     it into your local .luarocks tree (e.g., by adding "busted" to your
     rockspec's dependencies).
   - Run tests:  
     \# Ensure environment is set up first\!

     \# If Busted is globally available or its path was added by \`luarocks
     path\`:  
     busted

     \# Or specify the specs directory:  
     busted specs/

     \# If Busted was installed locally into ./.luarocks and its bin isn't on
     PATH:  
     ./.luarocks/bin/busted specs/

## Step 6: Helper Script for Environment Setup (Recommended)

To avoid manually setting environment variables every time, create a helper
script in your project root (e.g., env.sh or project_env.sh).

Example: env.sh

\#\!/bin/bash  
\# env.sh \- Sets up the Lua environment for this project.  
\# Usage: source ./env.sh  
\# After sourcing, the Lua paths will be set in your current shell.

\# Get the absolute path to the project root (where this script is located)  
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE\[0\]}")" && pwd)"

echo "Setting up Lua environment for project at ${PROJECT_ROOT}"

\# Check if luarocks command exists  
if \! command \-v luarocks &\> /dev/null  
then  
 echo "Error: luarocks command could not be found. Please ensure it's installed and
in your PATH."  
 return 1 \# Use return for sourced scripts  
fi

\# 1\. Configure LuaRocks to use the local tree and export paths  
\# The \`eval\` command executes the shell commands output by \`luarocks
path\`.  
eval $("$(which luarocks)" \--tree "${PROJECT_ROOT}/.luarocks" path)

\# 2\. Prepend project's 'lib' directory to LUA_PATH  
\# This ensures local project modules are found before dependencies or system
modules.  
export
LUA_PATH="${PROJECT\_ROOT}/lib/?.lua;${PROJECT_ROOT}/lib/?/init.lua;$LUA_PATH"

\# Optional: If your project's 'lib' directory also directly contains C modules
(not typical):  
\# export LUA_CPATH="${PROJECT\_ROOT}/lib/?.so;${LUA_CPATH}" \# Adjust .so for
your OS

echo "LUA_PATH set to: $LUA\_PATH"  
if \[ \-n "$LUA_CPATH" \]; then  
 echo "LUA_CPATH set to: $LUA_CPATH"  
fi  
echo "Environment configured. You can now run your Lua scripts or Busted."

How to use the helper script:

1. Make it executable:  
   chmod \+x env.sh

2. Source it in your current terminal session:  
   source ./env.sh

   Now, LUA_PATH and LUA_CPATH are set for the current session. You can run lua
   main.lua or busted specs/ directly.

You could also create a run_tests.sh or run_app.sh script that sources env.sh
(or includes its logic) and then executes the command.

## Conclusion

By following this setup, you create a robust and isolated environment for your
Lua project. Each project can have its own set of dependency versions managed in
its local .luarocks tree, preventing conflicts and making your project more
portable and easier for others (and your future self) to set up and run. The key
is consistently using the \--tree flag for LuaRocks operations and correctly
configuring LUA_PATH and LUA_CPATH to recognize both your project's libraries
and its isolated dependencies.
