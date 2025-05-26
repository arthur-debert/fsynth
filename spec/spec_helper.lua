local pl_path = require("pl.path")

-- Helper functions for fsynth tests

local M = {}

function M.is_windows()
	return pl_path.sep == "\\\\"
end

-- Get the temporary directory for tests
local function get_tmp_dir()
	local tmpdir = os.getenv("TMPDIR") or "/tmp"
	local fsynth_test_dir = tmpdir .. "/fsynth_tests"
	-- Create the test directory if it doesn't exist
	local success, err = os.execute("mkdir -p " .. fsynth_test_dir)
	if not success then
		error("Failed to create test directory: " .. (err or "unknown error"))
	end
	return fsynth_test_dir
end

-- Clean function to remove test files after tests
local function clean_tmp_dir()
	local tmp_dir = get_tmp_dir()
	os.execute("rm -rf " .. tmp_dir .. "/*")
end

-- Make these functions available
local function rmdir_recursive(dir_path)
	if dir_path and type(dir_path) == "string" and dir_path ~= "/" and dir_path ~= "." and dir_path ~= ".." then
		-- Basic safety checks for the path
		-- Ensure it's within the temp directory structure if possible, or just be careful
		local tmp_root = os.getenv("TMPDIR") or "/tmp"
		if string.sub(dir_path, 1, string.len(tmp_root)) == tmp_root then
			os.execute("rm -rf " .. '"' .. dir_path .. '"')
		else
			-- Or handle error: not removing arbitrary paths
			print("Warning: rmdir_recursive called on a path not confirmed to be in temp: " .. dir_path)
		end
	else
		print("Warning: rmdir_recursive called with invalid path: " .. tostring(dir_path))
	end
end

return {
	get_tmp_dir = get_tmp_dir,
	clean_tmp_dir = clean_tmp_dir,
	rmdir_recursive = rmdir_recursive,
	is_windows = M.is_windows,
	readlink = function(path_str)
		local lfs = require("lfs")
		return lfs.symlinkattributes(path_str, "target")
	end,
}
