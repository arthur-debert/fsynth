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

- **Exclusivity:** `execute()` will fail if the target path already exists (either as a file or a directory). It
  does not overwrite.
- **Parent Directories:** `execute()` will attempt to create parent directories if
  `options.create_parent_dirs` is true. If it's false (the default) and parent
  directories do not exist, the operation will fail.
- **Undo Safety:** `undo()` relies on a stored checksum (`target_checksum`)
  recorded upon successful file creation.
    - It will fail if this `target_checksum` was not recorded (e.g., `execute()`
      failed before checksum calculation).
    - It will fail if calculating the current checksum of the file fails during `undo()`.
    - It will fail if the current checksum of the file does not match the
      `target_checksum`, indicating the file has been modified since creation.
    - This prevents deleting a modified or unrelated file.
- **File Permissions:** `execute()` can optionally set file permissions (mode) if
  `options.mode` is provided. Failure to set permissions results in a warning
  but does not cause the overall operation to fail.
- **Tolerant Undo for Non-Existent File:** If the file at `target_path` does not
  exist when `undo()` is called, the undo operation succeeds as per the
  "Tolerant Success Principle".

### `DeleteOperation`

- **Target Identification:** The type of item to be deleted (file, directory, or symlink)
  is determined during `validate()` and stored. `execute()` relies on this stored `item_type`.
- **Symlinks:**
    - `execute()` deletes the symbolic link itself, not the target it points to.
    - `validate()` attempts to record the symlink's target path.
    - `undo()` will recreate the symlink, pointing to its original target path.
    - If the original symlink was broken and its target could not be read during
      `validate()`, `undo()` will fail as the target is unknown.
- **Non-Existent Items:**
    - `execute()` on a path that does not exist (or ceases to exist before actual deletion)
      is considered a successful no-op. `item_actually_deleted` will be false.
    - `undo()` in this case is also a successful no-op, as `item_actually_deleted` is false.
- **Recursive Delete for Directories:**
    - The operation has an `options.is_recursive` flag (defaults to false).
    - If a directory is not empty and `is_recursive` is false, `validate()` fails.
    - If a directory is not empty and `is_recursive` is true, `validate()` currently
      issues a warning that true recursive deletion (of contents) is not implemented;
      `execute()` will likely fail as `os.remove` typically doesn't delete non-empty directories.
- **Undo Safety (General):**
    - `undo()` will fail if a file or directory already exists at the `source` path,
      to prevent overwriting unrelated items.
