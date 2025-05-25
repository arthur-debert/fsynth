local Operation = require("fsynth.operation_base")
local Checksum = require("fsynth.checksum")
local log = require("fsynth.log")
local pl_file = require("pl.file")
local pl_path = require("pl.path")
local pl_dir = require("pl.dir")
local fmt = require("string-format-all")
-- os.remove is a standard Lua function, no need to require 'os' for it.

---------------------------------------------------------------------
-- CopyFileOperation
---------------------------------------------------------------------
local CopyFileOperation = {}
CopyFileOperation.__index = CopyFileOperation
setmetatable(CopyFileOperation, { __index = Operation }) -- Inherit from Operation

function CopyFileOperation.new(source_path, target_path, options)
  -- Call base class constructor. Note: Penlight's Operation.new doesn't take self.
  -- Our base Operation.new also doesn't expect 'self' as the first argument.
  local self = Operation.new(source_path, target_path, options)
  setmetatable(self, CopyFileOperation) -- Set metatable to CopyFileOperation

  -- Initialize operation-specific options
  self.options.overwrite = self.options.overwrite or false
  self.options.create_parent_dirs = self.options.create_parent_dirs or false

  -- Initial checksum of the source file
  -- self:checksum() by default works on self.source and stores it in self.checksum_data.source_checksum
  -- We call it here to populate the initial source checksum.
  -- If it fails (e.g., source doesn't exist), self:checksum() returns false, message
  -- This initial check result is implicitly stored in self.checksum_data.source_checksum
  self:checksum()
  self.checksum_data.initial_source_checksum = self.checksum_data.source_checksum

  self.checksum_data.target_checksum = nil
  self.undone_pomoci_zalohy = false -- "undone_by_backup"

  return self
end

function CopyFileOperation:validate()
  log.debug("CopyFileOperation:validate called")
  if not self.source then
    log.warn("Source path not specified")
    return false, "Source path not specified for CopyFileOperation"
  end
  if not self.target then
    log.warn("Target path not specified")
    return false, "Target path not specified for CopyFileOperation"
  end

  -- Verify source
  log.debug("Checking if source exists: %s", self.source)
  local source_exists = pl_path.isfile(self.source)
  log.debug("Source exists? %s", source_exists)
  if not source_exists then
    return false, fmt("Source path ('{}') is not a file or does not exist.", self.source)
  end

  -- Verify if source file has changed since object creation
  -- The self:checksum() method compares current source checksum with self.checksum_data.source_checksum
  -- which was set during new() to self.checksum_data.initial_source_checksum
  -- For this to work as intended, self.checksum_data.source_checksum must be the *initial* one.
  -- Let's ensure self.checksum_data.source_checksum holds the initial checksum for this check.
  -- Save the current checksum value
  local original_checksum = self.checksum_data.source_checksum
  -- Use the initial value for validation
  self.checksum_data.source_checksum = self.checksum_data.initial_source_checksum
  log.debug("Comparing initial checksum: %s", self.checksum_data.initial_source_checksum)

  local checksum_ok, checksum_err = self:checksum() -- This will compare current against initial_source_checksum
  log.debug("Checksum validation result: %s, %s", checksum_ok, checksum_err)

  -- Restore the original value after validation
  self.checksum_data.source_checksum = original_checksum

  if not checksum_ok then
    return false, fmt("Source file validation failed: {}", checksum_err or "checksum mismatch or error")
  end

  -- Verify target
  if pl_path.exists(self.target) then
    if pl_path.isdir(self.target) then
      return false, fmt("Target path ('{}') is a directory.", self.target)
    end
    if not self.options.overwrite then
      return false, fmt("Target file ('{}') exists and overwrite is false.", self.target)
    end
  else -- Target does not exist
    if not self.options.create_parent_dirs then
      local parent_dir = pl_path.dirname(self.target)
      if parent_dir and parent_dir ~= "" and parent_dir ~= "." and not pl_path.isdir(parent_dir) then
        return false,
            fmt("Parent directory of target ('{}') does not exist and create_parent_dirs is false.", parent_dir)
      end
    end
  end

  return true
end
function CopyFileOperation:execute()
  log.info("CopyFileOperation:execute called for %s to %s", self.source, self.target)
  local ok, err_msg

  -- Create Parent Directories for Target
  if self.options.create_parent_dirs then
    local parent_dir = pl_path.dirname(self.target)
    if parent_dir and parent_dir ~= "" and parent_dir ~= "." and not pl_path.isdir(parent_dir) then
      ok, err_msg = pcall(function() pl_dir.makepath(parent_dir) end)
      if not ok then
        return false, fmt("Failed to create parent directories for '{}': {}", self.target, tostring(err_msg))
      end
    end
  end

  -- Note: Backup of original target if self.options.overwrite is true is not implemented here.
  -- pl_file.copy in Penlight should handle overwriting if the target file exists.

  -- Copy File
  log.info("Attempting to copy %s to %s", self.source, self.target)
  ok, err_msg = pcall(function()
    -- pl.file.copy(src, dst, overwrite_flag)
    -- Penlight's copy function might need an explicit overwrite flag if we want to be sure.
    -- However, the documentation for pl.file.copy usually implies it overwrites.
    -- For safety, if pl.file.copy doesn't overwrite by default, one might need to remove target first.
    -- Let's assume pl.file.copy handles overwrite correctly if target exists.
    local result = pl_file.copy(self.source, self.target)
    log.debug("pl_file.copy result: %s", result)
    return result
  end)
  log.debug("pcall result: %s, type: %s", ok, type(err_msg))

  if not ok then
    log.error("pcall failed: %s", err_msg)
    -- If pcall itself failed (e.g. error in pl_file.copy) err_msg has the error.
    -- If pl_file.copy returned false (indicating failure), err_msg would be `false` and we need pl_file.last_error()
    -- For pl_file.copy, it returns (true) or (nil, msg). So if not ok, err_msg is the message.
    return false, fmt("Failed to copy file from '{}' to '{}': {}", self.source, self.target, tostring(err_msg))
  end
  if type(err_msg) ~= "boolean" or err_msg == false then
    log.error("pl_file.copy returned non-success: %s, %s", type(err_msg), err_msg)
    return false, fmt("Failed to copy file from '{}' to '{}': {}", self.source, self.target, tostring(err_msg))
  end


  -- Record Target Checksum
  log.debug("Calculating target checksum for: %s", self.target)
  local new_target_checksum, checksum_target_err = Checksum.calculate_sha256(self.target)
  log.debug("Target checksum result: %s, %s", new_target_checksum, checksum_target_err)
  if not new_target_checksum then
    log.error("Failed to calculate target checksum: %s", checksum_target_err)
    -- Copied file, but cannot checksum it. This is a problematic state.
    -- Attempt to remove the problematic copied file.
    pcall(function() os.remove(self.target) end)
    return false,
        fmt("Failed to calculate checksum for copied file '{}': {}", self.target, tostring(checksum_target_err))
  end
  self.checksum_data.target_checksum = new_target_checksum
  log.info("Target checksum stored: %s", self.checksum_data.target_checksum)

  return true
end

function CopyFileOperation:undo()
  local ok, err_msg

  if not pl_path.exists(self.target) then
    -- If the target file doesn't exist, it might have been deleted by other means.
    -- Or, if we had a backup mechanism, we would restore it here.
    -- For now, if it's not there, the "undo" (deletion) is effectively done or not applicable.
    return true, fmt("Target file '{}' does not exist, undo operation is a no-op or file already removed.", self.target)
  end

  if not self.checksum_data.target_checksum then
    -- This implies the execute() step failed to record a checksum, or this is an invalid state.
    return false, fmt("No target checksum recorded for '{}' from execution, cannot safely undo.", self.target)
  end

  local current_target_checksum, checksum_err = Checksum.calculate_sha256(self.target)
  if not current_target_checksum then
    return false,
        fmt("Failed to calculate checksum for target file '{}' during undo: {}", self.target, tostring(checksum_err))
  end

  if current_target_checksum ~= self.checksum_data.target_checksum then
    return false,
        "Copied file content of '" ..
        fmt("{} has changed since operation (checksum mismatch), cannot safely undo.", self.target)
  end

  -- Delete the copied file
  ok, err_msg = pcall(function() os.remove(self.target) end)
  if not ok then
    return false, fmt("Failed to delete copied file '{}' during undo: {}", self.target, tostring(err_msg))
  end

  self.undone_pomoci_zalohy = false -- As we are just deleting.
  return true
end

return CopyFileOperation
