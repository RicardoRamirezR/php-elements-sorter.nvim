-- ============================================================================
-- lua/php-elements-sorter/utils/lsp.lua
-- LSP-related utilities
-- ============================================================================

local M = {}

local Result = require('php-elements-sorter.utils.result')
local log = require('php-elements-sorter.utils.log')

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

--- Validate LSP position structure
---@param position table LSP position object
---@return table result Result with validated position or error
function M.validate_position(position)
  if not position or type(position) ~= 'table' then
    return Result.err('Position is not a table')
  end

  if position.line == nil then
    return Result.err('Position missing line')
  end

  if position.character == nil then
    return Result.err('Position missing character')
  end

  if type(position.line) ~= 'number' then
    return Result.err('Position line is not a number')
  end

  if type(position.character) ~= 'number' then
    return Result.err('Position character is not a number')
  end

  if position.line < 0 then
    return Result.err('Position line cannot be negative')
  end

  if position.character < 0 then
    return Result.err('Position character cannot be negative')
  end

  return Result.ok(position)
end

--- Validate LSP range structure
---@param range table LSP range object
---@return table result Result with validated range or error
function M.validate_range(range)
  if not range or type(range) ~= 'table' then
    return Result.err('Range is not a table')
  end

  if not range.start then
    return Result.err('Range missing start position')
  end

  if not range['end'] then
    return Result.err('Range missing end position')
  end

  -- Validate start position
  local start_result = M.validate_position(range.start)
  if Result.is_err(start_result) then
    return Result.err('Invalid start position: ' .. start_result.error)
  end

  -- Validate end position
  local end_result = M.validate_position(range['end'])
  if Result.is_err(end_result) then
    return Result.err('Invalid end position: ' .. end_result.error)
  end

  -- Validate that end is after or equal to start
  if range['end'].line < range.start.line then
    return Result.err('End line is before start line')
  end

  if range['end'].line == range.start.line and range['end'].character < range.start.character then
    return Result.err('End character is before start character on same line')
  end

  return Result.ok(range)
end

--- Validate LSP range structure (legacy boolean version for compatibility)
---@param range table LSP range object
---@return boolean valid
function M.is_valid_range(range)
  local result = M.validate_range(range)
  return Result.is_ok(result)
end

--- Validate and normalize LSP range
---@param range table LSP range object
---@return table result Result with normalized range or error
function M.normalize_range(range)
  -- First check basic structure
  if not range or type(range) ~= 'table' then
    return Result.err('Range is not a table')
  end

  if not range.start or type(range.start) ~= 'table' then
    return Result.err('Range missing start position')
  end

  if not range['end'] or type(range['end']) ~= 'table' then
    return Result.err('Range missing end position')
  end

  -- Check that positions have required fields
  if range.start.line == nil or range.start.character == nil then
    return Result.err('Start position missing line or character')
  end

  if range['end'].line == nil or range['end'].character == nil then
    return Result.err('End position missing line or character')
  end

  -- Check types
  if type(range.start.line) ~= 'number' or type(range.start.character) ~= 'number' then
    return Result.err('Start position fields are not numbers')
  end

  if type(range['end'].line) ~= 'number' or type(range['end'].character) ~= 'number' then
    return Result.err('End position fields are not numbers')
  end

  -- Normalize to non-negative values
  local normalized = {
    start = {
      line = math.max(0, range.start.line),
      character = math.max(0, range.start.character),
    },
    ['end'] = {
      line = math.max(0, range['end'].line),
      character = math.max(0, range['end'].character),
    },
  }

  -- After normalization, validate that end >= start
  if normalized['end'].line < normalized.start.line then
    return Result.err('End line is before start line (after normalization)')
  end

  if
    normalized['end'].line == normalized.start.line
    and normalized['end'].character < normalized.start.character
  then
    return Result.err('End character is before start character on same line (after normalization)')
  end

  return Result.ok(normalized)
end

--- Build LSP range params
---@param encoding string LSP encoding
---@return table result Result with params or error
function M.build_range_params(encoding)
  return Result.try(function()
    local current_win = vim.api.nvim_get_current_win()
    local params = vim.lsp.util.make_range_params(current_win, encoding)

    if type(params) ~= 'table' then
      error('Range params is not a table')
    end

    if not params.range then
      error('Range params missing range')
    end

    return params
  end, 'build_range_params'):and_then(function(params)
    return M.validate_range(params.range):map(function()
      return params
    end)
  end)
end

