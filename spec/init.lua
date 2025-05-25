-- Simple test setup for fsynth
package.path = package.path .. ";../?.lua;./?/init.lua"

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

-- Setup and teardown hooks for Busted
before_each(function()
  clean_tmp_dir()
end)

after_each(function()
  clean_tmp_dir()
end)

-- The require statements below are not needed as Busted will automatically discover the spec files