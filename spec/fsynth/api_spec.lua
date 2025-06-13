describe("Fsynth API", function()
	local fsynth = require("fsynth")

	-- Helper to create mock operations for testing
	local function create_mock_operation(type_name, should_validate, should_execute)
		local mock = {
			type = type_name,
			source = "mock_source",
			target = "mock_target",
			validate_called = false,
			execute_called = false,
			undo_called = false,
		}

		function mock:validate()
			self.validate_called = true
			return should_validate, not should_validate and "Mock validation error" or nil
		end

		function mock:execute()
			self.execute_called = true
			return should_execute, not should_execute and "Mock execution error" or nil
		end

		function mock:undo()
			self.undo_called = true
			return true
		end

		function mock:checksum()
			return true
		end

		return mock
	end

	describe("Queue Management", function()
		describe("new_queue", function()
			it("should create a new queue", function()
				local queue = fsynth.new_queue()
				assert.is_not_nil(queue)
				assert.equals(0, queue:size())
			end)
		end)

		describe("queue operations", function()
			local queue

			before_each(function()
				queue = fsynth.new_queue()
			end)

			it("should add operations to the queue", function()
				local op1 = create_mock_operation("MockOp1", true, true)
				local op2 = create_mock_operation("MockOp2", true, true)

				queue:add(op1)
				assert.equals(1, queue:size())

				queue:add(op2)
				assert.equals(2, queue:size())
			end)

			it("should return operations for inspection", function()
				local op1 = create_mock_operation("Type1", true, true)
				local op2 = create_mock_operation("Type2", true, true)

				queue:add(op1)
				queue:add(op2)

				local operations = queue:get_operations()
				assert.equals(2, #operations)
				assert.equals("Type1", operations[1].type)
				assert.equals("Type2", operations[2].type)
			end)

			it("should clear all operations", function()
				queue:add(create_mock_operation("Op1", true, true))
				queue:add(create_mock_operation("Op2", true, true))
				assert.equals(2, queue:size())

				queue:clear()
				assert.equals(0, queue:size())
				assert.same({}, queue:get_operations())
			end)

			it("should remove operation at specific index", function()
				local op1 = create_mock_operation("Op1", true, true)
				local op2 = create_mock_operation("Op2", true, true)
				local op3 = create_mock_operation("Op3", true, true)

				queue:add(op1)
				queue:add(op2)
				queue:add(op3)

				queue:remove(2)

				assert.equals(2, queue:size())
				local ops = queue:get_operations()
				assert.equals("Op1", ops[1].type)
				assert.equals("Op3", ops[2].type)
			end)

			it("should error when removing invalid index", function()
				queue:add(create_mock_operation("Op1", true, true))

				assert.has_error(function()
					queue:remove(0)
				end)

				assert.has_error(function()
					queue:remove(2)
				end)
			end)

			it("should error when adding nil operation", function()
				assert.has_error(function()
					queue:add(nil)
				end, "Cannot add nil operation to queue")
			end)
		end)
	end)

	describe("Operation Factories", function()
		-- Test that operation factories create operations with correct parameters

		describe("copy_file", function()
			it("should create a copy file operation with correct parameters", function()
				local op = fsynth.op.copy_file("source.txt", "target.txt")
				assert.equals("CopyFile", op.type)
				assert.equals("source.txt", op.source)
				assert.equals("target.txt", op.target)
				assert.is_function(op.validate)
				assert.is_function(op.execute)
			end)

			it("should pass options correctly", function()
				local op = fsynth.op.copy_file("source.txt", "target.txt", {
					overwrite = true,
					verify_checksum_before = true,
					verify_checksum_after = true,
					preserve_attributes = true,
				})
				assert.is_not_nil(op)
				-- The actual option mapping is tested in the operation's own tests
			end)
		end)

		describe("create_directory", function()
			it("should create a directory operation with correct parameters", function()
				local op = fsynth.op.create_directory("test_dir")
				assert.equals("CreateDirectory", op.type)
				assert.equals("test_dir", op.target)
				assert.is_function(op.validate)
				assert.is_function(op.execute)
			end)
		end)

		describe("create_file", function()
			it("should create a file operation with correct parameters", function()
				local op = fsynth.op.create_file("test.txt", "file content")
				assert.equals("CreateFile", op.type)
				assert.equals("test.txt", op.target)
				assert.is_not_nil(op.options.content)
				assert.equals("file content", op.options.content)
			end)
		end)

		describe("symlink", function()
			it("should create a symlink operation with correct parameters", function()
				local op = fsynth.op.symlink("existing.txt", "link.txt")
				assert.equals("Symlink", op.type)
				assert.equals("existing.txt", op.source)
				assert.equals("link.txt", op.target)
			end)
		end)

		describe("move_file", function()
			it("should create a move operation with correct parameters", function()
				local op = fsynth.op.move_file("source.txt", "target.txt")
				assert.equals("MoveFile", op.type)
				assert.equals("source.txt", op.source)
				assert.equals("target.txt", op.target)
			end)
		end)

		describe("delete_file", function()
			it("should create a delete file operation with correct parameters", function()
				local op = fsynth.op.delete_file("test.txt")
				assert.equals("DeleteFile", op.type)
				assert.equals("test.txt", op.target)
			end)
		end)

		describe("delete_directory", function()
			it("should create a delete directory operation with correct parameters", function()
				local op = fsynth.op.delete_directory("test_dir")
				assert.equals("DeleteDirectory", op.type)
				assert.equals("test_dir", op.target)
			end)
		end)
	end)

	describe("Processor", function()
		describe("new_processor", function()
			it("should create a new processor", function()
				local processor = fsynth.new_processor()
				assert.is_not_nil(processor)
				assert.is_function(processor.execute)
			end)
		end)

		describe("execute", function()
			local queue, processor

			before_each(function()
				queue = fsynth.new_queue()
				processor = fsynth.new_processor()
			end)

			describe("execution models", function()
				it("should pass correct options for standard model", function()
					local op1 = create_mock_operation("Op1", true, true)
					local op2 = create_mock_operation("Op2", true, true)

					queue:add(op1)
					queue:add(op2)

					local results = processor:execute(queue, {
						model = "standard",
						dry_run = false,
					})

					assert.is_true(results:is_success())
					assert.equals(2, results.executed_count)
					assert.is_true(op1.validate_called)
					assert.is_true(op1.execute_called)
					assert.is_true(op2.validate_called)
					assert.is_true(op2.execute_called)
				end)

				it("should validate all operations first with validate_first model", function()
					local op1 = create_mock_operation("Op1", true, true)
					local op2 = create_mock_operation("Op2", false, true) -- Will fail validation
					local op3 = create_mock_operation("Op3", true, true)

					queue:add(op1)
					queue:add(op2)
					queue:add(op3)

					local results = processor:execute(queue, {
						model = "validate_first",
						dry_run = false,
					})

					assert.is_false(results:is_success())
					-- All should be validated
					assert.is_true(op1.validate_called)
					assert.is_true(op2.validate_called)
					assert.is_true(op3.validate_called)
					-- None should be executed due to validation failure
					assert.is_false(op1.execute_called)
					assert.is_false(op2.execute_called)
					assert.is_false(op3.execute_called)
				end)

				it("should continue on errors with best_effort model", function()
					local op1 = create_mock_operation("Op1", true, true)
					local op2 = create_mock_operation("Op2", true, false) -- Will fail execution
					local op3 = create_mock_operation("Op3", true, true)

					queue:add(op1)
					queue:add(op2)
					queue:add(op3)

					local results = processor:execute(queue, {
						model = "best_effort",
						dry_run = false,
					})

					-- Best effort returns true even with failures
					assert.is_true(results:is_success())
					assert.equals(2, results.executed_count) -- op1 and op3
					assert.equals(1, #results:get_errors())

					assert.is_true(op1.execute_called)
					assert.is_true(op2.execute_called)
					assert.is_true(op3.execute_called)
				end)

				it("should support transactional model with rollback", function()
					local op1 = create_mock_operation("Op1", true, true)
					local op2 = create_mock_operation("Op2", true, true)
					local op3 = create_mock_operation("Op3", true, false) -- Will fail

					queue:add(op1)
					queue:add(op2)
					queue:add(op3)

					local results = processor:execute(queue, {
						model = "transactional",
						dry_run = false,
					})

					assert.is_false(results:is_success())
					assert.equals(2, results.rollback_count) -- op1 and op2 should be rolled back

					assert.is_true(op1.execute_called)
					assert.is_true(op1.undo_called) -- Should be rolled back
					assert.is_true(op2.execute_called)
					assert.is_true(op2.undo_called) -- Should be rolled back
					assert.is_true(op3.execute_called)
					assert.is_false(op3.undo_called) -- Failed, nothing to undo
				end)
			end)

			describe("dry run mode", function()
				it("should only validate operations in dry run mode", function()
					local op1 = create_mock_operation("Op1", true, true)
					local op2 = create_mock_operation("Op2", true, true)

					queue:add(op1)
					queue:add(op2)

					local results = processor:execute(queue, {
						dry_run = true,
					})

					assert.is_true(results:is_success())
					assert.equals(2, results.executed_count) -- In dry run, this counts validations

					-- Should validate but not execute
					assert.is_true(op1.validate_called)
					assert.is_false(op1.execute_called)
					assert.is_true(op2.validate_called)
					assert.is_false(op2.execute_called)
				end)

				it("should report validation errors in dry run", function()
					local op1 = create_mock_operation("Op1", true, true)
					local op2 = create_mock_operation("Op2", false, true) -- Will fail validation

					queue:add(op1)
					queue:add(op2)

					local results = processor:execute(queue, {
						dry_run = true,
					})

					assert.is_false(results:is_success())
					assert.equals(1, #results:get_errors())
					assert.equals("Mock validation error", results:get_errors()[1].message)
				end)
			end)

			describe("results object", function()
				it("should provide detailed execution logger", function()
					local op = create_mock_operation("Op1", true, true)
					queue:add(op)

					local results = processor:execute(queue, {
						dry_run = true,
					})

					local messages = results:get_messages()
					assert.is_table(messages)
					assert.is_true(#messages > 0)
					assert.matches("Starting execution", messages[1])
				end)

				it("should track execution counts correctly", function()
					queue:add(create_mock_operation("Op1", true, true))
					queue:add(create_mock_operation("Op2", true, true))

					local results = processor:execute(queue, {
						dry_run = false,
					})

					assert.equals(2, results.executed_count)
					assert.equals(0, results.skipped_count)
					assert.equals(0, results.rollback_count)
					assert.equals(0, #results:get_errors())
				end)

				it("should provide error details with operation index", function()
					queue:add(create_mock_operation("Op1", true, true))
					queue:add(create_mock_operation("Op2", true, false)) -- Will fail
					queue:add(create_mock_operation("Op3", true, true))

					local results = processor:execute(queue, {
						dry_run = false,
						model = "best_effort", -- Continue on error
					})

					local errors = results:get_errors()
					assert.equals(1, #errors)
					assert.equals(2, errors[1].operation_index) -- Second operation failed
					assert.equals("Op2", errors[1].operation_type)
					assert.equals("Mock execution error", errors[1].message)
					assert.equals("error", errors[1].severity)
				end)
			end)

			describe("logging configuration", function()
				it("should respect logger level configuration", function()
					local op = create_mock_operation("Op1", true, true)
					queue:add(op)

					local old_level = fsynth.logger.level

					local results = processor:execute(queue, {
						log_level = "debug",
						dry_run = true,
					})

					-- logger level should be restored after execution
					assert.equals(old_level, fsynth.logger.level)
				end)
			end)
		end)
	end)

	describe("API accessibility", function()
		it("should provide access to logger module", function()
			assert.is_not_nil(fsynth.logger)
			assert.is_function(fsynth.logger.debug)
			assert.is_function(fsynth.logger.info)
			assert.is_function(fsynth.logger.error)
		end)

		it("should provide access to internal components", function()
			assert.is_not_nil(fsynth._internal)
			assert.is_not_nil(fsynth._internal.checksum)
			assert.is_not_nil(fsynth._internal.processor)
			assert.is_not_nil(fsynth._internal.queue)
			assert.is_not_nil(fsynth._internal.operations)
		end)
	end)
end)
