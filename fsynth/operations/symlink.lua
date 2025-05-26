local Operation = require("fsynth.operation_base")
-- always use the log module, no prints
local log = require("fsynth.log")
local pl_path = require("pl.path")
local pl_file = require("pl.file") -- Assuming pl.file.symlink exists
local pl_dir = require("pl.dir")
local fmt = require("string.format.all")
local lfs = require("lfs") -- Use LuaFileSystem directly for symlink operations
-- os.remove is a standard Lua function

---------------------------------------------------------------------
-- SymlinkOperation
---------------------------------------------------------------------
local SymlinkOperation = {}
SymlinkOperation.__index = SymlinkOperation
setmetatable(SymlinkOperation, { __index = Operation }) -- Inherit from Operation

function SymlinkOperation.new(link_target_path, link_path, options)
	log.debug("Creating new SymlinkOperation from %s to %s", link_target_path, link_path)
	-- self.source = the target path that the symlink will point to
	-- self.target = the symlink path itself
	local self = Operation.new(link_target_path, link_path, options)
	setmetatable(self, SymlinkOperation)
	self.options.create_parent_dirs = self.options.create_parent_dirs or false
	self.options.overwrite = self.options.overwrite or false
	self.link_actually_created = false
	self.original_target_was_file = false
	self.original_target_was_symlink = false
	self.original_target_data = nil
	return self
end

function SymlinkOperation:validate()
	log.debug("Validating SymlinkOperation from %s to %s", self.source, self.target)
	if not self.source or self.source == "" then
		local err_msg = "Link target path (source) not specified for SymlinkOperation"
		log.error(err_msg)
		return false, err_msg
	end
	if not self.target or self.target == "" then
		local err_msg = "Link path (target) not specified for SymlinkOperation"
		log.error(err_msg)
		return false, err_msg
	end

	-- Target Validation
	local target_exists = pl_path.exists(self.target)
	if target_exists then
		if not self.options.overwrite then
			local err_msg = fmt("Link path '{}' already exists and overwrite is false.", self.target)
			log.error(err_msg)
			return false, err_msg
		end
		-- If overwrite is true and target is a directory, fail
		if pl_path.isdir(self.target) then
			local err_msg = fmt("Cannot create symlink at '{}': path is a directory.", self.target)
			log.error(err_msg)
			return false, err_msg
		end
		-- If it exists, it's a file or a symlink, and overwrite is true.
		-- This is allowed, but we should record what's there for restoration.
		if pl_path.islink(self.target) then
			self.original_target_was_symlink = true
			self.original_target_data = lfs.symlinkattributes(self.target, "target")
		else
			self.original_target_was_file = true
			self.original_target_data = pl_file.read(self.target)
		end
	else
		-- Target does not exist; check parent directories
		if not self.options.create_parent_dirs then
			local parent_dir = pl_path.dirname(self.target)
			if parent_dir and parent_dir ~= "" and parent_dir ~= "." and not pl_path.isdir(parent_dir) then
				log.error("Parent directory of '%s' does not exist and create_parent_dirs is false.", self.target)
				return false, "No such file or directory"
			end
		end
	end
	log.debug("SymlinkOperation validation successful from %s to %s", self.source, self.target)
	return true
end

