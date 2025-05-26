-- fsynth/logging.lua
-- Configures and provides logging capabilities using log.lua

local log = require("log")

-- Configuration
local LOG_FILE_PATH = os.getenv("FSYNTH_LOG_FILE") or "/var/tmp/lua-fsynth.log"
local CONSOLE_LOG_LEVEL = os.getenv("FSYNTH_LOG_LEVEL") or "warn"
local LOG_LEVELS = { "trace", "debug", "info", "warn", "error", "fatal" }

-- Truncate log file at startup
local function truncate_log_file(filepath)
	local fp, err = io.open(filepath, "w")
	if fp then
		fp:close()
	else
		local warn_msg = string.format("Warn: Truncate failed for '%s': %s\n", filepath, err or "unknown")
		io.stderr:write(warn_msg)
	end
end

truncate_log_file(LOG_FILE_PATH)

-- Configure basic console logging via the log object's properties
if log then
	log.level = CONSOLE_LOG_LEVEL
	if type(log.usecolor) == "boolean" then -- Check if usecolor is a boolean property
		log.usecolor = true -- Enable colors for console if supported
	elseif type(log.usecolor) == "function" then -- Check if usecolor is a function
		log.usecolor(true)
	end
else
	-- Fallback if log module itself is nil (should not happen with pcall earlier, but defensive)
	log = {}
	for _, level_name in ipairs(LOG_LEVELS) do
		log[level_name] = function(...)
			local msg_parts = {}
			for i = 1, select("#", ...) do
				table.insert(msg_parts, tostring(select(i, ...)))
			end
			io.stdout:write(string.format("[%s] %s\n", level_name:upper(), table.concat(msg_parts, " ")))
		end
	end
	io.stderr:write("Warn: 'log' module was nil, using basic stdout fallback.\n")
end

-- Attempt to open the file for appending for file logging
local file_handle, err_fh = io.open(LOG_FILE_PATH, "a")
if not file_handle then
	local warn_msg = string.format("Warn: Log '%s' open fail: %s. No file log.\n", LOG_FILE_PATH, err_fh or "unknown")
	io.stderr:write(warn_msg)
end

-- Wrap logging functions to add file logging
for _, level_name in ipairs(LOG_LEVELS) do
	local original_fn = log[level_name]
	if type(original_fn) == "function" then
		log[level_name] = function(...)
			-- Call original function (handles console logging based on log.level)
			original_fn(...)

			-- Always log to file if file_handle is available
			if file_handle then
				local msg_parts = { ... } -- Collect all varargs correctly
				local n_msg_parts = select("#", ...) -- Get true count, robust to nils

				local message
				if n_msg_parts > 0 and type(msg_parts[1]) == "string" and n_msg_parts > 1 then
					-- First arg is format string, subsequent are values for format specifiers.
					local fmt_str = msg_parts[1]
					local fmt_args = { table.unpack(msg_parts, 2, n_msg_parts) }
					local success_format, result_format = pcall(string.format, fmt_str, table.unpack(fmt_args))
					if success_format then
						message = result_format
					else
						-- Formatting failed. Fallback to concatenating all original arguments.
						local string_parts_fallback = {}
						for i_fallback = 1, n_msg_parts do
							table.insert(string_parts_fallback, tostring(msg_parts[i_fallback]))
						end
						local err_info = " (format error: " .. tostring(result_format) .. ")"
						message = table.concat(string_parts_fallback, " ") .. err_info
					end
				elseif n_msg_parts > 0 then
					-- Not a format string case, or only one argument. Concatenate all parts as strings.
					local string_parts_concat = {}
					for i_concat = 1, n_msg_parts do -- Iterate up to n_msg_parts to handle nils correctly
						table.insert(string_parts_concat, tostring(msg_parts[i_concat]))
					end
					message = table.concat(string_parts_concat, " ")
				else
					message = "" -- No arguments passed to log function
				end

				-- Try to get line info (might be expensive, use with caution or make optional)
				local info = debug.getinfo(2, "Sl") -- Level 2 for the caller of log[level_name]
				local lineinfo_str = ""
				if info and info.short_src and info.currentline and info.currentline > 0 then
					lineinfo_str = string.format("%s:%d", info.short_src, info.currentline)
				end

				local formatted_log = string.format(
					"%s [%-5s] %s: %s\n",
					os.date("%Y-%m-%d %H:%M:%S"),
					level_name:upper(),
					lineinfo_str,
					message
				)
				file_handle:write(formatted_log)
				file_handle:flush()
			end
		end
	else
		-- If original function doesn't exist, create a basic one for file logging
		log[level_name] = function(...)
			if file_handle then
				local msg_parts = {}
				for i = 1, select("#", ...) do
					table.insert(msg_parts, select(i, ...))
				end
				local message
				if #msg_parts > 0 and type(msg_parts[1]) == "string" and #msg_parts > 1 then
					message = string.format(msg_parts[1], unpack(msg_parts, 2, #msg_parts))
				elseif #msg_parts > 0 then
					local string_parts = {}
					for _, p in ipairs(msg_parts) do
						table.insert(string_parts, tostring(p))
					end
					message = table.concat(string_parts, " ")
				else
					message = ""
				end
				local info = debug.getinfo(2, "Sl")
				local lineinfo_str = ""
				if info and info.short_src and info.currentline and info.currentline > 0 then
					lineinfo_str = string.format("%s:%d", info.short_src, info.currentline)
				end
				local formatted_log = string.format(
					"%s [%-5s] %s: %s\n",
					os.date("%Y-%m-%d %H:%M:%S"),
					level_name:upper(),
					lineinfo_str,
					message
				)
				file_handle:write(formatted_log)
				file_handle:flush()
			end
		end
	end
end

-- Ensure the log file is closed when Lua exits, if possible.
-- This is a best-effort approach. For robust cleanup, a proper exit handler
-- mechanism in the main application would be better.
-- local cleanup = { __gc = function() if file_handle then file_handle:close() end }
-- setmetatable({}, cleanup)
-- Note: Lua's default GC behavior might not guarantee __gc on script exit for upvalues.
-- A more explicit close in the main app's shutdown is safer if critical.

return log
