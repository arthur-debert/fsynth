local file_permissions = require("fsynth.file_permissions")
local helper = require("spec.spec_helper")
local pl_path = require("pl.path")
local pl_file = require("pl.file")
local lfs = require("lfs")

-- Determine if running on Windows for platform-specific tests
local is_windows = package.config:sub(1, 1) == "\\"

describe("file_permissions", function()
	local tmp_dir

	setup(function()
		helper.clean_tmp_dir()
		tmp_dir = helper.get_tmp_dir()
	end)

	teardown(function()
		helper.clean_tmp_dir()
	end)

	describe("copy_with_attributes", function()
		it("should copy a file with attributes preserved", function()
			-- Create a source file
			local source_path = pl_path.join(tmp_dir, "source_with_attrs.txt")
			local target_path = pl_path.join(tmp_dir, "target_with_attrs.txt")
			local content = "File content for attribute testing"

			local file = io.open(source_path, "w")
			file:write(content)
			file:close()

			-- Set some specific permissions on the source file
			-- This is platform dependent
			if not is_windows then
				-- On Unix, set permissions to 0644 (owner read/write, others read)
				os.execute(string.format("chmod 644 %q", source_path))

				-- Now copy with attributes preserved
				local success = file_permissions.copy_with_attributes(source_path, target_path)
				assert.is_true(success)

				-- Verify file was copied correctly
				assert.truthy(pl_path.exists(target_path))
				assert.are.equal(content, pl_file.read(target_path))

				-- Permissions should match between files
				lfs.attributes(source_path) -- to populate cache if any
				lfs.attributes(target_path) -- to populate cache if any
				local src_perm = lfs.attributes(source_path, "permissions")
				local target_perm = lfs.attributes(target_path, "permissions")
				assert.are.equal(src_perm, target_perm)
			else
				-- Windows implementation
				-- Just verify basic copy functionality
				local success = file_permissions.copy_with_attributes(source_path, target_path)
				assert.is_true(success)
				-- Penlight's pl.path.exists returns the path string (truthy) or nil (falsy).
				-- For Busted, assert.truthy is more appropriate than assert.is_true for non-boolean true.
				assert.truthy(pl_path.exists(target_path))
				assert.are.equal(content, pl_file.read(target_path))
				-- Cannot easily test attribute preservation on Windows in this environment
				-- but the underlying CopyFileA function should preserve attributes
			end
		end)
	end)

	describe("set_mode", function()
		it("should set file permissions on Unix systems", function()
			if is_windows then
				-- Skip test if on Windows
				return
			end

			-- Create a test file
			local test_path = pl_path.join(tmp_dir, "permission_test.txt")
			local file = io.open(test_path, "w")
			file:write("Testing permissions")
			file:close()

			-- Set permissions to read-only for everyone (444)
			local success, err = file_permissions.set_mode(test_path, "444")
			assert.is_true(success, err)

			local mode = file_permissions.get_mode(test_path)
			assert.are.equal("444", mode)

			-- Try to write to the file - should fail
			local write_file = io.open(test_path, "w")
			assert.is_nil(write_file) -- Write should fail with "Permission denied"

			-- Set permissions back to read-write (644)
			success, err = file_permissions.set_mode(test_path, "644")
			assert.is_true(success, err)

			-- Verify permissions were updated
			mode = file_permissions.get_mode(test_path)
			assert.are.equal("644", mode)

			-- Now writing should work
			write_file = io.open(test_path, "w")
			assert.is_not_nil(write_file)
			write_file:write("Updated content")
			write_file:close()
		end)

		it("should handle read-only attribute on Windows", function()
			if not is_windows then
				-- Skip test if not on Windows
				return
			end

			-- Create a test file
			local test_path = pl_path.join(tmp_dir, "win_readonly_test.txt")
			local file = io.open(test_path, "w")
			file:write("Testing Windows read-only attribute")
			file:close()

			-- Set as read-only
			local success, err = file_permissions.set_mode(test_path, "444")
			assert.is_true(success, err)

			-- Check if file is read-only using attrib command
			local f_attrib_check1 = io.popen(string.format('attrib "%s"', test_path:gsub("/", "\\")))
			local output1 = f_attrib_check1:read("*a")
			f_attrib_check1:close()

			-- Output should contain "R" attribute
			assert.truthy(output1:match("R"))

			-- Remove read-only attribute
			success, err = file_permissions.set_mode(test_path, "666")
			assert.is_true(success, err)

			-- Check if read-only attribute was removed
			local f_attrib_check2 = io.popen(string.format('attrib "%s"', test_path:gsub("/", "\\")))
			local output2 = f_attrib_check2:read("*a")
			f_attrib_check2:close()

			-- Output should not contain "R" attribute
			assert.falsy(output2:match("R"))
		end)
	end)

	describe("get_mode", function()
		it("should return file permissions on Unix systems", function()
			if is_windows then
				pending("Unix-specific permission test")
			end

			-- Create a test file
			local test_path = pl_path.join(tmp_dir, "get_mode_test.txt")
			local file = io.open(test_path, "w")
			file:write("Testing get_mode")
			file:close()

			-- Set specific permissions
			os.execute(string.format("chmod 644 %q", test_path))

			-- Get and verify permissions
			local mode = file_permissions.get_mode(test_path)
			assert.are.equal("644", mode)

			-- Change permissions and verify again
			os.execute(string.format("chmod 755 %q", test_path))
			mode = file_permissions.get_mode(test_path)
			assert.are.equal("755", mode)
		end)

		it("should return basic permissions representation on Windows", function()
			if not is_windows then
				-- Skip test if not on Windows
				return
			end

			-- Create a test file
			local test_path = pl_path.join(tmp_dir, "win_get_mode_test.txt")
			local file = io.open(test_path, "w")
			file:write("Testing Windows get_mode")
			file:close()

			-- By default, file should be writable
			local mode = file_permissions.get_mode(test_path)
			assert.are.equal("666", mode)

			-- Set as read-only
			os.execute(string.format('attrib +R "%s"', test_path:gsub("/", "\\")))

			-- Should now report as read-only
			mode = file_permissions.get_mode(test_path)
			assert.are.equal("444", mode)
		end)
	end)

	describe("is_readable", function()
		it("should return true for a readable file", function()
			local test_file = pl_path.join(tmp_dir, "readable_file.txt")
			pl_file.write(test_file, "content")
			if not is_windows then
				os.execute(string.format("chmod 644 %q", test_file)) -- Ensure readable
			end
			local readable, err = file_permissions.is_readable(test_file)
			assert.is_true(readable, "File should be readable. Error: " .. tostring(err))
		end)

		it("should return false for a non-readable file (Unix)", function()
			if is_windows then
				pending("Unix-specific non-readable file test")
				return
			end
			local test_file = pl_path.join(tmp_dir, "non_readable_file.txt")
			pl_file.write(test_file, "content")
			os.execute(string.format("chmod 000 %q", test_file)) -- Make non-readable
			local readable, err = file_permissions.is_readable(test_file)
			assert.is_false(readable, "File should not be readable. Error: " .. tostring(err))
			os.execute(string.format("chmod 644 %q", test_file)) -- cleanup
		end)

		it("should return true for a readable directory", function()
			local test_subdir = pl_path.join(tmp_dir, "readable_subdir")
			lfs.mkdir(test_subdir)
			if not is_windows then
				os.execute(string.format("chmod 755 %q", test_subdir)) -- Ensure readable/listable
			end
			local readable, err = file_permissions.is_readable(test_subdir)
			assert.is_true(readable, "Directory should be readable. Error: " .. tostring(err))
		end)

		it("should return false for a non-existent path", function()
			local test_file = pl_path.join(tmp_dir, "non_existent_file.txt")
			local readable, err = file_permissions.is_readable(test_file)
			assert.is_false(readable)
			assert.is_string(err)
		end)

		it("should handle Windows read-only attribute for readability", function()
			if not is_windows then
				-- Skip test if not on Windows
				return
			end
			local test_file = pl_path.join(tmp_dir, "win_readable_test.txt")
			pl_file.write(test_file, "content")
			-- By default, it should be readable
			local readable1, err1 = file_permissions.is_readable(test_file)
			assert.is_true(readable1, "File should be readable by default. Error: " .. tostring(err1))

			-- Setting +R on Windows doesn't necessarily prevent reading by owner
			-- The is_readable for Windows checks if io.open(path, "rb") works
			os.execute(string.format('attrib +R "%s"', test_file:gsub("/", "\\")))
			local readable2, err2 = file_permissions.is_readable(test_file)
			assert.is_true(readable2, "File should still be readable by owner even if +R. Error: " .. tostring(err2))
			os.execute(string.format('attrib -R "%s"', test_file:gsub("/", "\\"))) -- cleanup
		end)
	end)

	describe("is_writable", function()
		it("should return true for a writable file", function()
			local test_file = pl_path.join(tmp_dir, "writable_file.txt")
			pl_file.write(test_file, "content")
			if not is_windows then
				os.execute(string.format("chmod 644 %q", test_file)) -- Ensure writable by owner
			else
				os.execute(string.format('attrib -R "%s"', test_file:gsub("/", "\\"))) -- Ensure not read-only
			end
			local writable, err = file_permissions.is_writable(test_file)
			assert.is_true(writable, "File should be writable. Error: " .. tostring(err))
		end)

		it("should return false for a non-writable file (read-only)", function()
			local test_file = pl_path.join(tmp_dir, "non_writable_file.txt")
			pl_file.write(test_file, "content")
			if not is_windows then
				os.execute(string.format("chmod 444 %q", test_file)) -- Make read-only for owner
			else
				os.execute(string.format('attrib +R "%s"', test_file:gsub("/", "\\"))) -- Make read-only
			end
			local writable, err = file_permissions.is_writable(test_file)
			assert.is_false(writable, "File should not be writable. Error: " .. tostring(err))
			-- Cleanup
			if not is_windows then
				os.execute(string.format("chmod 644 %q", test_file))
			else
				os.execute(string.format('attrib -R "%s"', test_file:gsub("/", "\\")))
			end
		end)

		it("should return true for a writable directory", function()
			local test_subdir = pl_path.join(tmp_dir, "writable_subdir")
			lfs.mkdir(test_subdir)
			if not is_windows then
				os.execute(string.format("chmod 755 %q", test_subdir)) -- Ensure writable by owner
			end
			local writable, err = file_permissions.is_writable(test_subdir)
			assert.is_true(writable, "Directory should be writable. Error: " .. tostring(err))
		end)

		it("should return false for a non-writable directory (Unix)", function()
			if is_windows then
				pending("Unix-specific non-writable directory test")
				return
			end
			local test_subdir = pl_path.join(tmp_dir, "non_writable_subdir")
			lfs.mkdir(test_subdir)
			os.execute(string.format("chmod 555 %q", test_subdir)) -- Make read-only for owner (cannot create files)
			local writable, err = file_permissions.is_writable(test_subdir)
			assert.is_false(writable, "Directory should not be writable. Error: " .. tostring(err))
			os.execute(string.format("chmod 755 %q", test_subdir)) -- cleanup
		end)

		it("should return false for a non-existent path for writability", function()
			local test_file = pl_path.join(tmp_dir, "non_existent_writable.txt")
			local writable, err = file_permissions.is_writable(test_file)
			assert.is_false(writable)
			assert.is_string(err)
		end)
	end)

	describe("move_with_attributes", function()
		local source_file, target_file
		local source_dir, target_dir

		before_each(function()
			source_file = pl_path.join(tmp_dir, "move_source.txt")
			target_file = pl_path.join(tmp_dir, "move_target.txt")
			pl_file.write(source_file, "content to move")

			source_dir = pl_path.join(tmp_dir, "move_source_dir")
			target_dir = pl_path.join(tmp_dir, "move_target_dir")
			lfs.mkdir(source_dir)
			pl_file.write(pl_path.join(source_dir, "file_in_dir.txt"), "content")

			if not is_windows then
				os.execute(string.format("chmod 777 %q", source_file)) -- Set some distinct perms
				os.execute(string.format("chmod 777 %q", source_dir))
			else
				-- For Windows, ensure it's not read-only to start
				os.execute(string.format('attrib -R "%s"', source_file:gsub("/", "\\")))
			end
		end)

		after_each(function()
			-- Clean up any remaining files/dirs from move tests
			if pl_path.exists(source_file) then
				os.remove(source_file)
			end
			if pl_path.exists(target_file) then
				os.remove(target_file)
			end
			if pl_path.exists(source_dir) then
				helper.rmdir_recursive(source_dir)
			end
			if pl_path.exists(target_dir) then
				helper.rmdir_recursive(target_dir)
			end
		end)

		it("should move a file and preserve attributes", function()
			local src_attrs_before
			if not is_windows then
				src_attrs_before = lfs.attributes(source_file)
			end

			local success, err = file_permissions.move_with_attributes(source_file, target_file)
			assert.is_true(success, "Move should succeed. Error: " .. tostring(err))
			assert.is_false(pl_path.exists(source_file), "Source file should not exist after move")
			assert.truthy(pl_path.exists(target_file), "Target file should exist after move")
			assert.are.equal("content to move", pl_file.read(target_file))
			if not is_windows then
				local target_attrs_after = lfs.attributes(target_file)
				assert.are.equal(
					src_attrs_before.permissions,
					target_attrs_after.permissions,
					"Permissions should be preserved on Unix"
				)
				-- Timestamp preservation can be tricky
				-- else
				-- On Windows, MoveFileA (used by pl.file.move) generally preserves attributes.
				-- For now, successful move implies attributes are likely preserved by OS call.
				-- A more direct check could involve setting a specific attribute (like +R)
				-- on source and verifying it on target if needed for stricter tests.
				-- No specific Windows attribute preservation check here yet.
			end
		end)

		it("should move a directory and preserve attributes", function()
			local src_attrs_before
			if not is_windows then
				src_attrs_before = lfs.attributes(source_dir)
			end

			local success, err = file_permissions.move_with_attributes(source_dir, target_dir)
			assert.is_true(success, "Move directory should succeed. Error: " .. tostring(err))
			assert.is_false(pl_path.exists(source_dir), "Source directory should not exist after move")
			assert.truthy(pl_path.exists(target_dir), "Target directory should exist after move")
			assert.truthy(
				pl_path.exists(pl_path.join(target_dir, "file_in_dir.txt")),
				"File within moved directory should exist"
			)
			if not is_windows then
				local target_attrs_after = lfs.attributes(target_dir)
				assert.are.equal(
					src_attrs_before.permissions,
					target_attrs_after.permissions,
					"Directory permissions should be preserved on Unix"
				)
			end
		end)

		it("should fail to move a non-existent source file", function()
			local non_existent_source = pl_path.join(tmp_dir, "i_do_not_exist.txt")
			local success, err = file_permissions.move_with_attributes(non_existent_source, target_file)
			assert.is_false(success, "Move should fail for non-existent source")
			assert.is_string(err)
		end)

		it("should fail if dest parent dir does not exist for move", function()
			local deep_target_dir = pl_path.join(tmp_dir, "new_parent_dir_move", "deep_target_dir_for_move")
			local deep_target_file = pl_path.join(deep_target_dir, "move_target.txt")

			if pl_path.exists(pl_path.join(tmp_dir, "new_parent_dir_move")) then
				helper.rmdir_recursive(pl_path.join(tmp_dir, "new_parent_dir_move"))
			end

			local success, err = file_permissions.move_with_attributes(source_file, deep_target_file)
			assert.is_false(
				success,
				"Move should fail if destination parent directory does not exist. Error: " .. tostring(err)
			)
			assert.is_string(err)
			assert.truthy(pl_path.exists(source_file), "Source file should still exist after failed move")
		end)

		it("should handle move to existing file (overwrite Unix, fail Windows)", function()
			local existing_target_content = "already here"
			pl_file.write(target_file, existing_target_content)

			local success, err = file_permissions.move_with_attributes(source_file, target_file)

			if is_windows then
				-- MoveFileA (used by pl.file.move) fails if dest exists unless flag is used.
				-- Penlight's pl.file.move does not expose this flag, so it should fail.
				assert.is_false(success, "Move on Windows should fail if target file exists. Error: " .. tostring(err))
				assert.is_true(
					pl_path.exists(source_file),
					"Source file should still exist after failed move on Windows"
				)
				assert.are.equal(
					existing_target_content,
					pl_file.read(target_file),
					"Target file content should be unchanged after failed move on Windows"
				)
			else
				-- 'mv' on Unix typically overwrites if permissions allow.
				assert.is_true(success, "Move on Unix should overwrite. Error: " .. tostring(err))
				assert.is_false(pl_path.exists(source_file), "Source file should not exist after move on Unix")
				assert.truthy(pl_path.exists(target_file), "Target file should exist after move on Unix")
				assert.are.equal(
					"content to move",
					pl_file.read(target_file),
					"Target file should have new content after move on Unix"
				)
			end
		end)
	end)
end)
