-- ============================================================================
-- lua/php-elements-sorter/utils/timer.lua
-- Timer manager using libuv timers (cancellable)
-- ============================================================================

local M = {}

local log = require('php-elements-sorter.utils.log')

-- Active timers registry: id -> { timer, callback, delay, created_at, key }
local active_timers = {}

local stats = {
  created = 0,
  stopped = 0,
  completed = 0,
}

local next_id = 0

local function gen_id()
  next_id = next_id + 1
  return next_id
end

--- Create a new cancellable timer
---@param delay number Delay in milliseconds
---@param callback function Function to call
---@param opts table? Options { key: string? }
---@return number|nil timer_id
function M.create(delay, callback, opts)
  opts = opts or {}

  if type(delay) ~= 'number' or delay < 0 then
    log.warn('Invalid timer delay: ' .. tostring(delay))
    return nil
  end

  if type(callback) ~= 'function' then
    log.warn('Timer callback is not a function')
    return nil
  end

  local timer_id = gen_id()
  local handle = vim.uv.new_timer()

  if not handle then
    log.error('Failed to create libuv timer')
    return nil
  end

  handle:start(delay, 0, vim.schedule_wrap(function()
    handle:stop()
    handle:close()

    active_timers[timer_id] = nil
    stats.completed = stats.completed + 1

    local ok, err = pcall(callback)
    if not ok then
      log.error('Timer callback failed: ' .. tostring(err))
    end
  end))

  active_timers[timer_id] = {
    handle = handle,
    callback = callback,
    delay = delay,
    created_at = os.time(),
    key = opts.key,
  }

  stats.created = stats.created + 1

  log.debug(string.format('Created timer %d (delay: %dms, key: %s)', timer_id, delay, opts.key or 'none'))

  return timer_id
end

--- Stop a timer by ID
---@param timer_id number
---@return boolean success
function M.stop(timer_id)
  local info = active_timers[timer_id]
  if not info then
    return false
  end

  if info.handle and not info.handle:is_closing() then
    info.handle:stop()
    info.handle:close()
  end

  active_timers[timer_id] = nil
  stats.stopped = stats.stopped + 1

  log.debug('Stopped timer ' .. timer_id)
  return true
end

--- Stop all timers with a specific key
---@param key string
---@return number count
function M.stop_by_key(key)
  local count = 0
  local ids = {}

  for id, info in pairs(active_timers) do
    if info.key == key then
      table.insert(ids, id)
    end
  end

  for _, id in ipairs(ids) do
    M.stop(id)
    count = count + 1
  end

  return count
end

--- Stop all active timers
---@return number count
function M.stop_all()
  local count = 0
  local ids = {}

  for id in pairs(active_timers) do
    table.insert(ids, id)
  end

  for _, id in ipairs(ids) do
    M.stop(id)
    count = count + 1
  end

  return count
end

--- Debounce: cancel previous timer with same key, create new one
---@param key string
---@param delay number
---@param callback function
---@return number|nil timer_id
function M.debounce(key, delay, callback)
  M.stop_by_key(key)
  return M.create(delay, callback, { key = key })
end

--- Throttle: skip if timer with same key already active
---@param key string
---@param delay number
---@param callback function
---@return number|nil timer_id
function M.throttle(key, delay, callback)
  for _, info in pairs(active_timers) do
    if info.key == key then
      return nil
    end
  end
  return M.create(delay, callback, { key = key })
end

--- Create a repeating timer
---@param delay number Delay in milliseconds
---@param callback function
---@param count number Number of repeats (-1 for infinite)
---@param key string?
---@return number|nil timer_id
function M.repeat_timer(delay, callback, count, key)
  if count == 0 then
    return nil
  end

  local timer_id = gen_id()
  local handle = vim.uv.new_timer()

  if not handle then
    log.error('Failed to create libuv repeat timer')
    return nil
  end

  local remaining = count

  handle:start(delay, delay, vim.schedule_wrap(function()
    local ok, err = pcall(callback)
    if not ok then
      log.error('Repeat timer callback failed: ' .. tostring(err))
    end

    if remaining > 0 then
      remaining = remaining - 1
    end

    if remaining == 0 then
      if handle and not handle:is_closing() then
        handle:stop()
        handle:close()
      end
      active_timers[timer_id] = nil
      stats.completed = stats.completed + 1
    end
  end))

  active_timers[timer_id] = {
    handle = handle,
    callback = callback,
    delay = delay,
    created_at = os.time(),
    key = key,
  }

  stats.created = stats.created + 1
  return timer_id
end

--- Get statistics
---@return table stats
function M.get_stats()
  local active_count = 0
  local by_key = {}

  for _, info in pairs(active_timers) do
    active_count = active_count + 1
    local k = info.key or 'none'
    by_key[k] = (by_key[k] or 0) + 1
  end

  return {
    active = active_count,
    created = stats.created,
    stopped = stats.stopped,
    completed = stats.completed,
    by_key = by_key,
  }
end

--- Cleanup old timers (potential leaks)
---@param max_age_seconds number
---@return number count
function M.cleanup_old_timers(max_age_seconds)
  max_age_seconds = max_age_seconds or 300
  local now = os.time()
  local ids = {}

  for id, info in pairs(active_timers) do
    if (now - info.created_at) > max_age_seconds then
      table.insert(ids, id)
    end
  end

  for _, id in ipairs(ids) do
    log.warn(string.format('Cleaning up old timer %d', id))
    M.stop(id)
  end

  return #ids
end

--- Reset statistics
function M.reset_stats()
  stats = { created = 0, stopped = 0, completed = 0 }
end

--- Pretty print timer statistics
function M.print_stats()
  local s = M.get_stats()
  print('Timer Statistics:')
  print(string.format('  Active:    %d', s.active))
  print(string.format('  Created:   %d', s.created))
  print(string.format('  Stopped:   %d', s.stopped))
  print(string.format('  Completed: %d', s.completed))

  if vim.tbl_count(s.by_key) > 0 then
    print('  By Key:')
    for k, c in pairs(s.by_key) do
      print(string.format('    %s: %d', k, c))
    end
  end
end

return M
