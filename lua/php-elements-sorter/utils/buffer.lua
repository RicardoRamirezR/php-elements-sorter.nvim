-- ============================================================================
-- lua/php-elements-sorter/utils/buffer.lua
-- Buffer-related utilities
-- ============================================================================

local M = {}

--- Get current buffer info
---@return number bufnr, string filetype
function M.get_info()
  local bufnr = vim.api.nvim_get_current_buf()
  local filetype = vim.bo[bufnr].filetype
  return bufnr, filetype
end

--- Check if buffer is valid
---@param bufnr number Buffer number
---@return boolean
function M.is_valid(bufnr)
  return vim.api.nvim_buf_is_valid(bufnr)
end

--- Check if buffer is a PHP file
---@param bufnr number? Buffer number (default: current)
---@return boolean
function M.is_php(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  return vim.bo[bufnr].filetype == 'php'
end

--- Check if buffer is loaded
---@param bufnr number Buffer number
---@return boolean
function M.is_loaded(bufnr)
  return vim.api.nvim_buf_is_loaded(bufnr)
end

return M