function SymlinkOperation:execute()
	log.info("Executing SymlinkOperation from %s to %s", self.source, self.target)

	-- Ensure validation has been run
	if self.original_target_data == nil and pl_path.exists(self.target) and self.options.overwrite then
		local valid, err = self:validate()
		if not valid then
			return false, err
		end
	end

	local ok, err_msg

	-- Create Parent Directories for Link Path (self.target)
	if self.options.create_parent_dirs then
		local parent_dir = pl_path.dirname(self.target)
		if parent_dir and parent_dir ~= "" and parent_dir ~= "." and not pl_path.isdir(parent_dir) then
			log.debug("Creating parent directory for symlink: %s", parent_dir)
			ok, err_msg = pcall(function()
				pl_dir.makepath(parent_dir)
			end)
			if not ok then
				err_msg = fmt("Failed to create parent directories for '{}': {}", self.target, tostring(err_msg))
				log.error(err_msg)
				return false, err_msg
			end
			log.info("Parent directory created: %s", parent_dir)
		end
	end

	-- Handle Existing Link Path (self.target)
	if pl_path.exists(self.target) then
		if self.options.overwrite then
			-- Double-check it's not a directory
			if pl_path.isdir(self.target) then
				err_msg = fmt("Cannot create symlink at '{}': path is a directory.", self.target)
				log.error(err_msg)
				return false, err_msg
			end
			-- So, it's either a file or a symlink.
			log.debug("Removing existing item for overwrite: %s", self.target)
			local removed_existing, remove_err = pcall(function()
				os.remove(self.target)
			end)
			if not removed_existing then
				err_msg = fmt("Failed to remove existing item at link path '{}': {}", self.target, tostring(remove_err))
				log.error(err_msg)
				return false, err_msg
			end
			log.info("Existing item removed for overwrite: %s", self.target)
		else
			-- This case should ideally be caught by validate(), but as a safeguard:
			err_msg = fmt("Link path '{}' already exists", self.target)
			log.error(err_msg)
			return false, err_msg
		end
	end

	-- Create Symlink
	-- lfs.symlink(target_path_for_link_content, path_of_link_itself)
	log.debug("Creating symlink from %s to %s", self.target, self.source)
	local ok, err_msg = pcall(function()
		return lfs.link(self.source, self.target, true)
	end)
	if not ok then
		err_msg = fmt("Failed to create symlink from '{}' to '{}': {}", self.target, self.source, tostring(err_msg))
		log.error(err_msg)
		return false, err_msg
	end
	-- pcall succeeded, err_msg is the result of lfs.link
	-- LuaFileSystem's lfs.link returns true on success, or nil plus error message on failure
	if not err_msg then
		err_msg = "No such file or directory"
		log.error("Failed to create symlink from '%s' to '%s': %s", self.target, self.source, err_msg)
		return false, err_msg
	end
	-- If err_msg is true, it means lfs.symlink succeeded.
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
		-- If symlink doesn't exist, we can still try to restore original if we overwrote something
		if self.original_target_was_file or self.original_target_was_symlink then
			-- Continue to restoration
		else
			local msg = fmt("Undo: Symlink at '{}' does not exist, no action taken.", self.target)
			log.info(msg)
			return true, msg
		end
	else
		if not pl_path.islink(self.target) then
			local err_msg = fmt("Undo: Item at '{}' is not a symlink, cannot safely undo.", self.target)
			log.warn(err_msg)
			return false, err_msg
		end

		log.debug("Removing symlink for undo: %s", self.target)
		local ok, err_msg = pcall(function()
			os.remove(self.target)
		end)
		if not ok then
			err_msg = fmt("Undo: Failed to delete symlink '{}': {}", self.target, tostring(err_msg))
			log.error(err_msg)
			return false, err_msg
		end
		log.info("Symlink successfully removed during undo: %s", self.target)
	end

	-- Restore original file or symlink if one was overwritten
	if self.original_target_was_file and self.original_target_data then
		log.debug("Restoring original file: %s", self.target)
		local ok, err_msg = pcall(function()
			pl_file.write(self.target, self.original_target_data)
		end)
		if not ok then
			err_msg = fmt("Undo: Failed to restore original file '{}': {}", self.target, tostring(err_msg))
			log.error(err_msg)
			return false, err_msg
		end
		log.info("Original file restored: %s", self.target)
	elseif self.original_target_was_symlink and self.original_target_data then
		log.debug("Restoring original symlink: %s -> %s", self.target, self.original_target_data)
		local ok, err_msg = pcall(function()
			return lfs.link(self.original_target_data, self.target, true)
		end)
		if not ok then
			err_msg = fmt("Undo: Failed to restore original symlink '{}': {}", self.target, tostring(err_msg))
			log.error(err_msg)
			return false, err_msg
		end
		log.info("Original symlink restored: %s", self.target)
	end

	return true
end

-- The Operation:checksum() method is inherited but not applicable/useful for symlinks
-- in the context of source file content verification. self.source is a path, not content.

return SymlinkOperation
