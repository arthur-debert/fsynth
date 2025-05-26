-- Operation Queue Processor
-- Responsible for executing operations in a queue with various execution strategies
local Queue = require("fsynth.queue")
local log = require("fsynth.log")
local fmt = require("string.format.all")

local Processor = {}
Processor.__index = Processor

-- Create a new processor with the specified options
-- Options include:
--   validate_first: Validate all operations before executing any
--   verify_checksums: Verify checksums before execution
--   best_effort: Continue executing operations even if some fail
--   transactional: Attempt to rollback completed operations on failure
--   force: Execute even if validation fails (when used with validate_first)
function Processor.new(options)
  log.debug(fmt("Creating new processor with options: {}", options and "some options" or "nil"))
  local self = setmetatable({
    options = options or {},
    executed = {},  -- For rollback tracking
    errors = {}
  }, Processor)
  log.debug(fmt("Processor created, type: {}, metatable: {}", type(self), getmetatable(self) == Processor))
  return self
end

-- Process a queue of operations according to the configured strategy
-- Returns:
--   success: true if all operations succeeded, false otherwise
--   errors: table of errors encountered during processing
function Processor:process(queue)
  log.debug(fmt("Processor:process called, self type: {}", type(self)))
  self.executed = {}
  self.errors = {}
  -- Optionally validate all operations first
  if self.options.validate_first then
    local validation_queue = Queue.new()
    local validation_failed = false
    -- Copy all operations to validation queue
    while not Queue.is_empty(queue) do
      local op = Queue.dequeue(queue)
      Queue.enqueue(validation_queue, op)
      local valid, err = op:validate()
      if not valid then
        table.insert(self.errors, {
          operation = op,
          phase = "validation",
          error = err
        })
        validation_failed = true
      end
    end
    -- If validation failed, don't proceed with execution
    if validation_failed and not self.options.force then
      -- Move operations back to original queue
      while not Queue.is_empty(validation_queue) do
        Queue.enqueue(queue, Queue.dequeue(validation_queue))
      end
      return false, self.errors
    end
    -- Move operations back to original queue
    while not Queue.is_empty(validation_queue) do
      Queue.enqueue(queue, Queue.dequeue(validation_queue))
    end
  end
  -- Process all operations
  while not Queue.is_empty(queue) do
    local op = Queue.dequeue(queue)
    -- Validate if not done already
    if not self.options.validate_first then
      local valid, err = op:validate()
      if not valid then
        table.insert(self.errors, {
          operation = op,
          phase = "validation",
          error = err
        })
        if not self.options.best_effort then
          -- Roll back if needed
          if self.options.transactional then
            self:rollback()
          end
          return false, self.errors
        end
        -- Skip execution and continue with next operation
        goto continue
      end
    end
    -- Check checksums if enabled
    if self.options.verify_checksums then
      local checksum_ok, err = op:checksum()
      if not checksum_ok then
        table.insert(self.errors, {
          operation = op,
          phase = "checksum",
          error = err
        })
        if not self.options.best_effort then
          -- Roll back if needed
          if self.options.transactional then
            self:rollback()
          end
          return false, self.errors
        end
        -- Skip execution and continue with next operation
        goto continue
      end
    end
    -- Execute operation
    local success, err = op:execute()
    if success then
      table.insert(self.executed, op)
    else
      table.insert(self.errors, {
        operation = op,
        phase = "execution",
        error = err
      })
      if not self.options.best_effort then
        -- Roll back if needed
        if self.options.transactional then
          self:rollback()
        end
        return false, self.errors
      end
    end
    ::continue::
  end
  -- Return success if no errors or best_effort mode
  if #self.errors == 0 then
    return true, nil
  else
    return self.options.best_effort, self.errors
  end
end

-- Attempt to roll back all executed operations in reverse order
-- Updates self.errors with any rollback errors
function Processor:rollback()
  local rollback_errors = {}
  -- Rollback in reverse order
  for i = #self.executed, 1, -1 do
    local op = self.executed[i]
    local success, err = op:undo()
    if not success then
      table.insert(rollback_errors, {
        operation = op,
        phase = "rollback",
        error = err
      })
    end
  end
  if #rollback_errors > 0 then
    -- Add rollback errors to existing errors
    for _, err in ipairs(rollback_errors) do
      table.insert(self.errors, err)
    end
  end
end

-- Format errors for display or logging
function Processor:format_errors()
  log.debug(fmt("format_errors called, self type: {}, errors count: {}", type(self), #self.errors))
  local result = {}
  for i, err in ipairs(self.errors) do
    local op_type = err.operation and type(err.operation) or "unknown"
    local source = err.operation and err.operation.source or "n/a"
    local target = err.operation and err.operation.target or "n/a"
    table.insert(result, fmt(
      "Error {} [{} phase]: {} (operation: {}, source: {}, target: {})",
      i,
      err.phase or "unknown",
      err.error or "unknown error",
      op_type,
      source,
      target
    ))
  end
  return table.concat(result, "\n")
end

return Processor