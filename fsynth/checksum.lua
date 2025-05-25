local sha2 = require("sha2")
local pl_file = require("pl.file")

local Checksum = {}

--- Calculates the SHA-256 hash of a file.
-- @param filepath The path to the file.
-- @return string The hexadecimal representation of the SHA-256 hash, or nil.
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

  -- Assuming sha2.sha256 returns the hex digest directly.
  -- Most common Lua sha2 libraries (like lua-sha2 or the one included with OpenResty)
  -- provide a function that returns a hex string.
  local hash_hex
  local success, result = pcall(function() hash_hex = sha2.sha256(content) end)

  if not success then
    return nil, "Error during SHA256 calculation for file " .. filepath .. ": " .. tostring(result)
  end
  
  if type(hash_hex) ~= "string" then
    -- This case is a fallback if sha2.sha256 returns raw bytes or something else.
    -- A more robust solution would involve a hex encoding function here if necessary.
    return nil, "SHA256 function did not return a string hash for file: " .. filepath .. ". Got type: " .. type(hash_hex)
  end

  return hash_hex
end

return Checksum
