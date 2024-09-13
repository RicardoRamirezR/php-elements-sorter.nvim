local M = {}

-- Types
---@alias TSNode userdata
---@alias TSParser userdata
---@alias TSTree userdata
---@alias TSQuery userdata

---@class Config
---@field add_visibility_spacing boolean
---@field sort_properties boolean
---@field sort_traits boolean
---@field sort_namespace_uses boolean
---@field sort_constants boolean
---@field default_visibility string
---@field remove_unused_imports boolean
---@field add_newline_between_const_and_properties boolean

---@class NodeInfo
---@field node TSNode
---@field comment TSNode?
---@field node_lines string[]
---@field comment_lines string[]?

---@class Range
---@field min number
---@field max number

-- Dependencies
local ts = vim.treesitter
local parsers = require('nvim-treesitter.parsers')
local vim_diagnostic = vim.diagnostic

-- Constants
local VISIBILITY_VALUES = { private = 1, protected = 2, public = 3 }

-- Configuration
---@type Config
M.config = {
  add_visibility_spacing = true,
  sort_properties = true,
  sort_traits = true,
  sort_namespace_uses = true,
  sort_constants = true,
  default_visibility = 'public',
  remove_unused_imports = true,
  add_newline_between_const_and_properties = true,
}

-- Plugin state
---@type number?
M.bufnr = nil
---@type TSNode?
M.root = nil
---@type string?
M.lang = nil
---@type string?
local prev_type = nil

-- Helper functions

---Get the visibility of a node as a string
---@param node TSNode
---@return string
local function get_visibility_string(node)
  for child in node:iter_children() do
    if child:type() == 'visibility_modifier' then
      return ts.get_node_text(child, 0)
    end
  end
  return M.config.default_visibility
end

---Compare two nodes based on their text and optionally their visibility
---@param a NodeInfo
---@param b NodeInfo
---@param compare_visibility boolean
---@return boolean
local function compare_nodes(a, b, compare_visibility)
  if compare_visibility then
    local vis_a = VISIBILITY_VALUES[get_visibility_string(a.node)]
    local vis_b = VISIBILITY_VALUES[get_visibility_string(b.node)]
    if vis_a ~= vis_b then
      return vis_a < vis_b
    end
  end
  return ts.get_node_text(a.node, 0) < ts.get_node_text(b.node, 0)
end

---Set the TreeSitter parser for the current buffer
local function set_treesitter_parser()
  local parser = parsers.get_parser(M.bufnr)
  local tree = parser:parse()[1]
  M.root = tree:root()
  M.lang = parser:lang()
end

---Update buffer with sorted lines
---@param range Range
---@param lines string[]
---@return boolean
local function update_buffer(range, lines)
  local original_lines = vim.api.nvim_buf_get_lines(0, range.min - 1, range.max, false)
  if vim.deep_equal(original_lines, lines) then
    return false
  end
  local success, err = pcall(vim.api.nvim_buf_set_lines, 0, range.min - 1, range.max, false, lines)
  if not success then
    vim.notify('Failed to update buffer: ' .. err, vim.log.levels.ERROR)
    return false
  end
  return true
end

---Check if a node is unused based on diagnostics
---@param row number
---@return boolean
local function is_unused(row)
  local diagnostics = vim_diagnostic.get(0, { lnum = row })
  for _, diag in ipairs(diagnostics) do
    if diag.message:match('is not used') or diag.message:match('is declared but not used') then
      return true
    end
  end
  return false
end

