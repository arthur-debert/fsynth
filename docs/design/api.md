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

- `overwrite` (boolean, default `false`) - Allow overwriting an existing file at the target path.
- `create_parent_dirs` (boolean, default `false`) - Create parent directories for the target path if they do not exist. (Implemented in `copy_file.lua` but not yet passed by `api.lua` factory - corrected in previous step).
- `preserve_attributes` (boolean, default `true`) - Preserve file attributes (e.g., timestamps, mode) from source to target. The underlying copy mechanism aims to preserve these where possible. (Name aligned with internal `preserve_attributes`).
- `mode` (string/number, optional) - Permissions (e.g., "644" or `0o644`) to set on the target file *after* copying. If set, this overrides any permissions that might have been preserved from the source or system defaults. (Implemented in `copy_file.lua` but not yet passed by `api.lua` factory - corrected in previous step).
- Note on Checksums: The operation internally always calculates a checksum of the source file before copy (during validation) and a checksum of the target file after copy. These are used for integrity checks during the operation's lifecycle (e.g., `validate`, `undo`). There is no API option to disable these internal checks. The documented options `verify_checksum_before`, `verify_checksum_after`, and `on_checksum_mismatch` have been removed as they don't map directly to configurable behaviors in the current implementation.

#### Create Directory

```lua
fsynth.op.create_directory(dir_path, options)
```

Options:

- `create_parent_dirs` (boolean, default `true`) - Create parent directories for `dir_path` if they do not exist. (Name aligned with internal `create_parent_dirs`).
- `mode` (string/number, optional) - Permissions (e.g., "755" or `0o755`) for the new directory. If not set, system defaults apply.
- `exclusive` (boolean, default `false`) - If `true`, the operation will fail if the directory already exists. If `false` and the directory exists, the operation is a successful no-op. (Implemented in `create_directory.lua` but not yet passed by `api.lua` factory - corrected in previous step).

#### Create File

```lua
fsynth.op.create_file(file_path, content, options)
```
Note: `create_file` is an exclusive operation. It will fail if `file_path` already exists. The `overwrite` option previously documented has been removed as it's not applicable.

Options:

- `create_parent_dirs` (boolean, default `false`) - Create parent directories for `file_path` if they do not exist. (Default aligned with operation's internal default).
- `mode` (string/number, optional) - Permissions (e.g., "644" or `0o644`) for the new file. If not set, system defaults apply.
- `content` (string, default `""`) - The content to write into the file. Passed as the second argument to the factory function.
- The `encoding` option has been removed as it's not implemented.

#### Symlink

```lua
fsynth.op.symlink(existing_path, link_path, options)
```
The `existing_path` (what the symlink will point to) is stored as is. It can be a relative or absolute path. The `relative` option has been removed as this behavior is implicit.

Options:

- `overwrite` (boolean, default `false`) - Allow overwriting an existing file or symlink at `link_path`. Cannot overwrite a directory.
- `create_parent_dirs` (boolean, default `false`) - Create parent directories for `link_path` if they do not exist. (Implemented in `symlink.lua` but not yet passed by `api.lua` factory - corrected in previous step).

#### Move File

```lua
fsynth.op.move_file(source_path, target_path, options)
```

Options:

- `overwrite` (boolean, default `false`) - Allow overwriting an existing file or directory at the target path (subject to type compatibility, e.g., cannot move a file onto a directory unless it's a move-into operation).
- `create_parent_dirs` (boolean, default `false`) - Create parent directories for the target path if they do not exist. (Implemented in `move.lua` but not yet passed by `api.lua` factory - corrected in previous step).
- Note on Checksums: For files (not directories or symlinks), the operation internally calculates a checksum of the source file before the move and the target file after the move. Mismatches are logged as warnings but do not fail the operation. The documented `verify_checksum` option has been removed as there is no API option to disable these internal checks.

#### Delete File

```lua
fsynth.op.delete_file(file_path, options)
```
Note: Deleting a non-existent file is a successful no-op. No error is raised.
The options `backup_before_delete`, `backup_suffix`, and `ignore_if_not_exists` have been removed as they are not implemented.

Options: (Currently, no specific options are implemented for `delete_file` beyond the standard behavior of the delete operation.)

#### Delete Directory

```lua
fsynth.op.delete_directory(dir_path, options)
```
Note: Deleting a non-existent directory is a successful no-op. No error is raised.
The options `max_items` and `ignore_if_not_exists` have been removed as they are not implemented.

Options:

- `recursive` (boolean, default `false`) - If `true`, allows the validation to pass for a non-empty directory. However, the underlying `os.remove` in the current `DeleteOperation` will likely still fail to delete a non-empty directory. True recursive deletion of contents is not yet fully implemented.

### 3. Processor

The processor executes queued operations with configurable execution models:

```lua
local processor = fsynth.new_processor()
local results = processor:execute(queue, execution_config)
```

#### Execution Configuration

- `model` (string) - Execution model:

  - `"standard"` - Execute operations sequentially. The underlying processor stops on the first error by default.
  - `"validate_first"` - All operations are validated before any are executed. If validation fails for any operation, execution stops.
  - `"best_effort"` - Attempts to execute all operations, regardless of errors in preceding operations. Collects all errors.
  - `"transactional"` - If an error occurs, attempts to roll back any operations that were successfully executed in the current batch.
- The `on_error` configuration has been removed as its behavior is largely implied by the `model`.
- `dry_run` (boolean, default `false`) - Simulates execution. Operations are validated, but no actual filesystem changes are made. `execute()` methods of operations are not called by the processor.
- `log_level` (string, default `"info"`) - Logging verbosity for the fsynth system: `"trace"`, `"debug"`, `"info"`, `"warn"`, `"error"`.
- `parallel` (boolean, default `false`) - (Future enhancement) Enable parallel execution where safe.

### 4. Results Object

The processor returns a comprehensive results object:

```lua
results.success          -- boolean: Overall success status (true if no errors occurred).
results.errors           -- array: List of error objects encountered during execution.
results.executed_count   -- number: Count of operations for which `execute()` was called and considered successful by the processor (or would have been in a dry_run if validation passed).
results.skipped_count    -- number: (Not currently implemented by the API layer) Count of operations that were skipped for reasons other than error (e.g., conditional execution not met).
results.rollback_count   -- number: Count of operations that were successfully rolled back in `"transactional"` mode.
results.log              -- array: Detailed execution log messages collected during processing.

-- Methods
results:is_success()     -- Returns true if `results.success` is true.
results:get_errors()     -- Returns the array of error objects.
results:get_log()        -- Returns the execution log array.
```

#### Error Object Structure

```lua
{
    operation_index = 3,                            -- 1-based index of the operation in the input queue.
    operation_type = "CopyFile",                    -- Type of the operation (e.g., "CopyFile", "CreateDirectory").
    message = "Source file not found: /path/to/file", -- Detailed error message, which usually includes relevant paths.
    severity = "error"                              -- Severity, typically "error". Warnings from operations might be logged directly but not necessarily added to this errors array.
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
Additionally, operations now perform upfront checks for source readability and
target writability based on file/directory permissions.

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
