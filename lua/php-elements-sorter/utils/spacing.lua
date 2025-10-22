-- ============================================================================
-- lua/php-elements-sorter/utils/spacing.lua
-- MEJORA #4: Utilidades centralizadas para manejo de spacing
-- ============================================================================

local M = {}

local log = require('php-elements-sorter.utils.log')

--- Check if a line is empty or contains only whitespace
---@param line string Line to check
---@return boolean
local function is_empty_line(line)
  return line and line:match('^%s*$') ~= nil
end

--- Check if blank line is needed before a position
---@param bufnr number Buffer number
---@param line_idx number Line index (0-based)
---@return boolean needs_blank
local function needs_blank_before(bufnr, line_idx)
  if line_idx <= 0 then
    return false
  end

  local ok, prev_line = pcall(vim.api.nvim_buf_get_lines, bufnr, line_idx - 1, line_idx, false)

  if not ok or not prev_line or #prev_line == 0 then
    return false
  end

  return not is_empty_line(prev_line[1])
end

--- Check if blank line is needed after a position
---@param bufnr number Buffer number
---@param line_idx number Line index (0-based)
---@return boolean needs_blank
local function needs_blank_after(bufnr, line_idx)
  local ok, next_line = pcall(vim.api.nvim_buf_get_lines, bufnr, line_idx, line_idx + 1, false)

  if not ok or not next_line then
    return false
  end

  -- If no line after (end of buffer) or line is not empty
  return #next_line == 0 or not is_empty_line(next_line[1])
end

--- Ensure exactly one blank line before a position
---@param bufnr number Buffer number
---@param line_idx number Line index (0-based)
---@return boolean inserted Whether a line was inserted
function M.ensure_blank_before(bufnr, line_idx)
  if not needs_blank_before(bufnr, line_idx) then
    return false
  end

  local ok, err = pcall(vim.api.nvim_buf_set_lines, bufnr, line_idx, line_idx, false, { '' })

  if ok then
    log.debug(string.format('Inserted blank line before line %d', line_idx))
    return true
  else
    log.warn(string.format('Failed to insert blank line before %d: %s', line_idx, tostring(err)))
    return false
  end
end

--- Ensure exactly one blank line after a position
---@param bufnr number Buffer number
---@param line_idx number Line index (0-based)
---@return boolean inserted Whether a line was inserted
function M.ensure_blank_after(bufnr, line_idx)
  if not needs_blank_after(bufnr, line_idx) then
    return false
  end

  local ok, err = pcall(vim.api.nvim_buf_set_lines, bufnr, line_idx, line_idx, false, { '' })

  if ok then
    log.debug(string.format('Inserted blank line after line %d', line_idx))
    return true
  else
    log.warn(string.format('Failed to insert blank line after %d: %s', line_idx, tostring(err)))
    return false
  end
end

--- Ensure spacing around a block of lines
---@param bufnr number Buffer number
---@param start_line number Start line (0-based)
---@param end_line number End line (0-based, exclusive)
---@return number offset Total lines added (for offset adjustment)
function M.ensure_spacing_around_block(bufnr, start_line, end_line)
  local offset = 0

  -- Add blank before (if needed)
  if M.ensure_blank_before(bufnr, start_line) then
    offset = offset + 1
    -- Adjust end_line since we inserted before
    end_line = end_line + 1
  end

  -- Add blank after (if needed)
  if M.ensure_blank_after(bufnr, end_line) then
    offset = offset + 1
  end

  if offset > 0 then
    log.debug(
      string.format('Added %d spacing line(s) around block [%d-%d]', offset, start_line, end_line)
    )
  end

  return offset
end

--- Get spacing requirements without modifying buffer
---@param bufnr number Buffer number
---@param start_line number Start line (0-based)
---@param end_line number End line (0-based, exclusive)
---@return boolean needs_before, boolean needs_after
function M.check_spacing_needs(bufnr, start_line, end_line)
  local needs_before = needs_blank_before(bufnr, start_line)
  local needs_after = needs_blank_after(bufnr, end_line)

  return needs_before, needs_after
end

--- Build content with spacing (for atomic operations)
---@param bufnr number Buffer number
---@param start_line number Start line (0-based)
---@param end_line number End line (0-based, exclusive)
---@param content_lines table Lines to insert
---@return table final_lines Content with spacing added
function M.build_with_spacing(bufnr, start_line, end_line, content_lines)
  local final_lines = {}

  -- Check spacing needs
  local needs_before = needs_blank_before(bufnr, start_line)
  local needs_after = needs_blank_after(bufnr, end_line)

  -- Build final content
  if needs_before then
    table.insert(final_lines, '')
    log.debug('Will add blank line before block')
  end

  vim.list_extend(final_lines, content_lines)

  if needs_after then
    table.insert(final_lines, '')
    log.debug('Will add blank line after block')
  end

  return final_lines
end

--- Remove consecutive duplicate blank lines
---@param lines table Lines to clean
---@return table cleaned_lines
function M.remove_duplicate_blanks(lines)
  local cleaned = {}
  local prev_was_blank = false

  for _, line in ipairs(lines) do
    local is_blank = is_empty_line(line)

    -- Only add if not consecutive blank
    if not (is_blank and prev_was_blank) then
      table.insert(cleaned, line)
    end

    prev_was_blank = is_blank
  end

  return cleaned
end

--- Ensure maximum one blank line between elements
---@param bufnr number Buffer number
---@param start_line number Start line (0-based)
---@param end_line number End line (0-based, exclusive)
function M.normalize_spacing_in_range(bufnr, start_line, end_line)
  local ok, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, start_line, end_line, false)

  if not ok or not lines then
    log.warn('Failed to get lines for spacing normalization')
    return
  end

  local cleaned = M.remove_duplicate_blanks(lines)

  if #cleaned ~= #lines then
    local ok_set = pcall(vim.api.nvim_buf_set_lines, bufnr, start_line, end_line, false, cleaned)

    if ok_set then
      log.debug(
        string.format('Normalized spacing: removed %d duplicate blank lines', #lines - #cleaned)
      )
    else
      log.warn('Failed to set normalized spacing')
    end
  end
end

return M
