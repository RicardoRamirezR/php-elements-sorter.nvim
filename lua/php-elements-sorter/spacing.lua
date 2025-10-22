-- ============================================================================
-- lua/php-elements-sorter/spacing.lua
-- Spacing utilities - Refactorizado para usar utils/spacing
-- MEJORA #4: Eliminar duplicación usando spacing utilities centralizadas
-- ============================================================================

local M = {}

local parser = require('php-elements-sorter.parser')
local spacing_utils = require('php-elements-sorter.utils.spacing')

--- Ensure exactly one empty line before the first use and after the last use
---@param state table Plugin state
function M.add_spacing_around_namespace_uses(state)
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

  local first_use, last_use = nil, nil

  for _, node in query:iter_captures(state.root, state.bufnr, 0, -1) do
    local s, _, e, _ = node:range()
    first_use = first_use or s
    last_use = e
  end

  if not first_use then
    return
  end

  -- Use spacing utilities instead of manual checks
  spacing_utils.ensure_blank_before(state.bufnr, first_use)
  spacing_utils.ensure_blank_after(state.bufnr, last_use + 1)
end

--- Ensure exactly one empty line before first and after last member in a class
---@param state table Plugin state
function M.add_spacing_around_class_members(state)
  if not parser.set_treesitter_parser(state) then
    return
  end

  local ok, query = pcall(
    parser.parse_query,
    state.lang,
    '(class_declaration body: (declaration_list (_) @member))'
  )
  if not ok or not query then
    return
  end

  local members = {}

  for _, node in query:iter_captures(state.root, state.bufnr, 0, -1) do
    table.insert(members, node)
  end

  if #members == 0 then
    return
  end

  local first_member = members[1]
  local last_member = members[#members]

  -- Use spacing utilities
  local s, _, _, _ = first_member:range()
  spacing_utils.ensure_blank_before(state.bufnr, s)

  local _, _, e, _ = last_member:range()
  spacing_utils.ensure_blank_after(state.bufnr, e + 1)
end

--- Spacing after namespace uses
---@param state table Plugin state
function M.add_spacing_after_namespace_uses(state)
  if not state.config.add_newline_after_namespace_uses then
    return
  end
  if not parser.set_treesitter_parser(state) then
    return
  end

  local ok, query = pcall(parser.parse_query, state.lang, '(namespace_use_declaration) @use')
  if not ok or not query then
    return
  end

  local last_use_line = nil

  for _, node in query:iter_captures(state.root, state.bufnr, 0, -1) do
    local _, _, end_row, _ = node:range()
    last_use_line = end_row
  end

  if last_use_line then
    -- Use spacing utility
    spacing_utils.ensure_blank_after(state.bufnr, last_use_line + 1)
  end
end

--- Spacing after trait uses (corrected query)
---@param state table Plugin state
function M.add_spacing_after_trait_uses(state)
  if not state.config.add_newline_after_trait_uses then
    return
  end
  if not parser.set_treesitter_parser(state) then
    return
  end

  -- Correct query for trait uses within classes
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

    -- Use spacing utility instead of manual check
    spacing_utils.ensure_blank_after(state.bufnr, end_row + 1)
  end
end

return M
