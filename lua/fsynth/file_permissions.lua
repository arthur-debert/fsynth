-- File permission utilities for fsynth
-- This module provides platform-independent file permission handling
local logger = require("lual").logger()
local fmt = require("string.format.all")
local lfs = require("lfs")
local pl_path = require("pl.path") -- For is_writable on Windows directories
local pl_file = require("pl.file") -- For move_with_attributes

local file_permissions = {}

-- Determine if running on Windows
local is_windows = pl_path.sep == "\\"

--- Checks if a file or directory is readable by the current user.
-- @param path The path to the file or directory.
-- @return true if readable, false otherwise.
-- @return nil, error message on failure to check.
function file_permissions.is_readable(path)
	if not path or not pl_path.exists(path) then
		return false, "Path must be provided and exist"
	end
	logger.debug("Checking readability for %s", path)
	if is_windows then
		local f, err = io.open(path, "rb")
		if f then
			f:close()
			return true
		else
			logger.debug("Windows readability check failed for %s: %s", path, err or "unknown error")
			return false, err
		end
	else -- Unix-like
		local perms_str = lfs.attributes(path, "permissions")
		if not perms_str then
			return false, "Failed to get permissions string for " .. path
		end
		-- Owner permissions are at index 1, 2, 3 (e.g., rwx)
		-- Check for 'r' at the owner's read position (index 1)
		if perms_str:sub(1, 1) == "r" then
			return true
		else
			return false
		end
	end
end

--- Checks if a file or directory is writable by the current user.
-- For files, this means the file content can be changed.
-- For directories, this means items can be created or deleted within it.
-- @param path The path to the file or directory.
-- @return true if writable, false otherwise.
-- @return nil, error message on failure to check.
function file_permissions.is_writable(path)
	if not path or not pl_path.exists(path) then
		return false, "Path must be provided and exist"
	end
	logger.debug("Checking writability for %s", path)
	if is_windows then
		local mode = lfs.attributes(path, "mode")
		if mode == "file" then
			-- Try to open in append mode. If it succeeds, it's writable.
			-- Also, check the read-only attribute via existing get_mode loggeric.
			-- A file might be openable in "ab" even if +R if we own it, but generally
			-- the OS will prevent modification if +R is set by user.
			-- Let's rely on get_mode's interpretation of read-only for files.
			local win_mode = file_permissions.get_mode(path) -- "666" for writable, "444" for read-only
			if win_mode == "666" then
				-- Double check by trying to open
				local f, err_open = io.open(path, "ab")
				if f then
					f:close()
					return true
				else
					logger.debug("Win file writability (open 'ab') failed for %s: %s", path, err_open or "unknown error")
					return false, err_open
				end
			else
				return false -- "444" implies not writable
			end
		elseif mode == "directory" then
			-- Try to create and delete a temporary file
			local test_filename = ".fsynth_writetest_" .. os.time() .. math.random()
			local test_filepath = pl_path.join(path, test_filename)
			local f, err_create = io.open(test_filepath, "w")
			if f then
				f:close()
				local removed, err_remove = os.remove(test_filepath)
				if removed then
					return true
				else
					logger.warn("Failed to rm temp write-test file %s: %s", test_filepath, err_remove or "unknown error")
					return false -- Could create but not delete, still problematic
				end
			else
				logger.debug("Win dir writability (create temp) failed for %s: %s", path, err_create or "unknown error")
				return false, err_create
			end
		else
			return false, "Path is not a file or directory"
		end
	else -- Unix-like
		local perms_str = lfs.attributes(path, "permissions")
		if not perms_str then
			return false, "Failed to get permissions string for " .. path
		end
		-- Owner permissions are at index 1, 2, 3 (e.g., rwx)
		-- Check for 'w' at the owner's write position (index 2)
		if perms_str:sub(2, 2) == "w" then
			return true
		else
			return false
		end
	end
end

