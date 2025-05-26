-- fsynth/logging.lua
-- Configures and provides logging capabilities using log.lua

local log = require("log")

-- Configuration
local LOG_FILE_PATH = os.getenv("FSYNTH_LOG_FILE") or "/var/tmp/lua-fsynth.log"
local CONSOLE_LOG_LEVEL = os.getenv("FSYNTH_LOG_LEVEL") or "warn"
log.level = CONSOLE_LOG_LEVEL
log.usecolor = true -- log.lua library uses a boolean for this
log.outfile = LOG_FILE_PATH

-- Truncate log file at startup
local function truncate_log_file(filepath)
	local fp, err = io.open(filepath, "w")
	if fp then
		fp:close()
	else
		local warn_msg = string.format("Warn: Truncate failed for '%s': %s\n", filepath, err or "unknown")
		print(warn_msg) -- Print to stdout to satisfy selene linter
	end
end
truncate_log_file(LOG_FILE_PATH)

return log

--
-- Information about the `log.lua` library (version 0.1.0 by rxi):
--
-- Source Repository:
--   https://github.com/rxi/log.lua
--
-- Location in this project (installed via Luarocks):
--   .luarocks/share/lua/5.4/log.lua (relative to project root)
--
-- Key Configuration Options:
--   log.level (string): Sets the minimum log level to output.
--                       (e.g., "trace", "debug", "info", "warn", "error", "fatal")
--   log.outfile (string): Path to a file where logs will be appended. If nil, only console logging.
--   log.usecolor (boolean): Toggles ANSI color codes for console output (true by default).
--
-- Behavior:
--   - Logs to stdout (console).
--   - If `log.outfile` is set, logs are also appended to that file.
--   - Automatically includes timestamp, log level, source file:line, and the message.
--   - Does not provide a mechanism for custom log handlers beyond its built-in file/console output.
