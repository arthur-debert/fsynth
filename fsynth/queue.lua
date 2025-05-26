-- Efficient queue implementation
-- always use the log module, no prints
local log = require("fsynth.log")
local fmt = require("string.format.all")
local Queue = {}

function Queue.new()
	log.debug(fmt("Creating new queue"))
	return { front = 1, back = 0, data = {} }
end

function Queue.enqueue(queue, item)
	local back = queue.back + 1
	queue.back = back
	queue.data[back] = item
	log.trace(fmt("Enqueued item at position {}, queue size now {}", back, Queue.size(queue)))
end

function Queue.dequeue(queue)
	local front = queue.front
	if front > queue.back then
		log.trace(fmt("Attempted to dequeue from empty queue"))
		return nil
	end

	local value = queue.data[front]
	queue.data[front] = nil -- Allow garbage collection
	queue.front = front + 1

	-- Reset indices when queue is empty
	if queue.front > queue.back then
		log.trace(fmt("Queue is now empty, resetting indices"))
		queue.front = 1
		queue.back = 0
	end

	log.trace(fmt("Dequeued item from position {}, queue size now {}", front, Queue.size(queue)))
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
	log.debug(fmt("Queue cleared, removed {} items", size))
end

return Queue
