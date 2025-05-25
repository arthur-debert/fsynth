local Operation = require("fsynth.operation_base")
local Checksum = require("fsynth.checksum")
local pl_path = require("pl.path")
local pl_file = require("pl.file")
local pl_dir = require("pl.dir")
-- always use the log module, no prints
local log = require("fsynth.log")
local fmt = require("string-format-all")
-- os.remove is standard

---------------------------------------------------------------------
-- DeleteOperation
---------------------------------------------------------------------
local DeleteOperation = {}
DeleteOperation.__index = DeleteOperation
setmetatable(DeleteOperation, { __index = Operation }) -- Inherit from Operation

function DeleteOperation.new(path_to_delete, options)
  local self = Operation.new(path_to_delete, nil, options)
  setmetatable(self, DeleteOperation)

  self.options.is_recursive = self.options.is_recursive or false

  self.original_path_was_directory = false
  self.original_content = nil
  self.checksum_data.original_checksum = nil
  self.item_actually_deleted = false

  return self
end

function DeleteOperation:validate()
  if not self.source then
    return false, "Path to delete not specified for DeleteOperation"
  end

  if not pl_path.exists(self.source) then
    return false, fmt("Path to delete '{}' does not exist.", self.source)
  end

  self.original_path_was_directory = pl_path.isdir(self.source)

  if self.original_path_was_directory then
    local files, dirs -- To store results from pl_dir functions
    local pcall_ok_files, pcall_val_files = pcall(function() files = pl_dir.getfiles(self.source) end)
    if not pcall_ok_files then 
      return false, fmt("Error checking directory files for '{}': {}", 
                        self.source, tostring(pcall_val_files))
    end

    local pcall_ok_dirs, pcall_val_dirs = pcall(function() dirs = pl_dir.getsubdirs(self.source) end)
    if not pcall_ok_dirs then 
      return false, fmt("Error checking directory subdirs for '{}': {}", 
                        self.source, tostring(pcall_val_dirs))
    end

    local is_not_empty = (files and next(files)) or (dirs and next(dirs))

    if self.options.is_recursive then
      if is_not_empty then
        return false, fmt("Directory '{}' is not empty and recursive delete with safety limits is not yet " ..
                         "implemented. Only empty directory deletion is supported currently.", self.source)
      end
    else
      if is_not_empty then
        return false, fmt("Directory '{}' is not empty. Use is_recursive=true for empty directories " ..
                         "or wait for full recursive delete functionality.", self.source)
      end
    end
  else -- It's a file
    local content
    local pcall_read_ok, pcall_read_val = pcall(function() content = pl_file.read(self.source) end)
    if not pcall_read_ok then
      log.error(fmt("Failed to read file '{}' for deletion: {}", self.source, tostring(pcall_read_val)))
      return false, fmt("Failed to read file '{}' for deletion (pcall error): {}", 
                       self.source, tostring(pcall_read_val))
    end
    if content == nil and pcall_read_ok then
      -- This condition means pl_file.read itself returned nil, indicating an error like unreadability
      -- pcall_read_val would be nil in this case as it's the return of the function.
      -- A more explicit error from pl_file.read might be a second return value, not easily caught here.
      return false, fmt("Failed to read file '{}' for deletion: Penlight pl_file.read returned nil " ..
                       "(possibly unreadable).", self.source)
    end
    self.original_content = content

    local cs_result
    local pcall_cs_ok, pcall_cs_val = pcall(function() cs_result = Checksum.calculate_sha256(self.source) end)
    if not pcall_cs_ok then
      return false, fmt("Failed to calculate checksum for file '{}' (pcall error): {}", 
                       self.source, tostring(pcall_cs_val))
    end
    if not cs_result then
      return false, fmt("Failed to calculate checksum for file '{}': {}", 
                       self.source, pcall_cs_val or "checksum calculation failed")
    end
    self.checksum_data.original_checksum = cs_result
  end

  return true
end

