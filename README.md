# Fsynth 🗂️

predictable, and testable.\*\*

## Overview

Fsynth separates the _planning_ of filesystem operations from their _execution_.
Instead of immediately performing operations, you queue them up and execute them
as a batch.

Designed to isolate side-effects in your applications, enabling better
testability, easier resoning about your programs, a inspectable list of would-be
file system operations and dryr-run modes for free.

[![Lua](https://img.shields.io/badge/Lua-5.1%2B-blue.svg)](https://www.lua.org/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Tests](https://img.shields.io/badge/Tests-Passing-brightgreen.svg)](spec/)

## Disclaimer

A future-bound-journaling file-system is enterily impossible to build, as cool
as it may sound. Fsynth has a very narrow domain: non concurrent, non-mission
critical data. This is useful for scripts or programs running under controled
envinroments.

At any level of cuncurrency, you wil have unpredictable and even data loss.

While the code base pays good effort on ensuring it works safely, the
interaction with other systems changing is not a tractable problem under this
design. See [docs/correctness-decisions.md](docs/correctness-decisions.md).

### Real-World Example: Dotfiles Deployment

Here's a common scenario - deploying dotfiles across systems with backup
protection:

```lua
local fsynth = require("fsynth")

function deploy_dotfiles(dotfiles_repo, home_dir)
    local queue = fsynth.new_queue()
    local timestamp = os.date("%Y%m%d_%H%M%S")
    local backup_dir = home_dir .. "/.dotfiles_backup_" .. timestamp

    -- Create backup directory
    queue:add(fsynth.op.create_directory(backup_dir))

    -- Create config directories if they don't exist
    queue:add(fsynth.op.create_directory(home_dir .. "/.config"))
    -- create_parent_dirs defaults to true for create_directory, so no options needed here
    -- if that's the desired behavior for creating .local/bin.
    queue:add(fsynth.op.create_directory(home_dir .. "/.local/bin"))

    -- Backup and link shell config files
    local shell_files = {".bashrc", ".zshrc", ".profile"}
    for _, file in ipairs(shell_files) do
        -- Attempt to backup existing file.
        -- Note: fsynth.op.copy_file will fail validation if source_path does not exist.
        -- For a robust script, you might check existence with e.g. Penlight's pl.path.exists()
        -- before adding this operation to the queue if the source file is optional.
        queue:add(fsynth.op.copy_file(home_dir .. "/" .. file,
                                     backup_dir .. "/" .. file)) -- overwrite defaults to false

        -- Create symlink to dotfiles repo
        queue:add(fsynth.op.symlink(dotfiles_repo .. "/shell/" .. file,
                                   home_dir .. "/" .. file, {
            overwrite = true
        }))
    end

    -- Link editor configs
    queue:add(fsynth.op.symlink(dotfiles_repo .. "/vim/.vimrc",
                               home_dir .. "/.vimrc", {
        overwrite = true
    }))
    queue:add(fsynth.op.symlink(dotfiles_repo .. "/vim",
                               home_dir .. "/.vim", {
        overwrite = true
    }))

    -- Copy and make scripts executable (don't use symlinks for scripts)
    local scripts_dir = dotfiles_repo .. "/scripts"
    local target_bin = home_dir .. "/.local/bin"

    -- Copy script and make it executable.
    -- Note: Internal checksums are always active for copy_file.
    queue:add(fsynth.op.copy_file(scripts_dir .. "/update-system.sh",
                                 target_bin .. "/update-system", {
        mode = "755" -- Set executable permissions
    }))

    -- Create a record of deployment
    queue:add(fsynth.op.create_file(home_dir .. "/.dotfiles_info",
        "Dotfiles deployed: " .. timestamp ..
        "\nSource: " .. dotfiles_repo ..
        "\nBackup: " .. backup_dir))

    -- Execute with rollback on failure
    local processor = fsynth.new_processor()
    local results = processor:execute(queue, { model = "transactional" })

    return results:is_success()
end
```

```bash
luarocks install fsynth
```

Or install from source:

```bash
git clone https://github.com/yourusername/fsynth.git
cd fsynth
luarocks make
```

## Supported Operations

Fsynth provides these filesystem operations:

| Operation          | Description           | Key Features                               |
| ------------------ | --------------------- | ------------------------------------------ |
| `copy_file`        | Copy files            | Checksum verification, preserve attributes |
| `create_directory` | Create directories    | Auto-create parents, set permissions       |
| `create_file`      | Create new files      | Set content, permissions                   |
| `symlink`          | Create symbolic links | Relative/absolute, overwrite existing      |
| `move_file`        | Move/rename files     | Checksum verification (internal)           |
| `delete_file`      | Delete files          | Tolerant to non-existent files             |
| `delete_directory` | Delete directories    | Recursive option (limited for non-empty)   |

## Queue Primer

The queue is at the heart of Fsynth. Here's how it works:

```lua
-- 1. Create a queue
local queue = fsynth.new_queue()

-- 2. Add operations (they're not executed yet!)
queue:add(fsynth.op.create_directory("my_project"))
queue:add(fsynth.op.create_file("my_project/hello.lua", "print('Hello!')"))

-- 3. Inspect what's queued
print("Operations queued:", queue:size())  -- Output: 2
for i, op in ipairs(queue:get_operations()) do
    print(i, op.type, op.target)
end

-- 4. Execute when ready
local processor = fsynth.new_processor()
local results = processor:execute(queue)

-- 5. Check results
if results:is_success() then
    print("All operations completed!")
else
    for _, err in ipairs(results:get_errors()) do
        print("Error:", err.message)
    end
end
```

## Quick Start

### Basic File Operations

```lua
local fsynth = require("fsynth")
local queue = fsynth.new_queue()

-- Add some operations
queue:add(fsynth.op.create_directory("output"))
queue:add(fsynth.op.copy_file("input.txt", "output/input_backup.txt"))
queue:add(fsynth.op.create_file("output/readme.txt", "Backup completed!"))

-- Execute them
local processor = fsynth.new_processor()
local results = processor:execute(queue)
```

### Dry Run Mode

Test your operations without making changes:

```lua
local results = processor:execute(queue, {
    dry_run = true  -- Nothing will actually happen!
})

-- Check what would happen
for _, log_entry in ipairs(results:get_log()) do
    print(log_entry)
end
```

### Transactional Mode

Rollback everything if something fails:

```lua
local results = processor:execute(queue, {
    model = "transactional"  -- All or nothing!
})
```

## Common Use Cases

### Project Scaffolding

```lua
function create_project(name)
    local q = fsynth.new_queue()

    -- Structure
    q:add(fsynth.op.create_directory(name))
    q:add(fsynth.op.create_directory(name .. "/src"))
    q:add(fsynth.op.create_directory(name .. "/tests"))

    -- Files
    q:add(fsynth.op.create_file(name .. "/README.md", "# " .. name))
    q:add(fsynth.op.copy_file("templates/init.lua", name .. "/src/init.lua"))

    return q
end
```

## Documentation

- 🚀 [Usage Examples](docs/usage_examples.lua) - More code examples
- 📋 [API Reference](docs/api.md) - Complete API documentation
- 🔧 [Development Guide](docs/development/development.txt) - Contributing and
  development

## Why Use Fsynth?

- 🧪 **Testable** - Test file operations without touching the disk
- 🔍 **Previewable** - Dry-run mode shows what will happen
- ↩️ **Reversible** - Rollback on failure prevents partial states
- 📝 **Auditable** - Detailed logs of all operations

## License

MIT License. See [LICENSE](LICENSE) for details.

## Acknowledgments

Built with [Penlight](https://github.com/lunarmodules/Penlight) for robust
filesystem operations.

---

Made with ❤️ for the Lua community
