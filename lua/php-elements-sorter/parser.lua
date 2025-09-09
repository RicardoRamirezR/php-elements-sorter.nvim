-- lua/php-elements-sorter/parser.lua
-- Tree-sitter parser helpers and queries
local M = {}
local ts = vim.treesitter
local parsers = require('nvim-treesitter.parsers')

--- Parse query with compatibility for different TS APIs
function M.parse_query(lang, query)
  if vim.treesitter and vim.treesitter.query then
    if vim.treesitter.query.parse then
      return vim.treesitter.query.parse(lang, query)
    elseif vim.treesitter.query.parse_query then
      return vim.treesitter.query.parse_query(lang, query)
    end
  end
  if ts and ts.query then
    if ts.query.parse then
      return ts.query.parse(lang, query)
    end
  end
  error('No Tree-sitter query parsing function found')
end

--- Get parser for buffer & lang with compatibility
function M.get_parser(bufnr, lang)
  if vim.treesitter.get_parser then
    return vim.treesitter.get_parser(bufnr, lang)
  end
  if parsers.get_parser then
    return parsers.get_parser(bufnr, lang)
  end
  error('No Tree-sitter parser getter found')
end

--- Setup tree-sitter parser for current buffer and write into state
function M.set_treesitter_parser(state)
  local bufnr = vim.api.nvim_get_current_buf()
  state.bufnr = bufnr

  local ok, parser = pcall(M.get_parser, bufnr, 'php')
  if not ok or not parser then
    return false
  end

  local trees = parser:parse()
  if not trees or #trees == 0 then
    return false
  end

  local tree = trees[1]
  if not tree then
    return false
  end

  state.root = tree:root()
  state.lang = parser:lang()
  return state.lang == 'php' and state.root ~= nil
end

--- Check whether buffer contains class declaration
function M.has_class(state)
  if not M.set_treesitter_parser(state) then
    return false
  end
  if state.lang ~= 'php' or not state.root then
    return false
  end

  local ok, q = pcall(M.parse_query, state.lang, '(class_declaration) @class')
  if not ok or not q then
    return false
  end

  for _, _ in q:iter_captures(state.root, state.bufnr, 0, -1) do
    return true
  end
  return false
end

--- Extract trait/const/property declarations within a given row range
-- returns traits, consts, properties, and rows table with _start/_end (0-based)
function M.extract_range(state, start_row, end_row)
  if not M.set_treesitter_parser(state) then
    return {}, {}, {}, { _start = end_row, _end = start_row }
  end

  local query_string = [[
    (use_declaration) @trait
    (const_declaration) @const
    (property_declaration) @property
  ]]

  local ok, parsed_query = pcall(M.parse_query, state.lang, query_string)
  if not ok or not parsed_query then
    return {}, {}, {}, { _start = end_row, _end = start_row }
  end

  local captures = { trait = {}, const = {}, property = {} }
  local rows = { _start = end_row, _end = start_row }

  for id, node in parsed_query:iter_captures(state.root, state.bufnr, start_row, end_row) do
    local capture_name = parsed_query.captures[id]
    if not captures[capture_name] then
      goto continue
    end

    local real_node_start_row = node:start()
    local end_row_arg = end_row == -1 and real_node_start_row + 1 or end_row

    if real_node_start_row < rows._start then
      rows._start = real_node_start_row
    end
    if real_node_start_row > rows._end then
      rows._end = real_node_start_row
    end

    if real_node_start_row >= start_row and real_node_start_row <= end_row_arg then
      local prev_sibling = node:prev_sibling()
      local comment = prev_sibling and prev_sibling:type() == 'comment' and prev_sibling or nil

      local node_start_row, _, node_end_row, _ = node:range()
      local node_lines =
          vim.api.nvim_buf_get_lines(state.bufnr, node_start_row, node_end_row + 1, false)

      local comment_lines = nil
      if comment then
        local c_start_row, _, c_end_row, _ = comment:range()
        comment_lines = vim.api.nvim_buf_get_lines(state.bufnr, c_start_row, c_end_row + 1, false)
      end

      local candidate = {
        node = node,
        comment = comment,
        node_lines = node_lines,
        comment_lines = comment_lines,
      }

      table.insert(captures[capture_name], candidate)
    end

    ::continue::
  end

  return captures.trait, captures.const, captures.property, rows
end

return M
