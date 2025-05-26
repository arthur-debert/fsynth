local Operation = require("fsynth.operation_base")
-- always use the log module, no prints
local log = require("fsynth.log")
local pl_path = require("pl.path")
local pl_dir = require("pl.dir")
local fmt = require("string.format.all")
-- os.remove for undo, or pl_dir.rmdir

---------------------------------------------------------------------
-- CreateDirectoryOperation
---------------------------------------------------------------------
local CreateDirectoryOperation = {}
CreateDirectoryOperation.__index = CreateDirectoryOperation
setmetatable(CreateDirectoryOperation, { __index = Operation }) -- Inherit from Operation

function CreateDirectoryOperation.new(dir_path, options)
	log.debug("Creating new CreateDirectoryOperation for: %s", dir_path)
	local self = Operation.new(nil, dir_path, options)
	setmetatable(self, CreateDirectoryOperation)

	self.options.exclusive = self.options.exclusive or false
	-- Default create_parent_dirs to true if not specified
	self.options.create_parent_dirs = self.options.create_parent_dirs == nil and true or self.options.create_parent_dirs

	self.dir_actually_created_by_this_op = false
	return self
end

function CreateDirectoryOperation:validate()
	log.debug("Validating CreateDirectoryOperation for: %s", self.target)
	if not self.target then
		local err_msg = "Target directory path not specified for CreateDirectoryOperation"
		log.error(err_msg)
		return false, err_msg
	end

	if pl_path.exists(self.target) then
		if pl_path.isfile(self.target) then
			local err_msg = fmt("Target path '{}' exists and is a file.", self.target)
			log.error(err_msg)
			return false, err_msg
		end
		if self.options.exclusive and pl_path.isdir(self.target) then
			local err_msg = fmt("Directory '{}' already exists and operation is exclusive.", self.target)
			log.error(err_msg)
			return false, err_msg
		end
	else
		if not self.options.create_parent_dirs then
			local parent_dir = pl_path.dirname(self.target)
			if parent_dir and parent_dir ~= "" and parent_dir ~= "." and not pl_path.isdir(parent_dir) then
				local err_msg =
					fmt("Parent directory of '{}' does not exist and create_parent_dirs is false.", self.target)
				log.error(err_msg)
				return false, err_msg
			end
		end
	end
	log.debug("Directory operation validation successful for: %s", self.target)
	return true
end

function CreateDirectoryOperation:execute()
	log.info("Executing CreateDirectoryOperation for: %s", self.target)
	local err_msg
	local path_existed_as_dir_before_op = pl_path.isdir(self.target)

	if path_existed_as_dir_before_op and not self.options.exclusive then
		log.info("Directory already exists, no need to create: %s", self.target)
		self.dir_actually_created_by_this_op = false
		return true
	end

	if pl_path.exists(self.target) and not path_existed_as_dir_before_op then -- e.g. it's a file
		err_msg = fmt("Target path '{}' exists and is not a directory.", self.target)
		log.error(err_msg)
		return false, err_msg
	end

	local creation_success_flag -- Penlight's direct success (true) or failure (nil)
	local pcall_success, pcall_err_or_val

	if self.options.create_parent_dirs then
		log.debug("Creating directory with parent directories: %s", self.target)
		pcall_success, pcall_err_or_val = pcall(function()
			return pl_dir.makepath(self.target)
		end)
	else
		log.debug("Creating directory without parent directories: %s", self.target)
		pcall_success, pcall_err_or_val = pcall(function()
			return pl_dir.makedir(self.target)
		end)
	end

	if not pcall_success then
		err_msg = fmt("Failed to create directory '{}' (pcall error): {}", self.target, tostring(pcall_err_or_val))
		log.error(err_msg)
		return false, err_msg
	end

	-- If pcall succeeded, pcall_err_or_val is the first return value of the called function
	-- For pl_dir.makepath/makedir, success is true. If they fail, they return (nil, message).
	-- This logic is a bit complex due to dual error reporting. Let's simplify:
	-- If pcall_success is true, and pcall_err_or_val is true, then it's definitely a success.
	-- If pcall_success is true, but pcall_err_or_val is nil (meaning pl_dir.makepath/dir
	-- returned nil, msg), then it's a Penlight-reported error.
	-- Let's re-pcall to get both returns properly.

	if self.options.create_parent_dirs then
		pcall_success, creation_success_flag, err_msg = pcall(pl_dir.makepath, self.target)
	else
		pcall_success, creation_success_flag, err_msg = pcall(pl_dir.makedir, self.target)
	end

	if not pcall_success then
		err_msg = fmt("Failed to create directory '{}' (pcall error): {}", self.target, tostring(creation_success_flag))
		log.error(err_msg)
		return false, err_msg
	end
	if not creation_success_flag then -- Penlight function returned nil, msg
		err_msg = fmt("Failed to create directory '{}': {}", self.target, err_msg or "unknown Penlight error")
		log.error(err_msg)
		return false, err_msg
	end

	-- If we reached here, directory operation was successful
	if not path_existed_as_dir_before_op then
		self.dir_actually_created_by_this_op = true
		log.info("Directory successfully created: %s", self.target)
	else
		log.info("Directory already existed: %s", self.target)
	end

	return true
