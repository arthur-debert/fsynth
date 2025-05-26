-- High-level API for Fsynth
-- Provides a clean, user-friendly interface over the core components

local log = require("fsynth.log")
local Queue = require("fsynth.queue")
local Processor = require("fsynth.processor")
local fmt = require("string.format.all")

local M = {}

-- ===========================================================================
-- Operation Queue API
-- ===========================================================================

local OperationQueue = {}
OperationQueue.__index = OperationQueue

function OperationQueue.new()
	local self = setmetatable({
		_queue = Queue.new(),
		_operations = {}, -- Keep track of operations for inspection
	}, OperationQueue)
	log.debug("Created new OperationQueue")
	return self
end

function OperationQueue:add(operation)
	if not operation then
		error("Cannot add nil operation to queue")
	end
	Queue.enqueue(self._queue, operation)
	table.insert(self._operations, operation)
	log.trace(fmt("Added {} operation to queue", operation.type or "unknown"))
end

function OperationQueue:get_operations()
	-- Return a copy to prevent external modification
	local copy = {}
	for i, op in ipairs(self._operations) do
		copy[i] = op
	end
	return copy
end

function OperationQueue:clear()
	Queue.clear(self._queue)
	self._operations = {}
	log.debug("Cleared operation queue")
end

function OperationQueue:size()
	return #self._operations
end

