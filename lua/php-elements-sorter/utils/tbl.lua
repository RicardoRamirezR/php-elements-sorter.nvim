-- ============================================================================
-- lua/php-elements-sorter/utils/tbl.lua
-- Table manipulation utilities
-- ============================================================================

local M = {}

--- Check if a value is empty
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

--- Count items in a table
---@param tbl table Table to count
---@return number count
function M.count(tbl)
  if not tbl then
    return 0
  end
  local len = #tbl
  if len > 0 then
    return len
  end
  return vim.tbl_count(tbl)
end

--- Merge tables with preference for non-nil values
---@param ... table Tables to merge
---@return table merged
function M.merge(...)
  local result = {}
  for _, tbl in ipairs({ ... }) do
    if tbl then
      result = vim.tbl_deep_extend('force', result, tbl)
    end
  end
  return result
end

--- Deep copy a table
---@param tbl table Table to copy
---@return table copy
function M.deep_copy(tbl)
  return vim.deepcopy(tbl)
end

return M
