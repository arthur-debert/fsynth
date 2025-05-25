-- Base Operation class
-- always use the log module, no prints
local log = require("fsynth.log")
local Operation = {}
Operation.__index = Operation

local Checksum = require("fsynth.checksum")
-- Note: pl.path, pl.file, pl.dir are not directly used by the base Operation methods,
-- they are used by subclasses. They will be required in the specific operation files.

function Operation.new(source, target, options)
  local self = setmetatable({}, Operation)
  self.source = source
  self.target = target
  self.options = options or {}
  self.checksum_data = {} -- Initialize checksum_data
  return self
end

function Operation:validate()
  log.debug("Base validate() called, should be implemented by %s", self.__index)
  error("validate() must be implemented by subclasses")
end

function Operation:execute()
  log.debug("Base execute() called, should be implemented by %s", self.__index)
  error("execute() must be implemented by subclasses")
end

function Operation:checksum()
  log.debug("Calculating checksum for source: %s", self.source or "nil")
  if not self.source then
    log.debug("No source file to checksum")
    return true -- No source file to checksum
  end

  local current_checksum, err = Checksum.calculate_sha256(self.source)

  if not current_checksum then
    log.error("Checksum calculation failed: %s", err)
    return false, err -- Error during checksum calculation
  end

  if self.checksum_data.source_checksum then
    -- Compare with existing checksum
    log.debug("Comparing checksums for %s: stored=%s, current=%s",
              self.source, self.checksum_data.source_checksum, current_checksum)
    if self.checksum_data.source_checksum == current_checksum then
      log.debug("Checksum matches for %s", self.source)
      return true -- Checksum matches
    else
      local err_msg = "Source file has changed since operation was created: " .. self.source
      log.warn(err_msg)
      return false, err_msg
    end
  else
    -- Store new checksum
    log.debug("Storing new checksum for %s: %s", self.source, current_checksum)
    self.checksum_data.source_checksum = current_checksum
    return true -- First time checksumming this source
  end
end

function Operation:undo()
  log.debug("Base undo() called for %s, not supported", self.source or "unknown operation")
  return false, "Undo not supported for this operation"
end

return Operation
