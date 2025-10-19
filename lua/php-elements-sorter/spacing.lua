local M = {}

local parser = require('php-elements-sorter.parser')
local utils = require('php-elements-sorter.utils')

--- Ensure exactly one empty line before the first use and after the last use
function M.add_spacing_around_namespace_uses(state)
  if not state.config.sort_namespace_uses then
    return
  end
  if not parser.set_treesitter_parser(state) then
    return
  end

  local query = parser.parse_query(state.lang, '(namespace_use_declaration) @use')
  local first_use, last_use = nil, nil

  for _, node in query:iter_captures(state.root, state.bufnr, 0, -1) do
    local s, _, e, _ = node:range()
    first_use = first_use or s
    last_use = e
  end

  if not first_use then
    return
  end

  -- Before the first use
  if first_use > 0 then
    local prev_line = vim.api.nvim_buf_get_lines(state.bufnr, first_use - 1, first_use, false)[1]
    if prev_line and not utils.is_empty_line(prev_line) then
      vim.api.nvim_buf_set_lines(state.bufnr, first_use, first_use, false, { '' })
    end
  end

  -- After the last use
  local next_line = last_use + 1
  local lines = vim.api.nvim_buf_get_lines(state.bufnr, next_line, next_line + 1, false)
  if #lines == 0 or not utils.is_empty_line(lines[1]) then
    vim.api.nvim_buf_set_lines(state.bufnr, next_line, next_line, false, { '' })
  end
end

--- Ensure exactly one empty line before first and after last member in a class
function M.add_spacing_around_class_members(state)
  if not parser.set_treesitter_parser(state) then
    return
  end

  local query =
    parser.parse_query(state.lang, '(class_declaration body: (declaration_list (_) @member))')
  local members = {}

  for _, node in query:iter_captures(state.root, state.bufnr, 0, -1) do
    table.insert(members, node)
  end

  if #members == 0 then
    return
  end

  local first_member = members[1]
  local last_member = members[#members]

  local s, _, _, _ = first_member:range()
  if s > 0 then
    local prev_line = vim.api.nvim_buf_get_lines(state.bufnr, s - 1, s, false)[1]
    if prev_line and not utils.is_empty_line(prev_line) then
      vim.api.nvim_buf_set_lines(state.bufnr, s, s, false, { '' })
    end
  end

  local _, _, e, _ = last_member:range()
  local next_line = e + 1
  local lines = vim.api.nvim_buf_get_lines(state.bufnr, next_line, next_line + 1, false)
  if #lines == 0 or not utils.is_empty_line(lines[1]) then
    vim.api.nvim_buf_set_lines(state.bufnr, next_line, next_line, false, { '' })
  end
end

--- Existing: spacing after uses
function M.add_spacing_after_namespace_uses(state)
  if not state.config.add_newline_after_namespace_uses then
    return
  end
  if not parser.set_treesitter_parser(state) then
    return
  end

  local query = parser.parse_query(state.lang, '(namespace_use_declaration) @use')
  local last_use_line = nil

  for _, node in query:iter_captures(state.root, state.bufnr, 0, -1) do
    local _, _, end_row, _ = node:range()
    last_use_line = end_row
  end

  if last_use_line then
    local next_line = last_use_line + 1
    local lines = vim.api.nvim_buf_get_lines(state.bufnr, next_line, next_line + 1, false)
    if #lines == 0 or not utils.is_empty_line(lines[1]) then
      vim.api.nvim_buf_set_lines(state.bufnr, next_line, next_line, false, { '' })
    end
  end
end

--- Fixed: spacing after trait uses - now uses correct node type
function M.add_spacing_after_trait_uses(state)
  if not state.config.add_newline_after_trait_uses then
    return
  end
  if not parser.set_treesitter_parser(state) then
    return
  end

  -- Use_declaration within a class body represents trait uses in PHP
  local ok, query = pcall(
    parser.parse_query,
    state.lang,
    '(class_declaration body: (declaration_list (use_declaration) @trait))'
  )

  if not ok or not query then
    return
  end

  -- Collect all trait use nodes to avoid multiple modifications
  local trait_nodes = {}
  for _, node in query:iter_captures(state.root, state.bufnr, 0, -1) do
    table.insert(trait_nodes, node)
  end

  -- Process in reverse order to avoid offset issues when inserting lines
  for i = #trait_nodes, 1, -1 do
    local node = trait_nodes[i]
    local _, _, end_row, _ = node:range()
    local next_line = end_row + 1
    local lines = vim.api.nvim_buf_get_lines(state.bufnr, next_line, next_line + 1, false)
    if #lines == 0 or not utils.is_empty_line(lines[1]) then
      vim.api.nvim_buf_set_lines(state.bufnr, next_line, next_line, false, { '' })
    end
  end
end

return M
