local Operation = require("fsynth.operation_base")
local Checksum = require("fsynth.checksum")
-- always use the log module, no prints
local log = require("fsynth.log")
local pl_path = require("pl.path")
local pl_file = require("pl.file")
local pl_dir = require("pl.dir")
local fmt = require("string.format.all")
-- os.remove is a standard Lua function

---------------------------------------------------------------------
-- CreateFileOperation
---------------------------------------------------------------------
local CreateFileOperation = {}
CreateFileOperation.__index = CreateFileOperation
setmetatable(CreateFileOperation, { __index = Operation }) -- Inherit from Operation

function CreateFileOperation.new(target_path, options)
  log.debug("Creating new CreateFileOperation for target: %s", target_path)
  local self = Operation.new(nil, target_path, options) -- Source is nil for create
  setmetatable(self, CreateFileOperation) -- Set metatable to CreateFileOperation
  self.options.content = self.options.content or "" -- Default content is empty string
  self.options.create_parent_dirs = self.options.create_parent_dirs or false
  self.checksum_data.target_checksum = nil -- Specific to CreateFile, not in base Operation new()
  return self
end

function CreateFileOperation:validate()
  log.debug("Validating CreateFileOperation for target: %s", self.target or "nil")
  if not self.target then
    local err_msg = "Target path not specified for CreateFileOperation"
    log.error(err_msg)
    return false, err_msg
  end

  if type(self.options.content) ~= "string" then
    local err_msg = "Content for CreateFileOperation must be a string"
    log.error(err_msg)
    return false, err_msg
  end

  if not self.options.create_parent_dirs then
    local parent_dir = pl_path.dirname(self.target)
    if parent_dir and parent_dir ~= "" and parent_dir ~= "." and not pl_path.isdir(parent_dir) then
      local err_msg = fmt("Parent directory '{}' does not exist and create_parent_dirs is false", parent_dir)
      log.error(err_msg)
      return false, err_msg
    end
  end
  log.debug("CreateFileOperation validated successfully for: %s", self.target)
  return true
end

function CreateFileOperation:execute()
  log.info("Executing CreateFileOperation for target: %s", self.target)
  local ok, err_msg

  -- Create Parent Directories
  if self.options.create_parent_dirs then
    local parent_dir = pl_path.dirname(self.target)
    if parent_dir and parent_dir ~= "" and parent_dir ~= "." and not pl_path.isdir(parent_dir) then
      log.debug("Creating parent directory: %s", parent_dir)
      ok, err_msg = pcall(function() pl_dir.makepath(parent_dir) end)
      if not ok then
        err_msg = fmt("Failed to create parent directories for '{}': {}", self.target, tostring(err_msg))
        log.error(err_msg)
        return false, err_msg
      end
      log.info("Parent directory created: %s", parent_dir)
    end
  end

  -- Write File
  log.debug("Writing file: %s (%d bytes)", self.target, #self.options.content)
  ok, err_msg = pcall(function() pl_file.write(self.target, self.options.content) end)
  if not ok then
    err_msg = fmt("Failed to write file '{}': {}", self.target, tostring(err_msg))
    log.error(err_msg)
    return false, err_msg
  end
  log.info("File written successfully: %s", self.target)

  -- Record Checksum of the newly created file
  log.debug("Calculating checksum for created file: %s", self.target)
  local new_checksum, checksum_err = Checksum.calculate_sha256(self.target)
  if not new_checksum then
    -- Try to clean up by deleting the possibly partially written file
    log.warn("Cleaning up partially written file: %s", self.target)
    pcall(function() os.remove(self.target) end)
    err_msg = fmt("Failed to calculate checksum for created file '{}': {}", self.target, tostring(checksum_err))
    log.error(err_msg)
    return false, err_msg
  end
  self.checksum_data.target_checksum = new_checksum
  log.info("Target checksum stored: %s", self.checksum_data.target_checksum)

  return true
end

function CreateFileOperation:undo()
  log.info("Undoing CreateFileOperation for target: %s", self.target)
  local ok, err_msg

  if not pl_path.exists(self.target) then
    -- If the file doesn't exist, undo might be considered successful or a no-op.
    -- For robustness, let's indicate it wasn't there to begin with.
    local msg = fmt("File '{}' did not exist, undo operation is a no-op.", self.target)
    log.info(msg)
    return true, msg
  end

  if not self.checksum_data.target_checksum then
    err_msg = fmt("No checksum recorded for '{}' at creation, cannot safely undo.", self.target)
    log.error(err_msg)
    return false, err_msg
  end

  log.debug("Verifying checksum before undo for: %s", self.target)
  local current_checksum, checksum_err = Checksum.calculate_sha256(self.target)
  if not current_checksum then
    err_msg = fmt("Failed to calculate checksum for '{}' during undo: {}", self.target, tostring(checksum_err))
    log.error(err_msg)
    return false, err_msg
  end

  if current_checksum ~= self.checksum_data.target_checksum then
    err_msg = fmt("File content of '{}' has changed since creation " ..
               "(checksum mismatch), cannot safely undo.", self.target)
    log.warn(err_msg)
    return false, err_msg
  end

  -- Delete the file
  log.debug("Deleting file for undo: %s", self.target)
  ok, err_msg = pcall(function() os.remove(self.target) end)
  if not ok then
    err_msg = fmt("Failed to delete file '{}' during undo: {}", self.target, tostring(err_msg))
    log.error(err_msg)
    return false, err_msg
  end
  log.info("File successfully deleted during undo: %s", self.target)

  return true
end

return CreateFileOperation
