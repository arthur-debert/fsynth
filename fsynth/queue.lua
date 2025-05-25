-- Efficient queue implementation
local Queue = {}

function Queue.new()
  return { front = 1, back = 0, data = {} }
end

function Queue.enqueue(queue, item)
  local back = queue.back + 1
  queue.back = back
  queue.data[back] = item
end

function Queue.dequeue(queue)
  local front = queue.front
  if front > queue.back then return nil end
  
  local value = queue.data[front]
  queue.data[front] = nil  -- Allow garbage collection
  queue.front = front + 1
  
  -- Reset indices when queue is empty
  if queue.front > queue.back then
    queue.front = 1
    queue.back = 0
  end
  
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
  queue.data = {}
  queue.front = 1
  queue.back = 0
end

return Queue
