-- ============================================================================
-- lua/php-elements-sorter/parser.lua
-- Tree-sitter parser helpers and queries with caching
-- ============================================================================

local M = {}
local ts = vim.treesitter

local parsers = require('nvim-treesitter.parsers')
local log = require('php-elements-sorter.utils.log')

-- Query cache to avoid repeated parsing
local query_cache = {}

local function simple_hash(str)
  local hash = 0
  for i = 1, #str do
    hash = (hash * 31 + str:byte(i)) % (2 ^ 31 - 1)
  end
  return tostring(hash)
end

--- Clear query cache
function M.clear_query_cache()
  query_cache = {}
  log.debug('Query cache cleared')
end

--- Get cache statistics
---@return table stats
function M.get_cache_stats()
  local result = {
    total_queries = 0,
    cached_queries = {},
  }

  for lang, queries in pairs(query_cache) do
    result.total_queries = result.total_queries + vim.tbl_count(queries)
    result.cached_queries[lang] = vim.tbl_count(queries)
  end

  return result
end

--- Validate that PHP parser is available
---@return boolean success, string? error_message
function M.validate_parser()
  local has_ts, _ = pcall(require, 'nvim-treesitter.parsers')
  if not has_ts then
    return false, 'nvim-treesitter not available'
  end

  local has_php = parsers.has_parser('php')
  if not has_php then
    return false, 'PHP parser not installed. Run :TSInstall php'
  end

  return true, nil
end

--- Parse query with compatibility for different TS APIs and caching
---@param lang string Language name
---@param query_string string Query string
---@return table? query Parsed query or nil
function M.parse_query(lang, query_string)
  if not query_cache[lang] then
    query_cache[lang] = {}
  end

  local cache_key = simple_hash(query_string)

  if query_cache[lang][cache_key] then
    return query_cache[lang][cache_key]
  end

  local query = nil
  local parse_ok = false

  if vim.treesitter and vim.treesitter.query then
    if vim.treesitter.query.parse then
      parse_ok, query = pcall(vim.treesitter.query.parse, lang, query_string)
    elseif vim.treesitter.query.parse_query then
      parse_ok, query = pcall(vim.treesitter.query.parse_query, lang, query_string)
    end
  end

  if not parse_ok or not query then
    if ts and ts.query and ts.query.parse then
      parse_ok, query = pcall(ts.query.parse, lang, query_string)
    end
  end

  if not parse_ok then
    log.error(string.format('Failed to parse query for %s: %s', lang, tostring(query)))
    return nil
  end

  if not query then
    log.error('No Tree-sitter query parsing function found')
    return nil
  end

  query_cache[lang][cache_key] = query
  return query
end

--- Get parser for buffer & lang with compatibility
---@param bufnr number Buffer number
---@param lang string Language name
---@return table? parser Parser instance or nil
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
---@param state table Plugin state
---@return boolean success
function M.set_treesitter_parser(state)
  local bufnr = vim.api.nvim_get_current_buf()
  state.bufnr = bufnr

  local ok, parser = pcall(M.get_parser, bufnr, 'php')
  if not ok or not parser then
    log.debug(string.format('Failed to get parser for buffer %d: %s', bufnr, tostring(parser)))
    return false
  end

  local trees = parser:parse()
  if not trees or #trees == 0 then
    log.debug('Parser returned no trees')
    return false
  end

  local tree = trees[1]
  if not tree then
    log.debug('First tree is nil')
    return false
  end

  state.root = tree:root()
  state.lang = parser:lang()

  local success = state.lang == 'php' and state.root ~= nil

  if success then
    log.debug(string.format('Parser setup successful for buffer %d', bufnr))
  else
    log.debug(string.format('Parser setup failed for buffer %d', bufnr))
  end

  return success
end

--- Check whether buffer contains class declaration
---@param state table Plugin state
---@return boolean has_class
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

--- Normalize row range, handling -1 as "end of buffer"
---@param bufnr number Buffer number
---@param start_row number Start row (0-based)
---@param end_row number End row (0-based, -1 for end of buffer)
---@return number start_row, number end_row
local function normalize_range(bufnr, start_row, end_row)
  start_row = math.max(0, start_row)

  if end_row == -1 then
    end_row = vim.api.nvim_buf_line_count(bufnr) - 1
  end

  end_row = math.max(start_row, end_row)

  return start_row, end_row
end

--- Extract trait/const/property declarations within a given row range
---@param state table Plugin state
---@param start_row number Start row (0-based)
---@param end_row number End row (0-based, -1 for end of buffer)
---@return table traits, table consts, table properties, table rows
function M.extract_range(state, start_row, end_row)
  if not M.set_treesitter_parser(state) then
    return {}, {}, {}, { _start = start_row, _end = end_row }
  end

  start_row, end_row = normalize_range(state.bufnr, start_row, end_row)

  local query_string = [[
    (use_declaration) @trait
    (const_declaration) @const
    (property_declaration) @property
  ]]

  local ok, parsed_query = pcall(M.parse_query, state.lang, query_string)
  if not ok or not parsed_query then
    log.error('Failed to parse range extraction query: ' .. tostring(parsed_query))
    return {}, {}, {}, { _start = start_row, _end = end_row }
  end

  local captures = { trait = {}, const = {}, property = {} }
  local rows = { _start = end_row, _end = start_row }

  for id, node in parsed_query:iter_captures(state.root, state.bufnr, start_row, end_row + 1) do
    local capture_name = parsed_query.captures[id]
    if not captures[capture_name] then
      goto continue
    end

    local node_start_row = node:start()

    if node_start_row < rows._start then
      rows._start = node_start_row
    end
    if node_start_row > rows._end then
      rows._end = node_start_row
    end

    if node_start_row >= start_row and node_start_row <= end_row then
      local prev_sibling = node:prev_sibling()
      local comment = prev_sibling and prev_sibling:type() == 'comment' and prev_sibling or nil

      local node_start_line, _, node_end_line, _ = node:range()

      local ok_lines, node_lines =
        pcall(vim.api.nvim_buf_get_lines, state.bufnr, node_start_line, node_end_line + 1, false)

      if not ok_lines then
        log.warn(string.format('Failed to get lines %d-%d from buffer %d', node_start_line, node_end_line, state.bufnr))
        goto continue
      end

      local comment_lines = nil
      if comment then
        local c_start_line, _, c_end_line, _ = comment:range()
        local ok_comment, c_lines =
          pcall(vim.api.nvim_buf_get_lines, state.bufnr, c_start_line, c_end_line + 1, false)
        if ok_comment then
          comment_lines = c_lines
        end
      end

      table.insert(captures[capture_name], {
        node = node,
        comment = comment,
        node_lines = node_lines,
        comment_lines = comment_lines,
      })
    end

    ::continue::
  end

  log.debug(string.format(
    'Extracted range [%d-%d]: %d traits, %d consts, %d properties',
    start_row, end_row, #captures.trait, #captures.const, #captures.property
  ))

  return captures.trait, captures.const, captures.property, rows
end

return M
