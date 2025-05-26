local helper = require("spec.spec_helper")
local DeleteOperation = require("fsynth.operations.delete")
local Checksum = require("fsynth.checksum")
local pl_path = require("pl.path")
local pl_file = require("pl.file") -- Updated import - using file instead of fs

describe("DeleteOperation", function()
	local tmp_dir

	before_each(function()
		helper.clean_tmp_dir()
		tmp_dir = helper.get_tmp_dir()
	end)

	after_each(function()
		helper.clean_tmp_dir()
	end)

	local function create_file_for_test(path_str, content)
		local file = io.open(path_str, "w")
		assert.is_not_nil(file, "Failed to create file for test setup: " .. path_str)
		if content then
			file:write(content)
		end
		file:close()
		assert.is_true(pl_path.exists(path_str), "File was not created: " .. path_str)
	end

	local function create_dir_for_test(path_str)
		assert.is_true(pl_path.mkdir(path_str), "Failed to create directory for test setup: " .. path_str)
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

	describe(":execute", function()
		describe("Successful Deletion", function()
			it("should delete an existing file", function()
				local file_path_str = pl_path.join(tmp_dir, "file_to_delete.txt")
				local content = "some content"
				create_file_for_test(file_path_str, content)

				local op = DeleteOperation.new(file_path_str)
				local success, err = op:execute()

				assert.is_true(success, err)
				assert.is_false(pl_path.exists(file_path_str))
				assert.is_true(op.item_actually_deleted)
				assert.are.equal(content, op.original_content)
				assert.are.equal(Checksum.string(content), op.checksum_data.original_checksum)
			end)

			it("should delete an existing empty directory", function()
				local dir_path_str = pl_path.join(tmp_dir, "empty_dir_to_delete")
				create_dir_for_test(dir_path_str)

				local op = DeleteOperation.new(dir_path_str)
				local success, err = op:execute()

				assert.is_true(success, err)
				assert.is_false(pl_path.exists(dir_path_str))
				assert.is_true(op.item_actually_deleted)
				assert.is_nil(op.original_content)
				assert.is_nil(op.checksum_data.original_checksum)
			end)
		end)

		describe("Attempting to Delete Non-Existent Item", function()
			it("should succeed (no-op) if the target item does not exist", function()
				local file_path_str = pl_path.join(tmp_dir, "non_existent_file.txt")
				local op = DeleteOperation.new(file_path_str)

				local success, err = op:execute()
				assert.is_true(success, err)
				assert.is_false(op.item_actually_deleted)
			end)
		end)

		describe("Validation Failures and Expected Behavior", function()
			it("should fail validation if the path to delete is not specified (nil)", function()
				local op = DeleteOperation.new(nil)
				local valid, err = op:validate()
				assert.is_false(valid)
				assert.match("path is required", err)
			end)

			it("should fail validation if the path to delete is not specified (empty string)", function()
				local op = DeleteOperation.new("")
				local valid, err = op:validate()
				assert.is_false(valid)
				assert.match("path is required", err)
			end)

			it("should fail to delete a non-empty directory (current behavior)", function()
				local dir_path_str = pl_path.join(tmp_dir, "non_empty_dir")
				create_dir_for_test(dir_path_str)
				create_file_for_test(pl_path.join(dir_path_str, "some_file.txt"), "content")

				local op = DeleteOperation.new(dir_path_str)
				local success, err = op:execute()
				assert.is_false(success)
				assert.match("not empty", err)
				assert.is_true(pl_path.exists(dir_path_str))
				assert.is_false(op.item_actually_deleted)
			end)
		end)

		describe("Data Storage for Undo (Files)", function()
			it("should store original_content and original_checksum during validation of an existing file", function()
				local file_path_str = pl_path.join(tmp_dir, "file_for_undo_data.txt")
				local content = "data to be stored"
				create_file_for_test(file_path_str, content)

				local op = DeleteOperation.new(file_path_str)
				local valid, err = op:validate()

				assert.is_true(valid, err)
				assert.are.equal(content, op.original_content)
				assert.are.equal(Checksum.string(content), op.checksum_data.original_checksum)
				assert.are.equal("file", op.item_type)
			end)

			it("should store item_type 'directory' during validation of an existing directory", function()
				local dir_path_str = pl_path.join(tmp_dir, "dir_for_undo_data")
				create_dir_for_test(dir_path_str)

				local op = DeleteOperation.new(dir_path_str)
				local valid, err = op:validate()

				assert.is_true(valid, err)
				assert.is_nil(op.original_content)
				assert.is_nil(op.checksum_data.original_checksum)
				assert.are.equal("directory", op.item_type)
			end)
		end)
	end)

	describe(":undo", function()
		describe("Undo for Files", function()
			it("should successfully recreate a deleted file with original content and checksum", function()
				local file_path_str = pl_path.join(tmp_dir, "file_to_undo_delete.txt")
				local content = "Come back to me!"
				create_file_for_test(file_path_str, content)

				local op = DeleteOperation.new(file_path_str)
				local exec_success, exec_err = op:execute()
				assert.is_true(exec_success, exec_err)
				assert.is_false(pl_path.exists(file_path_str))
				assert.is_true(op.item_actually_deleted)
				assert.are.equal(content, op.original_content)
				assert.are.equal(Checksum.string(content), op.checksum_data.original_checksum)

				local undo_success, undo_err = op:undo()
				assert.is_true(undo_success, undo_err)
				assert.is_true(pl_path.exists(file_path_str))
				assert.are.equal(content, read_file_content(file_path_str))
				assert.are.equal(op.checksum_data.original_checksum, Checksum.path(file_path_str))
			end)

			it("should fail undo if the file path already exists before undoing", function()
				local file_path_str = pl_path.join(tmp_dir, "file_exists_for_undo.txt")
				local original_content = "original"
				create_file_for_test(file_path_str, original_content)

				local op = DeleteOperation.new(file_path_str)
				local exec_success, exec_err = op:execute()
				assert.is_true(exec_success, exec_err)
				assert.is_true(op.item_actually_deleted)

				create_file_for_test(file_path_str, "conflicting content")

				local undo_success, undo_err = op:undo()
				assert.is_false(undo_success)
				assert.match("already exists", undo_err)
				assert.are.equal("conflicting content", read_file_content(file_path_str))
			end)
		end)

		describe("Undo for Directories", function()
			it("should successfully recreate a deleted empty directory", function()
				local dir_path_str = pl_path.join(tmp_dir, "dir_to_undo_delete")
				create_dir_for_test(dir_path_str)

				local op = DeleteOperation.new(dir_path_str)
				local exec_success, exec_err = op:execute()
				assert.is_true(exec_success, exec_err)
				assert.is_false(pl_path.exists(dir_path_str))
				assert.is_true(op.item_actually_deleted)
				assert.are.equal("directory", op.item_type)

				local undo_success, undo_err = op:undo()
				assert.is_true(undo_success, undo_err)
				assert.is_true(pl_path.exists(dir_path_str))
				assert.is_true(pl_path.isdir(dir_path_str))
			end)

			it("should fail undo if the directory path already exists before undoing", function()
				local dir_path_str = pl_path.join(tmp_dir, "dir_exists_for_undo")
				create_dir_for_test(dir_path_str)

				local op = DeleteOperation.new(dir_path_str)
				local exec_success, exec_err = op:execute()
				assert.is_true(exec_success, exec_err)
				assert.is_true(op.item_actually_deleted)

				create_dir_for_test(dir_path_str)
				create_file_for_test(pl_path.join(dir_path_str, "marker.txt"), "marker")

				local undo_success, undo_err = op:undo()
				assert.is_false(undo_success)
				assert.match("already exists", undo_err)
				assert.is_true(pl_path.exists(pl_path.join(dir_path_str, "marker.txt")))
			end)
		end)

		describe("Undo when item was not deleted by the operation", function()
			it("should be a no-op if item_actually_deleted is false (e.g. item did not exist)", function()
				local file_path_str = pl_path.join(tmp_dir, "non_existent_for_undo.txt")
				local op = DeleteOperation.new(file_path_str)

				local exec_success, exec_err = op:execute()
				assert.is_true(exec_success, exec_err)
				assert.is_false(op.item_actually_deleted)

				local undo_success, undo_err = op:undo()
				assert.is_true(undo_success, undo_err)
				assert.is_false(pl_path.exists(file_path_str))
			end)

			it("should be a no-op if item_actually_deleted is false (e.g. failed to delete non-empty dir)", function()
				local dir_path_str = pl_path.join(tmp_dir, "non_empty_for_undo_noop")
				create_dir_for_test(dir_path_str)
				create_file_for_test(pl_path.join(dir_path_str, "child.txt"), "child")

				local op = DeleteOperation.new(dir_path_str)
				local exec_success, exec_err = op:execute()
				assert.is_false(exec_success)
				assert.is_false(op.item_actually_deleted)
				assert.are.equal("directory", op.item_type)

				local undo_success, undo_err = op:undo()
				assert.is_true(undo_success, undo_err)
				assert.is_true(pl_path.exists(dir_path_str))
				assert.is_true(pl_path.exists(pl_path.join(dir_path_str, "child.txt")))
			end)
		end)

		it("should fail undo if original_content is needed (file) but not available", function()
			local file_path_str = pl_path.join(tmp_dir, "file_no_content_for_undo.txt")
			local op = DeleteOperation.new(file_path_str)
			op.item_actually_deleted = true
			op.item_type = "file"
			op.original_content = nil
			op.checksum_data = { original_checksum = "dummy_checksum" }

			local undo_success, undo_err = op:undo()
			assert.is_false(undo_success)
			assert.match("Missing original_content for file undo", undo_err)
		end)

		it("should fail undo if original_checksum is needed (file) but not available", function()
			local file_path_str = pl_path.join(tmp_dir, "file_no_checksum_for_undo.txt")
			local op = DeleteOperation.new(file_path_str)
			op.item_actually_deleted = true
			op.item_type = "file"
			op.original_content = "some content"
			op.checksum_data = { original_checksum = nil }

			local undo_success, undo_err = op:undo()
			assert.is_false(undo_success)
			assert.match("Missing original_checksum for file undo", undo_err)
		end)

		it("should fail undo if item_type is unknown or not set but item was supposedly deleted", function()
			local file_path_str = pl_path.join(tmp_dir, "unknown_type_for_undo.txt")
			local op = DeleteOperation.new(file_path_str)
			op.item_actually_deleted = true
			op.item_type = nil

			local undo_success, undo_err = op:undo()
			assert.is_false(undo_success)
			assert.match("Unknown item_type for undo", undo_err)
		end)
	end)
end)