--- Validate LSP diagnostic structure
---@param diagnostic table LSP diagnostic
---@return table result Result with validated diagnostic or error
function M.validate_diagnostic(diagnostic)
  if not diagnostic or type(diagnostic) ~= 'table' then
    return Result.err('Diagnostic is not a table')
  end

  if not diagnostic.range then
    return Result.err('Diagnostic missing range')
  end

  return M.validate_range(diagnostic.range):map(function()
    return {
      range = diagnostic.range,
      message = diagnostic.message or '',
      severity = diagnostic.severity,
      code = diagnostic.code,
      source = diagnostic.source,
    }
  end)
end

--- Extract safe diagnostic from Neovim diagnostic
---@param nvim_diag table Neovim diagnostic
---@return table result Result with safe diagnostic or error
function M.extract_safe_diagnostic(nvim_diag)
  -- Check for LSP data
  if not nvim_diag.user_data or not nvim_diag.user_data.lsp then
    return Result.err('Diagnostic missing LSP data')
  end

  local lsp_data = nvim_diag.user_data.lsp

  if not lsp_data.range then
    return Result.err('LSP data missing range')
  end

  -- Validate and extract
  return M.validate_range(lsp_data.range):map(function(range)
    return {
      range = {
        start = {
          line = range.start.line,
          character = range.start.character,
        },
        ['end'] = {
          line = range['end'].line,
          character = range['end'].character,
        },
      },
      message = lsp_data.message or nvim_diag.message or '',
      severity = lsp_data.severity or nvim_diag.severity,
      code = lsp_data.code or nvim_diag.code,
      source = lsp_data.source or nvim_diag.source,
    }
  end)
end

--- Build safe diagnostics list from Neovim diagnostics
---@param diagnostics table List of Neovim diagnostics
---@return table safe_diagnostics List of validated diagnostics
function M.build_safe_diagnostics(diagnostics)
  local safe = {}
  local skipped = 0

  for _, nvim_diag in ipairs(diagnostics) do
    local result = M.extract_safe_diagnostic(nvim_diag)

    if Result.is_ok(result) then
      table.insert(safe, result.value)
    else
      skipped = skipped + 1
      log.debug('Skipped diagnostic: ' .. result.error)
    end
  end

  if skipped > 0 then
    log.debugf('Skipped %d diagnostics with invalid data', skipped)
  end

  return safe
end

--- Create LSP range from buffer positions
---@param start_line number Start line (0-based)
---@param start_char number Start character (0-based)
---@param end_line number End line (0-based)
---@param end_char number End character (0-based)
---@return table result Result with range or error
function M.create_range(start_line, start_char, end_line, end_char)
  local range = {
    start = { line = start_line, character = start_char },
    ['end'] = { line = end_line, character = end_char },
  }

  return M.validate_range(range)
end

--- Check if a position is within a range
---@param position table LSP position
---@param range table LSP range
---@return table result Result with boolean or error
function M.position_in_range(position, range)
  return M.validate_position(position):and_then(function(pos)
    return M.validate_range(range):map(function(r)
      -- Check if position is after start
      local after_start = pos.line > r.start.line
        or (pos.line == r.start.line and pos.character >= r.start.character)

      -- Check if position is before end
      local before_end = pos.line < r['end'].line
        or (pos.line == r['end'].line and pos.character <= r['end'].character)

      return after_start and before_end
    end)
  end)
end

--- Compare two ranges for equality
---@param range1 table First LSP range
---@param range2 table Second LSP range
---@return table result Result with boolean or error
function M.ranges_equal(range1, range2)
  return M.validate_range(range1):and_then(function(r1)
    return M.validate_range(range2):map(function(r2)
      return r1.start.line == r2.start.line
        and r1.start.character == r2.start.character
        and r1['end'].line == r2['end'].line
        and r1['end'].character == r2['end'].character
    end)
  end)
end

--- Check if two ranges overlap
---@param range1 table First LSP range
---@param range2 table Second LSP range
---@return table result Result with boolean or error
function M.ranges_overlap(range1, range2)
  return M.validate_range(range1):and_then(function(r1)
    return M.validate_range(range2):map(function(r2)
      -- Check if r1 starts before r2 ends
      local r1_before_r2_end = r1.start.line < r2['end'].line
        or (r1.start.line == r2['end'].line and r1.start.character <= r2['end'].character)

      -- Check if r2 starts before r1 ends
      local r2_before_r1_end = r2.start.line < r1['end'].line
        or (r2.start.line == r1['end'].line and r2.start.character <= r1['end'].character)

      return r1_before_r2_end and r2_before_r1_end
    end)
  end)
end

return M