-- Set permissions for a file
-- @param path The file path
-- @param mode Permission mode as string ("644", "755", etc.)
-- @return true on success, or false, error message on failure
function file_permissions.set_mode(path, mode)
	if not path or not mode then
		return false, "Path and mode must be provided"
	end
	logger.debug("Setting file permissions for %s to %s", path, mode)
	if is_windows then
		-- Windows doesn't support full permission sets like Unix
		-- We'll only implement read-only attribute for Windows
		logger.debug("Full permissions not supported on Windows - only read-only can be set")
		local first_digit = tonumber(mode:sub(1, 1))
		local is_readonly = first_digit and first_digit <= 4
		local attrib_cmd
		if is_readonly then
			attrib_cmd = string.format('attrib +R "%s"', path:gsub("/", "\\"))
		else
			attrib_cmd = string.format('attrib -R "%s"', path:gsub("/", "\\"))
		end
		logger.debug("Executing Windows permission command: %s", attrib_cmd)
		local success, err_exec, code_exec = os.execute(attrib_cmd)

		if success == true or success == 0 then -- Check for common success indicators
			-- Verify by checking the attribute (simplified, assumes attrib command works if it exits 0)
			local current_win_mode, get_mode_err = file_permissions.get_mode(path)
			if not current_win_mode then
				logger.warn("Set mode: Could not get mode for '%s' after attrib: %s", path, get_mode_err or "unknown")
				-- Proceeding, as attrib command itself reported success
			elseif (is_readonly and current_win_mode == "444") or (not is_readonly and current_win_mode == "666") then
				return true -- Verified
			else
				logger.warn(
					"Set mode: attrib for '%s' to '%s' (readonly: %s) seemed to succeed, but get_mode returned '%s'",
					path,
					mode,
					tostring(is_readonly),
					current_win_mode
				)
				-- Still return true as os.execute suggested success, but logger discrepancy
				return true
			end
			return true
		else
			local err_msg = "Failed to " .. (is_readonly and "set" or "clear") .. " read-only attribute on Windows."
			err_msg = err_msg .. " Command: " .. attrib_cmd .. " Status: " .. tostring(success)
			if err_exec then
				err_msg = err_msg .. " Err: " .. tostring(err_exec)
			end
			if code_exec then
				err_msg = err_msg .. " Code: " .. tostring(code_exec)
			end
			logger.error(err_msg)
			return false, err_msg
		end
	else -- Unix-like systems
		local chmod_cmd = string.format('chmod %s "%s"', mode, path)
		logger.debug("Executing chmod command: %s", chmod_cmd)
		local exec_status = os.execute(chmod_cmd)

		if exec_status == true or exec_status == 0 then
			local new_mode_str, get_err = file_permissions.get_mode(path)
			if new_mode_str == mode then
				return true
			else
				logger.warn(
					"chmod for '%s' to '%s' executed, but get_mode returned '%s' (expected '%s'). Error: %s",
					path,
					mode,
					new_mode_str or "nil",
					mode,
					get_err or "none"
				)
				return false,
					fmt(
						"Failed to verify permissions on '{}' after chmod. Expected '{}', got '{}'. Error: {}",
						path,
						mode,
						new_mode_str or "nil",
						get_err or "none"
					)
			end
		else
			local err_detail = "os.execute returned " .. tostring(exec_status)
			logger.error("Failed to execute chmod on '%s' to '%s'. Status: %s", path, mode, err_detail)
			return false,
				fmt("Failed to set permissions on '{}' to '{}'. Command execution failed: {}", path, mode, err_detail)
		end
	end
end

