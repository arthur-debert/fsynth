local helper = require("spec.spec_helper")
local CreateFileOperation = require("fsynth.operations.create_file")
local Checksum = require("fsynth.checksum")
local pl_path = require("pl.path")
local fs = require("pl.fs")

describe("CreateFileOperation", function()
  local tmp_dir

  before_each(function()
    helper.clean_tmp_dir()
    tmp_dir = helper.get_tmp_dir()
  end)

  after_each(function()
    helper.clean_tmp_dir()
  end)

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
      local op = CreateFileOperation:new({ path = file_path_str })

      local success, err = op:execute()
      assert.is_true(success, err)
      assert.is_true(pl_path.exists(file_path_str))
      assert.are.equal("", read_file_content(file_path_str))
      assert.is_not_nil(op.checksum_data.target_checksum)
      assert.are.equal(Checksum.string(""), op.checksum_data.target_checksum)
    end)

    it("should create a new file with specified string content", function()
      local file_path_str = pl_path.join(tmp_dir, "new_file_with_content.txt")
      local content = "Hello, Fsynth!"
      local op = CreateFileOperation:new({ path = file_path_str, content = content })

      local success, err = op:execute()
      assert.is_true(success, err)
      assert.is_true(pl_path.exists(file_path_str))
      assert.are.equal(content, read_file_content(file_path_str))
      assert.is_not_nil(op.checksum_data.target_checksum)
      assert.are.equal(Checksum.string(content), op.checksum_data.target_checksum)
    end)

    describe("options.create_parent_dirs = true", function()
      it("should create nested directories and the file if parent directories do not exist", function()
        local file_path_str = pl_path.join(tmp_dir, "parent", "child", "new_file.txt")
        local content = "Nested!"
        local op = CreateFileOperation:new({
          path = file_path_str,
          content = content,
          create_parent_dirs = true
        })

        local success, err = op:execute()
        assert.is_true(success, err)
        assert.is_true(pl_path.exists(pl_path.join(tmp_dir, "parent", "child")))
        assert.is_true(pl_path.exists(pl_path.join(tmp_dir, "parent")))
        assert.is_true(pl_path.exists(file_path_str))
        assert.are.equal(content, read_file_content(file_path_str))
        assert.is_not_nil(op.checksum_data.target_checksum)
      end)
    end)

    describe("options.create_parent_dirs = false (default)", function()
      it("should fail if an intermediate parent directory does not exist", function()
        local file_path_str = pl_path.join(tmp_dir, "missing_parent", "new_file.txt")
        local op = CreateFileOperation:new({ path = file_path_str, content = "test" })

        local success, err = op:execute()
        assert.is_false(success)
        assert.match("No such file or directory", err)
        assert.is_false(pl_path.exists(file_path_str))
        assert.is_nil(op.checksum_data.target_checksum)
      end)

      it("should succeed if the immediate parent directory exists", function()
        local parent_dir_str = pl_path.join(tmp_dir, "existing_parent_for_file")
        assert.is_true(fs.mkdir(parent_dir_str))
        local file_path_str = pl_path.join(parent_dir_str, "child_file.txt")
        local content = "Child content"
        local op = CreateFileOperation:new({ path = file_path_str, content = content })

        local success, err = op:execute()
        assert.is_true(success, err)
        assert.is_true(pl_path.exists(file_path_str))
        assert.are.equal(content, read_file_content(file_path_str))
        assert.is_not_nil(op.checksum_data.target_checksum)
      end)
    end)

    describe("Validation Failures", function()
      it("should fail validation if options.content is a number", function()
        local op = CreateFileOperation:new({ path = pl_path.join(tmp_dir, "file.txt"), content = 123 })
        local valid, err = op:validate()
        assert.is_false(valid)
        assert.match("content must be a string", err)
      end)

      it("should fail validation if options.content is a table", function()
        local op = CreateFileOperation:new({ path = pl_path.join(tmp_dir, "file.txt"), content = {} })
        local valid, err = op:validate()
        assert.is_false(valid)
        assert.match("content must be a string", err)
      end)

      it("should fail validation if the target path is not specified (nil)", function()
        local op = CreateFileOperation:new({ path = nil })
        local valid, err = op:validate()
        assert.is_false(valid)
        assert.match("path is required", err)
      end)

      it("should fail validation if the target path is not specified (empty string)", function()
        local op = CreateFileOperation:new({ path = "" })
        local valid, err = op:validate()
        assert.is_false(valid)
        assert.match("path is required", err)
      end)

      it("should fail validation if the target path is an existing directory", function()
        local dir_path_str = pl_path.join(tmp_dir, "existing_dir_for_file_test")
        assert.is_true(fs.mkdir(dir_path_str))
        local op = CreateFileOperation:new({ path = dir_path_str, content = "test" })
        local success, err = op:execute()
        assert.is_false(success)
        assert.match("is an existing directory", err)
      end)

      it("should fail if the target path already exists and is a file (implicit exclusive)", function()
        local file_path_str = pl_path.join(tmp_dir, "existing_file_for_create.txt")
        local f = io.open(file_path_str, "w")
        f:write("original content")
        f:close()

        local op = CreateFileOperation:new({ path = file_path_str, content = "new content" })
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
      local op = CreateFileOperation:new({ path = file_path_str, content = content })

      local success, err = op:execute()
      assert.is_true(success, err)
      assert.is_true(pl_path.exists(file_path_str))
      assert.is_not_nil(op.checksum_data.target_checksum)

      local undo_success, undo_err = op:undo()
      assert.is_true(undo_success, undo_err)
      assert.is_false(pl_path.exists(file_path_str))
    end)

    it("should fail (or do nothing) if the file does not exist at the time of undo", function()
      local file_path_str = pl_path.join(tmp_dir, "undo_file_gone.txt")
      local op = CreateFileOperation:new({ path = file_path_str, content = "test" })

      local success, err = op:execute()
      assert.is_true(success, err)
      assert.is_true(pl_path.exists(file_path_str))
      local stored_checksum = op.checksum_data.target_checksum

      assert.is_true(fs.delete(file_path_str)) -- Manually remove the file

      op.checksum_data.target_checksum = stored_checksum 
      local undo_success, undo_err = op:undo()
      assert.is_false(undo_success)
      assert.match("does not exist", undo_err)
    end)

    it("should fail if the file's content (and thus checksum) has changed since creation", function()
      local file_path_str = pl_path.join(tmp_dir, "undo_file_changed.txt")
      local op = CreateFileOperation:new({ path = file_path_str, content = "original content" })

      local success, err = op:execute()
      assert.is_true(success, err)
      assert.is_true(pl_path.exists(file_path_str))
      assert.is_not_nil(op.checksum_data.target_checksum)

      local f = io.open(file_path_str, "w")
      assert.is_not_nil(f)
      f:write("modified content")
      f:close()
      assert.is_true(pl_path.exists(file_path_str))

      local undo_success, undo_err = op:undo()
      assert.is_false(undo_success)
      assert.match("checksum mismatch", undo_err)
      assert.is_true(pl_path.exists(file_path_str)) 
    end)

    it("should fail if no target_checksum was stored (e.g., if execute failed)", function()
      local dir_path_as_file_str = pl_path.join(tmp_dir, "a_directory")
      assert.is_true(fs.mkdir(dir_path_as_file_str))

      local op = CreateFileOperation:new({ path = dir_path_as_file_str, content = "test" })
      local exec_success = op:execute()
      assert.is_false(exec_success)
      assert.is_nil(op.checksum_data.target_checksum)

      local undo_success, undo_err = op:undo()
      assert.is_false(undo_success)
      assert.match("No target checksum available", undo_err)
    end)

    it("should not attempt to remove file if it was not created by this operation", function()
      pending("Skipping: CreateFileOperation is always exclusive; file_actually_created_by_this_op logic not present yet for non-creation scenarios.")
    end)
  end)
end)
