-- Logging module for fsynth
-- Configures and provides logging capabilities using log.lua if available
-- By default, all levels will log to a file in /var/tmp/lua-fsynth.log, with
-- logs truncated at every run.
-- For the stream handler to output, you must set the log level to at least info
--
-- Testings will work like regular lib code: always log to the file, won't
-- log to stream unless log level is at least info.

local log

-- Try to load the log module, but provide a fallback if it fails
local success, result = pcall(require, "log")

local DEFAULT_LOG_LEVEL = "warn"
if success then
	log = result
else
	-- Create a simple fallback logger for testing or when log module is unavailable
	log = {}
	-- Define standard log levels
	local levels = { "trace", "debug", "info", "warn", "error", "fatal" }
	for _, level in ipairs(levels) do
		log[level] = function(msg, ...)
			if select("#", ...) > 0 and type(msg) == "string" then
				msg = string.format(msg, ...)
			end
		end
	end
end

-- Configure the logger
log.level = DEFAULT_LOG_LEVEL -- Default log level (stream outputs at info or higher)
log.outfile = os.getenv("FSYNTH_LOG_FILE") or "/var/tmp/lua-fsynth.log"

-- Set up file logging (always, including in test mode)
-- Truncate the log file at every run
local function truncate_log_file()
	local fp = io.open(log.outfile, "w")
	if fp then
		fp:close()
	end
end

-- Truncate the log file immediately when the module is loaded
truncate_log_file()

-- If using the real log module, set up file logging
if success then
	-- Create a separate logger instance for file logging with 'trace' level
	local file_log = setmetatable({}, { __index = log })
	file_log.level = "trace" -- Log all levels to file
	file_log.outfile = log.outfile
	file_log.usecolor = false -- Disable colors in file output

	-- Override the methods to ensure file logging always happens
	for _, mode in ipairs({ "trace", "debug", "info", "warn", "error", "fatal" }) do
		local original_fn = log[mode]
		log[mode] = function(...)
			-- Call original log function (will output to console based on log.level)
			original_fn(...)
			-- Also ensure writing to file regardless of console log level
			if mode ~= log.level and file_log.level == "trace" then
				local msg = select(1, ...)
				if type(msg) == "string" and select("#", ...) > 1 then
					-- Format message with any additional arguments
					msg = string.format(msg, select(2, ...))
				end
				local info = debug.getinfo(2, "Sl")
				local lineinfo = info.short_src .. ":" .. info.currentline
				-- Write to file directly
				local fp = io.open(file_log.outfile, "a")
				if fp then
					local nameupper = mode:upper()
					local str = string.format("[%-6s%s] %s: %s\n", nameupper, os.date(), lineinfo, msg)
					fp:write(str)
					fp:close()
				end
			end
		end
	end
end

return log
