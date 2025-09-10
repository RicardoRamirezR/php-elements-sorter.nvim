-- lua/php-elements-sorter/sorters.lua
-- Sorting logic for uses/constants/properties/traits, with correct visibility spacing

local M = {}
local parser = require('php-elements-sorter.parser')
local utils = require('php-elements-sorter.utils')
local spacing = require('php-elements-sorter.spacing')

local ts = vim.treesitter
local get_node_text = ts.get_node_text

--- Generic sort + update for a list of statements.
-- Ensures:
--  * properties: single blank line between different visibilities (if config enabled)
--  * optional newline between const -> property (state.prev_type preserved)
--  * single blank line before and after the whole block
local function sort_and_update(state, statements, compare_fn, is_property)
  if not statements or #statements == 0 then
    return false
  end

  -- compute original range (1-based)
  local range = { min = math.huge, max = 0 }
  for _, st in ipairs(statements) do
    local s, _, e, _ = st.node:range()
    range.min = math.min(range.min, s + 1)
    range.max = math.max(range.max, e + 1)
  end

  -- preserve original textual order for change detection
  local original_order = {}
  for _, st in ipairs(statements) do
    table.insert(original_order, get_node_text(st.node, 0) or '')
  end

  -- sort in-place
  table.sort(statements, compare_fn)

  -- detect order change
  local order_changed = false
  for i, st in ipairs(statements) do
    if (get_node_text(st.node, 0) or '') ~= original_order[i] then
      order_changed = true
      break
    end
  end

  if not order_changed then
    return false
  end

  -- Build new lines for the whole block.
  local lines = {}
  local prev_visibility = nil
  local prev_type_local = state.prev_type -- preserve for const->property rule

  for _, st in ipairs(statements) do
    -- newline between const and properties if configured
    if state.config.add_newline_between_const_and_properties then
      local current_type = st.node:type()
      if prev_type_local == 'const_declaration' and current_type == 'property_declaration' then
        if #lines == 0 or (#lines > 0 and lines[#lines] ~= '') then
          table.insert(lines, '')
        end
      end
      prev_type_local = current_type
    end

    -- attach comment lines (if any)
    if st.comment and st.comment_lines then
      -- append comment lines as-is
      vim.list_extend(lines, st.comment_lines)
    end

    -- visibility spacing: insert one blank line when visibility changes
    if is_property and state.config.add_visibility_spacing then
      local current_visibility =
          utils.get_visibility_string(st.node, state.config.default_visibility)
      if prev_visibility and current_visibility ~= prev_visibility then
        if #lines > 0 and lines[#lines] ~= '' then
          table.insert(lines, '')
        end
      end
      prev_visibility = current_visibility
    end

    -- append node lines
    if st.node_lines then
      vim.list_extend(lines, st.node_lines)
    end
  end

  -- Replace original range with new block lines
  local start_idx0 = range.min - 1
  local end_idx0 = range
  .max                       -- end is 1-based exclusive in get_lines but here buf_set_lines uses end index (0-based exclusive)
  pcall(vim.api.nvim_buf_set_lines, state.bufnr, start_idx0, end_idx0, false, lines)

  -- After writing, compute end index (0-based) where the block ends now
  local inserted_end0 = start_idx0 + #lines

  -- Ensure single blank line BEFORE the block (if previous line exists and is not empty)
  if start_idx0 - 1 >= 0 then
    local prev_line = vim.api.nvim_buf_get_lines(state.bufnr, start_idx0 - 1, start_idx0, false)[1]
    if prev_line and not utils.is_empty_line(prev_line) then
      -- insert an empty line at start_idx0
      pcall(vim.api.nvim_buf_set_lines, state.bufnr, start_idx0, start_idx0, false, { '' })
      -- adjust inserted_end0 because we inserted a line before the block
      inserted_end0 = inserted_end0 + 1
    end
  end

  -- Ensure single blank line AFTER the block (check the line at inserted_end0)
  local after_line =
      vim.api.nvim_buf_get_lines(state.bufnr, inserted_end0, inserted_end0 + 1, false)
  if #after_line == 0 or not utils.is_empty_line(after_line[1]) then
    pcall(vim.api.nvim_buf_set_lines, state.bufnr, inserted_end0, inserted_end0, false, { '' })
    -- no need to adjust further
  end

  -- persist prev_type back to state so next calls know previous element kind
  state.prev_type = prev_type_local

  return true
end

local function sort_constants_in_range(state, start_row, end_row)
  local traits, consts, props, _ = parser.extract_range(state, start_row, end_row)
  if state.config.sort_constants and #consts > 0 then
    sort_and_update(state, consts, function(a, b)
      return utils.compare_nodes(a, b, true, state.config.default_visibility)
    end, false)
  end
end

