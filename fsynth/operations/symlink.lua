local Operation = require("fsynth.operation_base")
local pl_path = require("pl.path")
local pl_file = require("pl.file") -- Assuming pl.file.symlink exists
local pl_dir = require("pl.dir")
-- os.remove is a standard Lua function

---------------------------------------------------------------------
-- SymlinkOperation
---------------------------------------------------------------------
local SymlinkOperation = {}
SymlinkOperation.__index = SymlinkOperation
setmetatable(SymlinkOperation, { __index = Operation }) -- Inherit from Operation

function SymlinkOperation.new(link_target_path, link_path, options)
  -- self.source will store link_target_path (what the link points to)
  -- self.target will store link_path (where the link is created)
  local self = Operation.new(link_target_path, link_path, options)
  setmetatable(self, SymlinkOperation)

  self.options.overwrite = self.options.overwrite or false
  self.options.create_parent_dirs = self.options.create_parent_dirs or false
  self.link_actually_created = false -- Used for undo logic

  return self
end

function SymlinkOperation:validate()
  if not self.source then -- link_target_path
    return false, "Link target path (source) not specified for SymlinkOperation"
  end
  if not self.target then -- link_path
    return false, "Link path (target) not specified for SymlinkOperation"
  end

  -- Link Path (self.target) Validation
  if pl_path.exists(self.target) then
    if not self.options.overwrite then
      return false, "Link path '" .. self.target .. "' exists and overwrite is false."
    end
    if pl_path.isdir(self.target) then
      return false, "Cannot overwrite a directory '" .. self.target .. "' with a symlink."
    end
    -- If it exists, it's a file or a symlink, and overwrite is true.
    -- It will be handled in execute().
  else -- Link path does not exist
    if not self.options.create_parent_dirs then
      local parent_dir = pl_path.dirname(self.target)
      if parent_dir and parent_dir ~= "" and parent_dir ~= "." and not pl_path.isdir(parent_dir) then
        return false, "Parent directory of link path '" .. parent_dir .. "' does not exist and create_parent_dirs is false."
      end
    end
  end

  -- Link Target Path (self.source) Validation:
  -- As per requirements, no validation on self.source's existence at this stage.

  return true
end

function SymlinkOperation:execute()
  local ok, err_msg

  -- Create Parent Directories for Link Path (self.target)
  if self.options.create_parent_dirs then
    local parent_dir = pl_path.dirname(self.target)
    if parent_dir and parent_dir ~= "" and parent_dir ~= "." and not pl_path.isdir(parent_dir) then
      ok, err_msg = pcall(function() pl_dir.makepath(parent_dir) end)
      if not ok then
        return false, "Failed to create parent directories for '" .. self.target .. "': " .. tostring(err_msg)
      end
    end
  end

  -- Handle Existing Link Path (self.target)
  if pl_path.exists(self.target) then
    if self.options.overwrite then
      -- If it's a directory, validate() should have caught it.
      -- So, it's either a file or a symlink.
      local removed_existing, remove_err = pcall(function() os.remove(self.target) end)
      if not removed_existing then
        return false, "Failed to remove existing item at link path '" .. self.target .. "': " .. tostring(remove_err)
      end
    else
      -- This case should ideally be caught by validate(), but as a safeguard:
      return false, "Link path '" .. self.target .. "' exists and overwrite is false (execute safeguard)."
    end
  end

  -- Create Symlink
  -- pl_file.symlink(target_path_for_link_content, path_of_link_itself)
  ok, err_msg = pcall(function() return pl_file.symlink(self.source, self.target) end)
  if not ok then
    -- pcall failed, err_msg is the error string from Lua
    return false, "Failed to create symlink from '" .. self.target .. "' to '" .. self.source .. "': " .. tostring(err_msg)
  end
  -- pcall succeeded, err_msg is the first return value of pl_file.symlink
  -- Penlight's pl.file.symlink returns (true) on success or (nil, message) on error.
  if err_msg == nil or type(err_msg) == "string" then -- This means pl_file.symlink itself returned (nil, msg)
      local actual_err_msg = err_msg or "unknown error from pl_file.symlink"
      return false, "Failed to create symlink from '" .. self.target .. "' to '" .. self.source .. "': " .. actual_err_msg
  end
  -- If err_msg is true, it means pl_file.symlink succeeded.

  self.link_actually_created = true
  return true
end

function SymlinkOperation:undo()
  if not self.link_actually_created then
    return true, "Undo: Link was not recorded as created, no action taken."
  end

  if not pl_path.exists(self.target) then
    return false, "Undo: Symlink at '" .. self.target .. "' does not exist, cannot remove."
  end

  if not pl_path.islink(self.target) then
    return false, "Undo: Item at '" .. self.target .. "' is not a symlink, cannot safely undo."
  end
  
  local ok, err_msg = pcall(function() os.remove(self.target) end)
  if not ok then
    return false, "Undo: Failed to delete symlink '" .. self.target .. "': " .. tostring(err_msg)
  end

  return true
end

-- The Operation:checksum() method is inherited but not applicable/useful for symlinks
-- in the context of source file content verification. self.source is a path, not content.

return SymlinkOperation
