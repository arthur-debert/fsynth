-- This module does test setup for looging
local lual = require("lual")
local M = {}

M.setup_logging = function()
	lual.config({
		level = lual.debug,
		pipelines = {
			{
				level = lual.debug,
				outputs = { type = lual.file, path = "/tmp/melt.log" }
			},
			{
				level = lual.debug,
				outputs = { type = lual.console },
				presenters = { lual.color }
			}
		},
		command_line_verbosity = {
			mapping = {
				v = "debug",
			},
			auto_detect = true,
		}
	})
	local logger = lual.logger()
	logger.debug("Logging setup complete - file output enabled")
	return true
end

return M
