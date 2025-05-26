local helper = require("spec.spec_helper")
local CreateFileOperation = require("fsynth.operations.create_file")
local file_permissions = require("fsynth.file_permissions") -- Added
local pl_path = require("pl.path")
local pl_file = require("pl.file") -- Updated import - using file instead of fs

local is_windows = pl_path.sep == "\\\\" -- Added

describe("CreateFileOperation", function()
	local tmp_dir

	before_each(function()
		helper.clean_tmp_dir()
		tmp_dir = helper.get_tmp_dir()
	end)

	after_each(function()
		helper.clean_tmp_dir()
	end)

	local function create_file_for_test(path_str, content)
		content = content or ""
		local file = io.open(path_str, "w")
		assert.is_not_nil(file, "Failed to create file for test setup: " .. path_str)
		file:write(content)
		file:close()
		assert.are.equal(path_str, pl_path.exists(path_str), "File was not created: " .. path_str)
	end

	local function read_file_content(path_str)
		local file = io.open(path_str, "r")
		if not file then
			return nil
		end
		local content = file:read("*a")
		file:close()
		return content
	end

	describe(":execute", function()
		it("should create a new, empty file by default", function()
			local file_path_str = pl_path.join(tmp_dir, "new_empty_file.txt")
			local op = CreateFileOperation.new(file_path_str)

			local success, err = op:execute()
			assert.is_true(success, err)
			assert.are.equal(file_path_str, pl_path.exists(file_path_str))
			assert.are.equal("", read_file_content(file_path_str))
			assert.is_not_nil(op.checksum_data.target_checksum)
		end)

		it("should create a new file with specified string content", function()
			local file_path_str = pl_path.join(tmp_dir, "new_file_with_content.txt")
			local content = "Hello, Fsynth!"
			local op = CreateFileOperation.new(file_path_str, { content = content })

			local success, err = op:execute()
			assert.is_true(success, err)
			assert.are.equal(file_path_str, pl_path.exists(file_path_str))
			assert.are.equal(content, read_file_content(file_path_str))
			assert.is_not_nil(op.checksum_data.target_checksum)
		end)

		describe("options.mode (permissions)", function()
			it("should create a new file with specified permissions (Unix-like mode)", function()
				if is_windows then
					pending("Skipping Unix-like mode test on Windows")
					return
				end
				local file_path_str = pl_path.join(tmp_dir, "new_file_with_mode.txt")
				local op = CreateFileOperation.new(file_path_str, { content = "mode test", mode = "755" })
				local success, err = op:execute()
				assert.is_true(success, err)
				assert.are.equal(file_path_str, pl_path.exists(file_path_str))
				local current_mode, mode_err = file_permissions.get_mode(file_path_str)
				assert.is_not_nil(current_mode, mode_err)
				assert.are.equal("755", current_mode)
			end)

			it("should create a new file and set it to read-only (platform-agnostic check via get_mode)", function()
				local file_path_str = pl_path.join(tmp_dir, "new_file_readonly.txt")
				-- "444" should make it read-only on Unix, and interpreted as read-only on Windows by our logic
				local op = CreateFileOperation.new(file_path_str, { content = "mode test", mode = "444" })
				local success, err = op:execute()
				assert.is_true(success, err)
				assert.are.equal(file_path_str, pl_path.exists(file_path_str))
				local current_mode, mode_err = file_permissions.get_mode(file_path_str)
				assert.is_not_nil(current_mode, mode_err)
				assert.are.equal("444", current_mode) -- file_permissions.get_mode returns "444" for read-only

				local writable, write_check_err = file_permissions.is_writable(file_path_str)
				assert.is_not_nil(writable, write_check_err)
				assert.is_false(writable, "File should be read-only (not writable)")
			end)

			it("should create a new file and set it to writable (platform-agnostic check via get_mode)", function()
				local file_path_str = pl_path.join(tmp_dir, "new_file_writable.txt")
				-- "666" should make it writable
				local op = CreateFileOperation.new(file_path_str, { content = "mode test", mode = "666" })
				local success, err = op:execute()
				assert.is_true(success, err)
				assert.are.equal(file_path_str, pl_path.exists(file_path_str))
				local current_mode, mode_err = file_permissions.get_mode(file_path_str)
				assert.is_not_nil(current_mode, mode_err)
				assert.are.equal("666", current_mode) -- file_permissions.get_mode returns "666" for writable

				local writable, write_check_err = file_permissions.is_writable(file_path_str)
				assert.is_not_nil(writable, write_check_err)
				assert.is_true(writable, "File should be writable")
			end)
		end)

		it("should fail to create a file if parent directory is not writable (Unix-like)", function()
			if is_windows then
				pending(
					"Skipping parent non-writable test on Windows due to complexity of setting up reliable non-writable parent for current user."
				)
				return
			end
			local non_writable_parent_str = pl_path.join(tmp_dir, "non_writable_parent")
			assert.is_true(pl_path.mkdir(non_writable_parent_str), "Failed to create parent for test")
			-- Set parent to r-x------ (owner cannot write)
			local mode_set_ok, mode_set_err = file_permissions.set_mode(non_writable_parent_str, "500")
			assert.is_true(mode_set_ok, "Failed to set parent dir to non-writable: " .. tostring(mode_set_err))

			-- Verify parent is indeed not writable for our user
			local parent_writable, parent_writable_err = file_permissions.is_writable(non_writable_parent_str)
			assert.is_false(
				parent_writable,
				"Parent directory '"
					.. non_writable_parent_str
					.. "' should be non-writable for the test to be valid. Error: "
					.. tostring(parent_writable_err)
			)

			local file_path_str = pl_path.join(non_writable_parent_str, "file_in_non_writable.txt")
			local op = CreateFileOperation.new(file_path_str, { content = "test" })

			local success, err = op:execute()
			assert.is_false(success)
			assert.match("Parent directory '.+' is not writable", err, "Error message mismatch. Got: " .. tostring(err))
			assert.is_false(pl_path.exists(file_path_str))

			-- Cleanup: try to make parent writable again to allow tmp_dir cleanup
			pcall(file_permissions.set_mode, non_writable_parent_str, "700")
		end)

		describe("options.create_parent_dirs = true", function()
			it("should create nested directories and the file if parent directories do not exist", function()
				local file_path_str = pl_path.join(tmp_dir, "parent", "child", "new_file.txt")
				local content = "Nested!"
				local op = CreateFileOperation.new(file_path_str, {
					content = content,
					create_parent_dirs = true,
				})

				local success, err = op:execute()
				assert.is_true(success, err)
				assert.are.equal(
					pl_path.join(tmp_dir, "parent", "child"),
					pl_path.exists(pl_path.join(tmp_dir, "parent", "child"))
				)
				assert.are.equal(pl_path.join(tmp_dir, "parent"), pl_path.exists(pl_path.join(tmp_dir, "parent")))
				assert.are.equal(file_path_str, pl_path.exists(file_path_str))
				assert.are.equal(content, read_file_content(file_path_str))
				assert.is_not_nil(op.checksum_data.target_checksum)
			end)
		end)

		describe("options.create_parent_dirs = false (default)", function()
			it("should fail if an intermediate parent directory does not exist", function()
				local file_path_str = pl_path.join(tmp_dir, "missing_parent", "new_file.txt")
				local op = CreateFileOperation.new(file_path_str, { content = "test" })

				local success, err = op:execute()
				assert.is_false(success)
				assert.match("Parent directory '.+' does not exist and create_parent_dirs is false", err)
				assert.is_false(pl_path.exists(file_path_str))
				assert.is_nil(op.checksum_data.target_checksum)
			end)

			it("should succeed if the immediate parent directory exists", function()
				local parent_dir_str = pl_path.join(tmp_dir, "existing_parent_for_file")
				assert.is_true(pl_path.mkdir(parent_dir_str))
				local file_path_str = pl_path.join(parent_dir_str, "child_file.txt")
				local content = "Child content"
				local op = CreateFileOperation.new(file_path_str, { content = content })

				local success, err = op:execute()
				assert.is_true(success, err)
				assert.are.equal(file_path_str, pl_path.exists(file_path_str))
				assert.are.equal(content, read_file_content(file_path_str))
				assert.is_not_nil(op.checksum_data.target_checksum)
			end)
		end)

		describe("Validation Failures", function()
			it("should fail validation if options.content is a number", function()
				local op = CreateFileOperation.new(pl_path.join(tmp_dir, "file.txt"), { content = 123 })
				local valid, err = op:validate()
				assert.is_false(valid)
				assert.match("Content for CreateFileOperation must be a string", err)
			end)

			it("should fail validation if options.content is a table", function()
				local op = CreateFileOperation.new(pl_path.join(tmp_dir, "file.txt"), { content = {} })
				local valid, err = op:validate()
				assert.is_false(valid)
				assert.match("Content for CreateFileOperation must be a string", err)
			end)

			it("should fail validation if the target path is not specified (nil)", function()
				local op = CreateFileOperation.new(nil)
				local valid, err = op:validate()
				assert.is_false(valid)
				assert.match("Target path not specified for CreateFileOperation", err)
			end)

			it("should fail validation if the target path is not specified (empty string)", function()
				local op = CreateFileOperation.new("")
				local valid, err = op:validate()
				assert.is_false(valid)
				assert.match("Target path not specified for CreateFileOperation", err)
			end)

			it("should fail validation if the target path is an existing directory", function()
				local dir_path_str = pl_path.join(tmp_dir, "existing_dir_for_file_test")
				assert.is_true(pl_path.mkdir(dir_path_str))
				local op = CreateFileOperation.new(dir_path_str, { content = "test" })
				local success, err = op:execute()
				assert.is_false(success)
				assert.match("is an existing directory", err)
			end)

			it("should fail if the target path already exists and is a file (implicit exclusive)", function()
				local file_path_str = pl_path.join(tmp_dir, "existing_file_for_create.txt")
				local f = io.open(file_path_str, "w")
				f:write("original content")
				f:close()

				local op = CreateFileOperation.new(file_path_str, { content = "new content" })
				local success, err = op:execute()
				assert.is_false(success)
				assert.match("already exists", err)
			end)
		end)
	end)

	describe(":undo", function()
		it("should remove a file that was created by the operation", function()
			local file_path_str = pl_path.join(tmp_dir, "undo_create_file.txt")
			local content = "content for undo"
			local op = CreateFileOperation.new(file_path_str, { content = content })

			local success, err = op:execute()
			assert.is_true(success, err)
			assert.are.equal(file_path_str, pl_path.exists(file_path_str))
			assert.is_not_nil(op.checksum_data.target_checksum)

			local undo_success, undo_err = op:undo()
			assert.is_true(undo_success, undo_err)
			assert.is_false(pl_path.exists(file_path_str))
		end)

		it(
			"should succeed tolerantly if the file does not exist at the time of undo (previously strict fail)",
			function()
				-- DECISION: Aligned with tolerant success policy.
				local file_path_str = pl_path.join(tmp_dir, "undo_file_gone.txt")
				local op = CreateFileOperation.new(file_path_str, { content = "test" })

				local success, err = op:execute()
				assert.is_true(success, err)
				assert.are.equal(file_path_str, pl_path.exists(file_path_str))
				local stored_checksum = op.checksum_data.target_checksum

				assert.is_true(pl_file.delete(file_path_str)) -- Updated to pl_file.delete

				op.checksum_data.target_checksum = stored_checksum -- Restore checksum as if it was set by op
				local undo_success, undo_err = op:undo()
				assert.is_true(undo_success, "Undo should succeed tolerantly: " .. tostring(undo_err))
				assert.match("already did not exist", undo_err, "Undo error message mismatch")
			end
		)

		it("should fail if the file's content (and thus checksum) has changed since creation", function()
			local file_path_str = pl_path.join(tmp_dir, "undo_file_changed.txt")
			local op = CreateFileOperation.new(file_path_str, { content = "original content" })

			local success, err = op:execute()
			assert.is_true(success, err)
			assert.are.equal(file_path_str, pl_path.exists(file_path_str))
			assert.is_not_nil(op.checksum_data.target_checksum)

			local f = io.open(file_path_str, "w")
			assert.is_not_nil(f)
			f:write("modified content")
			f:close()
			assert.are.equal(file_path_str, pl_path.exists(file_path_str))

			local undo_success, undo_err = op:undo()
			assert.is_false(undo_success)
			assert.match("checksum mismatch", undo_err)
			assert.are.equal(file_path_str, pl_path.exists(file_path_str))
		end)

		it("should succeed tolerantly if the file created by op is deleted before undo", function()
			-- DECISION: Implement tolerant success. If the file is already gone, undo should succeed.
			-- This test explicitly checks for tolerant success when the operation did create the file.

			local file_path_str = pl_path.join(tmp_dir, "undo_file_gone_tolerant.txt")
			local op = CreateFileOperation.new(file_path_str, { content = "test for tolerant undo" })
			local success, err = op:execute()
			assert.is_true(success, "Execute failed: " .. tostring(err))
			assert.are.equal(file_path_str, pl_path.exists(file_path_str), "File should exist after execute")

			-- Simulate file being deleted by external means
			assert.is_true(pl_file.delete(file_path_str), "Failed to delete file for test setup")
			assert.is_false(pl_path.exists(file_path_str), "File should not exist after manual delete")

			local undo_success, undo_err = op:undo()
			assert.is_true(undo_success, "Undo should succeed tolerantly: " .. tostring(undo_err))
			assert.is_false(pl_path.exists(file_path_str)) -- File should still not exist
		end)
	end)
end)