-- Preserve file attributes when copying on Unix systems
-- This function modifies the standard cp command to include the -p flag
-- @param src Source file path
-- @param dst Destination file path
-- @param preserve_attributes Whether to preserve attributes (default: true)
-- @return true on success, or false, error message on failure
function file_permissions.copy_with_attributes(src, dst, preserve_attributes)
	if preserve_attributes == nil then
		preserve_attributes = true
	end
	logger.debug("Copying file with attributes preservation=%s: %s -> %s", preserve_attributes, src, dst)
	if is_windows then
		-- On Windows, Penlight already uses CopyFileA which preserves attributes
		-- Just use the standard Penlight copy function
		return pl_file.copy(src, dst)
	else
		-- On Unix, use cp with the -p flag to preserve attributes
		if preserve_attributes then
			local cmd = string.format('cp -p "%s" "%s"', src, dst)
			logger.debug("Executing copy command: %s", cmd)
			local success = os.execute(cmd)
			if not success then
				return false, fmt("Failed to copy file with attributes from '{}' to '{}'", src, dst)
			end
			return true
		else
			-- Standard copy without preserving attributes: read content from source and write to destination.
			-- This ensures the destination file gets default OS permissions, respecting umask.
			logger.debug("Performing non-preserving copy (read/write) for Unix: %s -> %s", src, dst)
			local content, read_err = pl_file.read(src)
			if not content then -- pl_file.read returns (contents) or (nil, errmsg)
				return false,
					fmt("Failed to read source file '{}' for non-preserving copy: {}", src, read_err or "unknown error")
			end
			local write_ok, write_err = pl_file.write(dst, content)
			if not write_ok then
				return false,
					fmt(
						"Failed to write target file '{}' for non-preserving copy: {}",
						dst,
						write_err or "unknown error"
					)
			end
			return true
		end
	end
end

--- Moves a file or directory, attempting to preserve attributes.
-- On Unix, uses 'mv'. On Windows, uses Penlight's move which uses MoveFileA.
-- @param src Source path.
-- @param dst Destination path.
-- @return true on success, or false, error message on failure.
function file_permissions.move_with_attributes(src, dst)
	if not src or not dst then
		return false, "Source and destination paths must be provided"
	end
	if not pl_path.exists(src) then
		return false, "Source path does not exist: " .. src
	end

	logger.debug("Moving with attributes: %s -> %s", src, dst)

	if is_windows then
		-- Penlight's movefile uses MoveFileA (via alien/FFI) or rename command.
		-- MoveFileA preserves attributes.
		local ok, err = pl_file.move(src, dst)
		if not ok then
			return false, fmt("Failed to move on Windows from '{}' to '{}': {}", src, dst, err or "unknown error")
		end
		return true
	else -- Unix-like
		-- 'mv' command generally preserves attributes (owner, group, permissions, timestamps)
		-- when moving within the same filesystem. Across filesystems, it might act
		-- like cp -p + rm.
		local cmd = string.format('mv "%s" "%s"', src, dst)
		logger.debug("Executing move command: %s", cmd)
		local success, _, exitcode = os.execute(cmd)
		-- os.execute returns true for success (exit code 0 on some systems),
		-- or nil/false + error info on others.
		-- A direct check on exitcode is more reliable if available.
		-- For simplicity, we check if 'success' is truthy (often means command found and ran)
		-- and then we can check if the source is gone and dest exists.
		-- However, os.execute behavior varies. A robust check is harder.
		-- Let's assume if os.execute returns a truthy value and exitcode is 0 (if available), it's a success.
		-- For now, a simpler check:
		if success then -- success is true if command ran and exited with 0 on some Lua interpreters/OS
			if not pl_path.exists(src) and pl_path.exists(dst) then
				return true
			else
				-- mv might have failed silently or partially
				local reason = "mv command ran but source/destination state is inconsistent."
				if pl_path.exists(src) then
					reason = reason .. " Source still exists."
				end
				if not pl_path.exists(dst) then
					reason = reason .. " Destination does not exist."
				end
				logger.error("Move command inconsistency for %s to %s: %s", src, dst, reason)
				return false, fmt("Failed to move with mv from '{}' to '{}': {}", src, dst, reason)
			end
		else
			-- success might be nil, or false, or an error code depending on Lua/OS.
			-- exitcode might be available on some systems if success is nil.
			local err_msg = "mv command failed"
			if type(exitcode) == "number" and exitcode ~= 0 then
				err_msg = err_msg .. " (exit code " .. exitcode .. ")"
			end
			logger.error("Move command failed for %s to %s: %s", src, dst, err_msg)
			return false, fmt("Failed to move with mv from '{}' to '{}': {}", src, dst, err_msg)
		end
	end
