-- Test setup for fsynth
-- First ensure paths are set properly so dependencies can be found

-- Add project root and fsynth module paths
local project_root = os.getenv("FSYNTH_ROOT") or "../"
package.path = project_root
	.. "/?.lua;"
	.. project_root
	.. "/fsynth/?.lua;"
	.. project_root
	.. "/fsynth/?/init.lua;"
	.. project_root
	.. "/spec/?.lua;"
	.. project_root
	.. "/spec/mocks/?.lua;"
	.. package.path
-- Add our spec/mocks directory to the package path
package.path = project_root .. "/spec/mocks/?.lua;" .. package.path

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

-- Make helper functions available to all test files
_G.get_tmp_dir = get_tmp_dir
_G.clean_tmp_dir = clean_tmp_dir

-- Setup and teardown hooks for Busted
-- These will be available to test files because busted puts them in the global environment
-- But we need to check if they exist to avoid errors when running this file directly
if _G.before_each then
	_G.before_each(function()
		clean_tmp_dir()
	end)
end

if _G.after_each then
	_G.after_each(function()
		clean_tmp_dir()
	end)
end

-- Export helper functions to spec_helper for access in other test files
local helper = {}
helper.get_tmp_dir = get_tmp_dir
helper.clean_tmp_dir = clean_tmp_dir

return helper
