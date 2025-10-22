-- ============================================================================
-- lua/php-elements-sorter/utils/func.lua
-- Function utilities (debounce, safe_call, etc.)
-- ============================================================================

local M = {}

--- Safe pcall wrapper with error logging
---@param fn function Function to call
---@param error_msg string? Error message prefix
---@return boolean success, any result
function M.safe_call(fn, error_msg)
  local ok, result = pcall(fn)
  if not ok and error_msg then
    local log = require('php-elements-sorter.log')
    log.warn(error_msg .. ': ' .. tostring(result))
  end
  return ok, result
end

--- Create a debounced function
---@param fn function Function to debounce
---@param delay number Delay in milliseconds
---@return function debounced_fn
function M.debounce(fn, delay)
  local timer = nil
  return function(...)
    local args = { ... }
    if timer then
      timer:stop()
    end
    timer = vim.defer_fn(function()
      fn(unpack(args))
    end, delay)
  end
end

--- Create a throttled function
---@param fn function Function to throttle
---@param delay number Delay in milliseconds
---@return function throttled_fn
function M.throttle(fn, delay)
  local timer = nil
  local last_call = 0

  return function(...)
    local now = vim.loop.now()
    local args = { ... }

    if now - last_call >= delay then
      last_call = now
      fn(unpack(args))
    else
      if timer then
        timer:stop()
      end
      timer = vim.defer_fn(function()
        last_call = vim.loop.now()
        fn(unpack(args))
      end, delay - (now - last_call))
    end
  end
end

return M
