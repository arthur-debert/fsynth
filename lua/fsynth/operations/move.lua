local Operation = require("fsynth.operation_base")
local Checksum = require("fsynth.checksum")
local pl_path = require("pl.path")
local pl_file = require("pl.file") -- Not directly used for move, but good to have for consistency if needed later
local pl_dir = require("pl.dir")
local lfs = require("lfs")
-- always use the log module, no prints
local log = require("fsynth.logging")
local fmt = require("string.format.all")

---------------------------------------------------------------------
-- MoveOperation
---------------------------------------------------------------------
local MoveOperation = {}
MoveOperation.__index = MoveOperation
setmetatable(MoveOperation, { __index = Operation }) -- Inherit from Operation

function MoveOperation.new(source_path, target_path, options)
	local self = Operation.new(source_path, target_path, options)
	setmetatable(self, MoveOperation)

	self.options.overwrite = self.options.overwrite or false
	self.options.create_parent_dirs = self.options.create_parent_dirs or false
	-- self.options.move_into_if_target_is_dir = true -- DECISION: This is now default behavior

	self.was_directory = nil -- Set in validate(): true if source is a directory
	self.original_target_existed_and_was_overwritten = false
	self.target_is_directory_move_into = false -- Set in validate(): true if source is file and target is existing dir
	self.actual_target_path = nil -- Set in execute(): final path where source was moved, esp. if moved into dir

	self.source_is_symlink = false -- Set in validate(): true if source itself is a symlink
	self.source_symlink_target = nil -- Set in validate(): the path the source symlink pointed to

	self.checksum_data.initial_source_checksum = nil
	self.checksum_data.final_target_checksum = nil

	return self
end

