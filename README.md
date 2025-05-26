# Fsynth 🗂️

**A synthetic filesystem library for Lua that makes file operations safe,
predictable, and testable.**

[![Lua](https://img.shields.io/badge/Lua-5.1%2B-blue.svg)](https://www.lua.org/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Tests](https://img.shields.io/badge/Tests-Passing-brightgreen.svg)](spec/)

## Overview

Fsynth separates the _planning_ of filesystem operations from their _execution_.
Instead of immediately performing operations, you queue them up and execute them
as a batch.

### Real-World Example: Database Backup Script

Here's a common scenario - backing up a database with related files:

```lua
local fsynth = require("fsynth")

function backup_database(db_name)
    local timestamp = os.date("%Y%m%d_%H%M%S")
    local backup_dir = "backups/" .. db_name .. "_" .. timestamp

    local queue = fsynth.new_queue()

    -- Create backup structure
    queue:add(fsynth.op.create_directory(backup_dir))
    queue:add(fsynth.op.create_directory(backup_dir .. "/data"))
    queue:add(fsynth.op.create_directory(backup_dir .. "/logs"))

    -- Copy database files with verification
    queue:add(fsynth.op.copy_file(db_name .. ".db", backup_dir .. "/data/" .. db_name .. ".db", {
        verify_checksum_after = true  -- Ensure backup integrity
    }))

    -- Copy related files
    queue:add(fsynth.op.copy_file(db_name .. ".conf", backup_dir .. "/data/" .. db_name .. ".conf"))
    queue:add(fsynth.op.move_file("logs/current.log", backup_dir .. "/logs/backup.log"))

    -- Create metadata
    queue:add(fsynth.op.create_file(backup_dir .. "/backup_info.txt",
        "Backup created: " .. timestamp .. "\nDatabase: " .. db_name))

    -- Create a "latest" symlink
    queue:add(fsynth.op.symlink(backup_dir, "backups/latest", {
        overwrite = true
    }))

    -- Execute with rollback on failure
    local processor = fsynth.new_processor()
    local results = processor:execute(queue, { model = "transactional" })

    return results:is_success()
end
```

**Benefits of this approach:**

- ✅ If any step fails (disk full, permissions, etc.), the entire backup is
  rolled back
- ✅ Can preview with `dry_run = true` before actual execution
- ✅ Checksum verification ensures backup integrity
- ✅ All operations are logged for audit trails
- ✅ Easy to test without touching the filesystem

## Installation

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
| `move_file`        | Move/rename files     | Checksum verification                      |
| `delete_file`      | Delete files          | Optional backup before delete              |
| `delete_directory` | Delete directories    | Recursive with safety limits               |

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

### Safe File Updates

```lua
function update_config(config_path, new_content)
    local q = fsynth.new_queue()

    -- Backup existing
    q:add(fsynth.op.copy_file(config_path, config_path .. ".backup"))

    -- Write new config
    q:add(fsynth.op.delete_file(config_path))
    q:add(fsynth.op.create_file(config_path, new_content))

    return q
end
```

### Build Deployments

```lua
function deploy_build(version)
    local q = fsynth.new_queue()

    -- Create versioned directory
    q:add(fsynth.op.create_directory("releases/v" .. version))

    -- Copy artifacts
    q:add(fsynth.op.copy_file("dist/app.lua",
        "releases/v" .. version .. "/app.lua", {
        verify_checksum_after = true
    }))

    -- Update symlink
    q:add(fsynth.op.symlink("releases/v" .. version, "releases/current", {
        overwrite = true
    }))

    return q
end
```

## Documentation

- 📖 [In-Depth Guide](docs/guide/in-depth.md) - Execution models, error
  handling, advanced features
- 🚀 [Usage Examples](docs/usage_examples.lua) - More code examples
- 📋 [API Reference](docs/design/api.md) - Complete API documentation
- 🔧 [Development Guide](docs/development.txxt) - Contributing and development

## Why Use Fsynth?

- 🧪 **Testable** - Test file operations without touching the disk
- 🔍 **Previewable** - Dry-run mode shows what will happen
- ↩️ **Reversible** - Rollback on failure prevents partial states
- ✅ **Verifiable** - Checksums ensure data integrity
- 📝 **Auditable** - Detailed logs of all operations

## Limitations

Fsynth is designed for controlled, sequential filesystem operations. It's not
suitable for:

- High-concurrency environments
- Real-time file monitoring
- Large-scale parallel processing

## License

MIT License. See [LICENSE](LICENSE) for details.

## Acknowledgments

Built with [Penlight](https://github.com/lunarmodules/Penlight) for robust
filesystem operations.

---

Made with ❤️ for the Lua community