function DeleteOperation:execute()
  if not pl_path.exists(self.source) then
    self.item_actually_deleted = false
    return true, fmt("Path '{}' already deleted.", self.source)
  end

  local pcall_ok, penlight_success, penlight_errmsg

  if self.original_path_was_directory then
    pcall_ok, penlight_success, penlight_errmsg = pcall(pl_dir.rmdir, self.source)
    if not pcall_ok then
      return false, fmt("Failed to delete directory '{}' (pcall error): {}", 
                       self.source, tostring(penlight_success)) -- penlight_success is error from pcall
    end
    if not penlight_success then
      return false, fmt("Failed to delete directory '{}': {}", 
                       self.source, penlight_errmsg or "unknown Penlight error")
    end
  else -- It's a file
    local os_remove_pcall_ok, os_remove_ret1, os_remove_ret2 = pcall(os.remove, self.source)
    if not os_remove_pcall_ok then
      return false, fmt("Failed to delete file '{}' (pcall error): {}", 
                       self.source, tostring(os_remove_ret1)) -- ret1 is error from pcall
    end
    if not os_remove_ret1 then -- os.remove failed (returned nil, errmsg)
      return false, fmt("Failed to delete file '{}': {}", 
                       self.source, os_remove_ret2 or "unknown OS error")
    end
  end

  self.item_actually_deleted = true
  return true
end

function DeleteOperation:undo()
  if not self.item_actually_deleted then
    return true, "Undo: Item was not marked as deleted by this operation."
  end

  if pl_path.exists(self.source) then
    return false, fmt("Undo: Path '{}' already exists, cannot undo delete.", self.source)
  end

  local pcall_ok, penlight_success, penlight_errmsg

  if self.original_path_was_directory then
    pcall_ok, penlight_success, penlight_errmsg = pcall(pl_dir.makedir, self.source)
    if not pcall_ok then
      return false, fmt("Undo: Failed to recreate directory '{}' (pcall error): {}", 
                       self.source, tostring(penlight_success))
    end
    if not penlight_success then
      return false, fmt("Undo: Failed to recreate directory '{}': {}", 
                       self.source, penlight_errmsg or "unknown Penlight error")
    end
  else -- It was a file
    if self.original_content == nil then
      -- This could happen if original file was empty and pl_file.read returned nil,
      -- or if validation failed to read content for some reason.
      -- For empty files, original_content would be "".
      return false, fmt("Undo: No original content stored (or content was nil), " ..
                       "cannot undo file deletion for '{}'", self.source)
    end

    pcall_ok, penlight_success, penlight_errmsg = pcall(pl_file.write, self.source, self.original_content)
    if not pcall_ok then
      return false, fmt("Undo: Failed to restore file '{}' (pcall error): {}", 
                       self.source, tostring(penlight_success))
    end
    if not penlight_success then
      return false, fmt("Undo: Failed to restore file '{}': {}", 
                       self.source, penlight_errmsg or "unknown Penlight error")
    end

    -- Verify Checksum
    local current_checksum
    local cs_pcall_ok, cs_pcall_val = pcall(function() 
      current_checksum = Checksum.calculate_sha256(self.source) 
    end)
    if not cs_pcall_ok then
      return false, fmt("Undo: Error calculating checksum for restored file '{}' (pcall error): {}", 
                       self.source, tostring(cs_pcall_val))
    end
    if not current_checksum then
      return false, fmt("Undo: Failed to calculate checksum for restored file '{}': {}", 
                       self.source, cs_pcall_val or "checksum calculation failed")
    end
    
    if current_checksum ~= self.checksum_data.original_checksum then
      return false, fmt("Undo: Checksum mismatch after restoring file '{}'. " ..
                       "Content may be corrupt. Expected: {}, Got: {}", 
                       self.source, 
                       self.checksum_data.original_checksum or "nil", 
                       current_checksum or "nil")
    end
  end
  
  self.item_actually_deleted = false
  return true
end

return DeleteOperation
