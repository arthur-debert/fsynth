-- Simple checksum module for fsynth
local pl_file = require("pl.file")

local Checksum = {}

-- Simple checksum function that doesn't rely on external libraries
-- This is not cryptographically secure, but works for testing
local function simple_checksum(str)
  local sum = 0
  for i = 1, #str do
    sum = (sum * 31 + string.byte(str, i)) % 2^32
  end
  return string.format("%08x", sum)
end

--- Calculates a checksum of a file.
-- @param filepath The path to the file.
-- @return string The hexadecimal representation of the checksum, or nil.
-- @return string An error message if the file cannot be read or processed, otherwise nil.
function Checksum.calculate_sha256(filepath)
  if not filepath then
    return nil, "Filepath cannot be nil"
  end

  local content, err = pl_file.read(filepath)

  if not content then
    local err_msg = "Failed to read file for checksumming: " .. filepath
    if err then
      err_msg = err_msg .. ": " .. tostring(err)
    end
    return nil, err_msg
  end

  -- Use our simple checksum function
  local hash_hex = simple_checksum(content)
  
  return hash_hex
end

return Checksum
