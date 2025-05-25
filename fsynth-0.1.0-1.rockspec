rockspec_format = "3.0"
package = "fsynth"
version = "0.1.0-1"
source = {
   url = "."
}
description = {
   summary = "Synthetic filesystem for isolated operations",
   detailed = [[
      Fsynth provides a synthetic filesystem abstraction to isolate and queue 
      filesystem operations for batch execution. The primary goal is to separate 
      planning from execution, allowing most of the codebase to remain functional 
      and side-effect free.
   ]],
   homepage = "https://github.com/arthur-debert/fsynth.lua",
   license = "MIT"
}
dependencies = {
   "lua >= 5.1",
   "penlight >= 1.5.0",
   "log.lua >= 0.1.0",
   "string-format-all >= 0.2.0", -- Package name uses hyphens, but require() uses dots
   "busted >= 2.0.0"
}
test_dependencies = {
}
build = {
   type = "builtin",
   modules = {
      ["fsynth.init"] = "fsynth/init.lua",
      ["fsynth.operation_base"] = "fsynth/operation_base.lua",
      ["fsynth.processor"] = "fsynth/processor.lua",
      ["fsynth.queue"] = "fsynth/queue.lua",
      ["fsynth.checksum"] = "fsynth/checksum.lua",
      ["fsynth.utils"] = "fsynth/utils.lua",
      ["fsynth.log"] = "fsynth/log.lua",
      ["fsynth.operations.copy_file"] = "fsynth/operations/copy_file.lua",
      ["fsynth.operations.create_directory"] = "fsynth/operations/create_directory.lua",
      ["fsynth.operations.create_file"] = "fsynth/operations/create_file.lua",
      ["fsynth.operations.delete"] = "fsynth/operations/delete.lua",
      ["fsynth.operations.move"] = "fsynth/operations/move.lua",
      ["fsynth.operations.symlink"] = "fsynth/operations/symlink.lua"
   },
   copy_directories = {"docs"}
}
test = {
   type = "busted",
   -- Additional test configuration can go here
}