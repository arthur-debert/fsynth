-- Efficient queue implementation
-- always use the logger module, no prints
local logger = require("lual").logger()
local fmt = require("string.format.all")
local Queue = {}

function Queue.new()
	logger.debug(fmt("Creating new queue"))
	return { front = 1, back = 0, data = {} }
end

function Queue.enqueue(queue, item)
	local back = queue.back + 1
	queue.back = back
	queue.data[back] = item
	logger.trace(fmt("Enqueued item at position {}, queue size now {}", back, Queue.size(queue)))
end

function Queue.dequeue(queue)
	local front = queue.front
	if front > queue.back then
		logger.trace(fmt("Attempted to dequeue from empty queue"))
		return nil
	end

	local value = queue.data[front]
	queue.data[front] = nil -- Allow garbage collection
	queue.front = front + 1

	-- Reset indices when queue is empty
	if queue.front > queue.back then
		logger.trace(fmt("Queue is now empty, resetting indices"))
		queue.front = 1
		queue.back = 0
	end

	logger.trace(fmt("Dequeued item from position {}, queue size now {}", front, Queue.size(queue)))
	return value
end

function Queue.peek(queue)
	if queue.front > queue.back then
		return nil
	end
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
	logger.debug(fmt("Queue cleared, removed {} items", size))
end

return Queue