function OperationQueue:remove(index)
	if index < 1 or index > #self._operations then
		error(fmt("Index {} out of bounds (queue size: {})", index, #self._operations))
	end

	-- Remove from operations list
	table.remove(self._operations, index)

	-- Rebuild the internal queue
	Queue.clear(self._queue)
	for _, op in ipairs(self._operations) do
		Queue.enqueue(self._queue, op)
	end

	log.debug(fmt("Removed operation at index {}", index))
end

-- Internal method to get the queue for processing
function OperationQueue:_get_internal_queue()
	-- Create a copy of the queue for processing
	local process_queue = Queue.new()
	for _, op in ipairs(self._operations) do
		Queue.enqueue(process_queue, op)
	end
	return process_queue
end

-- ===========================================================================
-- Results API
-- ===========================================================================

local Results = {}
Results.__index = Results

function Results.new()
	return setmetatable({
		success = true,
		errors = {},
		executed_count = 0,
		skipped_count = 0,
		rollback_count = 0,
		log = {},
	}, Results)
end

function Results:is_success()
	return self.success
end

function Results:get_errors()
	return self.errors
end

function Results:get_log()
	return self.log
end

function Results:_add_error(operation_index, operation_type, message, severity)
	table.insert(self.errors, {
		operation_index = operation_index,
		operation_type = operation_type,
		message = message,
		severity = severity or "error",
	})
	self.success = false
end

function Results:_add_log(message)
	table.insert(self.log, message)
end

-- ===========================================================================
-- Processor Wrapper API
-- ===========================================================================

local ProcessorWrapper = {}
ProcessorWrapper.__index = ProcessorWrapper

function ProcessorWrapper.new()
	return setmetatable({}, ProcessorWrapper)
end

function ProcessorWrapper:execute(queue, config)
	config = config or {}
	local model = config.model or "standard"
	local on_error = config.on_error or "stop"
	local dry_run = config.dry_run or false
	local log_level = config.log_level or "info"

	-- Configure logging level (if supported)
	local old_level = log.level
	if log_level then
		log.level = log_level
	end

	local results = Results.new()
	results:_add_log(fmt("Starting execution with model: {}, dry_run: {}", model, dry_run))

	-- Get a copy of the queue for processing
	local process_queue = queue:_get_internal_queue()
	local operations = queue:get_operations()

	-- Configure processor options based on execution model
	local processor_options = {
		validate_first = (model == "validate_first"),
		best_effort = (model == "best_effort"),
		transactional = (model == "transactional"),
		force = false,
		verify_checksums = true,
	}

	-- Handle dry run mode
	if dry_run then
		results:_add_log("DRY RUN MODE: Simulating operations without making changes")

		-- Validate all operations
		for i, op in ipairs(operations) do
			results:_add_log(
				fmt("Validating operation {}: {} {}", i, op.type or "unknown", op.target or op.source or "")
			)

			local valid, err = op:validate()
			if not valid then
				results:_add_error(i, op.type, err or "Validation failed", "error")
				results:_add_log(fmt("  Validation failed: {}", err or "unknown error"))

				if model ~= "best_effort" and on_error == "stop" then
					results:_add_log("Stopping due to validation error")
					break
				end
			else
				results:_add_log("  Validation successful")
				results.executed_count = results.executed_count + 1
			end
		end
	else
		-- Execute operations for real
		local processor = Processor.new(processor_options)
		local success, errors = processor:process(process_queue)

		-- Process results
		if errors then
			for _, err in ipairs(errors) do
				-- Find operation index
				local op_index = 0
				for i, op in ipairs(operations) do
					if op == err.operation then
						op_index = i
						break
					end
				end

				results:_add_error(
					op_index,
					err.operation and err.operation.type or "unknown",
					err.error or "Unknown error",
					"error"
				)
				results:_add_log(fmt("Operation {} failed: {}", op_index, err.error or "unknown"))
			end
		end

		-- Count executed operations
		results.executed_count = #processor.executed
		results.success = success

		-- Handle rollback count for transactional mode
		if model == "transactional" and not success then
			results.rollback_count = #processor.executed
			results:_add_log(fmt("Rolled back {} operations", results.rollback_count))
		end
	end

	results:_add_log(
		fmt(
			"Execution completed. Success: {}, Executed: {}, Errors: {}",
			results.success,
			results.executed_count,
			#results.errors
		)
	)

	-- Restore original log level
	if old_level then
		log.level = old_level
	end

	return results
end

-- ===========================================================================
-- Operation Factories
-- ===========================================================================

M.op = {}

-- Copy file operation
function M.op.copy_file(source_path, target_path, options)
	local copy_file = require("fsynth.operations.copy_file")
	options = options or {}

	-- Map our API options to the internal implementation
	local internal_options = {
		overwrite = options.overwrite,
		preserve_timestamps = options.preserve_attributes,
		verify_checksum = options.verify_checksum_before or options.verify_checksum_after,
	}

	local op = copy_file.new(source_path, target_path, internal_options)
	op.type = "CopyFile"
	return op
end

-- Create directory operation
function M.op.create_directory(dir_path, options)
	local create_dir = require("fsynth.operations.create_directory")
	options = options or {}

	local internal_options = {
		create_parents = options.create_parents,
		mode = options.mode,
	}

	local op = create_dir.new(dir_path, internal_options)
	op.type = "CreateDirectory"
	op.target = dir_path -- Ensure target is set for inspection
	return op
end

-- Create file operation
function M.op.create_file(file_path, content, options)
	local create_file = require("fsynth.operations.create_file")
	options = options or {}

	local internal_options = {
		content = content, -- Content is passed through options
		mode = options.mode,
		overwrite = options.overwrite,
		create_parent_dirs = options.create_parents ~= false, -- Default to true like mkdir
	}

	local op = create_file.new(file_path, internal_options)
	op.type = "CreateFile"
	return op
end

-- Symlink operation
function M.op.symlink(existing_path, link_path, options)
	local symlink = require("fsynth.operations.symlink")
	options = options or {}

	local internal_options = {
		overwrite = options.overwrite,
		relative = options.relative,
	}

	local op = symlink.new(existing_path, link_path, internal_options)
	op.type = "Symlink"
	return op
end

-- Move file operation
function M.op.move_file(source_path, target_path, options)
	local move = require("fsynth.operations.move")
	options = options or {}

	local internal_options = {
		overwrite = options.overwrite,
		verify_checksum = options.verify_checksum,
	}

	local op = move.new(source_path, target_path, internal_options)
	op.type = "MoveFile"
	return op
end

-- Delete file operation
function M.op.delete_file(file_path, options)
	local delete = require("fsynth.operations.delete")
	options = options or {}

	local internal_options = {
		-- The delete operation doesn't support backup options in the current implementation
		-- These would need to be implemented separately
	}

	local op = delete.new(file_path, internal_options)
	op.type = "DeleteFile"
	op.target = file_path -- Ensure target is set
	return op
end

-- Delete directory operation
function M.op.delete_directory(dir_path, options)
	local delete = require("fsynth.operations.delete")
	options = options or {}

	local internal_options = {
		is_recursive = options.recursive,
		-- max_items is not currently implemented in the delete operation
	}

	local op = delete.new(dir_path, internal_options)
	op.type = "DeleteDirectory"
	op.target = dir_path -- Ensure target is set
	return op
end

-- ===========================================================================
-- Public API Functions
-- ===========================================================================

function M.new_queue()
	return OperationQueue.new()
end

function M.new_processor()
	return ProcessorWrapper.new()
end

-- Export the log module for direct access if needed
M.log = log

return M