end

function CreateDirectoryOperation:undo()
	log.info("Undoing CreateDirectoryOperation for: %s", self.target)
	if not self.dir_actually_created_by_this_op then
		local msg = fmt("Undo: Directory '{}' was not marked as created by this operation.", self.target)
		log.info(msg)
		return true, msg
	end

	if not pl_path.isdir(self.target) then
		self.dir_actually_created_by_this_op = false
		local err_msg = fmt("Undo: Target '{}' is not a directory or does not exist.", self.target)
		log.warn(err_msg)
		return false, err_msg
	end

	-- Safety Check: Directory must be empty
	local content_files, content_dirs
	local ok_files, err_files_or_data = pcall(function()
		content_files = pl_dir.getfiles(self.target)
		return content_files
	end)
	if not ok_files then
		return false, fmt("Undo: Error listing files in '{}': {}", self.target, tostring(err_files_or_data))
	end
	-- if ok_files is true, err_files_or_data is the actual table of files

	local ok_dirs, err_dirs_or_data = pcall(function()
		content_dirs = pl_dir.getsubdirs(self.target)
		return content_dirs
	end)
	if not ok_dirs then
		return false, fmt("Undo: Error listing subdirectories in '{}': {}", self.target, tostring(err_dirs_or_data))
	end
	-- if ok_dirs is true, err_dirs_or_data is the actual table of dirs

	if (err_files_or_data and next(err_files_or_data)) or (err_dirs_or_data and next(err_dirs_or_data)) then
		local err_msg = fmt("Undo: Directory '{}' is not empty, cannot safely undo.", self.target)
		log.warn(err_msg)
		return false, err_msg
	end

	-- Remove the directory
	local rmdir_pcall_ok, rmdir_pcall_val1, rmdir_pcall_val2 = pcall(pl_dir.rmdir, self.target)

	if not rmdir_pcall_ok then
		local err_msg =
			fmt("Undo: Failed to remove directory '{}' (pcall error): {}", self.target, tostring(rmdir_pcall_val1))
		log.error(err_msg)
		return false, err_msg
	end
	if not rmdir_pcall_val1 then -- Penlight rmdir returned nil, msg
		local err_msg =
			fmt("Undo: Failed to remove directory '{}': {}", self.target, rmdir_pcall_val2 or "unknown Penlight error")
		log.error(err_msg)
		return false, err_msg
	end

	log.info(fmt("Directory successfully removed during undo: {}", self.target))
	self.dir_actually_created_by_this_op = false
	return true
end

return CreateDirectoryOperation
