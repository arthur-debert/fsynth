local Operation = require("fsynth.operation_base")
local Checksum = require("fsynth.checksum")
local pl_path = require("pl.path")
local pl_file = require("pl.file")
local pl_dir = require("pl.dir")
-- os.remove is a standard Lua function

---------------------------------------------------------------------
-- CreateFileOperation
---------------------------------------------------------------------
local CreateFileOperation = {}
CreateFileOperation.__index = CreateFileOperation
setmetatable(CreateFileOperation, { __index = Operation }) -- Inherit from Operation

function CreateFileOperation.new(target_path, options)
  local self = Operation.new(nil, target_path, options) -- Source is nil for create
  setmetatable(self, CreateFileOperation) -- Set metatable to CreateFileOperation
  self.options.content = self.options.content or "" -- Default content is empty string
  self.options.create_parent_dirs = self.options.create_parent_dirs or false
  self.checksum_data.target_checksum = nil -- Specific to CreateFile, not in base Operation new()
  return self
end

function CreateFileOperation:validate()
  if not self.target then
    return false, "Target path not specified for CreateFileOperation"
  end

  if type(self.options.content) ~= "string" then
    return false, "Content for CreateFileOperation must be a string"
  end

  if not self.options.create_parent_dirs then
    local parent_dir = pl_path.dirname(self.target)
    if parent_dir and parent_dir ~= "" and parent_dir ~= "." and not pl_path.isdir(parent_dir) then
      return false, "Parent directory '" .. parent_dir .. "' does not exist and create_parent_dirs is false"
    end
  end
  return true
end

function CreateFileOperation:execute()
  local ok, err_msg

  -- Create Parent Directories
  if self.options.create_parent_dirs then
    local parent_dir = pl_path.dirname(self.target)
    if parent_dir and parent_dir ~= "" and parent_dir ~= "." and not pl_path.isdir(parent_dir) then
      ok, err_msg = pcall(function() pl_dir.makepath(parent_dir) end)
      if not ok then
        return false, "Failed to create parent directories for '" .. self.target .. "': " .. tostring(err_msg)
      end
    end
  end

  -- Write File
  ok, err_msg = pcall(function() pl_file.write(self.target, self.options.content) end)
  if not ok then
    return false, "Failed to write file '" .. self.target .. "': " .. tostring(err_msg)
  end

  -- Record Checksum of the newly created file
  local new_checksum, checksum_err = Checksum.calculate_sha256(self.target)
  if not new_checksum then
    -- Try to clean up by deleting the possibly partially written file
    pcall(function() os.remove(self.target) end)
    return false, "Failed to calculate checksum for created file '" .. self.target .. "': " .. tostring(checksum_err)
  end
  self.checksum_data.target_checksum = new_checksum

  return true
end

function CreateFileOperation:undo()
  local ok, err_msg

  if not pl_path.exists(self.target) then
    -- If the file doesn't exist, undo might be considered successful or a no-op.
    -- For robustness, let's indicate it wasn't there to begin with.
    return true, "File '" .. self.target .. "' did not exist, undo operation is a no-op."
  end

  if not self.checksum_data.target_checksum then
    return false, "No checksum recorded for '" .. self.target .. "' at creation, cannot safely undo."
  end

  local current_checksum, checksum_err = Checksum.calculate_sha256(self.target)
  if not current_checksum then
    return false, "Failed to calculate checksum for '" .. self.target .. "' during undo: " .. tostring(checksum_err)
  end

  if current_checksum ~= self.checksum_data.target_checksum then
    return false, "File content of '" .. self.target .. "' has changed since creation (checksum mismatch), cannot safely undo."
  end

  -- Delete the file
  ok, err_msg = pcall(function() os.remove(self.target) end)
  if not ok then
    return false, "Failed to delete file '" .. self.target .. "' during undo: " .. tostring(err_msg)
  end

  return true
end

return CreateFileOperation