- **Undo Safety (Files):**
    - `validate()` attempts to read the file's content (`original_content`) and
      calculate its checksum (`original_checksum`). If the file is unreadable,
      `original_content` is stored as an empty string, and `original_checksum` may be nil.
    - `undo()` for files will fail if:
        - `original_content` was not recorded (e.g., due to a read error during `validate`
          that prevented even storing an empty string, though current implementation aims to always store a string).
        - `original_checksum` was not recorded (e.g., checksum calculation failed during `validate`).
          This is to ensure content integrity cannot be accidentally compromised.
    - If `original_content` and `original_checksum` were recorded, the file is restored.
    - If the checksum of the restored file mismatches the `original_checksum` (or if
      calculating the restored file's checksum fails), `undo()` will log a warning
      but still succeed, provided the file write itself was successful. The primary
      failure condition is the *absence* of the original checksum needed for comparison.
- **Undo Safety (Directories & Symlinks):**
    - `undo()` for directories recreates the directory. No content is restored into it.
    - `undo()` for symlinks recreates the symlink using the `original_link_target` recorded
      during `validate()`. Failure occurs if this target wasn't recorded.

### `MoveOperation`

- **Path Determination:**
    - `actual_target_path`: The final path where the source is moved. If the
      initial `target` is a directory and the source is a file/symlink,
      `actual_target_path` becomes `target/basename(source)`. Otherwise,
      `actual_target_path` is the same as `target`.
- **File/Symlink into Directory:** If the source is a file or a symlink, and the
  `target` path is an existing directory, the source is moved _into_ this
  directory. The `options.overwrite` logic then applies to the `actual_target_path`
  within that directory.
- **Identical Source/Target:** Moving a path to itself (`source` is the same as `target`)
  is a validation error.
- **Source Existence:** `validate()` fails if the `source` path does not exist or is
  inaccessible. `execute()` also re-checks source existence and fails if it
  disappeared after validation.
- **Parent Directory Creation (`options.create_parent_dirs`):**
    - If true, `execute()` will attempt to create parent directories for the
      `actual_target_path`. Failure to create parents results in operation failure.
    - If false (default), `validate()` fails if the parent of `actual_target_path`
      does not exist (and is not the root).
    - When `undo()` is called and this option was true, it attempts to create
      parent directories for the original `source` path if they don't exist,
      logging a warning on failure but not failing the undo operation itself.
- **Overwrite Behavior (`options.overwrite`):**
    - If false (default), `execute()` fails if `actual_target_path` already exists.
    - If true, `execute()` will attempt to overwrite. However, overwriting is
      subject to type compatibility:
        - A directory can overwrite an existing empty directory (behavior may vary
          by underlying system `mv` for non-empty ones if not moving into).
        - A file can overwrite an existing file.
        - Moving a directory onto an existing file is an error.
        - Moving a file onto an existing directory is an error (unless it's the
          "move into directory" scenario).
- **Symlinks:**
    - The symbolic link itself is moved, not the target it points to. The link's
      target string (e.g., `../file.txt`) remains unchanged after the move.
    - `validate()` attempts to record the symlink's target path (`source_symlink_target`).
    - No content checksums are performed for the symlink itself or its target's content.
    - `undo()`: If `source_symlink_target` was recorded, `undo()` verifies if the
      restored symlink at the original `source` path still points to this target,
      logging a warning on mismatch or if the new target cannot be read.
- **Checksums (Files):**
    - For files (not symlinks or directories):
        - `validate()` calculates an `initial_source_checksum`. Failure to calculate
          this checksum results in validation failure.
        - `execute()` calculates a `final_target_checksum` after the move.
          Discrepancies with `initial_source_checksum` or calculation failures
          result in warnings, but the move operation itself is still considered successful.
        - `undo()` calculates a checksum for the restored file at the original `source`
          path. Discrepancies with `initial_source_checksum` or calculation failures
          result in warnings.
- **Undo Safety:**
    - `undo()` moves the item from `actual_target_path` (or `target` if `actual_target_path`
      was not set) back to the original `source` path.
    - `undo()` will fail if:
        - The item at `actual_target_path` (or `target`) no longer exists.
        - The original `source` path is now occupied by a different item (i.e., it
          exists and is not the same as `actual_target_path` before the undo move).
    - `undo()` does **not** restore items that were overwritten at the `actual_target_path`
      if `options.overwrite = true` was used during `execute()`. A warning is logged
      in such cases.

### `SymlinkOperation`

- **Parameters:** In `SymlinkOperation.new(link_target_path, link_path, options)`,
  `link_target_path` (what the symlink will point to) is stored as `self.source`,
  and `link_path` (where the symlink is created) is stored as `self.target`.
- **Relative Paths:** Supports creating symlinks where `link_target_path` is a
  relative path. This relative path string is stored as-is in the symlink.
- **Parent Directory Creation (`options.create_parent_dirs`):**
    - If true, `execute()` will attempt to create parent directories for the
      `link_path` (`self.target`). Failure to create parents results in operation failure.
    - If false (default), `validate()` fails if the parent of `link_path`
      does not exist.
- **Overwrite Behavior (`options.overwrite`):**
    - If false (default), `validate()` fails if `link_path` already exists.
    - If true:
        - `validate()` and `execute()` will fail if `link_path` is an existing directory.
        - If `link_path` is an existing file or symlink, `execute()` removes it before
          creating the new symlink. The original item (file content or target of
          the original symlink) is recorded for potential restoration by `undo()`.
- **Undo Safety:**
    - `undo()` is a no-op if the symlink was not recorded as successfully created
      (i.e., `link_actually_created` is false).
    - If the symlink at `link_path` (`self.target`) does not exist when `undo()` is called:
        - If no item was overwritten at `link_path` during `execute()`, `undo()`
          succeeds tolerantly (as per "Tolerant Success Principle").
        - If an item *was* overwritten, `undo()` proceeds to attempt restoration of
          that item.
    - If an item exists at `link_path` but is not a symlink, `undo()` fails to prevent
      accidental data modification.
    - Otherwise, `undo()` removes the symlink at `link_path`.
    - If an item (file or another symlink) was overwritten at `link_path` during
      `execute()`, `undo()` attempts to restore it:
        - For an original file, its content is rewritten.
        - For an original symlink, a new symlink is created to its original target string.
        - Failure during restoration (e.g., cannot write file) will cause `undo()` to fail.

### `CopyFileOperation`

- **Source Validation:**
    - `validate()` fails if the `source_path` is a directory, does not exist, is not a file, or is unreadable.
    - It also performs an integrity check: an initial checksum of the `source_path` is taken when the operation is created. `validate()` re-calculates the checksum and fails if it differs from the initial one, preventing operations on a changed source file.
- **Target Path (`target_path`):**
    - If `target_path` is an existing directory, the file is copied *into* this directory, forming an `actual_target_path` (e.g., `target_path/basename(source_path)`).
    - Otherwise, `actual_target_path` is the same as `target_path`.
- **Parent Directory Creation (`options.create_parent_dirs`):**
    - Defaults to `false`.
    - If true, `execute()` attempts to create parent directories for `actual_target_path`.
    - If false, `validate()` (for non-existent target) or `execute()` (for non-existent parent of an existing target dir) fails if parent directories do not exist.
- **Overwrite Behavior (`options.overwrite`):**
    - Defaults to `false`.
    - If `actual_target_path` exists and `overwrite` is false, `execute()` fails.
    - If `overwrite` is true, `execute()` will overwrite an existing file at `actual_target_path`.
    - It cannot overwrite a directory with a file.
- **Attributes and Permissions:**
    - `options.preserve_attributes` (defaults to `true`): If true, attempts to copy file attributes (e.g., permissions, timestamps) from source to target using a platform-aware copy function.
    - `options.mode` (optional): If provided (e.g., "644"), this file mode is explicitly set on `actual_target_path` *after* the copy. This overrides permissions derived from `preserve_attributes` or system defaults. Failure to set mode results in a warning but doesn't fail the operation.
- **Checksums:**
    - `initial_source_checksum` is stored during operation creation.
    - `target_checksum` is calculated for `actual_target_path` after a successful `execute()`.
        - If this checksum calculation fails, `execute()` cleans up the copied file and fails.
- **Undo Safety:**
    - `undo()` is a no-op if `actual_target_path` (recorded during `execute`) does not exist (tolerant success).
    - `undo()` will fail if:
        - The `target_checksum` was not recorded during `execute()`.
        - Calculating the current checksum of `actual_target_path` fails during `undo()`.
        - The current checksum of `actual_target_path` does not match the recorded `target_checksum` (ensuring the copied file wasn't altered).
    - If checks pass, `undo()` deletes the file at `actual_target_path`.

### `CreateDirectoryOperation`

- **Target Path (`dir_path`):** This is the path where the directory will be created.
- **Parent Directory Creation (`options.create_parent_dirs`):**
    - Defaults to `true`.
    - If true, `execute()` uses `pl_dir.makepath` to create `dir_path` including any necessary parent directories.
    - If false, `validate()` fails if parent directories of `dir_path` do not exist (for a non-existent `dir_path`). `execute()` uses `pl_path.mkdir`.
- **Exclusive Creation (`options.exclusive`):**
    - Defaults to `false`.
    - If true, `validate()` and `execute()` fail if `dir_path` already exists as a directory.
    - If false and `dir_path` already exists as a directory, `execute()` succeeds as a no-op (and `dir_actually_created_by_this_op` is marked false).
- **File Conflict:** `validate()` and `execute()` fail if `dir_path` exists and is a file.
- **Permissions (`options.mode`):**
    - Optional (e.g., "755"). If provided, this mode is set on the created directory.
    - Failure to set mode results in a warning but does not fail the overall operation.
- **Undo Safety:**
    - `undo()` is a no-op if the directory was not recorded as actually created by the operation instance (`dir_actually_created_by_this_op` is false).
    - **Strict Undo:** `undo()` will fail if `dir_path`:
        - Does not exist when `undo()` is called.
        - Exists but is not a directory.
        - Is not empty.
    - This strictness (especially failing if already deleted) contrasts with the tolerant undo for `CreateFileOperation` if the file is already gone. The rationale is to mirror `rmdir` behavior which typically requires the directory to exist and be empty.
    - If checks pass, `undo()` removes the directory using `pl_path.rmdir`.

---
