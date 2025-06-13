local Operation = require("fsynth.operation_base")
local Checksum = require("fsynth.checksum")
local pl_path = require("pl.path")
local pl_file = require("pl.file")
local pl_dir = require("pl.dir")
local lfs = require("lfs")
-- always use the logger module, no prints
local logger = require("lual").logger()
local fmt = require("string.format.all")
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
	self.item_type = nil
	self.original_link_target = nil

	return self
end

function DeleteOperation:validate()
	logger.debug("Validating DeleteOperation for: %s", self.source or "nil")
	if not self.source or self.source == "" then
		return false, "Path to delete not specified for DeleteOperation"
	end

	-- Try to get attributes of the link itself first
	local link_attrs_mode = lfs.symlinkattributes(self.source, "mode")

	if link_attrs_mode == "link" then
		self.item_type = "symlink"
		logger.debug("Validate Delete: Item '{}' is a symlink.", self.source)
		local pcall_ok, link_target = pcall(lfs.symlinkattributes, self.source, "target")
		if not pcall_ok or link_target == nil then
			logger.warn(
				fmt(
					"Could not read target of symlink '{}' (possibly broken): {}",
					self.source,
					tostring(link_target or (pcall_ok and "nil") or "pcall error")
				)
			)
			self.original_link_target = nil
		else
			self.original_link_target = link_target
			logger.debug("Validate Delete: Symlink '{}' points to '{}'.", self.source, self.original_link_target)
		end
		self.original_content = nil
		self.checksum_data.original_checksum = nil
	else
		-- Not a link (or lfs.symlinkattributes failed to identify it as such), try general attributes
		local attrs = lfs.attributes(self.source)
		if not attrs then
			if not pl_path.exists(self.source) then
				logger.warn("Validate Delete: Path '{}' does not exist.", self.source)
				return false, fmt("Path to delete '{}' does not exist.", self.source)
			end
			return false, fmt("Unable to get attributes for path '{}'. It might be inaccessible.", self.source)
		end

		if attrs.mode == "directory" then
			self.item_type = "directory"
			logger.debug("Validate Delete: Item '{}' is a directory.", self.source)
			-- Check if directory is empty (recursive delete not fully supported yet)
			local files, dirs
			local pcall_ok_files, pcall_val_files = pcall(function()
				files = pl_dir.getfiles(self.source)
			end)
			local pcall_ok_dirs, pcall_val_dirs = pcall(function()
				dirs = pl_dir.getdirectories(self.source)
			end)

			if not pcall_ok_files or not pcall_ok_dirs then
				return false,
					fmt(
						"Error checking if directory '{}' is empty: files_err={}, dirs_err={}",
						self.source,
						tostring(pcall_val_files),
						tostring(pcall_val_dirs)
					)
			end

			-- Penlight's getfiles/getdirectories return empty tables if dir is empty, not nil.
			local is_not_empty = (#files > 0) or (#dirs > 0)

			if is_not_empty and not self.options.is_recursive then
				return false, fmt("Directory '{}' is not empty and recursive delete is not enabled.", self.source)
			elseif is_not_empty and self.options.is_recursive then
				-- Placeholder for future recursive delete loggeric if needed.
				-- For now, even with is_recursive, we only support deleting if it was emptied by other means or is inherently empty.
				-- Or, this could be where we list contents for a full recursive delete op.
				logger.warn(
					"Validate Delete: Directory '{}' is not empty. Non-empty recursive delete not yet implemented, will likely fail in execute unless emptied first.",
					self.source
				)
				-- We can let it pass validation and os.remove in execute will fail if not empty.
			end
			self.original_content = nil
			self.checksum_data.original_checksum = nil
		else -- Assume file if not link or directory
			self.item_type = "file"
			logger.debug("Validate Delete: Item '{}' is a file.", self.source)
			local content
			local pcall_read_ok, pcall_read_val = pcall(function()
				content = pl_file.read(self.source)
			end)
			if not pcall_read_ok then
				return false,
					fmt(
						"Failed to read file '{}' for deletion (pcall error): {}",
						self.source,
						tostring(pcall_read_val)
					)
			end
			if content == nil then -- pl_file.read returns nil on error (e.g., unreadable)
				logger.warn(
					fmt(
						"File '{}' content is nil (unreadable or access error?). Original content for undo will be empty string.",
						self.source
					)
				)
				self.original_content = "" -- Store empty string for undo if unreadable
			else
				self.original_content = content
			end

			local cs_result
			local pcall_cs_ok, pcall_cs_val = pcall(function()
				cs_result = Checksum.calculate_sha256(self.source)
			end)
			if not pcall_cs_ok then
				return false,
					fmt(
						"Failed to calculate checksum for file '{}' (pcall error): {}",
						self.source,
						tostring(pcall_cs_val)
					)
			end
			if not cs_result then
				logger.warn(
					fmt(
						"Failed to calculate checksum for file '{}' (result was nil). Storing nil checksum.",
						self.source
					)
				)
				self.checksum_data.original_checksum = nil
			else
				self.checksum_data.original_checksum = cs_result
				logger.debug("Validate Delete: Stored checksum {} for file '{}'", cs_result, self.source)
			end
		end
	end

	logger.debug("DeleteOperation validated successfully for: %s", self.source)
	return true
end

function DeleteOperation:execute()
	logger.info("Execute Delete: Attempting for '%s' (intended type: %s)", self.source, self.item_type or "unknown")

	if self.item_type == nil then
		logger.debug("Execute Delete: item_type not set, running validate() first.")
		local valid, validate_err = self:validate()
		if not valid then
			if validate_err and type(validate_err) == "string" and validate_err:match("does not exist") then
				self.item_actually_deleted = false
				logger.info(
					"Execute Delete: Validation confirmed path '%s' does not exist. Tolerant success.",
					self.source
				)
				return true
			end
			logger.error("Execute Delete: Validation failed for '%s': %s", self.source, validate_err)
			return false, validate_err
		end
		if self.item_type == nil then -- Should be set by validate if successful
			local msg = fmt("Execute Delete: Validation ran but item_type still nil for '%s'. Aborting.", self.source)
			logger.error(msg)
			return false, msg
		end
	end

	-- Re-check existence with lfs.attributes just before deletion for an accurate state.
	local attrs = lfs.attributes(self.source)
	if not attrs then
		self.item_actually_deleted = false
		logger.info(
			"Execute Delete: Path '%s' not found or inaccessible immediately before os.remove. Tolerant success.",
			self.source
		)
		return true -- If it's gone now, consider the job done.
	end

	logger.debug("Execute Delete: Proceeding with os.remove for '%s' (actual mode via lfs: %s)", self.source, attrs.mode)
	local remove_pcall_ok, remove_success, remove_err_msg = pcall(os.remove, self.source)

	if not remove_pcall_ok then                                                                           -- pcall itself failed
		local err =
			fmt("Failed to delete '%s' (pcall error during os.remove): %s", self.source, tostring(remove_success)) -- remove_success is the error in this case
		logger.error(err)
		return false, err
	end

	if not remove_success then -- os.remove returned nil (failure)
		local err = fmt("Failed to delete '%s': %s", self.source, remove_err_msg or "unknown OS error from os.remove")
		logger.error(err)
		return false, err
	end

	logger.info("Execute Delete: Successfully deleted '%s'", self.source)
	self.item_actually_deleted = true
	return true
end

function DeleteOperation:undo()
	logger.info(
		"Undo Delete: Attempting for path '%s' (original type: %s)",
		self.source or "unknown",
		self.item_type or "unknown"
	)

	if not self.item_actually_deleted then
		logger.info(
			"Undo Delete: Item was not marked as deleted by this operation for '%s'. No action required.",
			self.source or "unknown"
		)
		return true, "Undo: Item was not marked as deleted by this operation."
	end

	if pl_path.exists(self.source) then
		local err = fmt("Undo Delete: Path '%s' already exists, cannot undo delete to avoid overwrite.", self.source)
		logger.warn(err)
		return false, err
	end

	local pcall_ok, success_flag, op_errmsg

	if self.item_type == "directory" then
		logger.info("Undo Delete: Recreating directory '%s'", self.source)
		pcall_ok, success_flag, op_errmsg = pcall(pl_path.mkdir, self.source)
		if not pcall_ok or not success_flag then
			local err = fmt(
				"Undo Delete: Failed to recreate directory '%s': %s",
				self.source,
				tostring(op_errmsg or (pcall_ok and success_flag) or "pcall error")
			)
			logger.error(err)
			return false, err
		end
		logger.info("Undo Delete: Directory '%s' recreated.", self.source)
	elseif self.item_type == "symlink" then
		if self.original_link_target == nil then
			logger.warn(
				fmt(
					"Undo Delete: Cannot recreate symlink '%s' as original target was nil (possibly a broken link that couldn't be read).",
					self.source
				)
			)
			-- This is a tricky case. If the original link was broken and we deleted it,
			-- we can't recreate it as it was. Failing might be safer.
			return false, "Undo Delete: Original symlink target was not recorded (possibly broken link)."
		end
		logger.info("Undo Delete: Recreating symlink '%s' -> '%s'", self.source, self.original_link_target)
		pcall_ok, success_flag, op_errmsg = pcall(lfs.link, self.original_link_target, self.source, true)
		if not pcall_ok or not success_flag then                 -- lfs.link returns true on success, or (nil, error message)
			local err_detail = op_errmsg
			if pcall_ok and success_flag == nil and op_errmsg == nil then -- lfs.link can return (nil, nil) on some errors
				err_detail = "lfs.link failed without specific error message"
			end
			local err = fmt(
				"Undo Delete: Failed to recreate symlink '%s': %s",
				self.source,
				tostring(err_detail or (pcall_ok and success_flag) or "pcall error")
			)
			logger.error(err)
			return false, err
		end
		logger.info("Undo Delete: Symlink '%s' recreated.", self.source)
	elseif self.item_type == "file" then
		if self.original_content == nil then
			local err = fmt(
				"Undo Delete: No original content stored (was nil or unreadable), cannot accurately undo file deletion for '%s'.",
				self.source
			)
			logger.error(err)
			-- Decide if we should create an empty file or fail. Failing seems safer if content is unknown.
			return false, err
		end
		logger.info("Undo Delete: Recreating file '%s'", self.source)
		pcall_ok, success_flag, op_errmsg = pcall(pl_file.write, self.source, self.original_content)
		if not pcall_ok or not success_flag then
			local err = fmt(
				"Undo Delete: Failed to restore file '%s': %s",
				self.source,
				tostring(op_errmsg or (pcall_ok and success_flag) or "pcall error")
			)
			logger.error(err)
			return false, err
		end
		logger.info("Undo Delete: File '%s' recreated.", self.source)

		-- Verify Checksum for files if original checksum was available
		if not self.checksum_data.original_checksum then
			local err = fmt(
				"Undo Delete: Original checksum not available for file '%s'. Cannot verify integrity and ensure safe undo.",
				self.source
			)
			logger.error(err)
			return false, err -- FAIL if original_checksum was nil
		end

		-- If original_checksum IS available, proceed to verify current against it (mismatch is a warning)
		logger.debug(
			"Undo Delete: Verifying checksum for restored file '%s' against original '%s'",
			self.source,
			self.checksum_data.original_checksum
		)
		local current_checksum
		local cs_pcall_ok, cs_pcall_val = pcall(function()
			current_checksum = Checksum.calculate_sha256(self.source)
		end)
		if not cs_pcall_ok or not current_checksum then
			logger.warn(
				fmt(
					"Undo Delete: Failed to calculate checksum for restored file '%s': {}. Continuing undo.",
					self.source,
					tostring(cs_pcall_val or "checksum calculation failed")
				)
			)
		elseif current_checksum ~= self.checksum_data.original_checksum then
			logger.warn(
				fmt(
					"Undo Delete: Checksum mismatch for restored file '%s'. Expected: {}, Got: {}. Continuing undo.",
					self.source,
					self.checksum_data.original_checksum,
					current_checksum
				)
			)
		else
			logger.debug("Undo Delete: Checksum verified for restored file '%s'.", self.source)
		end
	else
		local err = fmt(
			"Undo Delete: Unknown item_type '%s' for path '%s'. Cannot perform undo.",
			self.item_type or "nil",
			self.source
		)
		logger.error(err)
		return false, err
	end

	self.item_actually_deleted = false -- Reset flag after successful undo
	logger.info("Undo Delete: Successfully completed for '%s'", self.source)
	return true
end

return DeleteOperation
