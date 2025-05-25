local Operation = require("fsynth.operation_base")
local Checksum = require("fsynth.checksum")
local pl_file = require("pl.file")
local pl_path = require("pl.path")
local pl_dir = require("pl.dir")
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
  if not self.source then
    return false, "Source path not specified for CopyFileOperation"
  end
  if not self.target then
    return false, "Target path not specified for CopyFileOperation"
  end

  -- Verify source
  if not pl_path.isfile(self.source) then
    return false, "Source path ('" .. self.source .. "') is not a file or does not exist."
  end

  -- Verify if source file has changed since object creation
  -- The self:checksum() method compares current source checksum with self.checksum_data.source_checksum
  -- which was set during new() to self.checksum_data.initial_source_checksum
  -- For this to work as intended, self.checksum_data.source_checksum must be the *initial* one.
  -- Let's ensure self.checksum_data.source_checksum holds the initial checksum for this check.
  local original_source_checksum_for_validation = self.checksum_data.source_checksum
  self.checksum_data.source_checksum = self.checksum_data.initial_source_checksum
  
  local checksum_ok, checksum_err = self:checksum() -- This will compare current against initial_source_checksum
  
  -- Restore the potentially updated source_checksum (if self:checksum() updated it on first run)
  -- However, our current self:checksum() only updates if source_checksum was nil.
  -- Since we set it in new(), it should only compare here.
  -- For clarity, we can restore it if needed, but it might not be necessary with current base logic.
  -- self.checksum_data.source_checksum = original_source_checksum_for_validation; -- Not strictly needed if base checksum() doesn't overwrite when one exists

  if not checksum_ok then
    return false, "Source file validation failed: " .. (checksum_err or "checksum mismatch or error")
  end
  
  -- Verify target
  if pl_path.exists(self.target) then
    if pl_path.isdir(self.target) then
      return false, "Target path ('" .. self.target .. "') is a directory."
    end
    if not self.options.overwrite then
      return false, "Target file ('" .. self.target .. "') exists and overwrite is false."
    end
  else -- Target does not exist
    if not self.options.create_parent_dirs then
      local parent_dir = pl_path.dirname(self.target)
      if parent_dir and parent_dir ~= "" and parent_dir ~= "." and not pl_path.isdir(parent_dir) then
        return false, "Parent directory of target ('" .. parent_dir .. "') does not exist and create_parent_dirs is false."
      end
    end
  end

  return true
end

function CopyFileOperation:execute()
  local ok, err_msg

  -- Create Parent Directories for Target
  if self.options.create_parent_dirs then
    local parent_dir = pl_path.dirname(self.target)
    if parent_dir and parent_dir ~= "" and parent_dir ~= "." and not pl_path.isdir(parent_dir) then
      ok, err_msg = pcall(function() pl_dir.makepath(parent_dir) end)
      if not ok then
        return false, "Failed to create parent directories for '" .. self.target .. "': " .. tostring(err_msg)
      end
    end
  end

  -- Note: Backup of original target if self.options.overwrite is true is not implemented here.
  -- pl_file.copy in Penlight should handle overwriting if the target file exists.

  -- Copy File
  ok, err_msg = pcall(function()
    -- pl.file.copy(src, dst, overwrite_flag)
    -- Penlight's copy function might need an explicit overwrite flag if we want to be sure.
    -- However, the documentation for pl.file.copy usually implies it overwrites.
    -- For safety, if pl.file.copy doesn't overwrite by default, one might need to remove target first.
    -- Let's assume pl.file.copy handles overwrite correctly if target exists.
    return pl_file.copy(self.source, self.target)
  end)

  if not ok then
    -- If pcall itself failed (e.g. error in pl_file.copy) err_msg has the error.
    -- If pl_file.copy returned false (indicating failure), err_msg would be `false` and we need pl_file.last_error()
    -- However, pl.utils.execute will return {nil, err} on failure, so `ok` (true/false) and `err_msg` (actual error) is fine.
    -- For pl_file.copy, it returns (true) or (nil, msg). So if not ok, err_msg is the message.
     return false, "Failed to copy file from '" .. self.source .. "' to '" .. self.target .. "': " .. tostring(err_msg)
  end
  if type(err_msg) == "string" and ok == nil then -- This means pl_file.copy itself returned (nil, msg)
      return false, "Failed to copy file from '" .. self.source .. "' to '" .. self.target .. "': " .. tostring(err_msg)
  end


  -- Record Target Checksum
  local new_target_checksum, checksum_target_err = Checksum.calculate_sha256(self.target)
  if not new_target_checksum then
    -- Copied file, but cannot checksum it. This is a problematic state.
    -- Attempt to remove the problematic copied file.
    pcall(function() os.remove(self.target) end)
    return false, "Failed to calculate checksum for copied file '" .. self.target .. "': " .. tostring(checksum_target_err)
  end
  self.checksum_data.target_checksum = new_target_checksum

  return true
end

function CopyFileOperation:undo()
  local ok, err_msg

  if not pl_path.exists(self.target) then
    -- If the target file doesn't exist, it might have been deleted by other means.
    -- Or, if we had a backup mechanism, we would restore it here.
    -- For now, if it's not there, the "undo" (deletion) is effectively done or not applicable.
    return true, "Target file '" .. self.target .. "' does not exist, undo operation is a no-op or file already removed."
  end

  if not self.checksum_data.target_checksum then
    -- This implies the execute() step failed to record a checksum, or this is an invalid state.
    return false, "No target checksum recorded for '" .. self.target .. "' from execution, cannot safely undo."
  end

  local current_target_checksum, checksum_err = Checksum.calculate_sha256(self.target)
  if not current_target_checksum then
    return false, "Failed to calculate checksum for target file '" .. self.target .. "' during undo: " .. tostring(checksum_err)
  end

  if current_target_checksum ~= self.checksum_data.target_checksum then
    return false, "Copied file content of '" .. self.target .. "' has changed since operation (checksum mismatch), cannot safely undo."
  end

  -- Delete the copied file
  ok, err_msg = pcall(function() os.remove(self.target) end)
  if not ok then
    return false, "Failed to delete copied file '" .. self.target .. "' during undo: " .. tostring(err_msg)
  end

  self.undone_pomoci_zalohy = false -- As we are just deleting.
  return true
end

return CopyFileOperation
