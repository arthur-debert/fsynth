# Lua Dependence Management

Okay, here's a guide on how to use LuaRocks to manage project dependencies in an
isolated way, keeping your Lua runtime shared but project libraries separate. 🚀

---

## Using LuaRocks for Isolated Project Dependencies

LuaRocks, the package manager for Lua modules, can manage project dependencies
in a way that isolates them from other projects and the system-wide LuaRocks
installation. This is achieved by creating a local "rocktree" (a directory where
rocks are installed) for your project.

Here's how to set it up:

### 1. Create a Local Rocktree

For each project, you'll want a dedicated directory to store its dependencies.

```bash
mkdir myproject
cd myproject
mkdir .luarocks # This will be our local rocktree
```

Using a hidden directory like `.luarocks` is a common convention.

---

### 2. Configure LuaRocks to Use the Local Tree

You need to tell LuaRocks to use this local directory for the current project.
You can do this by setting environment variables or by using LuaRocks' own
configuration files. For project-specific isolation, directly invoking
`luarocks` with path flags is often the most straightforward for installation.
For running your project, you'll adjust `LUA_PATH` and `LUA_CPATH`.

**For Installing Dependencies:**

When you install a rock, you'll point LuaRocks to your local tree:

```bash
luarocks --tree ./.luarocks install <rockname>
```

For example:

```bash
luarocks --tree ./.luarocks install penlight
```

This command installs the `penlight` library into the `./.luarocks` directory
within your project.

**Alternative: `config.lua` or `luarocks init` (More Advanced)**

For more complex setups or to avoid typing `--tree` every time, you can explore
creating a local `config.lua` for LuaRocks within your project or using
`luarocks init` (if available and suited for your LuaRocks version, though this
is more common for creating rocks, not just consuming them). However, for simple
dependency isolation, the `--tree` flag is very effective.

---

### 3. Setting Up Your Project to Find Local Dependencies

Now that your dependencies are installed locally, you need to tell the Lua
runtime where to find them when you run your project's scripts. This is done by
manipulating the `LUA_PATH` and `LUA_CPATH` environment variables.

LuaRocks provides a convenient way to get the correct paths:

```bash
eval $(luarocks --tree ./.luarocks path)
```

Or, if you prefer to set them manually or in a run script:

```bash
export LUA_PATH="$(luarocks --tree ./.luarocks path --lr-path)"
export LUA_CPATH="$(luarocks --tree ./.luarocks path --lr-cpath)"
```

**Explanation:**

- `luarocks --tree ./.luarocks path` outputs shell commands to set `LUA_PATH`
  and `LUA_CPATH` correctly for the specified tree.
- `eval $(...)` executes those commands in the current shell.
- The `--lr-path` and `--lr-cpath` flags give you just the path strings, which
  you can use in scripts.

You can add these `export` lines to a shell script that launches your
application (e.g., `run.sh`) or set them in your shell before running your Lua
script.

---

### 4. Managing Dependencies (Rockspec)

For better project management and reproducibility, it's good practice to define
your project's dependencies in a **rockspec file**. A rockspec is a metadata
file that describes a rock (a Lua module/package). Even if you are not creating
a rock to be published, a local rockspec can help manage dependencies.

**Example `myproject-dev-1.rockspec` (for local development dependencies):**

```lua
package = "myproject-dev"
version = "1-1"
source = {
    url = "/dev/null" -- Dummy URL, as we're only using it for dependencies
}
dependencies = {
    "lua >= 5.1",
    "penlight >= 1.13.1",
    "lua-cjson >= 2.1"
}
build = {
    type = "none" -- We're not building a rock, just listing deps
}
```

**Installing dependencies from a rockspec:**

Once you have your rockspec file (e.g., `myproject-dev-1.rockspec`), you can
install all listed dependencies into your local tree:

```bash
luarocks --tree ./.luarocks make myproject-dev-1.rockspec
```

This command will read the `dependencies` table and install them into
`./.luarocks`.

If you only want to install dependencies without trying to "build" the dummy
package, you can use:

```bash
luarocks --tree ./.luarocks install --only-deps myproject-dev-1.rockspec
```

---

### 5. Running Your Project

With the environment variables set (Step 3), you can now run your Lua scripts,
and they will be able to `require` the locally installed dependencies.

```bash
# Ensure LUA_PATH and LUA_CPATH are set as per Step 3
# For example:
# eval $(luarocks --tree ./.luarocks path)

lua main.lua
```

---

### Workflow Summary 📝

1.  **Initialize Project:**

    ```bash
    mkdir myproject && cd myproject
    mkdir .luarocks
    # Optional: Create a rockspec file (e.g., myproject-dev-1.rockspec) with dependencies
    ```

2.  **Install Dependencies:**

    - Individually:
      ```bash
      luarocks --tree ./.luarocks install some_rock
      ```
    - From rockspec:
      ```bash
      luarocks --tree ./.luarocks make myproject-dev-1.rockspec
      # OR
      luarocks --tree ./.luarocks install --only-deps myproject-dev-1.rockspec
      ```

3.  **Set Up Environment for Running:** Create a `run.sh` script or execute in
    your shell before running Lua:

    ```bash
    #!/bin/bash
    # run.sh
    eval $(luarocks --tree "$(pwd)/.luarocks" path)
    lua your_main_script.lua "$@"
    ```

    Make it executable: `chmod +x run.sh`

4.  **Run:**
    ```bash
    ./run.sh
    ```

---

This approach ensures that each of your Lua projects can have its own set of
dependencies and versions, neatly isolated within the project's directory,
without interfering with each other or the system's LuaRocks setup. The Lua
runtime itself remains shared, as requested.
