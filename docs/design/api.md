# Fsynth API Design

## Overview

Fsynth provides a synthetic filesystem abstraction that isolates and queues
filesystem operations for batch execution. The API follows an explicit queue and
processor model, giving users fine-grained control over operation planning and
execution.

## Core Components

### 1. Operation Queue

The queue is a first-class citizen in the API, allowing operations to be added
from different parts of an application before batch execution.

```lua
local queue = fsynth.new_queue()
```

#### Queue Methods

- `queue:add(operation)` - Adds an operation to the queue
- `queue:get_operations()` - Returns all operations in the queue (for
  inspection)
- `queue:clear()` - Removes all operations from the queue
- `queue:size()` - Returns the number of operations in the queue
- `queue:remove(index)` - Removes operation at specific index (optional)

### 2. Operation Factories

All operations are created through factory functions in the `fsynth.op`
namespace:

#### Copy File

```lua
fsynth.op.copy_file(source_path, target_path, options)
```

Options:

- `verify_checksum_before` (boolean, default true) - Verify source checksum
  before copy
- `verify_checksum_after` (boolean, default true) - Verify target checksum after
  copy
- `overwrite` (boolean, default false) - Allow overwriting existing target
- `on_checksum_mismatch` (string, default "error") - Action on checksum failure:
  "error" or "warn"
- `preserve_attributes` (boolean, default true) - Preserve file attributes

#### Create Directory

```lua
fsynth.op.create_directory(dir_path, options)
```

Options:

- `create_parents` (boolean, default true) - Create parent directories if needed
- `mode` (string/number, optional) - Permissions for the new directory

#### Create File

```lua
fsynth.op.create_file(file_path, content, options)
```

Options:

- `mode` (string/number, optional) - Permissions for the new file
- `encoding` (string, default "utf-8") - File encoding
- `overwrite` (boolean, default false) - Allow overwriting existing file

#### Symlink

```lua
fsynth.op.symlink(existing_path, link_path, options)
```

Options:

- `overwrite` (boolean, default false) - Allow overwriting existing link
- `relative` (boolean, default false) - Create relative symlink

#### Move File

```lua
fsynth.op.move_file(source_path, target_path, options)
```

Options:

- `verify_checksum` (boolean, default true) - Verify file integrity
- `overwrite` (boolean, default false) - Allow overwriting existing target

#### Delete File

```lua
fsynth.op.delete_file(file_path, options)
```

Options:

- `backup_before_delete` (boolean, default false) - Create backup before
  deletion
- `backup_suffix` (string, default ".bak") - Suffix for backup file
- `ignore_if_not_exists` (boolean, default false) - Don't error if file doesn't
  exist

#### Delete Directory

```lua
fsynth.op.delete_directory(dir_path, options)
```

Options:

- `recursive` (boolean, default false) - Delete non-empty directories
- `max_items` (number, default 1000) - Safety limit for recursive deletion
- `ignore_if_not_exists` (boolean, default false) - Don't error if directory
  doesn't exist

### 3. Processor

The processor executes queued operations with configurable execution models:

```lua
local processor = fsynth.new_processor()
local results = processor:execute(queue, execution_config)
```

#### Execution Configuration

- `model` (string) - Execution model:

  - `"standard"` - Execute operations sequentially, stop on first error
  - `"validate_first"` - Validate all operations before executing any
  - `"best_effort"` - Try all operations, collect errors
  - `"transactional"` - Attempt rollback of completed operations on failure

- `on_error` (string) - Error handling strategy:

  - `"stop"` - Stop execution on first error
  - `"continue"` - Continue executing remaining operations
  - `"rollback"` - Rollback completed operations (transactional mode only)

- `dry_run` (boolean, default false) - Simulate execution without making changes
- `log_level` (string, default "info") - Logging verbosity: "trace", "debug",
  "info", "warn", "error"
- `parallel` (boolean, default false) - Enable parallel execution where safe
  (future enhancement)

### 4. Results Object

The processor returns a comprehensive results object:

```lua
results.success          -- boolean: Overall success status
results.errors           -- array: List of error objects
results.executed_count   -- number: Count of successfully executed operations
results.skipped_count    -- number: Count of skipped operations
results.rollback_count   -- number: Count of rolled back operations
results.log              -- array: Detailed execution log

-- Methods
results:is_success()     -- Returns true if all operations succeeded
results:get_errors()     -- Returns array of error objects
results:get_log()        -- Returns execution log
```

#### Error Object Structure

```lua
{
    operation_index = 3,
    operation_type = "CopyFile",
    message = "Source file not found: /path/to/file",
    path = "/path/to/file",
    severity = "error"  -- "error" or "warning"
}
```

## Design Principles

### 1. Immutability

Once an operation is created, its parameters cannot be changed. This ensures
predictable behavior and easier debugging.

### 2. Explicit Execution

Operations are never executed implicitly. The user must explicitly call
`processor:execute()` to run queued operations.

### 3. Comprehensive Options

Each operation type provides fine-grained control through its options table,
with sensible defaults.

### 4. Safety First

Operations include safety features like checksum verification, item count limits
for directory operations, and optional backups before destructive operations.

### 5. Testability

The separation of operation creation and execution makes it easy to test
operation planning without actual filesystem changes.

## Error Handling

Fsynth provides multiple levels of error handling:

1. **Operation Validation** - Each operation can be validated before execution
2. **Execution Models** - Different models provide different error handling
   strategies
3. **Rollback Support** - Transactional mode attempts to undo completed
   operations on failure
4. **Detailed Error Information** - Errors include context about the operation
   and failure reason

## Future Extensions

The API is designed to support future enhancements:

- Parallel execution of independent operations
- Operation dependencies and ordering constraints
- Progress callbacks for long-running batches
- Operation groups/sub-queues for logical grouping
- Custom operation types through plugins
