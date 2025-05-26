local Operation = require("fsynth.operation_base")
local Checksum = require("fsynth.checksum")
-- always use the log module, no prints
local log = require("fsynth.log")
local pl_path = require("pl.path")
local pl_file = require("pl.file")
local pl_dir = require("pl.dir")
local fmt = require("string.format.all")
local file_permissions = require("fsynth.file_permissions")
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

	-- File permissions mode to set after creation (e.g., "644", "755" on Unix-like systems;
	-- "444" for read-only, "666" for writable on Windows via this library's interpretation).
	-- If nil, system default permissions are used.
	self.options.mode = self.options.mode
	self.checksum_data.target_checksum = nil -- Specific to CreateFile, not in base Operation new()
	return self
end

function CreateFileOperation:validate()
	log.debug("Validating CreateFileOperation for target: %s", self.target or "nil")
	if not self.target or self.target == "" then
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

	local parent_dir_path = pl_path.dirname(self.target)
	if parent_dir_path == "" or parent_dir_path == "." then -- Current directory
		parent_dir_path = "."
	end

	-- Check if parent directory is writable before attempting to create the file
	if pl_path.exists(parent_dir_path) and pl_path.isdir(parent_dir_path) then
		local writable, write_err = file_permissions.is_writable(parent_dir_path)
		if not writable then
			err_msg = fmt(
				"Parent directory '{}' is not writable. Error: {}",
				parent_dir_path,
				write_err or "permission denied"
			)
			log.error(err_msg)
			return false, err_msg
		end
	elseif not self.options.create_parent_dirs then
		-- Parent doesn't exist and we are not allowed to create it
		err_msg = fmt("Parent directory '{}' does not exist and create_parent_dirs is false", parent_dir_path)
		log.error(err_msg)
		return false, err_msg
	end
	-- If parent_dir_path does not exist but create_parent_dirs is true, makepath will handle it later.

	-- Check if target is an existing directory
	if pl_path.isdir(self.target) then
		err_msg = fmt("Target '{}' is an existing directory", self.target)
		log.error(err_msg)
		return false, err_msg
	end

	-- Check if file already exists (exclusive mode)
	if pl_path.exists(self.target) then
		err_msg = fmt("File '{}' already exists", self.target)
		log.error(err_msg)
		return false, err_msg
	end

	-- Create Parent Directories
	if self.options.create_parent_dirs then
		local parent_dir = pl_path.dirname(self.target)
		if parent_dir and parent_dir ~= "" and parent_dir ~= "." and not pl_path.isdir(parent_dir) then
			log.debug("Creating parent directory: %s", parent_dir)
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

	-- Write File
	log.debug("Writing file: %s (%d bytes)", self.target, #self.options.content)
	ok, err_msg = pcall(function()
		pl_file.write(self.target, self.options.content)
	end)
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
		pcall(function()
			os.remove(self.target)
		end)
		err_msg = fmt("Failed to calculate checksum for created file '{}': {}", self.target, tostring(checksum_err))
		log.error(err_msg)
		return false, err_msg
	end
	self.checksum_data.target_checksum = new_checksum
	log.info("Target checksum stored: %s", self.checksum_data.target_checksum)

	-- Apply specified permissions if provided
	if self.options.mode then
		log.debug("Setting permissions on created file to: %s", self.options.mode)
		local perm_ok, perm_err = file_permissions.set_mode(self.target, self.options.mode)
		if not perm_ok then
			log.warn("Failed to set permissions on created file: %s", perm_err)
			-- We don't fail the operation if setting permissions fails
			-- Just log a warning
		end
	end

	return true
end

function CreateFileOperation:undo()
	log.info("Undoing CreateFileOperation for target: %s", self.target)
	local ok, err_msg

	if not pl_path.exists(self.target) then
		-- If the file doesn't exist, return false with error
		err_msg = fmt("File '{}' does not exist", self.target)
		log.error(err_msg)
		return false, err_msg
	end

	if not self.checksum_data.target_checksum then
		err_msg = fmt("No checksum recorded for '{}' at creation", self.target)
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
		err_msg = fmt(
			"File content of '{}' has changed since creation " .. "(checksum mismatch), cannot safely undo.",
			self.target
		)
		log.warn(err_msg)
		return false, err_msg
	end

	-- Delete the file
	log.debug("Deleting file for undo: %s", self.target)
	ok, err_msg = pcall(function()
		os.remove(self.target)
	end)
	if not ok then
		err_msg = fmt("Failed to delete file '{}' during undo: {}", self.target, tostring(err_msg))
		log.error(err_msg)
		return false, err_msg
	end
	log.info("File successfully deleted during undo: %s", self.target)

	return true
end

return CreateFileOperation