local function sort_properties_in_range(state, start_row, end_row)
  local traits, consts, props, _ = parser.extract_range(state, start_row, end_row)
  if state.config.sort_properties and #props > 0 then
    local changed = sort_and_update(state, props, function(a, b)
      return utils.compare_nodes(a, b, true, state.config.default_visibility)
    end, true)

    -- if no change, still ensure spacing around the properties block (before/after)
    if not changed and #props > 0 then
      local first_s, _, last_e, _ = props[1].node:range()
      local start_idx0 = first_s
      local end_idx0 = last_e + 1

      if start_idx0 - 1 >= 0 then
        local prev_line =
            vim.api.nvim_buf_get_lines(state.bufnr, start_idx0 - 1, start_idx0, false)[1]
        if prev_line and not utils.is_empty_line(prev_line) then
          pcall(vim.api.nvim_buf_set_lines, state.bufnr, start_idx0, start_idx0, false, { '' })
          end_idx0 = end_idx0 + 1
        end
      end

      local after_line = vim.api.nvim_buf_get_lines(state.bufnr, end_idx0, end_idx0 + 1, false)
      if #after_line == 0 or not utils.is_empty_line(after_line[1]) then
        pcall(vim.api.nvim_buf_set_lines, state.bufnr, end_idx0, end_idx0, false, { '' })
      end
    end
  end
end

local function sort_traits_in_range(state, start_row, end_row)
  local traits, consts, props, _ = parser.extract_range(state, start_row, end_row)
  if state.config.sort_traits and #traits > 0 then
    sort_and_update(state, traits, function(a, b)
      return utils.compare_nodes(a, b, false, state.config.default_visibility)
    end, false)
  end
end

--- Sort namespace use statements + internal spacing (before/after block)
function M.sort_namespace_uses_impl(state)
  if not state.config.sort_namespace_uses then
    return
  end
  if not parser.set_treesitter_parser(state) then
    return
  end

  local ok, query = pcall(parser.parse_query, state.lang, '(namespace_use_declaration) @use')
  if not ok or not query then
    return
  end

  local uses = {}
  for id, node in query:iter_captures(state.root, state.bufnr, 0, -1) do
    if query.captures[id] == 'use' then
      local s, _, e, _ = node:range()
      local node_lines = vim.api.nvim_buf_get_lines(state.bufnr, s, e + 1, false)
      table.insert(uses, { node = node, node_lines = node_lines })
    end
  end

  if #uses == 0 then
    return
  end

  -- Sort and update, then add spacing around the whole block
  local changed = sort_and_update(state, uses, function(a, b)
    return utils.compare_nodes(a, b, false, state.config.default_visibility)
  end, false)

  -- If no change, still ensure spacing around the block (user expects spacing even if order unchanged)
  if not changed then
    -- compute block bounds using first and last use nodes (original ranges)
    local first_s, _, last_e, _ = uses[1].node:range()
    local start_idx0 = first_s
    local end_idx0 = last_e + 1

    -- before first use (line index start_idx0 - 1)
    if start_idx0 - 1 >= 0 then
      local prev_line =
          vim.api.nvim_buf_get_lines(state.bufnr, start_idx0 - 1, start_idx0, false)[1]
      if prev_line and not utils.is_empty_line(prev_line) then
        pcall(vim.api.nvim_buf_set_lines, state.bufnr, start_idx0, start_idx0, false, { '' })
        end_idx0 = end_idx0 + 1
      end
    end

    -- after last use
    local after_line = vim.api.nvim_buf_get_lines(state.bufnr, end_idx0, end_idx0 + 1, false)
    if #after_line == 0 or not utils.is_empty_line(after_line[1]) then
      pcall(vim.api.nvim_buf_set_lines, state.bufnr, end_idx0, end_idx0, false, { '' })
    end
  end
end

--- Remove unused namespace uses (walk backwards)
function M.remove_unused_namespace_uses_impl(state)
  if not state.config.remove_unused_imports then
    return
  end
  if not parser.set_treesitter_parser(state) then
    return
  end

  local ok, query = pcall(parser.parse_query, state.lang, '(namespace_use_declaration) @use')
  if not ok or not query then
    return
  end

  local uses = {}
  for _, node in query:iter_captures(state.root, state.bufnr, 0, -1) do
    table.insert(uses, node)
  end

  for i = #uses, 1, -1 do
    if utils.is_unused(uses[i]:start()) then
      local s, _, e, _ = uses[i]:range()
      pcall(vim.api.nvim_buf_set_lines, state.bufnr, s, e + 1, false, {})
    end
  end
end

--- Process elements per class or globally
function M.process_and_sort_elements(state, start_row, end_row)
  if not parser.set_treesitter_parser(state) then
    return
  end

  local ok, class_query = pcall(parser.parse_query, state.lang, '(class_declaration) @class')
  if not ok or not class_query then
    sort_constants_in_range(state, start_row, end_row)
    sort_properties_in_range(state, start_row, end_row)
    sort_traits_in_range(state, start_row, end_row)
    return
  end

  local classes = {}
  for _, node in class_query:iter_captures(state.root, state.bufnr, start_row, end_row) do
    table.insert(classes, node)
  end

  if #classes == 0 then
    sort_constants_in_range(state, start_row, end_row)
    sort_properties_in_range(state, start_row, end_row)
    sort_traits_in_range(state, start_row, end_row)
    return
  end

  for _, class_node in ipairs(classes) do
    local s, _, e, _ = class_node:range()
    sort_constants_in_range(state, s, e)
    sort_properties_in_range(state, s, e)
    sort_traits_in_range(state, s, e)
  end
end

--- High-level pipeline
function M.sort_all_impl(state)
  if not parser.set_treesitter_parser(state) then
    return
  end

  M.sort_namespace_uses_impl(state)
  M.remove_unused_namespace_uses_impl(state)
  M.process_and_sort_elements(state, 0, -1)
  spacing.add_spacing_after_trait_uses(state) -- keep special trait-use spacing if desired
end

return M