---Extract PHP elements from a specific range in the current buffer
---@param start_row number
---@param end_row number
---@return NodeInfo[], NodeInfo[], NodeInfo[]
local function extract_range(start_row, end_row)
  local query_string = [[
    (use_declaration) @trait
    (const_declaration) @const
    (property_declaration) @property
  ]]

  local parsed_query = ts.query.parse(M.lang, query_string)
  local captures = {
    trait = {},
    const = {},
    property = {},
  }

  for id, node in parsed_query:iter_captures(M.root, M.bufnr, start_row, end_row) do
    local capture_name = parsed_query.captures[id]
    local real_node_start_row = node:start()
    local end_row_arg = end_row == -1 and real_node_start_row + 1 or end_row

    if real_node_start_row >= start_row and real_node_start_row <= end_row_arg then
      local prev_sibling = node:prev_sibling()
      local comment = prev_sibling and prev_sibling:type() == 'comment' and prev_sibling or nil

      local node_start_row, _, node_end_row, _ = node:range()
      local node_lines =
          vim.api.nvim_buf_get_lines(M.bufnr, node_start_row, node_end_row + 1, false)

      local comment_lines = nil
      if comment then
        local c_start_row, _, c_end_row, _ = comment:range()
        comment_lines = vim.api.nvim_buf_get_lines(M.bufnr, c_start_row, c_end_row + 1, false)
      end

      local candidate = {
        node = node,
        comment = comment,
        node_lines = node_lines,
        comment_lines = comment_lines,
      }

      if captures[capture_name] then
        table.insert(captures[capture_name], candidate)
      end
    end
  end

  return captures.trait, captures.const, captures.property
end

---Get the minimum and maximum range for a given query
---@param query TSQuery
---@return Range
local function get_min_max_range(query)
  local range = { min = math.huge, max = 0 }
  for _, node in query:iter_captures(M.root, M.bufnr, 0, -1) do
    local start_row, _, end_row, _ = node:range()
    range.min = math.min(range.min, start_row + 1)
    range.max = math.max(range.max, end_row + 1)
  end
  return range
end

-- Sorting functions

---Sort and update PHP elements in the buffer
---@param statements NodeInfo[]
---@param compare function
---@param is_property boolean
---@return boolean
local function sort_and_update(statements, compare, is_property)
  if #statements == 0 then
    return false
  end

  local range = { min = math.huge, max = 0 }

  for _, statement in ipairs(statements) do
    local start_row, _, end_row, _ = statement.node:range()
    range.min = math.min(range.min, start_row + 1)
    range.max = math.max(range.max, end_row + 1)
  end

  -- Store the original order of node texts
  local original_order = {}
  for _, statement in ipairs(statements) do
    table.insert(original_order, ts.get_node_text(statement.node, 0))
  end

  table.sort(statements, compare)

  -- Check if the sorted order is the same as the original order
  local order_changed = false
  for i, statement in ipairs(statements) do
    if ts.get_node_text(statement.node, 0) ~= original_order[i] then
      order_changed = true
      break
    end
  end

  if not order_changed then
    return false
  end

  local lines = {}
  local prev_visibility = nil

  for _, statement in ipairs(statements) do
    if M.config.add_newline_between_const_and_properties then
      local current_type = statement.node:type()
      if prev_type == 'const_declaration' and current_type == 'property_declaration' then
        if #lines == 0 or #lines > 0 and lines[#lines] ~= '' then
          table.insert(lines, '')
        end
      end
      prev_type = current_type
    end

    if statement.comment then
      vim.list_extend(lines, statement.comment_lines)
    end

    if is_property and M.config.add_visibility_spacing then
      local current_visibility = get_visibility_string(statement.node)
      if prev_visibility and current_visibility ~= prev_visibility then
        if #lines > 0 and lines[#lines] ~= '' then
          table.insert(lines, '')
        end
      end
      prev_visibility = current_visibility
    end

    vim.list_extend(lines, statement.node_lines)
  end

  return update_buffer(range, lines)
end

---Sort namespace use declarations
local function sort_namespace_uses()
  local query_string = [[(namespace_use_declaration) @namespace_use_declaration]]
  local parsed_query = ts.query.parse(M.lang, query_string)
  local uses = {}

  local start_row, end_row
  for _, node in parsed_query:iter_captures(M.root, M.bufnr, 0, -1) do
    local prev_sibling = node:prev_sibling()
    local comment = prev_sibling and prev_sibling:type() == 'comment' and prev_sibling or nil

    local comment_lines = nil
    if comment then
      start_row, _, end_row, _ = comment:range()
      comment_lines = vim.api.nvim_buf_get_lines(M.bufnr, start_row, end_row + 1, false)
    end

    start_row, _, end_row, _ = node:range()
    local node_lines = vim.api.nvim_buf_get_lines(M.bufnr, start_row, end_row + 1, false)

    table.insert(uses, {
      node = node,
      comment = comment,
      node_lines = node_lines,
      comment_lines = comment_lines,
    })
  end

  sort_and_update(uses, function(a, b)
    return compare_nodes(a, b, false)
  end, false)
