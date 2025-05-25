-- Base Operation class
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
  error("validate() must be implemented by subclasses")
end

function Operation:execute()
  error("execute() must be implemented by subclasses")
end

function Operation:checksum()
  if not self.source then
    return true -- No source file to checksum
  end

  local current_checksum, err = Checksum.calculate_sha256(self.source)

  if not current_checksum then
    return false, err -- Error during checksum calculation
  end

  if self.checksum_data.source_checksum then
    -- Compare with existing checksum
    if self.checksum_data.source_checksum == current_checksum then
      return true -- Checksum matches
    else
      return false, "Source file has changed since operation was created: " .. self.source
    end
  else
    -- Store new checksum
    self.checksum_data.source_checksum = current_checksum
    return true -- First time checksumming this source
  end
end

function Operation:undo()
  return false, "Undo not supported for this operation"
end

return Operation
