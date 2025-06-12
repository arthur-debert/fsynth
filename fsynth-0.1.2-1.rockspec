rockspec_format = "3.0"
package = "fsynth"
version = "0.1.2-1"
source = {
	url = "git://github.com/arthur-debert/fsynth",
}
-- The 'source' attribute can be omitted for local development if using
-- `luarocks make` to build and install from local source files.
-- `luarocks install` requires the 'source' attribute.
description = {
	summary = "Synthetic filesystem for isolated operations",
	detailed = [[
      Fsynth provides a synthetic filesystem abstraction to isolate and queue
      filesystem operations for batch execution. The primary goal is to separate
      planning from execution, allowing most of the codebase to remain functional
      and side-effect free.
   ]],
	homepage = "https://github.com/arthur-debert/fsynth",
	license = "MIT",
}
dependencies = {
	"lua >= 5.1",
	"penlight >= 1.14.0",
	"lual >= 1.0.11",
	"string-format-all >= 0.2.0", -- Package name uses hyphens, but require() uses dots
}
test_dependencies = {
	"busted >= 2.0.0",
	"luacov >= 0.16.0-1 ",
}
build = {
	type = "builtin",
	install = {
		lua = {
			["fsynth"] = "lua/fsynth",
		},
	},
}
test = {
	type = "busted",
	-- Additional test configuration can go here
}
