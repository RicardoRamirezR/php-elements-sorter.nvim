-- ============================================================================
-- lua/php-elements-sorter/preview.lua
-- Preview changes before applying them
-- ============================================================================

local M = {}

local log = require('php-elements-sorter.utils.log')

--- Create a unified diff between two line arrays
---@param original table Original lines
---@param modified table Modified lines
---@param context_lines number? Lines of context (default: 3)
---@return table diff_lines Lines of diff output
local function create_unified_diff(original, modified, context_lines)
  context_lines = context_lines or 3

  local diff_lines = {}

  -- Header
  table.insert(diff_lines, '--- Original')
  table.insert(diff_lines, '+++ Sorted')
  table.insert(diff_lines, '')

  -- Find all different line indices
  local max_len = math.max(#original, #modified)
  local diff_indices = {}

  for i = 1, max_len do
    if (original[i] or '') ~= (modified[i] or '') then
      table.insert(diff_indices, i)
    end
  end

  if #diff_indices == 0 then
    return diff_lines
  end

  -- Group differences into hunks with context
  local hunks = {}
  local current_hunk = nil

  for _, idx in ipairs(diff_indices) do
    local hunk_start = math.max(1, idx - context_lines)
    local hunk_end = math.min(max_len, idx + context_lines)

    if not current_hunk then
      current_hunk = { start_line = hunk_start, end_line = hunk_end }
    elseif hunk_start <= current_hunk.end_line + 1 then
      -- Extend current hunk
      current_hunk.end_line = math.max(current_hunk.end_line, hunk_end)
    else
      -- Start new hunk
      table.insert(hunks, current_hunk)
      current_hunk = { start_line = hunk_start, end_line = hunk_end }
    end
  end

  if current_hunk then
    table.insert(hunks, current_hunk)
  end

  -- Generate diff output for each hunk
  for _, hunk in ipairs(hunks) do
    -- Count lines in hunk
    local orig_count = math.min(hunk.end_line, #original) - hunk.start_line + 1
    local mod_count = math.min(hunk.end_line, #modified) - hunk.start_line + 1

    orig_count = math.max(0, orig_count)
    mod_count = math.max(0, mod_count)

    -- Hunk header
    table.insert(
      diff_lines,
      string.format('@@ -%d,%d +%d,%d @@', hunk.start_line, orig_count, hunk.start_line, mod_count)
    )

    -- Process lines in hunk
    for i = hunk.start_line, hunk.end_line do
      local orig_line = original[i]
      local mod_line = modified[i]

      if orig_line == mod_line then
        -- Context line (unchanged)
        if orig_line then
          table.insert(diff_lines, ' ' .. orig_line)
        end
      else
        -- Lines differ - show both
        if orig_line and (not mod_line or orig_line ~= mod_line) then
          table.insert(diff_lines, '-' .. orig_line)
        end
        if mod_line and (not orig_line or orig_line ~= mod_line) then
          table.insert(diff_lines, '+' .. mod_line)
        end
      end
    end

    table.insert(diff_lines, '')
  end

  return diff_lines
end

--- Show diff in a floating window
---@param original_lines table Original buffer lines
---@param sorted_lines table Sorted buffer lines
---@param on_accept function? Callback when user accepts changes
---@param on_cancel function? Callback when user cancels
---@return number bufnr, number winid Buffer and window IDs
function M.show_diff_window(original_lines, sorted_lines, on_accept, on_cancel)
  -- Check if there are any changes
  local has_changes = false
  if #original_lines ~= #sorted_lines then
    has_changes = true
  else
    for i = 1, #original_lines do
      if original_lines[i] ~= sorted_lines[i] then
        has_changes = true
        break
      end
    end
  end

  if not has_changes then
    vim.notify('[php-elements-sorter] No changes to preview', vim.log.levels.INFO)
    return nil, nil
  end

  -- Create diff
  local diff_lines = create_unified_diff(original_lines, sorted_lines)

  -- Create buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, diff_lines)
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
  vim.api.nvim_buf_set_option(buf, 'filetype', 'diff')

  -- Calculate window size
  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  -- Create window
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded',
    title = ' Preview Changes ',
    title_pos = 'center',
  })

  -- Add footer with instructions
  vim.api.nvim_buf_set_option(buf, 'modifiable', true)
  vim.api.nvim_buf_set_lines(buf, 0, 0, false, {
    '# PHP Elements Sorter - Preview Mode',
    '# Press <CR> or "a" to apply changes',
    '# Press <Esc> or "q" to cancel',
    '',
  })
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)

  -- Setup keymaps
  local function close_window()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  local function accept_changes()
    close_window()
    if on_accept then
      on_accept()
    end
    vim.notify('[php-elements-sorter] Changes applied', vim.log.levels.INFO)
  end

  local function cancel_changes()
    close_window()
    if on_cancel then
      on_cancel()
    end
    vim.notify('[php-elements-sorter] Changes cancelled', vim.log.levels.INFO)
  end

  -- Keymaps
  vim.keymap.set('n', '<CR>', accept_changes, { buffer = buf, nowait = true })
  vim.keymap.set('n', 'a', accept_changes, { buffer = buf, nowait = true })
  vim.keymap.set('n', '<Esc>', cancel_changes, { buffer = buf, nowait = true })
  vim.keymap.set('n', 'q', cancel_changes, { buffer = buf, nowait = true })

  -- Position cursor after header
  vim.api.nvim_win_set_cursor(win, { 5, 0 })

  log.debug('Opened preview window')

  return buf, win
