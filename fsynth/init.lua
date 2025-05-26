-- Main entry point for fsynth module
-- always use the log module, no prints
local log = require("fsynth.log")
local fmt = require("string.format.all")

-- Initialize the module
log.info(fmt("Initializing fsynth module"))

-- Load the high-level API
local api = require("fsynth.api")

-- Return the API module directly, but also expose internals for advanced usage
local fsynth = api

-- Expose internal components for advanced usage
fsynth._internal = {
	-- Export the main components
	checksum = require("fsynth.checksum"),
	processor = require("fsynth.processor"),
	queue = require("fsynth.queue"),
	-- Export operation types
	operations = {
		copy_file = require("fsynth.operations.copy_file"),
		create_directory = require("fsynth.operations.create_directory"),
		create_file = require("fsynth.operations.create_file"),
		delete = require("fsynth.operations.delete"),
		move = require("fsynth.operations.move"),
		symlink = require("fsynth.operations.symlink"),
	},
}

return fsynth
