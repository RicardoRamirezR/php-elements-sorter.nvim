-- ============================================================================
-- lua/php-elements-sorter/utils/log.lua
-- Pure logging functionality
-- ============================================================================

local M = {}

local config = nil

--- Initialize logger with plugin config
---@param plugin_config table Plugin configuration
function M.init(plugin_config)
  config = plugin_config
end

--- Check if debug mode is enabled
---@return boolean
function M.is_debug()
  return config and config.debug or false
end

--- Debug logging helper
---@param msg string Message to log
---@param level number? Log level (default: vim.log.levels.DEBUG)
function M.debug(msg, level)
  if M.is_debug() then
    level = level or vim.log.levels.DEBUG
    vim.notify('[php-elements-sorter] ' .. msg, level)
  end
end

--- Info logging
---@param msg string Message to log
function M.info(msg)
  vim.notify('[php-elements-sorter] ' .. msg, vim.log.levels.INFO)
end

--- Warning logging
---@param msg string Message to log
function M.warn(msg)
  vim.notify('[php-elements-sorter] ' .. msg, vim.log.levels.WARN)
end

--- Error logging
---@param msg string Message to log
function M.error(msg)
  vim.notify('[php-elements-sorter] ' .. msg, vim.log.levels.ERROR)
end

--- Log with formatted string
---@param format string Format string
---@param ... any Arguments
function M.debugf(format, ...)
  if M.is_debug() then
    M.debug(string.format(format, ...))
  end
end

--- Log table contents
---@param tbl table Table to inspect
---@param label string? Optional label
function M.dump(tbl, label)
  if M.is_debug() then
    local msg = label and (label .. ': ') or ''
    msg = msg .. vim.inspect(tbl)
    M.debug(msg)
  end
end

--- Notify user with plugin prefix
---@param msg string Message to show
---@param level number? Log level (default: INFO)
function M.notify(msg, level)
  level = level or vim.log.levels.INFO
  vim.notify('[php-elements-sorter] ' .. msg, level)
end

return M
