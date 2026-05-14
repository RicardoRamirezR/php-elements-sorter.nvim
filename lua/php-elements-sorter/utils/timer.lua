-- ============================================================================
-- lua/php-elements-sorter/utils/timer.lua
-- ============================================================================

local M = {}

local log = require('php-elements-sorter.utils.log')

-- Active timers registry
local active_timers = {}

-- Timer statistics
local stats = {
  created = 0,
  stopped = 0,
  completed = 0,
  leaked = 0,
}

--- Create a new timer with automatic tracking
---@param delay number Delay in milliseconds
---@param callback function Function to call
---@param opts table? Options (repeat_count, key)
---@return number|nil timer_id Timer ID or nil on error
function M.create(delay, callback, opts)
  opts = opts or {}

  -- Validate inputs
  if type(delay) ~= 'number' or delay < 0 then
    log.warn('Invalid timer delay: ' .. tostring(delay))
    return nil
  end

  if type(callback) ~= 'function' then
    log.warn('Timer callback is not a function')
    return nil
  end

  -- Create timer using vim.defer_fn (works in all Neovim versions)
  local timer_obj = vim.defer_fn(function()
    local ok, err = pcall(callback)

    if not ok then
      log.error('Timer callback failed: ' .. tostring(err))
    end

    -- Mark as completed
    stats.completed = stats.completed + 1

    -- Remove from active timers if not repeating
    local repeat_count = opts.repeat_count or 0
    if not repeat_count or repeat_count <= 0 then
      for id, timer_info in pairs(active_timers) do
        if timer_info.callback == callback then
          active_timers[id] = nil
          break
        end
      end
    end
  end, delay)

  -- Track timer
  local timer_id = vim.loop.hrtime() -- Use high-res time as unique ID
  active_timers[timer_id] = {
    timer = timer_obj,
    callback = callback,
    delay = delay,
    created_at = os.time(),
    key = opts.key,
    repeat_count = opts.repeat_count or 0,
  }

  stats.created = stats.created + 1

  log.debug(
    string.format('Created timer %s (delay: %dms, key: %s)', timer_id, delay, opts.key or 'none')
  )

  return timer_id
end

--- Stop a timer by ID
---@param timer_id number Timer ID
---@return boolean success
function M.stop(timer_id)
  local timer_info = active_timers[timer_id]

  if not timer_info then
    log.debug('Timer ' .. tostring(timer_id) .. ' not found or already stopped')
    return false
  end

  -- Stop the timer
  if timer_info.timer and timer_info.timer.stop then
    pcall(timer_info.timer.stop, timer_info.timer)
  end

  -- Remove from registry
  active_timers[timer_id] = nil
  stats.stopped = stats.stopped + 1

  log.debug('Stopped timer ' .. timer_id)

  return true
end

--- Stop all timers with a specific key
---@param key string Timer key
---@return number count Number of timers stopped
function M.stop_by_key(key)
  local count = 0

  for timer_id, timer_info in pairs(active_timers) do
    if timer_info.key == key then
      M.stop(timer_id)
      count = count + 1
    end
  end

  if count > 0 then
    log.debug(string.format('Stopped %d timers with key: %s', count, key))
  end

  return count
end

--- Stop all active timers
---@return number count Number of timers stopped
function M.stop_all()
  local count = 0

  for timer_id, _ in pairs(active_timers) do
    M.stop(timer_id)
    count = count + 1
  end

  if count > 0 then
    log.debug(string.format('Stopped all %d active timers', count))
  end

  return count
end

--- Create a debounced timer (cancels previous with same key)
---@param key string Unique key for this debounced operation
---@param delay number Delay in milliseconds
---@param callback function Function to call
---@return number|nil timer_id Timer ID or nil on error
function M.debounce(key, delay, callback)
  -- Stop any existing timer with this key
  M.stop_by_key(key)

  -- Create new timer with the key
  return M.create(delay, callback, { key = key })
end

--- Create a throttled timer
---@param key string Unique key for this throttled operation
---@param delay number Minimum delay between calls
---@param callback function Function to call
---@return number|nil timer_id Timer ID or nil on error
function M.throttle(key, delay, callback)
  -- Check if a timer with this key is already active
  for _, timer_info in pairs(active_timers) do
    if timer_info.key == key then
      -- Timer already running, skip this call
      log.debug('Throttled call skipped for key: ' .. key)
      return nil
    end
  end

  -- No active timer, create one
  return M.create(delay, callback, { key = key })
