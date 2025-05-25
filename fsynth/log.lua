-- Logging module for fsynth
-- Configures and provides logging capabilities using log.lua

local log = require("log")

-- Configure the logger
log.level = "info"  -- Default log level (info and above)
log.outfile = "/var/tmp/lua-fsynth.log"  -- File output location

-- Create a separate logger instance for file logging with 'trace' level
local file_log = setmetatable({}, {__index = log})
file_log.level = "trace"  -- Log all levels to file
file_log.outfile = "/var/tmp/lua-fsynth.log"
file_log.usecolor = false  -- Disable colors in file output

-- Override the methods to ensure file logging always happens
for _, mode in ipairs({"trace", "debug", "info", "warn", "error", "fatal"}) do
    local original_fn = log[mode]
    log[mode] = function(...)
        -- Call original log function (will output to console based on log.level)
        original_fn(...)
        -- Also ensure writing to file regardless of console log level
        if mode ~= log.level and file_log.level == "trace" then
            local msg = select(1, ...)
            if type(msg) == "string" and select('#', ...) > 1 then
                -- Format message with any additional arguments
                msg = string.format(msg, select(2, ...))
            end
            local info = debug.getinfo(2, "Sl")
            local lineinfo = info.short_src .. ":" .. info.currentline
            -- Write to file directly
            local fp = io.open(file_log.outfile, "a")
            if fp then
                local nameupper = mode:upper()
                local str = string.format("[%-6s%s] %s: %s\n",
                                         nameupper, os.date(), lineinfo, msg)
                fp:write(str)
                fp:close()
            end
        end
    end
end

return log