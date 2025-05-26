local helper = require("spec.spec_helper")
local CreateDirectoryOperation = require("fsynth.operations.create_directory")
local pl_path = require("pl.path")
local file_permissions = require("fsynth.file_permissions") -- Added
-- local fs = require("pl.fs")

local is_windows = pl_path.sep == "\\\\" -- Added

describe("CreateDirectoryOperation", function()
	local tmp_dir

	before_each(function()
		helper.clean_tmp_dir()
		tmp_dir = helper.get_tmp_dir()
	end)

	after_each(function()
		helper.clean_tmp_dir()
	end)

	describe(":execute", function()
		it("should create a new, empty directory", function()
			local dir_path_str = pl_path.join(tmp_dir, "new_dir")
			local op = CreateDirectoryOperation.new(dir_path_str)

			local success, err = op:execute()
			assert.is_true(success, err)
			assert.equal(dir_path_str, pl_path.exists(dir_path_str))
			assert.is_true(pl_path.isdir(dir_path_str))
			assert.is_true(op.dir_actually_created_by_this_op)
		end)

		describe("options.mode (permissions)", function()
			it("should create a new directory with specified permissions (Unix-like mode)", function()
				if is_windows then
					pending("Skipping Unix-like mode test for directories on Windows")
					return
				end
				local dir_path_str = pl_path.join(tmp_dir, "new_dir_with_mode")
				local op = CreateDirectoryOperation.new(dir_path_str, { mode = "755" })
				local success, err = op:execute()
				assert.is_true(success, err)
				assert.is_true(pl_path.isdir(dir_path_str))
				local current_mode, mode_err = file_permissions.get_mode(dir_path_str)
				assert.is_not_nil(current_mode, mode_err)
				assert.are.equal("755", current_mode)
			end)

			it("should create a new directory and affect its writability for content (Unix-like mode 555)", function()
				if is_windows then
					-- Windows directory permissions are complex; 'attrib +R' on a dir doesn't prevent creation inside.
					-- Our file_permissions.set_mode for dirs on Windows is a no-op for read-only type attributes.
					pending("Skipping dir read-only (content) test on Windows due to platform differences.")
					return
				end
				local dir_path_str = pl_path.join(tmp_dir, "new_dir_readonly_content")
				-- Mode "555" (r-xr-xr-x) makes the directory readable and executable but not writable for content.
				local op = CreateDirectoryOperation.new(dir_path_str, { mode = "555" })
				local success, err = op:execute()
				assert.is_true(success, err)
				assert.is_true(pl_path.isdir(dir_path_str))

				local current_mode, mode_err = file_permissions.get_mode(dir_path_str)
				assert.is_not_nil(current_mode, mode_err)
				assert.are.equal("555", current_mode)

				-- Verify writability (ability to create items inside)
				local writable, write_check_err = file_permissions.is_writable(dir_path_str)
				assert.is_not_nil(writable, write_check_err)
				assert.is_false(writable, "Directory should not be writable for content")
			end)

			it("should create a new directory and ensure it is writable for content (Unix-like mode 777)", function()
				if is_windows then
					pending("Skipping dir writable (content) test on Windows as default is usually writable.")
					return
				end
				local dir_path_str = pl_path.join(tmp_dir, "new_dir_writable_content")
				-- Mode "777" (rwxrwxrwx)
				local op = CreateDirectoryOperation.new(dir_path_str, { mode = "777" })
				local success, err = op:execute()
				assert.is_true(success, err)
				assert.is_true(pl_path.isdir(dir_path_str))

				local current_mode, mode_err = file_permissions.get_mode(dir_path_str)
				assert.is_not_nil(current_mode, mode_err)
				assert.are.equal("777", current_mode)

				-- Verify writability
				local writable, write_check_err = file_permissions.is_writable(dir_path_str)
				assert.is_not_nil(writable, write_check_err)
				assert.is_true(writable, "Directory should be writable for content")
			end)
		end)

		it("should fail to create a directory if parent directory is not writable (Unix-like)", function()
			if is_windows then
				pending("Skipping parent non-writable test on Windows due to complexity of setting up.")
				return
			end
			local non_writable_parent_str = pl_path.join(tmp_dir, "non_writable_parent_for_dir")
			assert.is_true(pl_path.mkdir(non_writable_parent_str), "Failed to create parent for test")
			-- Set parent to r-x------ (owner cannot write into it)
			local mode_set_ok, mode_set_err = file_permissions.set_mode(non_writable_parent_str, "500")
			assert.is_true(mode_set_ok, "Failed to set parent dir to non-writable: " .. tostring(mode_set_err))

			local parent_writable, parent_writable_err = file_permissions.is_writable(non_writable_parent_str)
			assert.is_false(
				parent_writable,
				"Parent directory '"
					.. non_writable_parent_str
					.. "' should be non-writable for the test to be valid. Error: "
					.. tostring(parent_writable_err)
			)

			local dir_path_str = pl_path.join(non_writable_parent_str, "dir_in_non_writable")
			-- create_parent_dirs is true by default, but makepath should fail if parent is not writable.
			-- Let's be explicit for the test's purpose if we want to test mkdir directly.
			-- However, the operation checks parent writability before attempting makepath or mkdir.
			local op = CreateDirectoryOperation.new(dir_path_str, { create_parent_dirs = false })

			local success, err = op:execute()
			assert.is_false(success)
			assert.match("Parent directory '.+' is not writable", err, "Error message mismatch. Got: " .. tostring(err))
			assert.is_false(pl_path.exists(dir_path_str))

			-- Cleanup: try to make parent writable again
			pcall(file_permissions.set_mode, non_writable_parent_str, "700")
		end)

		describe("options.exclusive = true", function()
			it("should succeed if the directory does not already exist", function()
				local dir_path_str = pl_path.join(tmp_dir, "exclusive_dir")
				local op = CreateDirectoryOperation.new(dir_path_str, { exclusive = true })

				local success, err = op:execute()
				assert.is_true(success, err)
				assert.equal(dir_path_str, pl_path.exists(dir_path_str))
				assert.is_true(op.dir_actually_created_by_this_op)
			end)

			it("should fail if the directory already exists", function()
				local dir_path_str = pl_path.join(tmp_dir, "exclusive_dir_exists")
				-- path.mkdir returns true on success
				assert.is_true(pl_path.mkdir(dir_path_str))

				local op = CreateDirectoryOperation.new(dir_path_str, { exclusive = true })
				local success, err = op:execute()
				assert.is_false(success)
				assert.match("already exists", err)
				assert.is_false(op.dir_actually_created_by_this_op)
			end)
		end)

		describe("options.exclusive = false", function()
			it("should report success if the directory already exists and exclusive is false", function()
				local dir_path_str = pl_path.join(tmp_dir, "non_exclusive_dir_exists")
				-- path.mkdir returns true on success
				assert.is_true(pl_path.mkdir(dir_path_str))

				local op = CreateDirectoryOperation.new(dir_path_str, { exclusive = false })
				local success, err = op:execute()
				assert.is_true(success, err)
				assert.equal(dir_path_str, pl_path.exists(dir_path_str))
				assert.is_false(op.dir_actually_created_by_this_op)
			end)

			it("should report success if the directory already exists and exclusive is not specified", function()
				local dir_path_str = pl_path.join(tmp_dir, "non_exclusive_dir_exists_implicit")
				-- path.mkdir returns true on success
				assert.is_true(pl_path.mkdir(dir_path_str))

				local op = CreateDirectoryOperation.new(dir_path_str)
				local success, err = op:execute()
				assert.is_true(success, err)
				assert.equal(dir_path_str, pl_path.exists(dir_path_str))
				assert.is_false(op.dir_actually_created_by_this_op)
			end)
		end)

		describe("options.create_parent_dirs = true", function()
			it("should create nested directories if parent directories do not exist", function()
				local dir_path_str = pl_path.join(tmp_dir, "parent", "child", "grandchild")
				local op = CreateDirectoryOperation.new(dir_path_str, { create_parent_dirs = true })

				local success, err = op:execute()
				assert.is_true(success, err)
				assert.equal(dir_path_str, pl_path.exists(dir_path_str))
				assert.equal(
					pl_path.join(tmp_dir, "parent", "child"),
					pl_path.exists(pl_path.join(tmp_dir, "parent", "child"))
				)
				assert.equal(pl_path.join(tmp_dir, "parent"), pl_path.exists(pl_path.join(tmp_dir, "parent")))
				assert.is_true(op.dir_actually_created_by_this_op)
			end)
		end)

		describe("options.create_parent_dirs = false", function()
			it("should fail if an intermediate parent directory does not exist", function()
				local dir_path_str = pl_path.join(tmp_dir, "parent_missing", "child")
				local op = CreateDirectoryOperation.new(dir_path_str, { create_parent_dirs = false })

				local success, err = op:execute()
				assert.is_false(success)
				-- The error now comes from the pre-check in execute()
				assert.match("Parent directory '.+' does not exist and create_parent_dirs is false", err)
				assert.is_false(op.dir_actually_created_by_this_op)
			end)

			it("should succeed if the immediate parent directory exists", function()
				local parent_dir_str = pl_path.join(tmp_dir, "existing_parent")
				-- path.mkdir returns true on success
				assert.is_true(pl_path.mkdir(parent_dir_str))
				local dir_path_str = pl_path.join(parent_dir_str, "child")
				local op = CreateDirectoryOperation.new(dir_path_str, { create_parent_dirs = false })

				local success, err = op:execute()
				assert.is_true(success, err)
				assert.equal(dir_path_str, pl_path.exists(dir_path_str))
				assert.is_true(op.dir_actually_created_by_this_op)
			end)
		end)

		describe("Validation Failures", function()
			it("should fail validation if the target path is an existing file", function()
				local file_path_str = pl_path.join(tmp_dir, "existing_file.txt")
				local f = io.open(file_path_str, "w")
				assert.is_not_nil(f)
				f:write("hello")
				f:close()

				local op = CreateDirectoryOperation.new(file_path_str)
				local success, err = op:execute()
				assert.is_false(success)
				assert.match("exists and is not a directory", err)
			end)

			it("should fail validation if the target path is not specified (nil)", function()
				local op = CreateDirectoryOperation.new(nil)
				local success, err = op:validate() -- Assuming validate is called by execute or directly testable
				assert.is_false(success)
				assert.match("Target directory path not specified", err)
			end)

			it("should fail validation if the target path is not specified (empty string)", function()
				local op = CreateDirectoryOperation.new("")
				local success, err = op:validate() -- Assuming validate is called by execute or directly testable
				assert.is_false(success)
				assert.match("Target directory path not specified", err)
			end)
		end)
	end)

	describe(":undo", function()
		it("should remove a directory that was created by the operation", function()
			local dir_path_str = pl_path.join(tmp_dir, "undo_dir")
			local op = CreateDirectoryOperation.new(dir_path_str)

			local success, err = op:execute()
			assert.is_true(success, err)
			assert.equal(dir_path_str, pl_path.exists(dir_path_str))
			assert.is_true(op.dir_actually_created_by_this_op)

			local undo_success, undo_err = op:undo()
			assert.is_true(undo_success, undo_err)
			assert.is_false(pl_path.exists(dir_path_str))
		end)

		it("should not remove a directory if dir_actually_created_by_this_op is false", function()
			local dir_path_str = pl_path.join(tmp_dir, "undo_not_created_dir")
			-- path.mkdir returns true on success
			assert.is_true(pl_path.mkdir(dir_path_str)) -- Pre-existing directory

			local op = CreateDirectoryOperation.new(dir_path_str, { exclusive = false })
			local success, err = op:execute()
			assert.is_true(success, err)
			assert.is_false(op.dir_actually_created_by_this_op) -- Key condition

			local undo_success, undo_err = op:undo()
			assert.is_true(undo_success, undo_err) -- Undo should report success (no-op)
			assert.equal(dir_path_str, pl_path.exists(dir_path_str)) -- Directory should still exist
		end)

		it("should fail (or do nothing harmlessly) if the directory is not empty before undoing", function()
			local dir_path_str = pl_path.join(tmp_dir, "undo_not_empty_dir")
			local op = CreateDirectoryOperation.new(dir_path_str)

			local success, err = op:execute()
			assert.is_true(success, err)
			assert.is_true(op.dir_actually_created_by_this_op)

			-- Create a file inside the directory
			local file_in_dir_str = pl_path.join(dir_path_str, "some_file.txt")
			local f = io.open(file_in_dir_str, "w")
			assert.is_not_nil(f)
			f:write("content")
			f:close()

			local undo_success, undo_err = op:undo()
			assert.is_false(undo_success)
			-- Updated to check for the actual error message
			assert.match("not empty", undo_err)
			assert.equal(dir_path_str, pl_path.exists(dir_path_str)) -- Directory should still exist
		end)

		it(
			"should succeed (or do nothing harmlessly) if the directory to be removed by undo does not exist anymore",
			function()
				local dir_path_str = pl_path.join(tmp_dir, "undo_dir_already_gone")
				local op = CreateDirectoryOperation.new(dir_path_str)

				local success, err = op:execute()
				assert.is_true(success, err)
				assert.is_true(op.dir_actually_created_by_this_op)
				assert.equal(dir_path_str, pl_path.exists(dir_path_str))

				-- Manually remove the directory
				-- path.rmdir returns true on success
				assert.is_true(pl_path.rmdir(dir_path_str))
				assert.is_false(pl_path.exists(dir_path_str))

				local undo_success, undo_err = op:undo()
				-- Updated - this should actually fail because the directory is not there
				assert.is_false(undo_success, undo_err)
			end
		)

		it(
			"PENDING: should clarify undo behavior if the directory to be removed by undo does not exist anymore",
			function()
				-- Explanation: The current test for an already-gone directory expects undo to fail.
				-- This is a strict interpretation. Other operations (e.g., SymlinkOperation undo)
				-- might treat this as a successful no-op.
				-- This test is a placeholder to decide on a consistent philosophy:
				-- - Strict failure: If the item the op created is gone, undo fails. (Current behavior for CreateDirectory)
				-- - Tolerant success: If the item is gone, undo considers its job done.
				pending(
					"Decide on consistent undo philosophy for items already gone (strict failure vs. tolerant success)."
				)
				-- Example for tolerant success:
				-- local dir_path_str = pl_path.join(tmp_dir, "undo_dir_already_gone_tolerant")
				-- local op = CreateDirectoryOperation.new(dir_path_str)
				-- local _, _ = op:execute()
				-- assert.is_true(pl_path.rmdir(dir_path_str))
				-- local undo_success, undo_err = op:undo()
				-- assert.is_true(undo_success, undo_err)
			end
		)
	end)
end)
