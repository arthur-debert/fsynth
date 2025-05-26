# Correctness Decisions and Design Philosophy for Fsynth Operations

This document outlines key design decisions made for fsynth operations,
particularly concerning edge cases, error handling, and undo behavior.

## Undo Operations: Tolerant Success Principle

A guiding principle for `:undo()` methods across fsynth operations is **tolerant
success**. This means that if the state of the filesystem already reflects the
desired outcome of an undo operation (e.g., the item to be removed is already
gone), the undo operation should generally succeed rather than fail. This
promotes idempotency and resilience.

However, this tolerance is balanced with safety:

- If an undo operation cannot be performed safely (e.g., a file has changed
  since its creation and `CreateFileOperation:undo()` is called), it should
  fail.
- If an undo operation would overwrite a different, unrelated item that now
  exists at the original location, it should typically fail.

### Examples of Tolerant Success in Undo:

1.  **`CreateFileOperation:undo()` for a non-existent file:**

    - **Scenario:** A file is created by `CreateFileOperation`, then deleted
      externally. `undo()` is called.
    - **Behavior:** `undo()` succeeds. The goal was to ensure the file doesn't
      exist, and it already doesn't.
    - **Rationale:** Prevents errors if the filesystem state was already
      achieved by other means.

2.  **`DeleteOperation:undo()` when the original item was not actually deleted
    by `execute()`:**

    - **Scenario:** `DeleteOperation:execute()` is called on a non-existent
      path. `execute()` succeeds as a no-op, and `item_actually_deleted` is
      false. `undo()` is then called.
    - **Behavior:** `undo()` succeeds as a no-op. There's nothing to restore
      because nothing was deleted by this operation instance.
    - **Rationale:** The undo correctly reflects that no state change needs to
      be reverted for this specific operation's execution.

3.  **`SymlinkOperation:undo()` for a non-existent symlink:**
    - **Scenario:** A symlink is created by `SymlinkOperation`, then the symlink
      (not its target) is deleted externally. `undo()` is called, and no
      original file/symlink was overwritten at the link's path during creation.
    - **Behavior:** `undo()` succeeds. The goal was to ensure the symlink
      doesn't exist at that path, and it already doesn't.
    - **Rationale:** Consistent with the tolerant approach.

### Strictness vs. Tolerance:

The choice between strict failure (undo fails if its specific action cannot be
performed, even if the desired state is met) and tolerant success was made to
favor robustness in automated sequences of operations. Tolerant success
generally makes undo operations more idempotent.

## Specific Operation Behaviors

### `CreateFileOperation`

- **Exclusivity:** `execute()` will fail if the target file already exists. It
  does not overwrite.
- **Undo Safety:** `undo()` relies on a stored checksum. If the file content has
  changed since creation, or if no checksum was recorded (e.g., `execute()`
  failed or wasn't called for that specific file instance), `undo()` will fail
  to prevent deleting a modified or unrelated file.

### `DeleteOperation`

- **Symlinks:** Deletes the symbolic link itself, not the target it points to.
  `undo()` will recreate the symlink, pointing to its original target path.
  Broken symlinks can be deleted; undoing a deleted broken symlink whose target
  could not be read will fail as the target is unknown.
- **Non-Existent Items:** `execute()` on a non-existent path is a successful
  no-op. `undo()` in this case is also a successful no-op.
- **Undo Safety (Files):** If `item_type` is "file", `undo()` will fail if the
  `original_checksum` was not recorded during `validate()`, as content integrity
  cannot be assured. If the checksum _was_ recorded, but the restored file's
  checksum mismatches (or current checksum calculation fails), `undo()` will log
  a warning but still succeed if the file write itself was successful.

### `MoveOperation`

- **File into Directory:** If the source is a file and the target is an existing
  directory, the source file is moved _into_ the target directory by default
  (e.g., `mv source.txt existing_dir/` results in `existing_dir/source.txt`).
  The `overwrite` option applies to the final path within the directory.
- **Identical Source/Target:** Moving a path to itself is a validation error,
  similar to POSIX `mv`.
- **Symlinks:** Moves the symbolic link itself, not its target. The link's
  target string remains unchanged. Checksums are not performed on the content of
  symlink targets during move; `undo` verifies the restored link's target string
  if it was readable.
- **Undo Safety:** `undo()` will fail if the item at the `actual_target_path`
  (where it was moved) no longer exists, or if the original `source` path is now
  occupied by a different item. It does _not_ restore items that were
  overwritten at the target if `overwrite = true` was used.

### `SymlinkOperation`

- **Relative Paths:** Supports creating symlinks with relative target paths. The
  relative path string is stored as-is.
- **Overwrite:** Can overwrite existing files or symlinks if `overwrite = true`.
  It cannot overwrite an existing directory.
- **Undo Safety:** `undo()` will remove the created symlink. If an item was
  overwritten during `execute()`, `undo()` will attempt to restore that original
  item (file content or original symlink target).

---
