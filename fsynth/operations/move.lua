local Operation = require("fsynth.operation_base")
local Checksum = require("fsynth.checksum")
local pl_path = require("pl.path")
local pl_file = require("pl.file") -- Not directly used for move, but good to have for consistency if needed later
local pl_dir = require("pl.dir")
-- always use the log module, no prints
local log = require("fsynth.log")
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
	-- self.options.overwrite_directory_contents is not used yet, per instructions

	self.was_directory = nil                              -- Will be set in validate()
	self.original_target_existed_and_was_overwritten = false -- Will be set in execute()

	self.checksum_data.initial_source_checksum = nil      -- For files, set in validate()
	self.checksum_data.final_target_checksum = nil        -- For files, set in execute()

	return self
end

function MoveOperation:validate()
	if not self.source or self.source == "" then
		return false, "Source path not specified for MoveOperation"
	end
	if not self.target or self.target == "" then
		return false, "Target path not specified for MoveOperation"
	end

	-- Source Validation
	if not pl_path.exists(self.source) then
		return false, fmt("Source path '{}' does not exist.", self.source)
	end
	self.was_directory = pl_path.isdir(self.source)

	if not self.was_directory then -- It's a file
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
	end

	-- Target Validation
	if pl_path.exists(self.target) then
		if not self.options.overwrite then
			return false, fmt("Target path '{}' already exists", self.target)
		end
		-- If overwrite is true:
		if self.was_directory and pl_path.isfile(self.target) then
			return false, "Cannot move a directory onto a file"
		end
		if not self.was_directory and pl_path.isdir(self.target) then
			-- As per spec: "assume this is an error" without 'overwrite_directory_contents'
			return false, "Cannot move a file onto a directory"
		end
		-- If source and target are both files, or both dirs, overwrite is fine.
	else -- Target does not exist
		if not self.options.create_parent_dirs then
			local parent_dir = pl_path.dirname(self.target)
			if parent_dir and parent_dir ~= "" and parent_dir ~= "." and not pl_path.isdir(parent_dir) then
				return false, "No such file or directory"
			end
		end
	end

	return true
end

function MoveOperation:execute()
	-- Ensure validation has been run
	if self.was_directory == nil then
		local valid, err = self:validate()
		if not valid then
			return false, err
		end
	end

	local target_existed_before_move = pl_path.exists(self.target)
	local pcall_success, pcall_err_or_val

	-- Create Parent Directories
	if self.options.create_parent_dirs then
		local parent_dir = pl_path.dirname(self.target)
		if parent_dir and parent_dir ~= "" and parent_dir ~= "." and not pl_path.isdir(parent_dir) then
			local parent_create_ok, parent_create_err
			pcall_success, parent_create_ok, parent_create_err = pcall(pl_dir.makepath, parent_dir)
			if not pcall_success then
				log.error(
					fmt(
						"Failed to create parent directories for '{}' (pcall error): {}",
						self.target,
						tostring(parent_create_ok)
					)
				)
				return false,
					fmt(
						"Failed to create parent directories for '{}' (pcall error): {}",
						self.target,
						tostring(parent_create_ok)
					)
			end
			if not parent_create_ok then
				log.error(
					fmt(
						"Failed to create parent directories for '{}': {}",
						self.target,
						parent_create_err or "unknown Penlight error"
					)
				)
				return false,
					fmt(
						"Failed to create parent directories for '{}': {}",
						self.target,
						parent_create_err or "unknown Penlight error"
					)
			end
		end
	end

	-- Handle Overwrite Flag
	if target_existed_before_move and self.options.overwrite then
		self.original_target_existed_and_was_overwritten = true
		-- Note: Actual backup of the overwritten item is not implemented here.
	end

	-- Move
	local move_success, move_err_msg
	pcall_success, move_success, move_err_msg = pcall(pl_file.move, self.source, self.target)

	if not pcall_success then
		return false,
			fmt("Failed to move '{}' to '{}' (pcall error): {}", self.source, self.target, tostring(move_success))
	end
	if not move_success then
		return false,
			fmt("Failed to move '{}' to '{}': {}", self.source, self.target, move_err_msg or "unknown Penlight error")
	end

	-- Checksum Target (if file)
	if not self.was_directory then
		local cs_success, cs_result_or_err
		cs_success, cs_result_or_err = pcall(Checksum.calculate_sha256, self.target)

		if not cs_success then                   -- pcall error during checksum calculation
			pcall(pl_file.move, self.target, self.source) -- Attempt to move back
			return false,
				fmt(
					"Failed to calculate checksum for moved file '{}' (pcall error: {}). " .. "Move has been reverted.",
					self.target,
					tostring(cs_result_or_err)
				)
		end
		if not cs_result_or_err then             -- Checksum.calculate_sha256 returned nil
			pcall(pl_file.move, self.target, self.source) -- Attempt to move back
			return false,
				fmt(
					"Failed to calculate checksum for moved file '{}': {}. " .. "Move has been reverted.",
					self.target,
					"Checksum calculation failed"
				)
		end

		self.checksum_data.final_target_checksum = cs_result_or_err

		if self.checksum_data.initial_source_checksum ~= self.checksum_data.final_target_checksum then
			pcall(pl_file.move, self.target, self.source) -- Attempt to move back
			return false, "Checksum mismatch after move"
		end
	end

	return true
end

function MoveOperation:undo()
	if not pl_path.exists(self.target) then
		return false, fmt("Item to undo move from target '{}' does not exist.", self.target)
	end

	if pl_path.exists(self.source) then
		return false, fmt("Cannot undo move, path '{}' already exists at original source location.", self.source)
	end

	-- Move Back
	local move_back_pcall_ok, move_back_success, move_back_err_msg = pcall(pl_file.move, self.target, self.source)

	if not move_back_pcall_ok then
		return false,
			fmt(
				"Failed to move '{}' back to '{}' during undo (pcall error): {}",
				self.target,
				self.source,
				tostring(move_back_success)
			)
	end
	if not move_back_success then
		return false,
			fmt(
				"Failed to move '{}' back to '{}' during undo: {}",
				self.target,
				self.source,
				move_back_err_msg or "unknown Penlight error"
			)
	end

	-- Regarding self.original_target_existed_and_was_overwritten:
	-- As per spec, this undo does not restore the original item that was at self.target.
	-- It only moves the self.source item (now at self.target) back to self.source.
	-- If a backup mechanism were in place, it would be used here.

	return true
end

return MoveOperation