end

-- Get file permissions as a string (e.g., "644", "755")
-- @param path The file path
-- @return permissions string or nil, error message on failure
function file_permissions.get_mode(path)
	if not path then
		return nil, "Path must be provided"
	end

	if not pl_path.exists(path) then
		return nil, "Path does not exist: " .. path
	end

	if is_windows then
		-- Windows doesn't have a direct octal mode. We simplify to read-only or not.
		local cmd = string.format('attrib "%s"', path:gsub("/", "\\"))
		local f = io.popen(cmd)
		if not f then
			return nil, "Failed to get file attributes on Windows (popen failed for " .. path .. ")"
		end
		local output = f:read("*a")
		local ok, err_close, code_close = f:close()

		if not ok then
			-- attrib returns exit code 1 if file not found.
			if code_close == 1 and output and (output:match("File not found") or output:match("Path not found")) then
				-- This case should ideally be caught by pl_path.exists above, but as a fallback:
				return nil, "File not found (reported by attrib): " .. path
			end
			local err_fmt = "Failed to get file attributes for '%s' (attrib command failed). "
				.. "Exit: %s, Err: %s, Out: %s"
			local err_msg = fmt(err_fmt, path, tostring(code_close), tostring(err_close), output or "nil")
			logger.warn(err_msg)
			return nil, err_msg
		end

		if not output or output == "" then
			-- This can happen if the path is valid but attrib doesn't list it (e.g. some system dirs)
			-- or if the file genuinely has no attributes listed that match 'R'.
			-- If pl_path.exists was true, assume writable for our simplified model.
			logger.debug("Attrib for '%s' empty output. Assuming not read-only.", path)
			return "666"
		end

		output = output:match("^%s*(.-)%s*$") -- Trim whitespace
		local is_readonly = false
		-- Look for 'R' as a whole word/char among attributes.
		-- Example outputs: "A SHR         C:\file.txt", "   R        C:\file.txt"
		for attr_char in output:gmatch("%S+") do
			if attr_char == "R" then
				is_readonly = true
				break
			end
		end

		if is_readonly then
			return "444" -- Represents read-only
		else
			return "666" -- Represents writable
		end
	else        -- Unix-like systems
		local perms_str = lfs.attributes(path, "permissions")
		if not perms_str then
			-- lfs.attributes returns nil if path doesn't exist or other errors.
			-- Existence already checked, so this is likely a permissions issue to read attributes.
			return nil, "Failed to get lfs permissions string for " .. path
		end

		if #perms_str ~= 9 then -- Expected format "rwxrwxrwx"
			return nil, "Invalid permissions string format from lfs for '" .. path .. "': " .. perms_str
		end

		local function calculate_digit(p_str, start_idx)
			local digit = 0
			if p_str:sub(start_idx, start_idx) == "r" then
				digit = digit + 4
			end
			if p_str:sub(start_idx + 1, start_idx + 1) == "w" then
				digit = digit + 2
			end
			if p_str:sub(start_idx + 2, start_idx + 2) == "x" then
				digit = digit + 1
			end
			return digit
		end

		local owner_digit = calculate_digit(perms_str, 1)
		local group_digit = calculate_digit(perms_str, 4)
		local other_digit = calculate_digit(perms_str, 7)

		return string.format("%d%d%d", owner_digit, group_digit, other_digit)
	end
end

return file_permissions
