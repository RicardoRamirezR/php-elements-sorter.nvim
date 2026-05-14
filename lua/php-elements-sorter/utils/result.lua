-- ============================================================================
-- lua/php-elements-sorter/utils/result.lua
-- ============================================================================

local M = {}

local log = require('php-elements-sorter.utils.log')

-- Result metatable for method chaining
local Result_mt = {}
Result_mt.__index = Result_mt

--- Create a successful result
---@param value any The success value
---@return table result Result object with success = true
function M.ok(value)
  local result = {
    success = true,
    value = value,
    error = nil,
  }
  return setmetatable(result, Result_mt)
end

--- Create an error result
---@param error string|table The error message or object
---@param context string? Optional context for better debugging
---@return table result Result object with success = false
function M.err(error, context)
  local error_msg = type(error) == 'string' and error or vim.inspect(error)

  if context then
    error_msg = string.format('[%s] %s', context, error_msg)
  end

  local result = {
    success = false,
    value = nil,
    error = error_msg,
  }
  return setmetatable(result, Result_mt)
end

--- Check if result is successful
---@param result table Result object
---@return boolean
function M.is_ok(result)
  return result and result.success == true
end

--- Check if result is an error
---@param result table Result object
---@return boolean
function M.is_err(result)
  return result and result.success == false
end

--- Map over result value if successful (method)
---@param fn function Function to transform value
---@return table result New result
function Result_mt:map(fn)
  if self.success then
    local ok, mapped_value = pcall(fn, self.value)
    if ok then
      return M.ok(mapped_value)
    else
      return M.err(mapped_value, 'map')
    end
  end
  return self
end

--- Map over error if result is error (method)
---@param fn function Function to transform error
---@return table result New result
function Result_mt:map_err(fn)
  if not self.success then
    local ok, mapped_error = pcall(fn, self.error)
    if ok then
      return M.err(mapped_error)
    else
      return M.err(mapped_error, 'map_err')
    end
  end
  return self
end

--- Chain result with another operation (method)
---@param fn function Function that returns a Result
---@return table result New result
function Result_mt:and_then(fn)
  if self.success then
    local ok, new_result = pcall(fn, self.value)
    if ok then
      return new_result
    else
      return M.err(new_result, 'and_then')
    end
  end
  return self
end

--- Unwrap result value or return default (method)
---@param default any Default value if result is error
---@return any value
function Result_mt:unwrap_or(default)
  if self.success then
    return self.value
  end
  return default
end

--- Unwrap result value or call function to get default (method)
---@param fn function Function to call if result is error
---@return any value
function Result_mt:unwrap_or_else(fn)
  if self.success then
    return self.value
  end
  return fn(self.error)
end

--- Map over result value if successful (functional style)
---@param result table Result object
---@param fn function Function to transform value
---@return table result New result
function M.map(result, fn)
  return result:map(fn)
end

--- Map over error if result is error (functional style)
---@param result table Result object
---@param fn function Function to transform error
---@return table result New result
function M.map_err(result, fn)
  return result:map_err(fn)
end

--- Chain result with another operation (functional style)
---@param result table Result object
---@param fn function Function that returns a Result
---@return table result New result
function M.and_then(result, fn)
  return result:and_then(fn)
end

--- Unwrap result value or return default (functional style)
---@param result table Result object
---@param default any Default value if result is error
---@return any value
function M.unwrap_or(result, default)
  return result:unwrap_or(default)
end

--- Unwrap result value or call function to get default (functional style)
---@param result table Result object
---@param fn function Function to call if result is error
---@return any value
function M.unwrap_or_else(result, fn)
  return result:unwrap_or_else(fn)
end

--- Execute function and wrap result
---@param fn function Function to execute
---@param context string? Optional context
---@return table result
function M.try(fn, context)
  local ok, result = pcall(fn)

  if ok then
    return M.ok(result)
  else
    log.warn(string.format('Operation failed: %s', tostring(result)))
    return M.err(result, context)
  end
end

--- Execute function with arguments and wrap result
---@param fn function Function to execute
---@param context string? Optional context
---@param ... any Arguments to pass to function
---@return table result
function M.try_with(fn, context, ...)
  local args = { ... }
  local ok, result = pcall(function()
    return fn(unpack(args))
  end)

  if ok then
    return M.ok(result)
  else
    log.warn(string.format('Operation failed: %s', tostring(result)))
    return M.err(result, context)
  end
end

--- Collect multiple results, return error if any fails
---@param results table List of results
---@return table result Combined result with list of values or first error
function M.collect(results)
  local values = {}

  for i, result in ipairs(results) do
    if M.is_err(result) then
      return M.err(result.error, string.format('collect[%d]', i))
    end
    table.insert(values, result.value)
  end

  return M.ok(values)
end

--- Execute function and log error if it fails
---@param fn function Function to execute
---@param error_msg string Error message to log
---@return table result
function M.try_or_log(fn, error_msg)
  local result = M.try(fn, error_msg)

  if M.is_err(result) then
    log.error(error_msg .. ': ' .. result.error)
  end

  return result
end

--- Match on result (like Rust's match)
---@param result table Result object
---@param handlers table Table with 'ok' and 'err' handler functions
---@return any
function M.match(result, handlers)
  if M.is_ok(result) then
    if handlers.ok then
      return handlers.ok(result.value)
    end
  else
    if handlers.err then
      return handlers.err(result.error)
    end
  end
end

--- Convert vim api call to Result
---@param api_fn function Vim API function
---@param ... any Arguments
---@return table result
function M.from_vim_api(api_fn, ...)
  local args = { ... }
  local ok, result = pcall(function()
    return api_fn(unpack(args))
  end)

  if ok then
    return M.ok(result)
  else
    return M.err(result, 'vim_api')
  end
end

--- Unwrap result or panic with error
---@param result table Result object
---@param msg string? Optional panic message
---@return any value
function M.expect(result, msg)
  if M.is_ok(result) then
    return result.value
  end

  local error_msg = msg or 'Called expect() on an error result'
  error(string.format('%s: %s', error_msg, result.error))
end

--- Create result from nullable value
---@param value any Value that might be nil
---@param error_msg string Error message if value is nil
---@return table result
function M.from_nullable(value, error_msg)
  if value ~= nil then
    return M.ok(value)
  else
    return M.err(error_msg or 'Value was nil')
  end
end

--- Create result from boolean check
---@param condition boolean Condition to check
---@param value any Value to return if true
---@param error_msg string Error message if false
---@return table result
function M.from_bool(condition, value, error_msg)
  if condition then
    return M.ok(value)
  else
    return M.err(error_msg or 'Condition was false')
  end
end

return M
