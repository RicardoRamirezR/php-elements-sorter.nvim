-- ============================================================================
-- lua/php-elements-sorter/utils.lua
-- General utilities: visibility, buffer updates, diagnostics
-- ============================================================================

local M = {}
local ts = vim.treesitter
local get_node_text = ts.get_node_text
local vim_diagnostic = vim.diagnostic

local VISIBILITY_VALUES = { private = 1, protected = 2, public = 3 }

--- Is line empty or whitespace?
---@param line string Line to check
---@return boolean
function M.is_empty_line(line)
  return line:match('^%s*$') ~= nil
end

--- Get visibility string from node (returns default if none)
---@param node table Treesitter node
---@param default_visibility string Default visibility
---@return string visibility
function M.get_visibility_string(node, default_visibility)
  if not node then
    return default_visibility or 'public'
  end
  for child in node:iter_children() do
    if child:type() == 'visibility_modifier' then
      return get_node_text(child, 0) or default_visibility
    end
  end
  return default_visibility or 'public'
end

--- Compare two statement entries (a,b) with optional visibility ordering
---@param a table First statement
---@param b table Second statement
---@param compare_visibility boolean Whether to compare by visibility
---@param default_visibility string Default visibility
---@return boolean
function M.compare_nodes(a, b, compare_visibility, default_visibility)
  if compare_visibility then
    local vis_a = VISIBILITY_VALUES[M.get_visibility_string(a.node, default_visibility)] or 0
    local vis_b = VISIBILITY_VALUES[M.get_visibility_string(b.node, default_visibility)] or 0
    if vis_a ~= vis_b then
      return vis_a < vis_b
    end
  end
  local ta = get_node_text(a.node, 0) or ''
  local tb = get_node_text(b.node, 0) or ''
  return ta < tb
end

--- Update buffer lines in 1-based inclusive range {min, max}
---@param range table Range with min and max
---@param lines table Lines to set
---@return boolean changed
function M.update_buffer(range, lines)
  if not range or not lines then
    return false
  end
  local start_idx = math.max(0, range.min - 1)
  local end_idx = range.max
  local original = vim.api.nvim_buf_get_lines(0, start_idx, end_idx, false)
  if vim.deep_equal(original, lines) then
    return false
  end
  local ok, err = pcall(vim.api.nvim_buf_set_lines, 0, start_idx, end_idx, false, lines)
  if not ok then
    vim.notify('Failed to update buffer: ' .. tostring(err), vim.log.levels.ERROR)
    return false
  end
  return true
end

--- Return true if diagnostics mark the row as unused (0-based row)
---@param row number Row number (0-based)
---@return boolean
function M.is_unused(row)
  if not row then
    return false
  end
  local diags = vim_diagnostic.get(0, { lnum = row })
  for _, d in ipairs(diags) do
    local msg = d.message or ''
    if msg:match('is not used') or msg:match('is declared but not used') then
      return true
    end
  end
  return false
end

return M
