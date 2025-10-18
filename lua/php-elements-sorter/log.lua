-- lua/php-elements-sorter/log.lua
-- Logging utilities for the plugin

local M = {}

-- Internal reference to config (set during plugin setup)
local config = nil

--- Initialize logger with plugin config
---@param plugin_config table Plugin configuration
function M.init(plugin_config)
  config = plugin_config
end

--- Debug logging helper
---@param msg string Message to log
---@param level number? Log level (default: vim.log.levels.DEBUG)
function M.debug(msg, level)
  if config and config.debug then
    level = level or vim.log.levels.DEBUG
    vim.notify('[php-elements-sorter] ' .. msg, level)
  end
end

--- Info logging
---@param msg string Message to log
function M.info(msg)
  M.debug(msg, vim.log.levels.INFO)
end

--- Warning logging
---@param msg string Message to log
function M.warn(msg)
  M.debug(msg, vim.log.levels.WARN)
end

--- Error logging
---@param msg string Message to log
function M.error(msg)
  M.debug(msg, vim.log.levels.ERROR)
end

--- Log with formatted string (sprintf-like)
---@param format string Format string
---@param ... any Arguments
function M.debugf(format, ...)
  if config and config.debug then
    M.debug(string.format(format, ...))
  end
end

--- Log table contents (for debugging)
---@param tbl table Table to inspect
---@param label string? Optional label
function M.dump(tbl, label)
  if config and config.debug then
    local msg = label and (label .. ': ') or ''
    msg = msg .. vim.inspect(tbl)
    M.debug(msg)
  end
end

--- Check if debug mode is enabled
---@return boolean
function M.is_debug()
  return config and config.debug or false
end

--- Check if a value is empty (nil, empty string, empty table)
---@param value any Value to check
---@return boolean
function M.is_empty(value)
  if value == nil then
    return true
  end
  if type(value) == 'string' and value == '' then
    return true
  end
  if type(value) == 'table' and vim.tbl_isempty(value) then
    return true
  end
  return false
end

--- Safe table deep copy
---@param tbl table Table to copy
---@return table
function M.deep_copy(tbl)
  return vim.deepcopy(tbl)
end

--- Get current buffer info
---@return number bufnr, string filetype
function M.get_buffer_info()
  local bufnr = vim.api.nvim_get_current_buf()
  local filetype = vim.bo[bufnr].filetype
  return bufnr, filetype
end

--- Check if buffer is a PHP file
---@param bufnr number? Buffer number (default: current buffer)
---@return boolean
function M.is_php_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  return vim.bo[bufnr].filetype == 'php'
end

--- Get LSP encoding for buffer
---@param bufnr number Buffer number
---@return string encoding (e.g., 'utf-16', 'utf-8')
function M.get_lsp_encoding(bufnr)
  local clients = vim.lsp.get_clients({ bufnr = bufnr })
  local first_client = clients[1]
  return first_client and first_client.offset_encoding or 'utf-16'
end

--- Create a default LSP range (0,0 to 0,0)
---@return table range
function M.default_lsp_range()
  return {
    start = { line = 0, character = 0 },
    ['end'] = { line = 0, character = 0 },
  }
end

--- Build LSP range params with error handling
---@param encoding string LSP encoding
---@return table|nil range_params, string|nil error
function M.build_range_params(encoding)
  local ok, range_params = pcall(vim.lsp.util.make_range_params, encoding)
  if ok and range_params and range_params.range then
    return range_params, nil
  end
  return nil, 'Failed to build range params'
end

--- Get LSP clients that support a specific method
---@param bufnr number Buffer number
---@param method string LSP method (e.g., 'textDocument/codeAction')
---@return table clients
function M.get_lsp_clients_for_method(bufnr, method)
  return vim.lsp.get_clients({
    bufnr = bufnr,
    filter = function(client)
      return client.supports_method(method)
    end,
  })
end

--- Get client name from client ID
---@param client_id number LSP client ID
---@return string name
function M.get_client_name(client_id)
  local client = vim.lsp.get_client_by_id(client_id)
  return client and client.name or 'unknown'
end

--- Safe pcall wrapper with logging
---@param state table Plugin state for logging
---@param fn function Function to call
---@param error_msg string Error message prefix
---@return boolean success, any result
function M.safe_call(state, fn, error_msg)
  local ok, result = pcall(fn)
  if not ok then
    M.debug(state, error_msg .. ': ' .. tostring(result), vim.log.levels.WARN)
  end
  return ok, result
end

--- Validate LSP range structure
---@param range table LSP range object
---@return boolean valid
function M.is_valid_lsp_range(range)
  if not range or type(range) ~= 'table' then
    return false
  end

  local start = range.start
  local end_pos = range['end']

  if not start or not end_pos then
    return false
  end

  return start.line ~= nil
    and start.character ~= nil
    and end_pos.line ~= nil
    and end_pos.character ~= nil
end

--- Count items in a table (works with both arrays and dictionaries)
---@param tbl table Table to count
---@return number count
function M.count(tbl)
  if not tbl then
    return 0
  end
  -- Try array length first
  local len = #tbl
  if len > 0 then
    return len
  end
  -- Fall back to vim.tbl_count for dictionaries
  return vim.tbl_count(tbl)
end

--- Merge tables with preference for non-nil values
---@param ... table Tables to merge
---@return table merged
function M.merge_tables(...)
  local result = {}
  for _, tbl in ipairs({ ... }) do
    if tbl then
      result = vim.tbl_deep_extend('force', result, tbl)
    end
  end
  return result
end

--- Format string with parameters (simple sprintf-like)
---@param format string Format string with %s placeholders
---@param ... any Values to insert
---@return string formatted
function M.format(format, ...)
  return string.format(format, ...)
end

--- Notify user with plugin prefix
---@param msg string Message to show
---@param level number? Log level (default: INFO)
function M.notify(msg, level)
  level = level or vim.log.levels.INFO
  vim.notify('[php-elements-sorter] ' .. msg, level)
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

return M
