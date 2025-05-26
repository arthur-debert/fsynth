-- Utility functions for fsynth
-- always use the log module, no prints
local log = require("fsynth.log")
local pl_path = require("pl.path")

local Utils = {}

-- Returns true if the path exists and is a file
function Utils.is_file(path)
  log.debug("Checking if path is a file: %s", path)
  return pl_path.isfile(path)
end

-- Returns true if the path exists and is a directory
function Utils.is_directory(path)
  log.debug("Checking if path is a directory: %s", path)
  return pl_path.isdir(path)
end

-- Returns the parent directory of a path
function Utils.get_parent_dir(path)
  log.debug("Getting parent directory for: %s", path)
  return pl_path.dirname(path)
end

-- Creates all directories in the path if they don't exist
function Utils.ensure_directory_exists(path)
  log.debug("Ensuring directory exists: %s", path)
  if not pl_path.exists(path) then
    local success, err = pl_path.mkdir(path)
    if not success then
      log.error("Failed to create directory %s: %s", path, err)
      return false, err
    end
    log.info("Created directory: %s", path)
    return true
  end
  return true
end

-- Safely join paths, ensuring proper path separators
function Utils.join_paths(...)
  local result = pl_path.join(...)
  log.debug("Joined paths: %s", result)
  return result
end

return Utils