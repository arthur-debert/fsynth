-- Tests for the CopyFileOperation
local CopyFileOperation = require("fsynth.operations.copy_file")
local pl_file = require("pl.file")
local helper = require("spec.spec_helper")

describe("CopyFileOperation", function()
    -- Set up test environment
    setup(function()
        helper.clean_tmp_dir()
    end)

    teardown(function()
        helper.clean_tmp_dir()
    end)

    it("should create a new operation with defaults", function()
        local tmp_dir = helper.get_tmp_dir()
        local source = tmp_dir .. "/source.txt"
        local target = tmp_dir .. "/target.txt"

        local op = CopyFileOperation.new(source, target)

        assert.are.equal(source, op.source)
        assert.are.equal(target, op.target)
        assert.is_false(op.options.overwrite)
        assert.is_false(op.options.create_parent_dirs)
    end)

    it("should validate file existence before copying", function()
        local tmp_dir = helper.get_tmp_dir()
        local source = tmp_dir .. "/nonexistent.txt"
        local target = tmp_dir .. "/target.txt"

        local op = CopyFileOperation.new(source, target)

        local valid, err = op:validate()
        assert.is_false(valid)
        assert.truthy(err:match("not a file or does not exist"))
    end)

    it("should validate target directory existence", function()
        local tmp_dir = helper.get_tmp_dir()
        local source = tmp_dir .. "/source.txt"
        local nonexistent_dir = tmp_dir .. "/nonexistent_dir"
        local target = nonexistent_dir .. "/target.txt"

        -- Create source file
        local file = io.open(source, "w")
        file:write("Test content")
        file:close()

        local op = CopyFileOperation.new(source, target)

        local valid, err = op:validate()
        assert.is_false(valid)
        assert.truthy(err:match("Parent directory of target"))
    end)

    it("should validate target overwrite settings", function()
        local tmp_dir = helper.get_tmp_dir()
        local source = tmp_dir .. "/source.txt"
        local target = tmp_dir .. "/target.txt"

        -- Create source file
        local file = io.open(source, "w")
        file:write("Source content")
        file:close()

        -- Create target file
        file = io.open(target, "w")
        file:write("Target content")
        file:close()

        local op = CopyFileOperation.new(source, target)

        local valid, err = op:validate()
        assert.is_false(valid)
        assert.truthy(err:match("exists and overwrite is false"))

        -- Create new operation with overwrite=true
        local op2 = CopyFileOperation.new(source, target, { overwrite = true })

        local valid2 = op2:validate()
        assert.is_true(valid2)
    end)

    it("should successfully copy a file", function()
        local tmp_dir = helper.get_tmp_dir()
        local source = tmp_dir .. "/source.txt"
        local target = tmp_dir .. "/target.txt"
        local content = "Test content for copying"

        print("TEST: Creating source file at", source)
        -- Create source file
        local file = io.open(source, "w")
        file:write(content)
        file:close()

        print("TEST: Creating CopyFileOperation with overwrite=true")
        local op = CopyFileOperation.new(source, target, {overwrite = true})

        print("TEST: Validating operation")
        local valid, err = op:validate()
        print("TEST: Validation result:", valid, err)
        assert.is_true(valid, "Validation failed: " .. tostring(err))

        local success = op:execute()
        assert.is_true(success)

        -- Verify content was copied correctly
        local target_content = pl_file.read(target)
        assert.are.equal(content, target_content)
    end)

    it("should create parent directories when option is set", function()
        local tmp_dir = helper.get_tmp_dir()
        local source = tmp_dir .. "/source.txt"
        local target_dir = tmp_dir .. "/nested/dirs"
        local target = target_dir .. "/target.txt"
        local content = "Test content for copying to nested directory"

        -- Create source file
        local file = io.open(source, "w")
        file:write(content)
        file:close()

        local op = CopyFileOperation.new(source, target, { create_parent_dirs = true })

        local valid = op:validate()
        assert.is_true(valid)

        local success = op:execute()
        assert.is_true(success)

        -- Verify content was copied correctly
        local target_content = pl_file.read(target)
        assert.are.equal(content, target_content)
    end)

    it("should store checksums for source and target", function()
        local tmp_dir = helper.get_tmp_dir()
        local source = tmp_dir .. "/source.txt"
        local target = tmp_dir .. "/target.txt"
        local content = "Checksum test content"

        -- Create source file
        local file = io.open(source, "w")
        file:write(content)
        file:close()

        local op = CopyFileOperation.new(source, target)

        -- Initial checksumming happens in new()
        assert.truthy(op.checksum_data.source_checksum)
        assert.truthy(op.checksum_data.initial_source_checksum)

        local success = op:execute()
        assert.is_true(success)

        -- After execution, target checksum should be stored
        assert.truthy(op.checksum_data.target_checksum)
    end)

    it("should properly undo a copy operation", function()
        local tmp_dir = helper.get_tmp_dir()
        local source = tmp_dir .. "/source.txt"
        local target = tmp_dir .. "/target.txt"
        local content = "Test content for undoing"

        -- Create source file
        local file = io.open(source, "w")
        file:write(content)
        file:close()

        local op = CopyFileOperation.new(source, target)

        local success = op:execute()
        assert.is_true(success)

        -- Verify target was created
        assert.truthy(io.open(target, "r"))

        -- Undo the operation
        local undo_success = op:undo()
        assert.is_true(undo_success)

        -- Verify target was removed
        local target_file = io.open(target, "r")
        assert.is_false(target_file ~= nil)
    end)

    it("should detect source file changes and fail validation", function()
        local tmp_dir = helper.get_tmp_dir()
        local source = tmp_dir .. "/source.txt"
        local target = tmp_dir .. "/target.txt"

        -- Create source file
        local file = io.open(source, "w")
        file:write("Initial content")
        file:close()

        local op = CopyFileOperation.new(source, target)

        -- Change the source file
        file = io.open(source, "w")
        file:write("Modified content")
        file:close()

        -- Verify validation fails due to checksum mismatch
        local valid, err = op:validate()
        assert.is_false(valid)
        assert.truthy(err:match("Source file validation failed"))
    end)
end)
