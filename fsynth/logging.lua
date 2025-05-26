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
