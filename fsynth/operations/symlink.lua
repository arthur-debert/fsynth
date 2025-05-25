local Operation = require("fsynth.operation_base")
-- always use the log module, no prints
local log = require("fsynth.log")
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
  log.debug("Creating new SymlinkOperation from %s to %s", link_target_path, link_path)
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
  log.debug("Validating SymlinkOperation from %s to %s", self.source, self.target)
  if not self.source then -- link_target_path
    local err_msg = "Link target path (source) not specified for SymlinkOperation"
    log.error(err_msg)
    return false, err_msg
  end
  if not self.target then -- link_path
    local err_msg = "Link path (target) not specified for SymlinkOperation"
    log.error(err_msg)
    return false, err_msg
  end

  -- Link Path (self.target) Validation
  if pl_path.exists(self.target) then
    if not self.options.overwrite then
      local err_msg = "Link path '" .. self.target .. "' exists and overwrite is false."
      log.error(err_msg)
      return false, err_msg
    end
    if pl_path.isdir(self.target) then
      local err_msg = "Cannot overwrite a directory '" .. self.target .. "' with a symlink."
      log.error(err_msg)
      return false, err_msg
    end
    -- If it exists, it's a file or a symlink, and overwrite is true.
    -- It will be handled in execute().
    log.debug("Target exists but will be overwritten: %s", self.target)
  else -- Link path does not exist
    if not self.options.create_parent_dirs then
      local parent_dir = pl_path.dirname(self.target)
      if parent_dir and parent_dir ~= "" and parent_dir ~= "." and not pl_path.isdir(parent_dir) then
        local err_msg = "Parent directory of link path '" .. parent_dir ..
                        "' does not exist and create_parent_dirs is false."
        log.error(err_msg)
        return false, err_msg
      end
    end
  end

  -- Link Target Path (self.source) Validation:
  -- As per requirements, no validation on self.source's existence at this stage.
  log.debug("SymlinkOperation validation successful from %s to %s", self.source, self.target)
  return true
end

function SymlinkOperation:execute()
  log.info("Executing SymlinkOperation from %s to %s", self.source, self.target)
  local ok, err_msg

  -- Create Parent Directories for Link Path (self.target)
  if self.options.create_parent_dirs then
    local parent_dir = pl_path.dirname(self.target)
    if parent_dir and parent_dir ~= "" and parent_dir ~= "." and not pl_path.isdir(parent_dir) then
      log.debug("Creating parent directory for symlink: %s", parent_dir)
      ok, err_msg = pcall(function() pl_dir.makepath(parent_dir) end)
      if not ok then
        err_msg = "Failed to create parent directories for '" .. self.target .. "': " .. tostring(err_msg)
        log.error(err_msg)
        return false, err_msg
      end
      log.info("Parent directory created: %s", parent_dir)
    end
  end

  -- Handle Existing Link Path (self.target)
  if pl_path.exists(self.target) then
    if self.options.overwrite then
      -- If it's a directory, validate() should have caught it.
      -- So, it's either a file or a symlink.
      log.debug("Removing existing item for overwrite: %s", self.target)
      local removed_existing, remove_err = pcall(function() os.remove(self.target) end)
      if not removed_existing then
        err_msg = "Failed to remove existing item at link path '" .. self.target .. "': " .. tostring(remove_err)
        log.error(err_msg)
        return false, err_msg
      end
      log.info("Existing item removed for overwrite: %s", self.target)
    else
      -- This case should ideally be caught by validate(), but as a safeguard:
      err_msg = "Link path '" .. self.target .. "' exists and overwrite is false (execute safeguard)."
      log.error(err_msg)
      return false, err_msg
    end
  end

  -- Create Symlink
  -- pl_file.symlink(target_path_for_link_content, path_of_link_itself)
  log.debug("Creating symlink from %s to %s", self.target, self.source)
  ok, err_msg = pcall(function() return pl_file.symlink(self.source, self.target) end)
  if not ok then
    -- pcall failed, err_msg is the error string from Lua
    err_msg = "Failed to create symlink from '" .. self.target .. "' to '" .. self.source .. "': " .. tostring(err_msg)
    log.error(err_msg)
    return false, err_msg
  end
  -- pcall succeeded, err_msg is the first return value of pl_file.symlink
  -- Penlight's pl.file.symlink returns (true) on success or (nil, message) on error.
  if err_msg == nil or type(err_msg) == "string" then -- This means pl_file.symlink itself returned (nil, msg)
      local actual_err_msg = err_msg or "unknown error from pl_file.symlink"
      err_msg = "Failed to create symlink from '" .. self.target .. "' to '" .. self.source .. "': " .. actual_err_msg
      log.error(err_msg)
      return false, err_msg
  end
  -- If err_msg is true, it means pl_file.symlink succeeded.
  log.info("Symlink successfully created from %s to %s", self.target, self.source)
  self.link_actually_created = true
  return true
end

function SymlinkOperation:undo()
  log.info("Undoing SymlinkOperation for: %s", self.target)
  if not self.link_actually_created then
    local msg = "Undo: Link was not recorded as created, no action taken."
    log.info(msg)
    return true, msg
  end

  if not pl_path.exists(self.target) then
    local err_msg = "Undo: Symlink at '" .. self.target .. "' does not exist, cannot remove."
    log.warn(err_msg)
    return false, err_msg
  end

  if not pl_path.islink(self.target) then
    local err_msg = "Undo: Item at '" .. self.target .. "' is not a symlink, cannot safely undo."
    log.warn(err_msg)
    return false, err_msg
  end
  
  log.debug("Removing symlink for undo: %s", self.target)
  local ok, err_msg = pcall(function() os.remove(self.target) end)
  if not ok then
    err_msg = "Undo: Failed to delete symlink '" .. self.target .. "': " .. tostring(err_msg)
    log.error(err_msg)
    return false, err_msg
  end
  log.info("Symlink successfully removed during undo: %s", self.target)
  return true
end

-- The Operation:checksum() method is inherited but not applicable/useful for symlinks
-- in the context of source file content verification. self.source is a path, not content.

return SymlinkOperation
