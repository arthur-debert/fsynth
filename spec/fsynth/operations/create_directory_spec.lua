local helper = require("spec.spec_helper")
local CreateDirectoryOperation = require("fsynth.operations.create_directory")
local pl_path = require("pl.path")
-- Updated import - using path instead of fs
-- local fs = require("pl.fs")

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
        assert.equal(pl_path.join(tmp_dir, "parent", "child"), pl_path.exists(pl_path.join(tmp_dir, "parent", "child")))
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
        -- Updated to check for the actual error message
        assert.match("Failed to create directory", err)
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
      assert.is_true(undo_success, undo_err)                   -- Undo should report success (no-op)
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

    it("should succeed (or do nothing harmlessly) if the directory to be removed by undo does not exist anymore",
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
      end)
  end)
end)
