local helper = require("spec.spec_helper")
local MoveOperation = require("fsynth.operations.move")
local Checksum = require("fsynth.checksum")
local pl_file = require("pl.file")
local pl_path = require("pl.path")

describe("MoveOperation", function()
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

	local function create_dir_for_test(path_str, make_parents)
		if make_parents then
			assert.is_true(
				pl_path.mkdir(path_str, make_parents),
				"Failed to create directory for test setup: " .. path_str
			)
		else
			assert.is_true(pl_path.mkdir(path_str), "Failed to create directory for test setup: " .. path_str)
		end
		assert.are.equal(path_str, pl_path.exists(path_str), "Directory was not created: " .. path_str)
		assert.is_true(pl_path.isdir(path_str), "Path is not a directory: " .. path_str)
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

	local function verify_dir_structure(base_path_str, expected_structure)
		for name, item_type in pairs(expected_structure) do
			local item_path_str = pl_path.join(base_path_str, name)
			assert.are.equal(
				item_path_str,
				pl_path.exists(item_path_str),
				"Expected item " .. name .. " does not exist in " .. base_path_str
			)
			if item_type == "file" then
				assert.is_true(pl_path.isfile(item_path_str), "Expected " .. name .. " to be a file.")
			elseif item_type == "dir" then
				assert.is_true(pl_path.isdir(item_path_str), "Expected " .. name .. " to be a directory.")
			end
		end
	end

	describe(":execute", function()
		describe("Successful Moves", function()
			it("should move a file to a new, non-existent path", function()
				local source_path_str = pl_path.join(tmp_dir, "source_file.txt")
				create_file_for_test(source_path_str, "move content")
				local target_path_str = pl_path.join(tmp_dir, "target_file.txt")
				local op = MoveOperation.new(source_path_str, target_path_str)

				local success, err = op:execute()
				assert.is_true(success, err)
				assert.is_false(pl_path.exists(source_path_str))
				assert.are.equal(target_path_str, pl_path.exists(target_path_str))
				assert.are.equal("move content", read_file_content(target_path_str))
				assert.is_not_nil(op.checksum_data.initial_source_checksum)
				assert.is_not_nil(op.checksum_data.final_target_checksum)
				assert.are.equal(op.checksum_data.initial_source_checksum, op.checksum_data.final_target_checksum)
			end)

			it("should move an empty directory to a new, non-existent path", function()
				local source_dir_str = pl_path.join(tmp_dir, "source_empty_dir")
				create_dir_for_test(source_dir_str)
				local target_dir_str = pl_path.join(tmp_dir, "target_empty_dir")
				local op = MoveOperation.new(source_dir_str, target_dir_str)

				local success, err = op:execute()
				assert.is_true(success, err)
				assert.is_false(pl_path.exists(source_dir_str))
				assert.are.equal(target_dir_str, pl_path.exists(target_dir_str))
				assert.is_true(pl_path.isdir(target_dir_str))
			end)

			it("should move a non-empty directory to a new, non-existent path", function()
				local source_dir_str = pl_path.join(tmp_dir, "source_non_empty_dir")
				create_dir_for_test(source_dir_str)
				create_file_for_test(pl_path.join(source_dir_str, "child.txt"), "child content")
				create_dir_for_test(pl_path.join(source_dir_str, "child_dir"))

				local target_dir_str = pl_path.join(tmp_dir, "target_non_empty_dir")
				local op = MoveOperation.new(source_dir_str, target_dir_str)

				local success, err = op:execute()
				assert.is_true(success, err)
				assert.is_false(pl_path.exists(source_dir_str))
				assert.are.equal(target_dir_str, pl_path.exists(target_dir_str))
				assert.is_true(pl_path.isdir(target_dir_str))
				verify_dir_structure(target_dir_str, { ["child.txt"] = "file", ["child_dir"] = "dir" })
			end)
		end)

		describe("options.overwrite = true", function()
			it("should move a file onto an existing file", function()
				local source_path_str = pl_path.join(tmp_dir, "source_overwrite.txt")
				create_file_for_test(source_path_str, "new data")
				local target_path_str = pl_path.join(tmp_dir, "target_to_overwrite.txt")
				create_file_for_test(target_path_str, "old data")
				local op = MoveOperation.new(source_path_str, target_path_str, { overwrite = true })

				local success, err = op:execute()
				assert.is_true(success, err)
				assert.is_false(pl_path.exists(source_path_str))
				assert.are.equal(target_path_str, pl_path.exists(target_path_str))
				assert.are.equal("new data", read_file_content(target_path_str))
				assert.is_true(op.original_target_existed_and_was_overwritten)
			end)

			it("should move an empty directory onto an existing empty directory", function()
				local source_dir_str = pl_path.join(tmp_dir, "source_empty_dir_ow")
				create_dir_for_test(source_dir_str)
				local target_dir_str = pl_path.join(tmp_dir, "target_empty_dir_ow")
				create_dir_for_test(target_dir_str)
				local op = MoveOperation.new(source_dir_str, target_dir_str, { overwrite = true })

				local success, err = op:execute()
				assert.is_true(success, err)
				assert.is_false(pl_path.exists(source_dir_str))
				assert.are.equal(target_dir_str, pl_path.exists(target_dir_str))
				assert.is_true(pl_path.isdir(target_dir_str))
				assert.is_true(op.original_target_existed_and_was_overwritten)
			end)
		end)

		describe("options.overwrite = false (default)", function()
			it("should fail if target file path already exists", function()
				local source_path_str = pl_path.join(tmp_dir, "s_file_no_ow.txt")
				create_file_for_test(source_path_str, "data")
				local target_path_str = pl_path.join(tmp_dir, "t_file_no_ow.txt")
				create_file_for_test(target_path_str, "existing")
				local op = MoveOperation.new(source_path_str, target_path_str)

				local success, err = op:execute()
				assert.is_false(success)
				assert.match("already exists", err)
				assert.are.equal(source_path_str, pl_path.exists(source_path_str))
				assert.are.equal("existing", read_file_content(target_path_str))
				assert.is_false(op.original_target_existed_and_was_overwritten)
			end)

			it("should fail if target directory path already exists", function()
				local source_dir_str = pl_path.join(tmp_dir, "s_dir_no_ow")
				create_dir_for_test(source_dir_str)
				local target_dir_str = pl_path.join(tmp_dir, "t_dir_no_ow")
				create_dir_for_test(target_dir_str)
				local op = MoveOperation.new(source_dir_str, target_dir_str)

				local success, err = op:execute()
				assert.is_false(success)
				assert.match("already exists", err)
				assert.are.equal(source_dir_str, pl_path.exists(source_dir_str))
				assert.are.equal(target_dir_str, pl_path.exists(target_dir_str))
				assert.is_false(op.original_target_existed_and_was_overwritten)
			end)
		end)

		describe("options.create_parent_dirs = true", function()
			it("should move a file, creating parent directories for target", function()
				local source_path_str = pl_path.join(tmp_dir, "s_file_parents.txt")
				create_file_for_test(source_path_str, "content")
				local target_path_str = pl_path.join(tmp_dir, "parent", "child", "t_file_parents.txt")
				local op = MoveOperation.new(source_path_str, target_path_str, { create_parent_dirs = true })

				local success, err = op:execute()
				assert.is_true(success, err)
				assert.is_false(pl_path.exists(source_path_str))
				assert.are.equal(target_path_str, pl_path.exists(target_path_str))
				assert.are.equal("content", read_file_content(target_path_str))
				assert.are.equal(
					pl_path.join(tmp_dir, "parent", "child"),
					pl_path.exists(pl_path.join(tmp_dir, "parent", "child"))
				)
				assert.are.equal(pl_path.join(tmp_dir, "parent"), pl_path.exists(pl_path.join(tmp_dir, "parent")))
			end)
		end)

		describe("options.create_parent_dirs = false (default)", function()
			it("should fail if intermediate parent directory for target does not exist", function()
				local source_path_str = pl_path.join(tmp_dir, "s_file_no_parents.txt")
				create_file_for_test(source_path_str, "content")
				local target_path_str = pl_path.join(tmp_dir, "missing_parent", "t_file_no_parents.txt")
				local op = MoveOperation.new(source_path_str, target_path_str)

				local success, err = op:execute()
				assert.is_false(success)
				assert.match(
					"Parent directory '.+' for target '.+' does not exist and create_parent_dirs is false",
					err,
					"Error message did not match. Got: " .. tostring(err)
				)
				assert.are.equal(source_path_str, pl_path.exists(source_path_str))
			end)
		end)

		describe("Validation Failures", function()
			it("should fail if source path does not exist", function()
				local source_path_str = pl_path.join(tmp_dir, "non_existent_source.txt")
				local target_path_str = pl_path.join(tmp_dir, "target.txt")
				local op = MoveOperation.new(source_path_str, target_path_str)
				local valid, err = op:validate()
				assert.is_false(valid)
				assert.match("does not exist", err)
			end)

			it("should fail if source path is not specified", function()
				local target_path_str = pl_path.join(tmp_dir, "target.txt")
				local op = MoveOperation.new(nil, target_path_str)
				local valid, err = op:validate()
				assert.is_false(valid)
				assert.match("Source path not specified for MoveOperation", err)
			end)

			it("should fail if target path is not specified", function()
				local source_path_str = pl_path.join(tmp_dir, "source.txt")
				create_file_for_test(source_path_str)
				local op = MoveOperation.new(source_path_str)
				local valid, err = op:validate()
				assert.is_false(valid)
				assert.match("Target path not specified for MoveOperation", err)
			end)

			it("should fail validation if moving a directory onto an existing file", function()
				local source_dir_str = pl_path.join(tmp_dir, "s_dir_to_file")
				create_dir_for_test(source_dir_str)
				local target_file_str = pl_path.join(tmp_dir, "t_file_is_file.txt")
				create_file_for_test(target_file_str)
				local op = MoveOperation.new(source_dir_str, target_file_str, { overwrite = true })
				local valid, err = op:validate()
				assert.is_false(valid)
				assert.match(
					"Cannot move a directory%-like source '.+' onto an existing file '.+'",
					err,
					"Error message did not match. Got: " .. tostring(err)
				)
			end)

			it("should move a file INTO an existing directory if target is a directory", function()
				-- DECISION: Moving a file to a path that is an existing directory
				-- should move the file INTO that directory.
				local source_file_str = pl_path.join(tmp_dir, "s_file_into_dir.txt")
				create_file_for_test(source_file_str, "content for move into dir")
				local source_basename = pl_path.basename(source_file_str)

				local target_dir_str = pl_path.join(tmp_dir, "t_existing_dir_for_move_into")
				create_dir_for_test(target_dir_str)

				local op = MoveOperation.new(source_file_str, target_dir_str)

				-- Check validation flags (optional, execute will validate too)
				local valid, val_err = op:validate()
				assert.is_true(valid, "Validation failed: " .. tostring(val_err))
				assert.is_true(op.target_is_directory_move_into, "target_is_directory_move_into should be true")

				local success, exec_err = op:execute()
				assert.is_true(success, "Execute failed: " .. tostring(exec_err))

				local expected_final_path = pl_path.join(target_dir_str, source_basename)

				assert.is_false(pl_path.exists(source_file_str), "Original source file should be gone")
				assert.are.equal(
					expected_final_path,
					pl_path.exists(expected_final_path),
					"File should exist in target directory"
				)
				assert.is_true(pl_path.isfile(expected_final_path), "Item in target directory should be a file")
				assert.are.equal("content for move into dir", read_file_content(expected_final_path))
				assert.are.equal(expected_final_path, op.actual_target_path, "actual_target_path not set correctly")

				-- Test Undo
				local initial_source_checksum = op.checksum_data.initial_source_checksum
				local undo_success, undo_err = op:undo()
				assert.is_true(undo_success, "Undo failed: " .. tostring(undo_err))
				assert.is_false(pl_path.exists(expected_final_path), "File should be gone from target dir after undo")
				assert.are.equal(
					source_file_str,
					pl_path.exists(source_file_str),
					"File should be restored to original source path"
				)
				assert.are.equal("content for move into dir", read_file_content(source_file_str))
				local restored_checksum = Checksum.calculate_sha256(source_file_str)
				assert.are.equal(initial_source_checksum, restored_checksum, "Checksum mismatch after undo")
			end)

			it("should fail validation if source and target paths are identical", function()
				-- DECISION: Moving a path to itself is a validation error.
				local path_str = pl_path.join(tmp_dir, "same_path.txt")
				create_file_for_test(path_str, "content")

				-- Test with overwrite = false (default)
				local op_no_overwrite = MoveOperation.new(path_str, path_str)
				local valid_no_ow, err_no_ow = op_no_overwrite:validate()
				assert.is_false(valid_no_ow, "Validation should fail for identical paths even with overwrite=false")
				assert.match(
					"Source path '.+' and target path '.+' are the same",
					err_no_ow,
					"Error message mismatch for overwrite=false. Got: " .. tostring(err_no_ow)
				)

				-- Test with overwrite = true
				local op_overwrite = MoveOperation.new(path_str, path_str, { overwrite = true })
				local valid_ow, err_ow = op_overwrite:validate()
				assert.is_false(valid_ow, "Validation should fail for identical paths even with overwrite=true")
				assert.match(
					"Source path '.+' and target path '.+' are the same",
					err_ow,
					"Error message mismatch for overwrite=true. Got: " .. tostring(err_ow)
				)

				-- Ensure file still exists and content is unchanged
				assert.are.equal(path_str, pl_path.exists(path_str))
				assert.are.equal("content", read_file_content(path_str))
			end)

			it(
				"should correctly handle moving a symbolic link (moving the link, not the target) and allow undo",
				function()
					-- DECISION: MoveOperation should identify symlinks using lfs.attributes.
					-- It should move the link itself. The link's target string is stored for undo verification.
					-- Checksums are skipped for symlink sources.
					if helper.is_windows() then
						pending(
							"Skipping symlink move test on Windows due to lfs.link permission issues or different behavior."
						)
						return
					end

					local lfs = require("lfs") -- Ensure lfs is available for symlink ops

					-- Setup: directory, target file inside, and symlink pointing to target file
					local file_target_name = "actual_target.txt"
					local link_target_path_abs = pl_path.join(tmp_dir, file_target_name)
					create_file_for_test(link_target_path_abs, "link target content")

					local source_symlink_name = "source_symlink"
					local source_symlink_path_abs = pl_path.join(tmp_dir, source_symlink_name)
					local symlink_creation_target = file_target_name -- Use relative path for link creation for robustness

					local original_cwd = lfs.currentdir()
					assert.is_true(lfs.chdir(tmp_dir), "Failed to chdir to tmp_dir for relative symlink creation")
					local link_success, link_err = lfs.link(symlink_creation_target, source_symlink_name, true)
					lfs.chdir(original_cwd) -- Restore CWD
					assert.is_true(link_success, "Failed to create source symlink: " .. tostring(link_err))
					assert.is_true(pl_path.islink(source_symlink_path_abs), "Source path is not a symlink")
					assert.are.equal(
						symlink_creation_target,
						lfs.symlinkattributes(source_symlink_path_abs, "target"),
						"Symlink target string mismatch after creation"
					)

					-- Target for the move operation
					local moved_symlink_path_abs = pl_path.join(tmp_dir, "moved_symlink_location")

					-- Operation
					local op = MoveOperation.new(source_symlink_path_abs, moved_symlink_path_abs)

					-- Validate (optional here, execute calls it)
					local valid, val_err = op:validate()
					assert.is_true(valid, "Validation failed: " .. tostring(val_err))
					assert.is_true(op.source_is_symlink, "op.source_is_symlink should be true")
					assert.are.equal(
						symlink_creation_target,
						op.source_symlink_target,
						"Stored symlink target is incorrect"
					)
					assert.is_nil(
						op.checksum_data.initial_source_checksum,
						"Initial checksum should be nil for symlink source"
					)

					-- Execute
					local success, exec_err = op:execute()
					assert.is_true(success, "Execute failed: " .. tostring(exec_err))

					assert.is_false(pl_path.exists(source_symlink_path_abs), "Original source symlink should be gone")
					assert.is_true(pl_path.islink(moved_symlink_path_abs), "Moved path should be a symlink")
					assert.are.equal(
						symlink_creation_target,
						lfs.symlinkattributes(moved_symlink_path_abs, "target"),
						"Moved symlink target string mismatch"
					)
					assert.are.equal(
						link_target_path_abs,
						pl_path.exists(link_target_path_abs),
						"Original link target file should still exist"
					)
					assert.are.equal(
						"link target content",
						pl_file.read(moved_symlink_path_abs),
						"Reading through moved symlink failed or content mismatch"
					)
					assert.is_nil(
						op.checksum_data.final_target_checksum,
						"Final checksum should be nil for symlink source"
					)
					assert.are.equal(
						moved_symlink_path_abs,
						op.actual_target_path,
						"actual_target_path not set correctly"
					)

					-- Test Undo
					local undo_success, undo_err = op:undo()
					assert.is_true(undo_success, "Undo failed: " .. tostring(undo_err))
					assert.is_false(pl_path.exists(moved_symlink_path_abs), "Moved symlink should be gone after undo")
					assert.is_true(pl_path.islink(source_symlink_path_abs), "Original symlink should be restored")
					assert.are.equal(
						symlink_creation_target,
						lfs.symlinkattributes(source_symlink_path_abs, "target"),
						"Restored symlink target string mismatch"
					)
					assert.are.equal(
						"link target content",
						pl_file.read(source_symlink_path_abs),
						"Reading through restored symlink failed or content mismatch"
					)
				end
			)
		end)

		describe("Checksums (for file moves)", function()
			it("should store initial_source_checksum during validation", function()
				local source_path_str = pl_path.join(tmp_dir, "cs_source.txt")
				create_file_for_test(source_path_str, "checksum test")
				local target_path_str = pl_path.join(tmp_dir, "cs_target.txt")
				local op = MoveOperation.new(source_path_str, target_path_str)

				local expected_checksum = Checksum.calculate_sha256(source_path_str)
				local valid, err = op:validate()
				assert.is_true(valid, err)
				assert.are.equal(expected_checksum, op.checksum_data.initial_source_checksum)
			end)

			it("should store final_target_checksum after execution and match initial_source_checksum", function()
				local source_path_str = pl_path.join(tmp_dir, "cs_exec_source.txt")
				create_file_for_test(source_path_str, "checksum exec")
				local target_path_str = pl_path.join(tmp_dir, "cs_exec_target.txt")
				local op = MoveOperation.new(source_path_str, target_path_str)

				local initial_checksum = Checksum.calculate_sha256(source_path_str)
				local success, err = op:execute()
				assert.is_true(success, err)
				assert.is_not_nil(op.checksum_data.final_target_checksum)
				assert.are.equal(initial_checksum, op.checksum_data.final_target_checksum)
				assert.are.equal(op.checksum_data.initial_source_checksum, op.checksum_data.final_target_checksum)
			end)
		end)
	end)

	describe(":undo", function()
		it("should move a file from target back to original source path", function()
			local source_path_str = pl_path.join(tmp_dir, "undo_s_file.txt")
			local target_path_str = pl_path.join(tmp_dir, "undo_t_file.txt")
			create_file_for_test(source_path_str, "undo content")
			local initial_checksum = Checksum.calculate_sha256(source_path_str)

			local op = MoveOperation.new(source_path_str, target_path_str)
			local exec_success, exec_err = op:execute()
			assert.is_true(exec_success, exec_err)
			assert.is_false(pl_path.exists(source_path_str))
			assert.are.equal(target_path_str, pl_path.exists(target_path_str))
			assert.are.equal(op.checksum_data.initial_source_checksum, initial_checksum)

			local undo_success, undo_err = op:undo()
			assert.is_true(undo_success, undo_err)
			assert.are.equal(source_path_str, pl_path.exists(source_path_str))
			assert.is_false(pl_path.exists(target_path_str))
			assert.are.equal("undo content", read_file_content(source_path_str))
			assert.are.equal(initial_checksum, Checksum.calculate_sha256(source_path_str))
		end)

		it("should move a directory from target back to original source path", function()
			local source_dir_str = pl_path.join(tmp_dir, "undo_s_dir")
			local target_dir_str = pl_path.join(tmp_dir, "undo_t_dir")
			create_dir_for_test(source_dir_str)
			create_file_for_test(pl_path.join(source_dir_str, "marker.txt"), "marker")

			local op = MoveOperation.new(source_dir_str, target_dir_str)
			local exec_success, exec_err = op:execute()
			assert.is_true(exec_success, exec_err)

			local undo_success, undo_err = op:undo()
			assert.is_true(undo_success, undo_err)
			assert.are.equal(source_dir_str, pl_path.exists(source_dir_str))
			assert.are.equal(
				pl_path.join(source_dir_str, "marker.txt"),
				pl_path.exists(pl_path.join(source_dir_str, "marker.txt"))
			)
			assert.is_false(pl_path.exists(target_dir_str))
		end)

		it("undo should NOT restore items at target if overwrite = true was used", function()
			local source_path_str = pl_path.join(tmp_dir, "undo_ow_s.txt")
			local target_path_str = pl_path.join(tmp_dir, "undo_ow_t.txt")

			create_file_for_test(source_path_str, "source data")
			create_file_for_test(target_path_str, "original target data")

			local op = MoveOperation.new(source_path_str, target_path_str, { overwrite = true })
			local exec_success, exec_err = op:execute()
			assert.is_true(exec_success, exec_err)
			assert.is_true(op.original_target_existed_and_was_overwritten)
			assert.are.equal("source data", read_file_content(target_path_str))

			local undo_success, undo_err = op:undo()
			assert.is_true(undo_success, undo_err)
			assert.are.equal(source_path_str, pl_path.exists(source_path_str))
			assert.are.equal("source data", read_file_content(source_path_str))
			assert.is_false(pl_path.exists(target_path_str))
		end)

		it("should fail undo if the moved item at target path no longer exists", function()
			local source_path_str = pl_path.join(tmp_dir, "undo_target_gone_s.txt")
			local target_path_str = pl_path.join(tmp_dir, "undo_target_gone_t.txt")
			create_file_for_test(source_path_str, "content")

			local op = MoveOperation.new(source_path_str, target_path_str)
			local exec_success, exec_err = op:execute()
			assert.is_true(exec_success, exec_err)
			assert.are.equal(
				op.actual_target_path or target_path_str,
				pl_path.exists(op.actual_target_path or target_path_str)
			)

			assert.is_true(pl_file.delete(op.actual_target_path or target_path_str))

			local undo_success, undo_err = op:undo()
			assert.is_false(undo_success)
			assert.match(
				"Item to undo move from '.+' does not exist",
				undo_err,
				"Error message did not match. Got: " .. tostring(undo_err)
			)
			assert.is_false(pl_path.exists(source_path_str))
		end)

		it("should fail undo if the original source path now exists (conflicts)", function()
			local source_path_str = pl_path.join(tmp_dir, "undo_s_conflict.txt")
			local target_path_str = pl_path.join(tmp_dir, "undo_t_conflict.txt")
			create_file_for_test(source_path_str, "original source data")

			local op = MoveOperation.new(source_path_str, target_path_str)
			local exec_success, exec_err = op:execute()
			assert.is_true(exec_success, exec_err)

			create_file_for_test(source_path_str, "conflicting data at source")

			local undo_success, undo_err = op:undo()
			assert.is_false(undo_success)
			assert.match("Cannot undo move, path .* already exists at original source location", undo_err)
			assert.are.equal(target_path_str, pl_path.exists(target_path_str))
			assert.are.equal("conflicting data at source", read_file_content(source_path_str))
		end)
	end)
end)