end

--- Preview sort operation without applying
---@param sort_fn function Function that performs the sort
---@param bufnr number? Buffer number (default: current)
---@return boolean success
function M.preview_sort(sort_fn, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Check if buffer is valid
  if not vim.api.nvim_buf_is_valid(bufnr) then
    log.error('Invalid buffer for preview')
    return false
  end

  -- Get original content
  local original_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- Create temporary buffer with same content
  local temp_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(temp_buf, 'filetype', vim.bo[bufnr].filetype)
  vim.api.nvim_buf_set_lines(temp_buf, 0, -1, false, vim.deepcopy(original_lines))

  -- Switch to temp buffer and sort
  local original_buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_set_current_buf(temp_buf)

  local ok, result = pcall(sort_fn)

  if not ok then
    log.error('Sort function failed: ' .. tostring(result))
    vim.api.nvim_set_current_buf(original_buf)
    vim.api.nvim_buf_delete(temp_buf, { force = true })
    return false
  end

  -- Get sorted content
  local sorted_lines = vim.api.nvim_buf_get_lines(temp_buf, 0, -1, false)

  -- Switch back to original buffer
  vim.api.nvim_set_current_buf(original_buf)
  vim.api.nvim_buf_delete(temp_buf, { force = true })

  -- Show diff with callbacks
  local function on_accept()
    -- Apply changes to original buffer
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, sorted_lines)
    log.info('Preview changes accepted and applied')
  end

  local function on_cancel()
    log.debug('Preview changes cancelled')
  end

  M.show_diff_window(original_lines, sorted_lines, on_accept, on_cancel)

  return true
end

--- Preview namespace uses sorting
---@param bufnr number? Buffer number (default: current)
---@return boolean success
function M.preview_namespace_uses(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local plugin = require('php-elements-sorter')

  return M.preview_sort(function()
    plugin.sort_namespace_uses()
  end, bufnr)
end

--- Preview elements sorting
---@param bufnr number? Buffer number (default: current)
---@return boolean success
function M.preview_elements(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local plugin = require('php-elements-sorter')

  return M.preview_sort(function()
    plugin.sort_elements()
  end, bufnr)
end

--- Preview all sorting operations
---@param bufnr number? Buffer number (default: current)
---@return boolean success
function M.preview_all(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local plugin = require('php-elements-sorter')

  return M.preview_sort(function()
    plugin.sort_all()
  end, bufnr)
end

--- Check if preview is available
---@return boolean available
function M.is_available()
  -- Preview requires floating window support
  return vim.fn.has('nvim-0.6') == 1
end

return M
