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
		assert.is_true(pl_path.exists(path_str), "File was not created: " .. path_str)
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
		assert.is_true(pl_path.exists(path_str), "Directory was not created: " .. path_str)
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
			assert.is_true(
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
				assert.is_true(pl_path.exists(target_path_str))
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
				assert.is_true(pl_path.exists(target_dir_str))
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
				assert.is_true(pl_path.exists(target_dir_str))
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
				assert.is_true(pl_path.exists(target_path_str))
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
				assert.is_true(pl_path.exists(target_dir_str))
				assert.is_true(pl_path.isdir(target_dir_str))
				assert.is_true(op.original_target_existed_and_was_overwritten)
			end)

			it("should move a non-empty directory onto an existing non-empty directory", function()
				local source_dir_str = pl_path.join(tmp_dir, "source_non_empty_ow")
				create_dir_for_test(source_dir_str)
				create_file_for_test(pl_path.join(source_dir_str, "new_file.txt"), "new")
				local target_dir_str = pl_path.join(tmp_dir, "target_non_empty_ow")
				create_dir_for_test(target_dir_str)
				create_file_for_test(pl_path.join(target_dir_str, "old_file.txt"), "old")

				local op = MoveOperation.new(source_dir_str, target_dir_str, { overwrite = true })
				local success, err = op:execute()
				assert.is_true(success, err)
				assert.is_false(pl_path.exists(source_dir_str))
				assert.is_true(pl_path.exists(target_dir_str))
				verify_dir_structure(target_dir_str, { ["new_file.txt"] = "file" })
				assert.is_false(pl_path.exists(pl_path.join(target_dir_str, "old_file.txt")))
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
				assert.match("Target path already exists", err)
				assert.is_true(pl_path.exists(source_path_str))
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
				assert.match("Target path already exists", err)
				assert.is_true(pl_path.exists(source_dir_str))
				assert.is_true(pl_path.exists(target_dir_str))
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
				assert.is_true(pl_path.exists(target_path_str))
				assert.are.equal("content", read_file_content(target_path_str))
				assert.is_true(pl_path.exists(pl_path.join(tmp_dir, "parent", "child")))
				assert.is_true(pl_path.exists(pl_path.join(tmp_dir, "parent")))
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
				assert.match("No such file or directory", err)
				assert.is_true(pl_path.exists(source_path_str))
			end)
		end)

		describe("Validation Failures", function()
			it("should fail if source path does not exist", function()
				local source_path_str = pl_path.join(tmp_dir, "non_existent_source.txt")
				local target_path_str = pl_path.join(tmp_dir, "target.txt")
				local op = MoveOperation.new(source_path_str, target_path_str)
				local valid, err = op:validate()
				assert.is_false(valid)
				assert.match("Source path does not exist", err)
			end)

			it("should fail if source path is not specified", function()
				local target_path_str = pl_path.join(tmp_dir, "target.txt")
				local op = MoveOperation.new(nil, target_path_str)
				local valid, err = op:validate()
				assert.is_false(valid)
				assert.match("Source path is required", err)
			end)

			it("should fail if target path is not specified", function()
				local source_path_str = pl_path.join(tmp_dir, "source.txt")
				create_file_for_test(source_path_str)
				local op = MoveOperation.new(source_path_str)
				local valid, err = op:validate()
				assert.is_false(valid)
				assert.match("Target path is required", err)
			end)

			it("should fail validation if moving a directory onto an existing file", function()
				local source_dir_str = pl_path.join(tmp_dir, "s_dir_to_file")
				create_dir_for_test(source_dir_str)
				local target_file_str = pl_path.join(tmp_dir, "t_file_is_file.txt")
				create_file_for_test(target_file_str)
				local op = MoveOperation.new(source_dir_str, target_file_str, { overwrite = true })
				local valid, err = op:validate()
				assert.is_false(valid)
				assert.match("Cannot move a directory onto a file", err)
			end)

			it("should fail validation if moving a file onto an existing directory (current behavior)", function()
				local source_file_str = pl_path.join(tmp_dir, "s_file_to_dir.txt")
				create_file_for_test(source_file_str)
				local target_dir_str = pl_path.join(tmp_dir, "t_dir_is_dir")
				create_dir_for_test(target_dir_str)
				local op = MoveOperation.new(source_file_str, target_dir_str, { overwrite = true })
				local valid, err = op:validate()
				assert.is_false(valid)
				assert.match("Cannot move a file onto a directory", err)
			end)
		end)

		describe("Checksums (for file moves)", function()
			it("should store initial_source_checksum during validation", function()
				local source_path_str = pl_path.join(tmp_dir, "cs_source.txt")
				create_file_for_test(source_path_str, "checksum test")
				local target_path_str = pl_path.join(tmp_dir, "cs_target.txt")
				local op = MoveOperation.new(source_path_str, target_path_str)

				local expected_checksum = Checksum.path(source_path_str)
				local valid, err = op:validate()
				assert.is_true(valid, err)
				assert.are.equal(expected_checksum, op.checksum_data.initial_source_checksum)
			end)

			it("should store final_target_checksum after execution and match initial_source_checksum", function()
				local source_path_str = pl_path.join(tmp_dir, "cs_exec_source.txt")
				create_file_for_test(source_path_str, "checksum exec")
				local target_path_str = pl_path.join(tmp_dir, "cs_exec_target.txt")
				local op = MoveOperation.new(source_path_str, target_path_str)

				local initial_checksum = Checksum.path(source_path_str)
				local success, err = op:execute()
				assert.is_true(success, err)
				assert.is_not_nil(op.checksum_data.final_target_checksum)
				assert.are.equal(initial_checksum, op.checksum_data.final_target_checksum)
				assert.are.equal(op.checksum_data.initial_source_checksum, op.checksum_data.final_target_checksum)
			end)

			it("should fail if initial_source_checksum and final_target_checksum do not match after move", function()
				local source_path_str = pl_path.join(tmp_dir, "cs_corrupt_source.txt")
				create_file_for_test(source_path_str, "data for checksum")
				local target_path_str = pl_path.join(tmp_dir, "cs_corrupt_target.txt")

				local original_move = pl_file.move
				_G.pl_file = _G.pl_file or {}
				_G.pl_file.move = function(src_abs, tgt_abs)
					local res, err_msg = original_move(src_abs, tgt_abs)
					if res then
						local f = io.open(tgt_abs, "a")
						f:write("corruption")
						f:close()
					end
					return res, err_msg
				end

				local op = MoveOperation.new(source_path_str, target_path_str)
				local success, err = op:execute()
				_G.pl_file.move = original_move

				assert.is_false(success)
				assert.match("Checksum mismatch after move", err)
				assert.is_true(pl_path.exists(target_path_str))
				assert.is_false(pl_path.exists(source_path_str))
			end)
		end)
	end)

	describe(":undo", function()
		it("should move a file from target back to original source path", function()
			local source_path_str = pl_path.join(tmp_dir, "undo_s_file.txt")
			local target_path_str = pl_path.join(tmp_dir, "undo_t_file.txt")
			create_file_for_test(source_path_str, "undo content")
			local initial_checksum = Checksum.path(source_path_str)

			local op = MoveOperation.new(source_path_str, target_path_str)
			local exec_success, exec_err = op:execute()
			assert.is_true(exec_success, exec_err)
			assert.is_false(pl_path.exists(source_path_str))
			assert.is_true(pl_path.exists(target_path_str))
			assert.are.equal(op.checksum_data.initial_source_checksum, initial_checksum)

			local undo_success, undo_err = op:undo()
			assert.is_true(undo_success, undo_err)
			assert.is_true(pl_path.exists(source_path_str))
			assert.is_false(pl_path.exists(target_path_str))
			assert.are.equal("undo content", read_file_content(source_path_str))
			assert.are.equal(initial_checksum, Checksum.path(source_path_str))
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
			assert.is_true(pl_path.exists(source_dir_str))
			assert.is_true(pl_path.exists(pl_path.join(source_dir_str, "marker.txt")))
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
			assert.is_true(pl_path.exists(source_path_str))
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
			assert.is_true(pl_path.exists(target_path_str))

			assert.is_true(pl_file.delete(target_path_str))

			local undo_success, undo_err = op:undo()
			assert.is_false(undo_success)
			assert.match("Item to undo move from target .* does not exist", undo_err)
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
			assert.is_true(pl_path.exists(target_path_str))
			assert.are.equal("conflicting data at source", read_file_content(source_path_str))
		end)
	end)
end)
