local Operation = require("fsynth.operation_base")
local Checksum = require("fsynth.checksum")
local log = require("fsynth.log")
local pl_path = require("pl.path")
local pl_dir = require("pl.dir")
local fmt = require("string.format.all")
local file_permissions = require("fsynth.file_permissions")
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

	--- Whether to preserve file attributes (like permissions, timestamps) from source to target.
	-- Defaults to true. If false, target gets system default attributes.
	-- This is applied during the copy operation itself by `file_permissions.copy_with_attributes`.
	self.options.preserve_attributes = self.options.preserve_attributes
	if self.options.preserve_attributes == nil then
		self.options.preserve_attributes = true
	end

	--- Optional. A specific file mode (e.g., "644", "755" on Unix-like systems;
	-- "444" for read-only, "666" for writable on Windows via this library's interpretation)
	-- to set on the target file *after* it has been copied.
	-- If provided, this mode will be applied using `file_permissions.set_mode` after the copy,
	-- regardless of the `preserve_attributes` setting or the source file's original permissions.
	-- If nil, the permissions resulting from `preserve_attributes` (or system defaults
	-- if `preserve_attributes` is false) will remain.
	self.options.mode = self.options.mode

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
	-- Updated: Check if source is a directory
	if pl_path.isdir(self.source) then
		return false, fmt("Source path ('{}') is a directory, not a file.", self.source)
	end
	local source_exists = pl_path.isfile(self.source)
	log.debug("Source exists? %s", source_exists)
	if not source_exists then
		return false, fmt("Source path ('{}') is not a file or does not exist.", self.source)
	end

	-- Verify source readability
	local readable, read_err = file_permissions.is_readable(self.source)
	if not readable then
		return false, fmt("Source file '{}' is not readable. Error: {}", self.source, read_err or "permission denied")
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
			-- If target is a directory, we will copy into it.
			-- The actual target path will be checked in execute() or if a file with the same name exists.
			log.debug("Target path ('{}') is a directory. Will attempt to copy into it.", self.target)
		elseif not self.options.overwrite then
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
	local actual_target_path = self.target

	-- Handle if target is a directory
	if pl_path.isdir(self.target) then
		actual_target_path = pl_path.join(self.target, pl_path.basename(self.source))
		log.info("Target is a directory. Actual target path set to: %s", actual_target_path)

		-- If the file now exists in the directory and overwrite is false, fail
		if pl_path.exists(actual_target_path) and not self.options.overwrite then
			err_msg = fmt("Target file '{}' exists in directory and overwrite is false.", actual_target_path)
			log.error(err_msg)
			return false, err_msg
		end
	end

	local target_parent_dir_path = pl_path.dirname(actual_target_path)
	if target_parent_dir_path == "" or target_parent_dir_path == "." then
		target_parent_dir_path = "."
	end

	-- Check if target parent directory is writable
	if pl_path.exists(target_parent_dir_path) and pl_path.isdir(target_parent_dir_path) then
		local writable, write_err = file_permissions.is_writable(target_parent_dir_path)
		if not writable then
			err_msg =
				fmt("Target parent dir '{}' not writable. Error: {}", target_parent_dir_path, write_err or "denied")
			log.error(err_msg)
			return false, err_msg
		end
	elseif not self.options.create_parent_dirs then
		err_msg = fmt("Target parent dir '{}' not found " .. "and create_parent_dirs is false.", target_parent_dir_path)
		log.error(err_msg)
		return false, err_msg
	end
	-- If target_parent_dir_path does not exist but create_parent_dirs is true, makepath will handle it.

	-- Create Parent Directories for Target
	if self.options.create_parent_dirs then
		local parent_dir = pl_path.dirname(actual_target_path)
		if parent_dir and parent_dir ~= "" and parent_dir ~= "." and not pl_path.isdir(parent_dir) then
			ok, err_msg = pcall(function()
				pl_dir.makepath(parent_dir)
			end)
			if not ok then
				return false,
					fmt("Failed to create parent directories for '{}': {}", actual_target_path, tostring(err_msg))
			end
		end
	end

	-- Note: Backup of original target if self.options.overwrite is true is not implemented here.
	-- pl_file.copy in Penlight should handle overwriting if the target file exists.

	-- Copy File
	log.info("Attempting to copy %s to %s", self.source, actual_target_path)
	ok, err_msg = pcall(function()
		-- Use our custom copy function that preserves attributes based on platform
		log.debug(
			"Using file_permissions.copy_with_attributes with preserve_attributes=%s",
			self.options.preserve_attributes
		)
		local result =
			file_permissions.copy_with_attributes(self.source, actual_target_path, self.options.preserve_attributes)
		log.debug("copy_with_attributes result: %s", result)
		return result
	end)
	log.debug("pcall result: %s, type: %s", ok, type(err_msg))

	if not ok then
		log.error("pcall failed: %s", err_msg)
		return false,
			fmt("Failed to copy file from '{}' to '{}': {}", self.source, actual_target_path, tostring(err_msg))
	end
	if type(err_msg) ~= "boolean" or err_msg == false then
		log.error("pl_file.copy returned non-success: %s, %s", type(err_msg), err_msg)
		return false,
			fmt("Failed to copy file from '{}' to '{}': {}", self.source, actual_target_path, tostring(err_msg))
	end

	-- Record Target Checksum
	log.debug("Calculating target checksum for: %s", actual_target_path)
	local new_target_checksum, checksum_target_err = Checksum.calculate_sha256(actual_target_path)
	log.debug("Target checksum result: %s, %s", new_target_checksum, checksum_target_err)

	-- Apply specified permissions if provided
	if self.options.mode then
		log.debug("Setting permissions on target file to: %s", self.options.mode)
		local perm_ok, perm_err = file_permissions.set_mode(actual_target_path, self.options.mode)
		if not perm_ok then
			log.warn("Failed to set permissions on target file: %s", perm_err)
		end
	end
	if not new_target_checksum then
		log.error("Failed to calculate target checksum: %s", checksum_target_err)
		pcall(function()
			os.remove(actual_target_path)
		end)
		return false,
			fmt(
				"Failed to calculate checksum for copied file '{}': {}",
				actual_target_path,
				tostring(checksum_target_err)
			)
	end
	self.checksum_data.target_checksum = new_target_checksum
	self.actual_target_path_used_for_execute = actual_target_path
	log.info("Target checksum stored: %s for path %s", self.checksum_data.target_checksum, actual_target_path)

	return true
end

function CopyFileOperation:undo()
	local ok, err_msg
	local path_to_undo = self.actual_target_path_used_for_execute or self.target

	if not pl_path.exists(path_to_undo) then
		return true,
			fmt("Target file '{}' does not exist, undo operation is a no-op or file already removed.", path_to_undo)
	end

	if not self.checksum_data.target_checksum then
		return false, fmt("No target checksum recorded for '{}' from execution, cannot safely undo.", path_to_undo)
	end

	local current_target_checksum, checksum_err = Checksum.calculate_sha256(path_to_undo)
	if not current_target_checksum then
		return false,
			fmt(
				"Failed to calculate checksum for target file '{}' during undo: {}",
				path_to_undo,
				tostring(checksum_err)
			)
	end

	if current_target_checksum ~= self.checksum_data.target_checksum then
		return false,
			"Copied file content of '" .. fmt(
				"'{}' has changed since operation (checksum mismatch), cannot safely undo.",
				path_to_undo
			) .. "'"
	end

	-- Delete the copied file
	ok, err_msg = pcall(function()
		os.remove(path_to_undo)
	end)
	if not ok then
		return false, fmt("Failed to delete copied file '{}' during undo: {}", path_to_undo, tostring(err_msg))
	end

	self.undone_pomoci_zalohy = false -- As we are just deleting.
	return true
end

return CopyFileOperation
