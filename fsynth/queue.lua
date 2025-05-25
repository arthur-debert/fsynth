-- Efficient queue implementation
-- always use the log module, no prints
local log = require("fsynth.log")
local Queue = {}

function Queue.new()
  log.debug("Creating new queue")
  return { front = 1, back = 0, data = {} }
end

function Queue.enqueue(queue, item)
  local back = queue.back + 1
  queue.back = back
  queue.data[back] = item
  log.trace("Enqueued item at position %d, queue size now %d", back, Queue.size(queue))
end

function Queue.dequeue(queue)
  local front = queue.front
  if front > queue.back then
    log.trace("Attempted to dequeue from empty queue")
    return nil
  end
  
  local value = queue.data[front]
  queue.data[front] = nil  -- Allow garbage collection
  queue.front = front + 1
  
  -- Reset indices when queue is empty
  if queue.front > queue.back then
    log.trace("Queue is now empty, resetting indices")
    queue.front = 1
    queue.back = 0
  end
  
  log.trace("Dequeued item from position %d, queue size now %d", front, Queue.size(queue))
  return value
end

function Queue.peek(queue)
  if queue.front > queue.back then return nil end
  return queue.data[queue.front]
end

function Queue.is_empty(queue)
  return queue.front > queue.back
end

function Queue.size(queue)
  return queue.back - queue.front + 1
end

function Queue.clear(queue)
  local size = Queue.size(queue)
  queue.data = {}
  queue.front = 1
  queue.back = 0
  log.debug("Queue cleared, removed %d items", size)
end

return Queue
