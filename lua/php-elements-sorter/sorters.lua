-- ============================================================================
-- lua/php-elements-sorter/sorters.lua
-- Sorting logic with statistics tracking
-- MEJORAS: #1 Buffer modifications atómicas + #4 Spacing utilities
-- ============================================================================

local M = {}

local parser = require('php-elements-sorter.parser')
local old_spacing = require('php-elements-sorter.spacing')
local spacing_utils = require('php-elements-sorter.utils.spacing')
local utils = require('php-elements-sorter.utils')
local log = require('php-elements-sorter.utils.log')

local ts = vim.treesitter
local get_node_text = ts.get_node_text

--- Build final content with spacing in one pass (usando spacing utils)
---@param bufnr number Buffer number
---@param start_idx0 number Start line (0-based)
---@param end_idx0 number End line (0-based, exclusive)
---@param sorted_lines table Lines to insert
---@return table final_lines, number new_end_idx0
local function build_final_content_with_spacing(bufnr, start_idx0, end_idx0, sorted_lines)
  -- Use new spacing utilities
  local final_lines = spacing_utils.build_with_spacing(bufnr, start_idx0, end_idx0, sorted_lines)

  -- Calculate new end index after insertion
  local new_end_idx0 = start_idx0 + #final_lines

  return final_lines, new_end_idx0
end

