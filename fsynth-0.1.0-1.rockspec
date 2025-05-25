rockspec_format = "3.0"
package = "fsynth"
version = "0.1.0-1"
source = {
   url = "git+https://github.com/username/fsynth.lua.git",
   tag = "v0.1.0"
}
description = {
   summary = "Synthetic filesystem for isolated operations",
   detailed = [[
      Fsynth provides a synthetic filesystem abstraction to isolate and queue 
      filesystem operations for batch execution. The primary goal is to separate 
      planning from execution, allowing most of the codebase to remain functional 
      and side-effect free.
   ]],
   homepage = "https://github.com/username/fsynth.lua",
   license = "MIT"
}
dependencies = {
   "lua >= 5.1",
   "penlight >= 1.5.0"
}
test_dependencies = {
   "busted >= 2.0.0"
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
      ["fsynth.operations.copy_file"] = "fsynth/operations/copy_file.lua",
      ["fsynth.operations.create_directory"] = "fsynth/operations/create_directory.lua",
      ["fsynth.operations.create_file"] = "fsynth/operations/create_file.lua",
      ["fsynth.operations.delete"] = "fsynth/operations/delete.lua",
      ["fsynth.operations.move"] = "fsynth/operations/move.lua",
      ["fsynth.operations.symlink"] = "fsynth/operations/symlink.lua"
   },
   copy_directories = {
      "docs"
   }
}
test = {
   type = "busted",
   -- Additional test configuration can go here
}