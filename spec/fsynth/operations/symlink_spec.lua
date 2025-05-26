local helper = require("spec.spec_helper")
local SymlinkOperation = require("fsynth.operations.symlink")
local pl_file = require("pl.file")
local pl_path = require("pl.path")
local lfs = require("lfs") -- Using LuaFileSystem directly for symlink operations

describe("SymlinkOperation", function()
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

	-- Helper function for readlink using LuaFileSystem
	local function readlink(path_str)
		return lfs.symlinkattributes(path_str, "target")
	end

	describe(":execute", function()
		describe("Successful Symlink Creation", function()
			it("should create a symlink to an existing file", function()
				local link_target_path_str = pl_path.join(tmp_dir, "actual_file.txt")
				create_file_for_test(link_target_path_str, "this is the target")
				local link_path_str = pl_path.join(tmp_dir, "my_link_to_file")

				local op = SymlinkOperation.new(link_target_path_str, link_path_str)
				local success, err = op:execute()

				assert.is_true(success, err)
				assert.is_true(pl_path.islink(link_path_str))
				assert.are.equal(link_target_path_str, readlink(link_path_str))
				assert.is_true(op.link_actually_created)
				assert.are.equal("this is the target", pl_file.read(link_path_str))
			end)

			it("should create a symlink to an existing directory", function()
				local link_target_dir_str = pl_path.join(tmp_dir, "actual_dir")
				create_dir_for_test(link_target_dir_str)
				create_file_for_test(pl_path.join(link_target_dir_str, "child.txt"), "child content")
				local link_path_str = pl_path.join(tmp_dir, "my_link_to_dir")

				local op = SymlinkOperation.new(link_target_dir_str, link_path_str)
				local success, err = op:execute()

				assert.is_true(success, err)
				assert.is_true(pl_path.islink(link_path_str))
				assert.are.equal(link_target_dir_str, readlink(link_path_str))
				assert.is_true(op.link_actually_created)
				assert.is_true(pl_path.isdir(link_path_str)) -- Symlink to dir is also a dir
				assert.are.equal(pl_path.join(link_path_str, "child.txt"),
					pl_path.exists(pl_path.join(link_path_str, "child.txt")))
				assert.are.equal("child content", pl_file.read(pl_path.join(link_path_str, "child.txt")))
			end)

			it("should create a symlink to a non-existent path (dangling link)", function()
				local link_target_path_str = pl_path.join(tmp_dir, "non_existent_target")
				local link_path_str = pl_path.join(tmp_dir, "my_dangling_link")

				local op = SymlinkOperation.new(link_target_path_str, link_path_str)
				local success, err = op:execute()

				assert.is_true(success, err)
				assert.is_true(pl_path.islink(link_path_str))
				assert.are.equal(link_target_path_str, readlink(link_path_str))
				assert.is_true(op.link_actually_created)
				assert.is_false(pl_path.exists(link_path_str))
			end)
		end)

		describe("options.overwrite = true", function()
			it("should replace an existing file with a symlink", function()
				local link_target_path_str = pl_path.join(tmp_dir, "target_for_overwrite.txt")
				create_file_for_test(link_target_path_str, "link points here")
				local link_path_str = pl_path.join(tmp_dir, "path_to_be_overwritten")
				create_file_for_test(link_path_str, "this file will be replaced")

				local op = SymlinkOperation.new(link_target_path_str, link_path_str, { overwrite = true })
				local success, err = op:execute()

				assert.is_true(success, err)
				assert.is_true(pl_path.islink(link_path_str))
				assert.are.equal(link_target_path_str, readlink(link_path_str))
				assert.is_true(op.link_actually_created)
				assert.is_true(op.original_target_was_file)
			end)

			it("should replace an existing symlink with a new symlink", function()
				local original_link_target_str = pl_path.join(tmp_dir, "original_sym_target.txt")
				create_file_for_test(original_link_target_str, "original")
				local new_link_target_str = pl_path.join(tmp_dir, "new_sym_target.txt")
				create_file_for_test(new_link_target_str, "new")
				local link_path_str = pl_path.join(tmp_dir, "symlink_to_be_replaced")

				assert.is_true(lfs.link(original_link_target_str, link_path_str, true))
				assert.is_true(pl_path.islink(link_path_str))
				assert.are.equal(original_link_target_str, readlink(link_path_str))

				local op = SymlinkOperation.new(new_link_target_str, link_path_str, { overwrite = true })
				local success, err = op:execute()

				assert.is_true(success, err)
				assert.is_true(pl_path.islink(link_path_str))
				assert.are.equal(new_link_target_str, readlink(link_path_str))
				assert.is_true(op.link_actually_created)
				assert.is_true(op.original_target_was_symlink)
			end)
		end)

		describe("options.overwrite = false (default)", function()
			it("should fail if link path (self.target) already exists as a file", function()
				local link_target_path_str = pl_path.join(tmp_dir, "target_no_ow.txt")
				create_file_for_test(link_target_path_str)
				local link_path_str = pl_path.join(tmp_dir, "link_exists_no_ow")
				create_file_for_test(link_path_str, "existing file")

				local op = SymlinkOperation.new(link_target_path_str, link_path_str)
				local success, err = op:execute()

				assert.is_false(success)
				assert.match("already exists", err)
				assert.is_false(pl_path.islink(link_path_str))
				assert.is_true(pl_path.isfile(link_path_str))
				assert.is_false(op.link_actually_created)
			end)

			it("should fail if link path (self.target) already exists as a symlink", function()
				local link_target_path_str = pl_path.join(tmp_dir, "target_no_ow_sym.txt")
				create_file_for_test(link_target_path_str)
				local existing_sym_target_str = pl_path.join(tmp_dir, "existing_sym_points_here.txt")
				create_file_for_test(existing_sym_target_str)
				local link_path_str = pl_path.join(tmp_dir, "link_is_symlink_no_ow")
				assert.is_true(lfs.link(existing_sym_target_str, link_path_str, true))

				local op = SymlinkOperation.new(link_target_path_str, link_path_str)
				local success, err = op:execute()

				assert.is_false(success)
				assert.match("already exists", err)
				assert.is_true(pl_path.islink(link_path_str))
				assert.are.equal(existing_sym_target_str, readlink(link_path_str))
				assert.is_false(op.link_actually_created)
			end)
		end)

		describe("options.create_parent_dirs = true", function()
			it("should create parent directories for the link path (self.target)", function()
				local link_target_path_str = pl_path.join(tmp_dir, "target_for_parents.txt")
				create_file_for_test(link_target_path_str)
				local link_path_str = pl_path.join(tmp_dir, "parent", "child", "my_link_with_parents")

				local op = SymlinkOperation.new(link_target_path_str, link_path_str, { create_parent_dirs = true })
				local success, err = op:execute()

				assert.is_true(success, err)
				assert.are.equal(pl_path.join(tmp_dir, "parent", "child"),
					pl_path.exists(pl_path.join(tmp_dir, "parent", "child")))
				assert.is_true(pl_path.isdir(pl_path.join(tmp_dir, "parent")))
				assert.is_true(pl_path.islink(link_path_str))
				assert.are.equal(link_target_path_str, readlink(link_path_str))
				assert.is_true(op.link_actually_created)
			end)
		end)

		describe("options.create_parent_dirs = false (default)", function()
			it("should fail if intermediate parent directory for link path (self.target) does not exist", function()
				local link_target_path_str = pl_path.join(tmp_dir, "target_no_parents.txt")
				create_file_for_test(link_target_path_str)
				local link_path_str = pl_path.join(tmp_dir, "missing_parent", "my_link_no_parents")

				local op = SymlinkOperation.new(link_target_path_str, link_path_str)
				local success, err = op:execute()

				assert.is_false(success)
				assert.match("No such file or directory", err)
				assert.is_false(pl_path.islink(link_path_str))
				assert.is_false(op.link_actually_created)
			end)
		end)

		describe("Validation Failures", function()
			it("should fail if link target path (self.source) is not specified", function()
				local link_path_str = pl_path.join(tmp_dir, "link_no_source")
				local op = SymlinkOperation.new(nil, link_path_str)
				local valid, err = op:validate()
				assert.is_false(valid)
				assert.match("Link target path .* not specified", err)
			end)

			it("should fail if link path (self.target) is not specified", function()
				local link_target_path_str = pl_path.join(tmp_dir, "target_no_link_path")
				local op = SymlinkOperation.new(link_target_path_str)
				local valid, err = op:validate()
				assert.is_false(valid)
				assert.match("Link path .* not specified", err)
			end)

			it(
				"should fail if link path (self.target) is an existing directory (cannot overwrite dir with symlink)",
				function()
					local link_target_path_str = pl_path.join(tmp_dir, "target_for_dir_conflict.txt")
					create_file_for_test(link_target_path_str)
					local link_path_isdir_str = pl_path.join(tmp_dir, "link_path_is_a_directory")
					create_dir_for_test(link_path_isdir_str)

					local op = SymlinkOperation.new(link_target_path_str, link_path_isdir_str, { overwrite = true })
					local valid, err_validate = op:validate()
					assert.is_false(valid)
					assert.match("Cannot create symlink .* is a directory", err_validate)

					local success_exec, err_exec = op:execute()
					assert.is_false(success_exec)
					assert.match("Cannot create symlink .* is a directory", err_exec)
					assert.is_false(pl_path.islink(link_path_isdir_str))
					assert.is_true(pl_path.isdir(link_path_isdir_str))
				end
			)
		end)
	end)

	describe(":undo", function()
		it("should remove a symlink that was created by the operation", function()
			local link_target_path_str = pl_path.join(tmp_dir, "target_for_undo.txt")
			create_file_for_test(link_target_path_str)
			local link_path_str = pl_path.join(tmp_dir, "link_to_undo")

			local op = SymlinkOperation.new(link_target_path_str, link_path_str)
			local exec_success, exec_err = op:execute()
			assert.is_true(exec_success, exec_err)
			assert.is_true(pl_path.islink(link_path_str))
			assert.is_true(op.link_actually_created)

			local undo_success, undo_err = op:undo()
			assert.is_true(undo_success, undo_err)
			assert.is_false(pl_path.islink(link_path_str))
			assert.is_false(pl_path.exists(link_path_str))
		end)

		it("should be a no-op if link_actually_created is false", function()
			local link_target_path_str = pl_path.join(tmp_dir, "target_no_op_undo.txt")
			create_file_for_test(link_target_path_str)
			local link_path_str = pl_path.join(tmp_dir, "link_no_op_undo_exists")
			create_file_for_test(link_path_str, "pre-existing file")

			local op = SymlinkOperation.new(link_target_path_str, link_path_str, { overwrite = false })
			local exec_success, exec_err = op:execute()
			assert.is_false(exec_success)
			assert.is_false(op.link_actually_created)

			local undo_success, undo_err = op:undo()
			assert.is_true(undo_success, undo_err)
			assert.are.equal(link_path_str, pl_path.exists(link_path_str))
			assert.is_false(pl_path.islink(link_path_str))
		end)

		it("should fail (or be a no-op success) if link path (self.target) no longer exists at time of undo", function()
			local link_target_path_str = pl_path.join(tmp_dir, "target_undo_gone.txt")
			create_file_for_test(link_target_path_str)
			local link_path_str = pl_path.join(tmp_dir, "link_undo_gone")

			local op = SymlinkOperation.new(link_target_path_str, link_path_str)
			local exec_success, exec_err = op:execute()
			assert.is_true(exec_success, exec_err)
			assert.is_true(op.link_actually_created)
			assert.is_true(pl_path.islink(link_path_str))

			assert.is_true(pl_file.delete(link_path_str))

			local undo_success, undo_err = op:undo()
			assert.is_true(undo_success, undo_err)
			assert.is_false(pl_path.islink(link_path_str))
		end)

		it(
			"should fail if link path (self.target) is not a symlink at time of undo (e.g., replaced by a file)",
			function()
				local link_target_path_str = pl_path.join(tmp_dir, "target_undo_not_link.txt")
				create_file_for_test(link_target_path_str)
				local link_path_str = pl_path.join(tmp_dir, "link_undo_not_link")

				local op = SymlinkOperation.new(link_target_path_str, link_path_str)
				local exec_success, exec_err = op:execute()
				assert.is_true(exec_success, exec_err)
				assert.is_true(op.link_actually_created)
				assert.is_true(pl_path.islink(link_path_str))

				assert.is_true(pl_file.delete(link_path_str))
				create_file_for_test(link_path_str, "now a file")

				local undo_success, undo_err = op:undo()
				assert.is_false(undo_success)
				assert.match("is not a symlink", undo_err)
				assert.are.equal(link_path_str, pl_path.exists(link_path_str))
				assert.are.equal("now a file", pl_file.read(link_path_str))
			end
		)

		it(
			"should successfully restore original file if overwrite=true was used and original_target_was_file=true",
			function()
				local link_target_path_str = pl_path.join(tmp_dir, "target_for_undo_overwrite.txt")
				create_file_for_test(link_target_path_str, "link points here")
				local link_path_str = pl_path.join(tmp_dir, "path_to_be_overwritten_for_undo")
				local original_content = "this file will be replaced and then restored"
				create_file_for_test(link_path_str, original_content)

				local op = SymlinkOperation.new(link_target_path_str, link_path_str, { overwrite = true })
				local success, err = op:execute()
				assert.is_true(success, err)
				assert.is_true(pl_path.islink(link_path_str))
				assert.is_true(op.original_target_was_file)
				assert.are.equal(original_content, op.original_target_data)

				local undo_success, undo_err = op:undo()
				assert.is_true(undo_success, undo_err)
				assert.is_false(pl_path.islink(link_path_str))
				assert.is_true(pl_path.isfile(link_path_str))
				assert.are.equal(original_content, pl_file.read(link_path_str))
			end
		)

		it(
			"should successfully restore original symlink if overwrite=true was used and original_target_was_symlink=true",
			function()
				local link_target_path_str = pl_path.join(tmp_dir, "target_for_undo_overwrite_sym.txt")
				create_file_for_test(link_target_path_str, "new link points here")

				local original_symlink_points_to_str = pl_path.join(tmp_dir, "original_symlink_target.txt")
				create_file_for_test(original_symlink_points_to_str, "original symlink content")

				local link_path_str = pl_path.join(tmp_dir, "symlink_to_be_overwritten_for_undo")
				assert.is_true(lfs.link(original_symlink_points_to_str, link_path_str, true))

				local op = SymlinkOperation.new(link_target_path_str, link_path_str, { overwrite = true })
				local success, err = op:execute()
				assert.is_true(success, err)
				assert.is_true(pl_path.islink(link_path_str))
				assert.are.equal(link_target_path_str, readlink(link_path_str))
				assert.is_true(op.original_target_was_symlink)
				assert.are.equal(original_symlink_points_to_str, op.original_target_data)

				local undo_success, undo_err = op:undo()
				assert.is_true(undo_success, undo_err)
				assert.is_true(pl_path.islink(link_path_str))
				assert.are.equal(original_symlink_points_to_str, readlink(link_path_str))
			end
		)
	end)
end)