end

---Remove unused namespace uses
local function remove_unused_namespace_uses()
  if not M.config.remove_unused_imports or not M.config.sort_namespace_uses then
    return
  end

  set_treesitter_parser()

  local query_string = [[ (namespace_use_declaration) @namespace_use_declaration ]]
  local parsed_query = ts.query.parse(M.lang, query_string)
  local start_row, end_row
  local captures = {}

  for _, node in parsed_query:iter_captures(M.root, M.bufnr, 0, -1) do
    local prev_sibling = node:prev_sibling()
    local comment = prev_sibling and prev_sibling:type() == 'comment' and prev_sibling or nil

    local comment_lines = nil
    if comment then
      start_row, _, end_row, _ = comment:range()
      comment_lines = vim.api.nvim_buf_get_lines(M.bufnr, start_row, end_row + 1, false)
    end

    start_row, _, end_row, _ = node:range()
    local node_lines = vim.api.nvim_buf_get_lines(M.bufnr, start_row, end_row + 1, false)

    table.insert(captures, {
      node = node,
      comment = comment,
      node_lines = node_lines,
      comment_lines = comment_lines,
    })
  end

  local range = { min = nil, max = nil }
  for i = #captures, 1, -1 do
    local remove = captures[i]
    if is_unused(remove.node:start()) then
      range.min = math.huge
      range.max = 0

      if remove.comment then
        start_row, _, end_row, _ = remove.comment:range()
        range.min = math.min(range.min, start_row + 1)
        range.max = math.max(range.max, end_row + 1)
      end

      start_row, _, end_row, _ = remove.node:range()
      range.min = math.min(range.min, start_row + 1)
      range.max = math.max(range.max, end_row + 1)

      vim.api.nvim_buf_set_lines(0, range.min - 1, range.max, false, {})
    end
  end
end

---Remove extra new lines
local function remove_extra_new_lines()
  set_treesitter_parser()
  local query = ts.query.parse(M.lang, [[(namespace_use_declaration) @namespace_use_declaration]])

  local range = get_min_max_range(query)
  for i = range.max, range.min, -1 do
    local node_line = vim.api.nvim_buf_get_lines(M.bufnr, i - 1, i, false)[1]
    if node_line:match('^%s*$') ~= nil then
      pcall(vim.api.nvim_buf_set_lines, M.bufnr, i - 1, i, false, {})
    end
  end

  local qs = [[
      (use_declaration
        "use" @vis
        (static_modifier)? @modifier
        (name) @property_element
    ) @prop
    (property_declaration
        (visibility_modifier) @vis
        (static_modifier)? @modifier
        (property_element) @property_element
    ) @prop
    (const_declaration
        (visibility_modifier) @vis
        "const" @modifier
        (const_element) @property_element
    ) @prop
  ]]

  query = ts.query.parse(M.lang, qs)

  range = get_min_max_range(query)

  for i = range.max, range.min, -1 do
    local node_line = vim.api.nvim_buf_get_lines(M.bufnr, i - 1, i, false)[1]
    if node_line:match('^%s*$') ~= nil then
      pcall(vim.api.nvim_buf_set_lines, M.bufnr, i - 1, i, false, {})
    end
  end

  query = ts.query.parse(M.lang, qs)

  local result = {}
  local current_entry = {}

  for id, node, _ in query:iter_captures(M.root, M.bufnr, 0, -1) do
    local name = query.captures[id]
    local text = ts.get_node_text(node, M.bufnr)

    if name == 'prop' then
      if next(current_entry) ~= nil then
        table.insert(result, current_entry)
      end
      current_entry = { node = node, type = node:type() }
    else
      current_entry[name] = text
    end
  end

  if next(current_entry) ~= nil then
    table.insert(result, current_entry)
  end

  local prev_vis
  local start_row, end_row

  for i = #result, 1, -1 do
    local entry = result[i]
    if prev_vis ~= entry.vis then
      local prev_sibling = entry.node:prev_sibling()
      local comment = prev_sibling and prev_sibling:type() == 'comment' and prev_sibling or nil
      local lines = {}

      range = { min = math.huge, max = 0 }
      if comment then
        start_row, _, end_row, _ = comment:range()
        range.min = math.min(range.min, start_row + 1)
        range.max = math.max(range.max, end_row + 1)
        local comment_lines = vim.api.nvim_buf_get_lines(M.bufnr, start_row, end_row + 1, false)
        for _, line in ipairs(comment_lines) do
          table.insert(lines, line)
        end
      end

      start_row, _, end_row, _ = entry.node:range()
      range.min = math.min(range.min, start_row + 1)
      range.max = math.max(range.max, end_row + 1)
      local original_lines = vim.api.nvim_buf_get_lines(M.bufnr, start_row, end_row + 1, false)
      for _, line in ipairs(original_lines) do
        table.insert(lines, line)
      end
      if prev_vis then
        table.insert(lines, '')
      else
        local next_line = vim.api.nvim_buf_get_lines(M.bufnr, end_row + 1, end_row + 2, false)[1]
        if next_line:match('^%s*$') == nil then
          table.insert(lines, '')
        end
      end
      vim.api.nvim_buf_set_lines(M.bufnr, range.min - 1, range.max, false, lines)
      prev_vis = entry.vis
    end
  end