function MoveOperation:validate()
	if not self.source or self.source == "" then
		return false, "Source path not specified for MoveOperation"
	end
	if not self.target or self.target == "" then
		return false, "Target path not specified for MoveOperation"
	end

	-- DECISION: Moving a path to itself is an error, similar to POSIX mv.
	if self.source == self.target then
		return false, fmt("Source path '{}' and target path '{}' are the same.", self.source, self.target)
	end

	-- Source Validation
	local source_link_mode = lfs.symlinkattributes(self.source, "mode") -- Attempt to get mode of link itself
	self.source_is_symlink = (source_link_mode == "link")

	if self.source_is_symlink then
		log.debug("Validate Move: Source '{}' is a symlink.", self.source)
		local pcall_ok, link_target_str = pcall(lfs.symlinkattributes, self.source, "target")
		if not pcall_ok or link_target_str == nil then
			log.warn(
				fmt(
					"Could not read target of source symlink '{}' (possibly broken): {}. Will proceed with move.",
					self.source,
					tostring(link_target_str or (pcall_ok and "nil") or "pcall error")
				)
			)
			self.source_symlink_target = nil
		else
			self.source_symlink_target = link_target_str
			log.debug("Validate Move: Source symlink '{}' points to '{}'.", self.source, self.source_symlink_target)
		end
		-- For symlinks, was_directory refers to what the link *points to* for target compatibility checks.
		-- If the link is broken, treat it as not pointing to a directory for conservatism.
		self.was_directory = pl_path.isdir(self.source) -- pl_path.isdir resolves the link
		self.checksum_data.initial_source_checksum = nil -- No content checksum for symlink itself
	else
		-- Not a symlink (or lfs.symlinkattributes didn't say "link"), so use lfs.attributes for regular file/dir
		local source_attrs = lfs.attributes(self.source)
		if not source_attrs then
			-- This implies source doesn't exist or is inaccessible if symlink check also failed to identify it.
			return false, fmt("Source path '{}' does not exist or is inaccessible.", self.source)
		end
		self.was_directory = (source_attrs.mode == "directory")
		if not self.was_directory then -- Source is a regular file
			log.debug("Validate Move: Source '{}' is a file.", self.source)
			local success, result = pcall(Checksum.calculate_sha256, self.source)
			if not success or not result then
				return false,
					fmt(
						"Failed to calculate initial checksum for source file '{}': {}",
						self.source,
						tostring(result or "pcall error")
					)
			end
			self.checksum_data.initial_source_checksum = result
			log.debug("Validate Move: Initial checksum for source file '{}': {}", self.source, result)
		else
			log.debug("Validate Move: Source '{}' is a directory.", self.source)
			-- No checksum for directories
			self.checksum_data.initial_source_checksum = nil
		end
	end

	-- Target Validation
	if pl_path.exists(self.target) then
		local target_is_dir = pl_path.isdir(self.target) -- Note: pl_path.isdir resolves symlinks

		if not self.was_directory and target_is_dir then
			-- Source is a file, target is an existing directory: This is a "move into" case.
			self.target_is_directory_move_into = true
			-- The actual file to check for overwrite would be self.target / basename(self.source)
			-- This check will happen in execute() before the move.
			log.debug(
				"Validate: Source (file/symlink-to-file) '{}', target '{}' is directory. Will attempt to move into directory.",
				self.source,
				self.target
			)
		elseif self.source_is_symlink and target_is_dir then
			-- If source IS a symlink (regardless of what it points to) and target is an existing directory
			-- this is also a move-into case for the symlink itself.
			self.target_is_directory_move_into = true
			log.debug(
				"Validate Move: Source (symlink) '{}', target '{}' is directory. Will attempt to move symlink into directory.",
				self.source,
				self.target
			)
		else
			-- Standard overwrite logic
			self.target_is_directory_move_into = false
			if not self.options.overwrite then
				return false, fmt("Target path '{}' already exists and overwrite is false.", self.target)
			end
			-- If overwrite is true:
			if self.was_directory and not target_is_dir then -- Moving a dir (or symlink-to-dir) onto a file
				return false,
					fmt("Cannot move a directory-like source '{}' onto an existing file '{}'", self.source, self.target)
			end
			-- Case: moving a file-like source (file or symlink-to-file) onto an existing directory, but NOT move-into logic (e.g. target was not a dir initially)
			-- This should be caught if target_is_directory_move_into is false, and types mismatch.
			if not self.was_directory and target_is_dir and not self.target_is_directory_move_into then
				return false,
					fmt(
						"Cannot move file-like source '{}' onto directory '{}' when not in move-into mode.",
						self.source,
						self.target
					)
			end
			log.debug(
				"Validate Move: Target '{}' exists and overwrite is true. Type compatibility checked.",
				self.target
			)
		end
	else -- Target does not exist
		self.target_is_directory_move_into = false -- Can't move into a non-existent directory
		if not self.options.create_parent_dirs then
			local parent_dir = pl_path.dirname(self.target)
			if parent_dir and parent_dir ~= "" and parent_dir ~= "." and not pl_path.isdir(parent_dir) then
				if pl_path.isfile(parent_dir) then
					return false, fmt("Cannot create target '{}', parent '{}' is a file.", self.target, parent_dir)
				end
				return false,
					fmt(
						"Parent directory '{}' for target '{}' does not exist and create_parent_dirs is false.",
						parent_dir,
						self.target
					)
			end
		end
	end

	log.debug(
		"Validate Move: Validation successful for '%s' -> '%s'. source_is_symlink: %s, target_is_directory_move_into: %s",
		self.source,
		self.target,
		tostring(self.source_is_symlink),
		tostring(self.target_is_directory_move_into)
	)
	return true
end

function MoveOperation:execute()
	log.info(
		"Execute Move: '%s' -> '%s' (Overwrite: %s, CreateParents: %s)",
		self.source,
		self.target,
		tostring(self.options.overwrite),
		tostring(self.options.create_parent_dirs)
	)
	-- Ensure validation has been run or run it now
	if self.was_directory == nil or (pl_path.exists(self.target) and self.target_is_directory_move_into == nil) then -- Re-validate if critical flags aren't set
		log.debug("Execute Move: Critical validation flags not set, re-validating.")
		local valid, err = self:validate()
		if not valid then
			log.error("Execute Move: Validation failed for '%s' -> '%s': %s", self.source, self.target, err)
			return false, err
		end
	end

	-- Determine the actual target path
	self.actual_target_path = self.target
	if self.target_is_directory_move_into then
		self.actual_target_path = pl_path.join(self.target, pl_path.basename(self.source))
		log.debug("Execute Move: Target is directory, actual_target_path set to '%s'", self.actual_target_path)
	end

	-- Check if source still exists before attempting move
	if not pl_path.exists(self.source) then
		local err = fmt("Execute Move: Source path '%s' disappeared after validation.", self.source)
		log.error(err)
		return false, err -- Or potentially true if tolerant, but this is unexpected after validation
	end

	-- Handle target existence and overwrite for the actual_target_path
	local actual_target_existed_before_move = pl_path.exists(self.actual_target_path)
	self.original_target_existed_and_was_overwritten = false -- Reset for this execution attempt

	if actual_target_existed_before_move then
		if not self.options.overwrite then
			local err = fmt("Target path '%s' already exists and overwrite is false.", self.actual_target_path)
			log.error(err)
			return false, err
		end
		-- If overwrite is true, we need to check type compatibility for the actual_target_path
		local actual_target_is_dir = pl_path.isdir(self.actual_target_path)
		if self.was_directory and not actual_target_is_dir then -- Moving a dir onto a file
			local err = fmt("Cannot move directory '%s' onto existing file '%s'", self.source, self.actual_target_path)
			log.error(err)
			return false, err
		end
		if not self.was_directory and actual_target_is_dir then -- Moving a file onto a dir (should not happen if target_is_directory_move_into was false)
			-- This case implies self.target_is_directory_move_into was false, but actual_target_path somehow became a directory.
			-- This path should ideally not be reached if logic is correct. If it is, it's an overwrite of a directory by a file.
			local err = fmt(
				"Cannot move file '%s' onto existing directory '%s' without explicit move-into logic handled.",
				self.source,
				self.actual_target_path
			)
			log.error(err)
			return false, err
		end
		-- If types are compatible for overwrite (file->file, dir->dir), or if actual_target_path was constructed for move-into
		log.info("Execute Move: Target '%s' exists and will be overwritten.", self.actual_target_path)
		self.original_target_existed_and_was_overwritten = true
		-- Note: Actual backup of the overwritten item is NOT implemented here for simplicity.
		-- For directories, pl_file.move might require the target directory to be empty for overwrite on some systems/Lua versions if not replacing.
		-- However, standard `mv` behavior for `mv dir1 dir2` (where dir2 exists) is to move dir1 *into* dir2 if dir2 is a directory.
		-- `pl_file.move` might replace dir2 if it's empty or an OS rename allows replacing non-empty. This needs care.
		-- For now, we assume pl_file.move handles directory overwrites as per its capabilities.
	end

	local pcall_success
	-- Create Parent Directories for actual_target_path
	if self.options.create_parent_dirs then
		local parent_dir = pl_path.dirname(self.actual_target_path)
		if parent_dir and parent_dir ~= "" and parent_dir ~= "." and not pl_path.isdir(parent_dir) then
			if pl_path.isfile(parent_dir) then
				local err =
					fmt("Cannot create parent for target '{}', '{}' is a file.", self.actual_target_path, parent_dir)
				log.error(err)
				return false, err
			end
			log.debug("Execute Move: Creating parent directory: %s", parent_dir)
			local parent_create_ok, parent_create_err
			pcall_success, parent_create_ok, parent_create_err = pcall(pl_dir.makepath, parent_dir)
			if not pcall_success or not parent_create_ok then
				local err = fmt(
					"Failed to create parent directories for '{}': {}",
					self.actual_target_path,
					tostring(parent_create_err or parent_create_ok or "pcall error")
				)
				log.error(err)
				return false, err
			end
			log.info("Execute Move: Parent directory created: %s", parent_dir)
		end
	end

	-- Perform the Move operation to actual_target_path
	log.info("Execute Move: Moving '%s' -> '%s'", self.source, self.actual_target_path)
	local move_success, move_err_msg
	pcall_success, move_success, move_err_msg = pcall(pl_file.move, self.source, self.actual_target_path)

	if not pcall_success then
		local err = fmt(
			"Failed to move '{}' to '{}' (pcall error): {}",
			self.source,
			self.actual_target_path,
			tostring(move_success)
		) -- move_success is error msg here
		log.error(err)
		return false, err
	end
	if not move_success then
		local err = fmt(
			"Failed to move '{}' to '{}': {}",
			self.source,
			self.actual_target_path,
			move_err_msg or "unknown Penlight error"
		)
		log.error(err)
		return false, err
	end
	log.info("Execute Move: Successfully moved '%s' to '%s'", self.source, self.actual_target_path)

	-- Checksum Target (if file-like and not a symlink)
	if not self.was_directory and not self.source_is_symlink then
		log.debug("Execute Move: Calculating checksum for moved file: %s", self.actual_target_path)
		local cs_success, cs_result_or_err = pcall(Checksum.calculate_sha256, self.actual_target_path)

		if not cs_success or not cs_result_or_err then
			log.warn(
				fmt(
					"Checksum calculation failed for '%s' after move: {}. Operation succeeded but checksum not verified.",
					self.actual_target_path,
					tostring(cs_result_or_err or cs_success)
				)
			)
			self.checksum_data.final_target_checksum = nil
		else
			self.checksum_data.final_target_checksum = cs_result_or_err
			log.info(
				"Execute Move: Final target checksum for '%s': %s",
				self.actual_target_path,
				self.checksum_data.final_target_checksum
			)
			if self.checksum_data.initial_source_checksum ~= self.checksum_data.final_target_checksum then
				log.warn(
					fmt(
						"Checksum mismatch after move for '%s'. Initial: %s, Final: %s. File may have been corrupted or changed during move.",
						self.actual_target_path,
						self.checksum_data.initial_source_checksum,
						self.checksum_data.final_target_checksum
					)
				)
			end
		end
	elseif self.source_is_symlink then
		log.debug("Execute Move: Source was a symlink, skipping final target checksumming for the link itself.")
		self.checksum_data.final_target_checksum = nil -- Or a special value like 'symlink_moved'
	end

	return true
end

function MoveOperation:undo()
	log.info(
		"Undo Move: Attempting for '%s' (original source) from '%s' (actual target)",
		self.source,
		self.actual_target_path or self.target
	)
	local current_location = self.actual_target_path or self.target

	if not pl_path.exists(current_location) then
		local err = fmt("Item to undo move from '%s' does not exist.", current_location)
		log.error(err)
		return false, err
	end

	-- Check if original source path is now occupied (unless it's the same path we are moving from due to target_is_directory_move_into logic)
	if pl_path.exists(self.source) and self.source ~= current_location then
		local err = fmt("Cannot undo move, path '%s' already exists at original source location.", self.source)
		log.error(err)
		return false, err
	end

	-- If original target was overwritten, this undo does NOT restore it. It just moves the source back.
	if self.original_target_existed_and_was_overwritten then
		log.warn(
			"Undo Move: Original item at target '%s' was overwritten and will not be restored by this undo.",
			self.target
		)
	end

	-- Create parent directories for the original source path if they were created during execute for target and might be missing now
	-- This is a bit tricky as we don't explicitly track if source's parents were removed.
	-- For simplicity, we can try to ensure parent of self.source exists if create_parent_dirs was true.
	if self.options.create_parent_dirs then -- Check if original operation might have needed parent creation for target
		local source_parent_dir = pl_path.dirname(self.source)
		if
			source_parent_dir
			and source_parent_dir ~= ""
			and source_parent_dir ~= "."
			and not pl_path.isdir(source_parent_dir)
		then
			if pl_path.isfile(source_parent_dir) then
				local err =
					fmt("Cannot create parent for undo to source '{}', '{}' is a file.", self.source, source_parent_dir)
				log.error(err)
				return false, err
			end
			log.debug(
				"Undo Move: Attempting to create parent directory '%s' for original source path '%s'",
				source_parent_dir,
				self.source
			)
			local parent_create_ok, parent_create_err = pcall(pl_dir.makepath, source_parent_dir)
			if not parent_create_ok then
				log.warn(
					fmt(
						"Undo Move: Failed to create parent directory '%s' for original source. Error: %s. Continuing undo attempt.",
						source_parent_dir,
						tostring(parent_create_err)
					)
				)
				-- Not returning false, as pl_file.move might still succeed or provide a better error.
			end
		end
	end

	-- Move Back from actual_target_path to self.source
	log.info("Undo Move: Moving '%s' -> '%s'", current_location, self.source)
	local move_back_pcall_ok, move_back_success, move_back_err_msg = pcall(pl_file.move, current_location, self.source)

	if not move_back_pcall_ok then
		local err = fmt(
			"Failed to move '%s' back to '%s' during undo (pcall error): {}",
			current_location,
			self.source,
			tostring(move_back_success)
		) -- move_back_success is error here
		log.error(err)
		return false, err
	end
	if not move_back_success then
		local err = fmt(
			"Failed to move '%s' back to '%s' during undo: {}",
			current_location,
			self.source,
			move_back_err_msg or "unknown Penlight error"
		)
		log.error(err)
		return false, err
	end
	log.info("Undo Move: Successfully moved '%s' back to '%s'", current_location, self.source)

	-- Verify checksum if it was a file (not a symlink) and original checksum exists
	if not self.was_directory and not self.source_is_symlink and self.checksum_data.initial_source_checksum then
		log.debug("Undo Move: Verifying checksum for restored source file: %s", self.source)
		local restored_cs_ok, restored_cs = pcall(Checksum.calculate_sha256, self.source)
		if not restored_cs_ok or not restored_cs then
			log.warn(
				fmt(
					"Checksum calculation failed for '%s' after undo move: {}. Undo completed but checksum not verified.",
					self.source,
					tostring(restored_cs or restored_cs_ok)
				)
			)
		elseif restored_cs ~= self.checksum_data.initial_source_checksum then
			log.warn(
				fmt(
					"Checksum mismatch for '%s' after undo move. Expected: %s, Got: %s. File may have been corrupted.",
					self.source,
					self.checksum_data.initial_source_checksum,
					restored_cs
				)
			)
		else
			log.info("Undo Move: Checksum verified for restored source file '%s'", self.source)
		end
	elseif self.source_is_symlink then
		log.debug("Undo Move: Source was a symlink. Verifying link target if available.")
		if self.source_symlink_target then -- Check if we have an original target to compare against
			local pcall_ok, current_link_target = pcall(lfs.symlinkattributes, self.source, "target")
			if pcall_ok and current_link_target then
				if current_link_target ~= self.source_symlink_target then
					log.warn(
						fmt(
							"Undo Move: Restored symlink '%s' target '%s' does not match original target '%s'.",
							self.source,
							current_link_target,
							self.source_symlink_target
						)
					)
				else
					log.info(
						"Undo Move: Restored symlink '%s' target '%s' matches original.",
						self.source,
						current_link_target
					)
				end
			else
				log.warn(
					fmt(
						"Undo Move: Could not read target of restored symlink '%s' to verify. Error: %s",
						self.source,
						tostring(current_link_target or (pcall_ok and "nil") or "pcall error")
					)
				)
			end
		else
			log.debug(
				"Undo Move: No original symlink target recorded (e.g. source was broken link), skipping target verification."
			)
		end
	end

	self.original_target_existed_and_was_overwritten = false
	self.actual_target_path = nil
	return true
end

return MoveOperation