end

--- Create a repeating timer
---@param delay number Delay in milliseconds
---@param callback function Function to call
---@param count number Number of times to repeat (-1 for infinite)
---@param key string? Optional key for tracking
---@return number|nil timer_id Timer ID or nil on error
function M.repeat_timer(delay, callback, count, key)
  if count == 0 then
    return nil
  end

  local remaining = count

  local function wrapped_callback()
    callback()

    if remaining > 0 then
      remaining = remaining - 1
    end

    if remaining ~= 0 then
      -- Schedule next iteration
      M.create(delay, wrapped_callback, { key = key, repeat_count = remaining })
    end
  end

  return M.create(delay, wrapped_callback, { key = key, repeat_count = remaining })
end

--- Get statistics about timers
---@return table stats Timer statistics
function M.get_stats()
  local active_count = 0
  local by_key = {}

  for _, timer_info in pairs(active_timers) do
    active_count = active_count + 1

    local key = timer_info.key or 'none'
    by_key[key] = (by_key[key] or 0) + 1
  end

  return {
    active = active_count,
    created = stats.created,
    stopped = stats.stopped,
    completed = stats.completed,
    leaked = stats.leaked,
    by_key = by_key,
  }
end

--- Get list of active timers
---@return table timers List of active timer info
function M.get_active_timers()
  local timers = {}

  for timer_id, timer_info in pairs(active_timers) do
    table.insert(timers, {
      id = timer_id,
      key = timer_info.key,
      delay = timer_info.delay,
      age_seconds = os.time() - timer_info.created_at,
    })
  end

  -- Sort by age (oldest first)
  table.sort(timers, function(a, b)
    return a.age_seconds > b.age_seconds
  end)

  return timers
end

--- Cleanup old timers (potential leaks)
---@param max_age_seconds number Maximum age in seconds
---@return number count Number of timers cleaned up
function M.cleanup_old_timers(max_age_seconds)
  max_age_seconds = max_age_seconds or 300 -- Default 5 minutes

  local current_time = os.time()
  local cleaned = 0

  for timer_id, timer_info in pairs(active_timers) do
    local age = current_time - timer_info.created_at

    if age > max_age_seconds then
      log.warn(
        string.format(
          'Cleaning up old timer %s (age: %ds, key: %s)',
          timer_id,
          age,
          timer_info.key or 'none'
        )
      )

      M.stop(timer_id)
      stats.leaked = stats.leaked + 1
      cleaned = cleaned + 1
    end
  end

  if cleaned > 0 then
    log.warn(string.format('Cleaned up %d potentially leaked timers', cleaned))
  end

  return cleaned
end

--- Reset statistics (useful for testing)
function M.reset_stats()
  stats = {
    created = 0,
    stopped = 0,
    completed = 0,
    leaked = 0,
  }
  log.debug('Timer statistics reset')
end

--- Check for potential timer leaks
---@return table report Leak report
function M.check_leaks()
  local current_time = os.time()
  local potential_leaks = {}

  for timer_id, timer_info in pairs(active_timers) do
    local age = current_time - timer_info.created_at

    -- Timers older than 1 minute are suspicious
    if age > 60 then
      table.insert(potential_leaks, {
        id = timer_id,
        key = timer_info.key or 'none',
        age_seconds = age,
        delay = timer_info.delay,
      })
    end
  end

  return {
    has_leaks = #potential_leaks > 0,
    count = #potential_leaks,
    leaks = potential_leaks,
    total_active = vim.tbl_count(active_timers),
  }
end

--- Pretty print timer statistics
function M.print_stats()
  local s = M.get_stats()

  print('Timer Statistics:')
  print(string.format('  Active:    %d', s.active))
  print(string.format('  Created:   %d', s.created))
  print(string.format('  Stopped:   %d', s.stopped))
  print(string.format('  Completed: %d', s.completed))
  print(string.format('  Leaked:    %d', s.leaked))

  if vim.tbl_count(s.by_key) > 0 then
    print('  By Key:')
    for key, count in pairs(s.by_key) do
      print(string.format('    %s: %d', key, count))
    end
  end

  -- Check for leaks
  local leak_report = M.check_leaks()
  if leak_report.has_leaks then
    print(string.format('\n  ⚠️  Warning: %d potential leaks detected!', leak_report.count))
  end
end

return M
