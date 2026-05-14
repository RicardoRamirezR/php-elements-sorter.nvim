-- ============================================================================
-- lua/php-elements-sorter/utils/string.lua
-- ============================================================================

local M = {}

--- Format string with parameters
---@param format string Format string
---@param ... any Values to insert
---@return string formatted
function M.format(format, ...)
  return string.format(format, ...)
end

--- Trim whitespace from string
---@param str string String to trim
---@return string trimmed
function M.trim(str)
  return str:match('^%s*(.-)%s*$')
end

--- Split string by delimiter
---@param str string String to split
---@param delimiter string Delimiter
---@return table parts
function M.split(str, delimiter)
  local result = {}
  local pattern = string.format('([^%s]+)', delimiter)
  for part in str:gmatch(pattern) do
    table.insert(result, part)
  end
  return result
end

--- Check if string starts with prefix
---@param str string String to check
---@param prefix string Prefix to match
---@return boolean
function M.starts_with(str, prefix)
  return str:sub(1, #prefix) == prefix
end

--- Check if string ends with suffix
---@param str string String to check
---@param suffix string Suffix to match
---@return boolean
function M.ends_with(str, suffix)
  return str:sub(-#suffix) == suffix
end

return M
