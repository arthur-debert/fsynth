-- Tests for the Processor module
local Processor = require("fsynth.processor")
local Queue = require("fsynth.queue")
local CopyFileOperation = require("fsynth.operations.copy_file")
local helper = require("spec.spec_helper")

describe("Processor", function()
	-- Set up test environment
	setup(function()
		helper.clean_tmp_dir()
	end)

	teardown(function()
		helper.clean_tmp_dir()
	end)

	-- Create a mock operation for testing
	local function create_mock_operation(should_validate, should_execute, should_undo)
		local mock = {
			source = "mock_source",
			target = "mock_target",
			validate_called = false,
			execute_called = false,
			undo_called = false,
			checksum_called = false,
		}

		function mock:validate()
			self.validate_called = true
			return should_validate, not should_validate and "Validation failed" or nil
		end

		function mock:execute()
			self.execute_called = true
			return should_execute, not should_execute and "Execution failed" or nil
		end

		function mock:undo()
			self.undo_called = true
			return should_undo, not should_undo and "Undo failed" or nil
		end

		function mock:checksum()
			self.checksum_called = true
			return true
		end

		return mock
	end

	it("should create a new processor with default options", function()
		local processor = Processor.new()
		assert.are.same({}, processor.options)
		assert.are.same({}, processor.executed)
		assert.are.same({}, processor.errors)
	end)

	it("should create a new processor with custom options", function()
		local processor = Processor.new({ validate_first = true, best_effort = true })
		assert.are.same({ validate_first = true, best_effort = true }, processor.options)
	end)

	describe("process", function()
		it("should process operations successfully", function()
			local processor = Processor.new()
			local queue = Queue.new()
			local op1 = create_mock_operation(true, true, true)
			local op2 = create_mock_operation(true, true, true)

			Queue.enqueue(queue, op1)
			Queue.enqueue(queue, op2)

			local success = processor:process(queue)

			assert.is_true(success)
			assert.is_true(op1.validate_called)
			assert.is_true(op1.execute_called)
			assert.is_false(op1.undo_called)
			assert.is_true(op2.validate_called)
			assert.is_true(op2.execute_called)
			assert.is_false(op2.undo_called)
			assert.are.equal(2, #processor.executed)
			assert.are.equal(0, #processor.errors)
		end)

		it("should stop on validation failure", function()
			local processor = Processor.new()
			local queue = Queue.new()
			local op1 = create_mock_operation(true, true, true)
			local op2 = create_mock_operation(false, true, true)
			local op3 = create_mock_operation(true, true, true)

			Queue.enqueue(queue, op1)
			Queue.enqueue(queue, op2)
			Queue.enqueue(queue, op3)

			local success = processor:process(queue)

			assert.is_false(success)
			assert.is_true(op1.validate_called)
			assert.is_false(op1.undo_called)
			assert.is_true(op2.validate_called)
			assert.is_false(op2.execute_called)
			assert.is_false(op3.validate_called)
			assert.is_false(op3.execute_called)
			assert.are.equal(1, #processor.errors)
			assert.are.equal("validation", processor.errors[1].phase)
		end)

		it("should validate all operations first when validate_first is true", function()
			local processor = Processor.new({ validate_first = true })
			local queue = Queue.new()
			local op1 = create_mock_operation(true, true, true)
			local op2 = create_mock_operation(false, true, true)

			Queue.enqueue(queue, op1)
			Queue.enqueue(queue, op2)

			local success = processor:process(queue)

			assert.is_false(success)
			assert.is_true(op1.validate_called)
			assert.is_true(op2.validate_called)
			assert.is_false(op1.execute_called)
			assert.is_false(op2.execute_called)
			assert.are.equal(1, #processor.errors)
		end)

		it("should continue execution on error with best_effort", function()
			local processor = Processor.new({ best_effort = true })
			local queue = Queue.new()
			local op1 = create_mock_operation(true, true, true)
			local op2 = create_mock_operation(true, false, true)
			local op3 = create_mock_operation(true, true, true)

			Queue.enqueue(queue, op1)
			Queue.enqueue(queue, op2)
			Queue.enqueue(queue, op3)

			local success = processor:process(queue)

			assert.is_true(success) -- best_effort returns true
			assert.is_true(op1.execute_called)
			assert.is_true(op2.execute_called)
			assert.is_true(op3.execute_called)
			assert.are.equal(2, #processor.executed) -- op1 and op3
			assert.are.equal(1, #processor.errors)
			assert.are.equal("execution", processor.errors[1].phase)
		end)

		it("should rollback on failure with transactional option", function()
			local processor = Processor.new({ transactional = true })
			local queue = Queue.new()
			local op1 = create_mock_operation(true, true, true)
			local op2 = create_mock_operation(true, false, true)

			Queue.enqueue(queue, op1)
			Queue.enqueue(queue, op2)

			local success = processor:process(queue)

			assert.is_false(success)
			assert.is_true(op1.execute_called)
			assert.is_true(op1.undo_called)
			assert.is_true(op2.execute_called)
			assert.are.equal(1, #processor.executed) -- only op1 succeeded
			assert.are.equal(1, #processor.errors)
		end)

		it("should handle undo failures during rollback", function()
			local processor = Processor.new({ transactional = true })
			local queue = Queue.new()
			local op1 = create_mock_operation(true, true, false) -- undo will fail
			local op2 = create_mock_operation(true, false, true)

			Queue.enqueue(queue, op1)
			Queue.enqueue(queue, op2)

			local success = processor:process(queue)

			assert.is_false(success)
			assert.is_true(op1.undo_called)
			assert.are.equal(2, #processor.errors) -- execution error + rollback error
			assert.are.equal("rollback", processor.errors[2].phase)
		end)

		it("should verify checksums when verify_checksums is true", function()
			local processor = Processor.new({ verify_checksums = true })
			local queue = Queue.new()
			local op = create_mock_operation(true, true, true)

			Queue.enqueue(queue, op)

			local success = processor:process(queue)

			assert.is_true(success)
			assert.is_true(op.checksum_called)
		end)
	end)

	describe("format_errors", function()
		it("should format errors properly", function()
			local processor = Processor.new()
			local op = create_mock_operation(false, true, true)

			processor.errors = {
				{
					operation = op,
					phase = "validation",
					error = "Test validation error",
				},
			}

			local formatted = processor:format_errors()
			assert.truthy(formatted:match("validation phase"))
			assert.truthy(formatted:match("Test validation error"))
		end)
	end)

	-- Integration test with actual file operations
	describe("integration", function()
		it("should process file operations", function()
			local tmp_dir = helper.get_tmp_dir()
			local source_path = tmp_dir .. "/source.txt"
			local target_path = tmp_dir .. "/target.txt"
			local content = "Test content"

			-- Create a source file
			local file = io.open(source_path, "w")
			file:write(content)
			file:close()

			local processor = Processor.new()
			local queue = Queue.new()
			local copy_op = CopyFileOperation.new(source_path, target_path, { overwrite = true })

			Queue.enqueue(queue, copy_op)

			local success = processor:process(queue)

			assert.is_true(success)
			assert.are.equal(1, #processor.executed)

			-- Verify target file was created with correct content
			local target_file = io.open(target_path, "r")
			local target_content = target_file:read("*all")
			target_file:close()

			assert.are.equal(content, target_content)
		end)

		it("should rollback file operations on failure", function()
			local tmp_dir = helper.get_tmp_dir()
			local source_path = tmp_dir .. "/source2.txt"
			local target1_path = tmp_dir .. "/target1.txt"
			local target2_path = tmp_dir .. "/target2.txt" -- This will fail
			local content = "Test content"

			-- Create a source file
			local file = io.open(source_path, "w")
			file:write(content)
			file:close()

			local processor = Processor.new({ transactional = true })
			local queue = Queue.new()

			-- First operation will succeed
			local copy_op1 = CopyFileOperation.new(source_path, target1_path, { overwrite = true })

			-- Second operation will fail - source doesn't exist
			local copy_op2 = CopyFileOperation.new(tmp_dir .. "/nonexistent.txt", target2_path, { overwrite = true })

			Queue.enqueue(queue, copy_op1)
			Queue.enqueue(queue, copy_op2)

			local success = processor:process(queue)

			assert.is_false(success)
			assert.are.equal(1, #processor.executed)
			assert.are.equal(1, #processor.errors)

			-- Check that target1 was created but removed during rollback
			assert.is_false(io.open(target1_path, "r") ~= nil)
		end)
	end)
end)
