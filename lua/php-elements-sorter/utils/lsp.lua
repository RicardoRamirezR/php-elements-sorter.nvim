-- ============================================================================
-- lua/php-elements-sorter/utils/lsp.lua
-- LSP-related utilities
-- ============================================================================

local M = {}

--- Get LSP encoding for buffer
---@param bufnr number Buffer number
---@return string encoding
function M.get_encoding(bufnr)
  local clients = vim.lsp.get_clients({ bufnr = bufnr })
  local first_client = clients[1]
  return first_client and first_client.offset_encoding or 'utf-16'
end

--- Get client name from client ID
---@param client_id number LSP client ID
---@return string name
function M.get_client_name(client_id)
  local client = vim.lsp.get_client_by_id(client_id)
  return client and client.name or 'unknown'
end

--- Get LSP clients that support a specific method
---@param bufnr number Buffer number
---@param method string LSP method
---@return table clients
function M.get_clients_for_method(bufnr, method)
  return vim.lsp.get_clients({
    bufnr = bufnr,
    filter = function(client)
      return client.supports_method(method)
    end,
  })
end

--- Create a default LSP range
---@return table range
function M.default_range()
  return {
    start = { line = 0, character = 0 },
    ['end'] = { line = 0, character = 0 },
  }
end

--- Validate LSP range structure
---@param range table LSP range object
---@return boolean valid
function M.is_valid_range(range)
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

--- Build LSP range params
---@param encoding string LSP encoding
---@return table|nil params, string|nil error
function M.build_range_params(encoding)
  local ok, range_params = pcall(vim.lsp.util.make_range_params, encoding)
  if ok and range_params and range_params.range then
    return range_params, nil
  end
  return nil, 'Failed to build range params'
end

return M