--- Apply single buffer modification atomically
---@param bufnr number Buffer number
---@param start_line number Start line (0-based)
---@param end_line number End line (0-based, exclusive)
---@param lines table Lines to set
---@return boolean success
local function apply_single_modification(bufnr, start_line, end_line, lines)
  log.debug(
    string.format('Applying modification at lines %d-%d (%d lines)', start_line, end_line, #lines)
  )

  local ok, err = pcall(vim.api.nvim_buf_set_lines, bufnr, start_line, end_line, false, lines)

  if not ok then
    log.error(
      string.format(
        'Failed to apply modification at lines %d-%d: %s',
        start_line,
        end_line,
        tostring(err)
      )
    )
    return false
  end

  log.debug(string.format('Successfully applied modification'))
  return true
end

--- Generic sort + update for a list of statements with statistics
---@param state table Plugin state
---@param statements table List of statements to sort
---@param compare_fn function Comparison function
---@param is_property boolean Whether these are properties
---@return boolean changed, number count
local function sort_and_update(state, statements, compare_fn, is_property)
  if not statements or #statements == 0 then
    log.debug('No statements to sort')
    return false, 0
  end

  log.debug(
    string.format('Sorting %d statements (is_property: %s)', #statements, tostring(is_property))
  )

  -- Compute original range (1-based)
  local range = { min = math.huge, max = 0 }
  for _, st in ipairs(statements) do
    local s, _, e, _ = st.node:range()
    range.min = math.min(range.min, s + 1)
    range.max = math.max(range.max, e + 1)
  end

  log.debug(string.format('Statement range: %d-%d', range.min, range.max))

  -- Preserve original textual order for change detection
  local original_order = {}
  for _, st in ipairs(statements) do
    table.insert(original_order, get_node_text(st.node, 0) or '')
  end

  -- Sort in-place
  table.sort(statements, compare_fn)

  -- Detect order change
  local order_changed = false
  for i, st in ipairs(statements) do
    if (get_node_text(st.node, 0) or '') ~= original_order[i] then
      order_changed = true
      log.debug(string.format('Order changed at position %d', i))
      break
    end
  end

  if not order_changed then
    log.debug('No order change detected, but checking spacing...')

    -- Even if no order change, ensure spacing using new utilities
    if #statements > 0 then
      local first_s, _, last_e, _ = statements[1].node:range()
      for i = 2, #statements do
        local s, _, e, _ = statements[i].node:range()
        first_s = math.min(first_s, s)
        last_e = math.max(last_e, e)
      end

      local start_idx0 = first_s
      local end_idx0 = last_e + 1

      -- Check if spacing is needed
      local needs_before, needs_after =
        spacing_utils.check_spacing_needs(state.bufnr, start_idx0, end_idx0)

      if needs_before or needs_after then
        log.debug('Spacing needs adjustment without reordering')

        -- Get current content
        local ok, current_lines =
          pcall(vim.api.nvim_buf_get_lines, state.bufnr, start_idx0, end_idx0, false)

        if ok and current_lines then
          -- Build with spacing
          local final_lines =
            spacing_utils.build_with_spacing(state.bufnr, start_idx0, end_idx0, current_lines)

          return apply_single_modification(state.bufnr, start_idx0, end_idx0, final_lines), 0
        end
      end
    end

    return false, 0
  end

  log.debug('Building sorted lines')

  -- Build new lines for the whole block
  local sorted_lines = {}
  local prev_visibility = nil
  local prev_type_local = state.prev_type

  for _, st in ipairs(statements) do
    -- Newline between const and properties if configured
    if state.config.add_newline_between_const_and_properties then
      local current_type = st.node:type()
      if prev_type_local == 'const_declaration' and current_type == 'property_declaration' then
        if #sorted_lines == 0 or (#sorted_lines > 0 and sorted_lines[#sorted_lines] ~= '') then
          table.insert(sorted_lines, '')
          log.debug('Added newline between const and property')
        end
      end
      prev_type_local = current_type
    end

    -- Attach comment lines (if any)
    if st.comment and st.comment_lines then
      vim.list_extend(sorted_lines, st.comment_lines)
      log.debug(string.format('Added %d comment lines', #st.comment_lines))
    end

    -- Visibility spacing: insert one blank line when visibility changes
    if is_property and state.config.add_visibility_spacing then
      local current_visibility =
        utils.get_visibility_string(st.node, state.config.default_visibility)
      if prev_visibility and current_visibility ~= prev_visibility then
        if #sorted_lines > 0 and sorted_lines[#sorted_lines] ~= '' then
          table.insert(sorted_lines, '')
          log.debug(
            string.format('Added visibility spacing: %s -> %s', prev_visibility, current_visibility)
          )
        end
      end
      prev_visibility = current_visibility
    end

    -- Append node lines
    if st.node_lines then
      vim.list_extend(sorted_lines, st.node_lines)
    end
  end

  log.debug(string.format('Built %d sorted lines', #sorted_lines))

  -- Calculate indices for replacement
  local start_idx0 = range.min - 1
  local end_idx0 = range.max

  -- Build final content WITH spacing in ONE operation
  local final_lines, new_end_idx0 =
    build_final_content_with_spacing(state.bufnr, start_idx0, end_idx0, sorted_lines)

  log.debug(
    string.format(
      'Final content has %d lines (range %d-%d)',
      #final_lines,
      start_idx0,
      new_end_idx0
    )
  )

  -- Apply in ONE atomic operation
  local success = apply_single_modification(state.bufnr, start_idx0, end_idx0, final_lines)

  if not success then
    log.error('Failed to apply buffer modification')
    return false, 0
  end

  state.prev_type = prev_type_local

  log.debug(string.format('Successfully sorted and updated %d statements', #statements))

  return true, #statements
end

--- Sort constants in range
---@param state table Plugin state
---@param start_row number Start row
---@param end_row number End row
---@return boolean changed, number count
local function sort_constants_in_range(state, start_row, end_row)
  local traits, consts, props, _ = parser.extract_range(state, start_row, end_row)
  if state.config.sort_constants and #consts > 0 then
    return sort_and_update(state, consts, function(a, b)
      return utils.compare_nodes(a, b, true, state.config.default_visibility)
    end, false)
  end
  return false, 0
end

--- Sort properties in range
---@param state table Plugin state
---@param start_row number Start row
---@param end_row number End row
---@return boolean changed, number count
local function sort_properties_in_range(state, start_row, end_row)
  local traits, consts, props, _ = parser.extract_range(state, start_row, end_row)
  if state.config.sort_properties and #props > 0 then
    return sort_and_update(state, props, function(a, b)
      return utils.compare_nodes(a, b, true, state.config.default_visibility)
    end, true)
  end
  return false, 0
end

--- Sort traits in range
---@param state table Plugin state
---@param start_row number Start row
---@param end_row number End row
---@return boolean changed, number count
local function sort_traits_in_range(state, start_row, end_row)
  local traits, consts, props, _ = parser.extract_range(state, start_row, end_row)
  if state.config.sort_traits and #traits > 0 then
    return sort_and_update(state, traits, function(a, b)
      return utils.compare_nodes(a, b, false, state.config.default_visibility)
    end, false)
  end
  return false, 0
end

--- Sort namespace use statements
---@param state table Plugin state
---@return number count Number of uses sorted
function M.sort_namespace_uses_impl(state)
  if not state.config.sort_namespace_uses then
    log.debug('Namespace use sorting disabled in config')
    return 0
  end
  if not parser.set_treesitter_parser(state) then
    log.warn('Failed to setup treesitter parser for namespace uses')
    return 0
  end

  local ok, query = pcall(parser.parse_query, state.lang, '(namespace_use_declaration) @use')
  if not ok or not query then
    log.error('Failed to parse namespace use query: ' .. tostring(query))
    return 0
  end

  local uses = {}
  for id, node in query:iter_captures(state.root, state.bufnr, 0, -1) do
    if query.captures[id] == 'use' then
      local s, _, e, _ = node:range()
      local ok_lines, node_lines = pcall(vim.api.nvim_buf_get_lines, state.bufnr, s, e + 1, false)

      if ok_lines then
        table.insert(uses, { node = node, node_lines = node_lines })
      else
        log.warn(string.format('Failed to get lines for use statement at row %d', s))
      end
    end
  end

  if #uses == 0 then
    log.debug('No namespace use statements found')
    return 0
  end

  log.debug(string.format('Found %d namespace use statements', #uses))

  local changed, count = sort_and_update(state, uses, function(a, b)
    return utils.compare_nodes(a, b, false, state.config.default_visibility)
  end, false)

  return count
end

--- Remove unused namespace uses
---@param state table Plugin state
---@return number count Number of uses removed
function M.remove_unused_namespace_uses_impl(state)
  if not state.config.remove_unused_imports then
    return 0
  end
  if not parser.set_treesitter_parser(state) then
    return 0
  end

  local ok, query = pcall(parser.parse_query, state.lang, '(namespace_use_declaration) @use')
  if not ok or not query then
    return 0
  end

  local uses = {}
  for _, node in query:iter_captures(state.root, state.bufnr, 0, -1) do
    table.insert(uses, node)
  end

  -- Collect all removals (in reverse order to avoid offset issues)
  local to_remove = {}
  for i = #uses, 1, -1 do
    if utils.is_unused(uses[i]:start()) then
      local s, _, e, _ = uses[i]:range()
      table.insert(to_remove, { start_line = s, end_line = e + 1 })
    end
  end

  -- Apply removals one by one (already in reverse order)
  local removed_count = 0
  for _, removal in ipairs(to_remove) do
    local ok = apply_single_modification(state.bufnr, removal.start_line, removal.end_line, {})
    if ok then
      removed_count = removed_count + 1
    end
  end

  return removed_count
end

--- Process elements per class or globally
---@param state table Plugin state
---@param start_row number Start row
---@param end_row number End row
---@return table stats Statistics {constants, properties, traits}
function M.process_and_sort_elements(state, start_row, end_row)
  if not parser.set_treesitter_parser(state) then
    return { constants = 0, properties = 0, traits = 0 }
  end

  local stats = { constants = 0, properties = 0, traits = 0 }

  local ok, class_query = pcall(parser.parse_query, state.lang, '(class_declaration) @class')
  if not ok or not class_query then
    local _, const_count = sort_constants_in_range(state, start_row, end_row)
    local _, prop_count = sort_properties_in_range(state, start_row, end_row)
    local _, trait_count = sort_traits_in_range(state, start_row, end_row)

    stats.constants = const_count
    stats.properties = prop_count
    stats.traits = trait_count
    return stats
  end

  local classes = {}
  for _, node in class_query:iter_captures(state.root, state.bufnr, start_row, end_row) do
    table.insert(classes, node)
  end

  if #classes == 0 then
    local _, const_count = sort_constants_in_range(state, start_row, end_row)
    local _, prop_count = sort_properties_in_range(state, start_row, end_row)
    local _, trait_count = sort_traits_in_range(state, start_row, end_row)

    stats.constants = const_count
    stats.properties = prop_count
    stats.traits = trait_count
    return stats
  end

  for _, class_node in ipairs(classes) do
    local s, _, e, _ = class_node:range()
    local _, const_count = sort_constants_in_range(state, s, e)
    local _, prop_count = sort_properties_in_range(state, s, e)
    local _, trait_count = sort_traits_in_range(state, s, e)

    stats.constants = stats.constants + const_count
    stats.properties = stats.properties + prop_count
    stats.traits = stats.traits + trait_count
  end

  return stats
end

--- High-level pipeline with statistics
---@param state table Plugin state
---@return table stats Complete statistics
function M.sort_all_impl(state)
  if not parser.set_treesitter_parser(state) then
    log.warn('Failed to setup parser for sort_all')
    return { uses = 0, removed = 0, constants = 0, properties = 0, traits = 0 }
  end

  log.debug('Starting sort_all pipeline')

  local stats = { uses = 0, removed = 0, constants = 0, properties = 0, traits = 0 }

  stats.uses = M.sort_namespace_uses_impl(state)
  log.debug(string.format('Sorted %d namespace uses', stats.uses))

  stats.removed = M.remove_unused_namespace_uses_impl(state)
  log.debug(string.format('Removed %d unused uses', stats.removed))

  local element_stats = M.process_and_sort_elements(state, 0, -1)
  stats.constants = element_stats.constants
  stats.properties = element_stats.properties
  stats.traits = element_stats.traits

  log.debug(
    string.format(
      'Sorted elements: %d constants, %d properties, %d traits',
      stats.constants,
      stats.properties,
      stats.traits
    )
  )

  old_spacing.add_spacing_after_trait_uses(state)

  log.info(
    string.format(
      'Sort completed: %d uses, %d removed, %d constants, %d properties, %d traits',
      stats.uses,
      stats.removed,
      stats.constants,
      stats.properties,
      stats.traits
    )
  )

  return stats
end

return M
