-- Main entry point for fsynth module
-- always use the log module, no prints
local log = require("fsynth.log")

-- Initialize the module
log.info("Initializing fsynth module")

-- Return the module table
return {
  -- Export the main components
  checksum = require("fsynth.checksum"),
  processor = require("fsynth.processor"),
  queue = require("fsynth.queue"),
  utils = require("fsynth.utils"),
  -- Export operation types
  operations = {
    copy_file = require("fsynth.operations.copy_file"),
    create_directory = require("fsynth.operations.create_directory"),
    create_file = require("fsynth.operations.create_file"),
    delete = require("fsynth.operations.delete"),
    move = require("fsynth.operations.move"),
    symlink = require("fsynth.operations.symlink")
  },
  -- Export the log module
  log = log
}