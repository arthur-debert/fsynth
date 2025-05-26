-- Mock log module for testing
local mock_log = {}

-- Define all the log levels
local levels = { "trace", "debug", "info", "warn", "error", "fatal" }

-- Create mock functions for each log level
for _, level in ipairs(levels) do
	mock_log[level] = function(_)
		-- During tests, we don't need to actually log anything
		-- This just prevents errors when code tries to log
	end
end

-- Set default level
mock_log.level = "info"
mock_log.outfile = os.getenv("TMPDIR") and (os.getenv("TMPDIR") .. "/lua-fsynth-test.log") or "/tmp/lua-fsynth-test.log"

return mock_log