end

---Process and sort PHP elements
---@param start_row number
---@param end_row number
local function process_and_sort_elements(start_row, end_row)
  local traits, constants, properties = extract_range(start_row, end_row)

  if M.config.sort_properties then
    sort_and_update(properties, function(a, b)
      return compare_nodes(a, b, true)
    end, true)
  end

  if M.config.sort_constants then
    sort_and_update(constants, function(a, b)
      return compare_nodes(a, b, true)
    end, false)
  end

  if M.config.sort_traits then
    sort_and_update(traits, function(a, b)
      return compare_nodes(a, b, false)
    end, false)
  end
end

-- Main function to sort PHP elements
---@return nil
function M.sort_php_elements()
  M.bufnr = vim.api.nvim_get_current_buf()
  local parser = parsers.get_parser(M.bufnr)
  prev_type = nil

  if not parser then
    error('Failed to get parser for the current buffer.')
  end

  local tree = parser:parse()[1]
  if not tree then
    error('Failed to parse the syntax tree.')
  end

  set_treesitter_parser()

  if M.lang ~= 'php' then
    error('This command is only for PHP files')
  end

  local class_query = ts.query.parse(M.lang, '(class_declaration) @class')
  local classes = {}

  for _, node in class_query:iter_captures(M.root, M.bufnr, 0, -1) do
    table.insert(classes, node)
  end

  if #classes == 0 then
    process_and_sort_elements(0, -1)
  else
    for _, class_node in ipairs(classes) do
      local start_row, _, end_row, _ = class_node:range()
      process_and_sort_elements(start_row, end_row)
    end
  end

  sort_namespace_uses()
  remove_unused_namespace_uses()
  remove_extra_new_lines()
end

-- Plugin setup function
---@param user_config Config
---@return nil
function M.setup(user_config)
  M.config = vim.tbl_deep_extend('force', M.config, user_config or {})

  vim.api.nvim_create_user_command('SortPHPElements', function()
    M.sort_php_elements()
  end, {})

  local group = vim.api.nvim_create_augroup('SortPHPElements', { clear = true })
  vim.api.nvim_create_autocmd('BufWritePre', {
    pattern = { '*.php' },
    callback = function()
      -- Uncomment the following line to enable automatic sorting on file save
      -- M.sort_php_elements()
    end,
    group = group,
  })
end

return M
