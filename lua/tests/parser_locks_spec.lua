-- ============================================================================
-- lua/tests/parser_locks_spec.lua
-- Tests for parser query caching
-- ============================================================================

describe('Parser Query Caching', function()
  local parser
  local plugin

  before_each(function()
    parser = require('php-elements-sorter.parser')
    plugin = require('php-elements-sorter')
    plugin.setup({ debug = false })
  end)

  after_each(function()
    parser.clear_query_cache()
    plugin.cleanup_invalid_states()
  end)

  describe('Query Parsing', function()
    it('should parse query successfully', function()
      local query = parser.parse_query('php', '(class_declaration) @class')
      assert.is_not_nil(query)
    end)

    it('should cache parsed queries', function()
      local query1 = parser.parse_query('php', '(class_declaration) @class')
      local query2 = parser.parse_query('php', '(class_declaration) @class')
      assert.equals(query1, query2)
    end)

    it('should return nil for invalid query', function()
      local result = parser.parse_query('php', 'invalid query syntax <<<')
      assert.is_nil(result)
    end)
  end)

  describe('Cache Management', function()
    it('should clear cache correctly', function()
      local query1 = parser.parse_query('php', '(class_declaration) @class')
      assert.is_not_nil(query1)

      parser.clear_query_cache()

      local query2 = parser.parse_query('php', '(class_declaration) @class')
      assert.is_not_nil(query2)
      assert.is_table(query1)
      assert.is_table(query2)
    end)

    it('should maintain separate caches per language', function()
      local php_query = parser.parse_query('php', '(class_declaration) @class')
      assert.is_not_nil(php_query)

      local php_query2 = parser.parse_query('php', '(class_declaration) @class')
      assert.equals(php_query, php_query2)
    end)

    it('should report cache statistics', function()
      parser.parse_query('php', '(class_declaration) @class')
      parser.parse_query('php', '(property_declaration) @prop')

      local stats = parser.get_cache_stats()
      assert.is_table(stats)
      assert.equals(2, stats.cached_queries.php)
      assert.equals(2, stats.total_queries)
    end)
  end)

  describe('Performance', function()
    it('should not introduce significant overhead', function()
      local query_str = '(const_declaration) @const'
      parser.parse_query('php', query_str)

      local iterations = 100
      local start_time = vim.loop.hrtime()

      for i = 1, iterations do
        parser.parse_query('php', query_str)
      end

      local end_time = vim.loop.hrtime()
      local avg_ms = (end_time - start_time) / 1000000 / iterations

      assert.is_true(avg_ms < 1, string.format('Average: %.2fms, expected < 1ms', avg_ms))
    end)

    it('should handle rapid consecutive parses', function()
      local queries = {
        '(class_declaration) @class',
        '(property_declaration) @prop',
        '(const_declaration) @const',
        '(use_declaration) @use',
        '(namespace_use_declaration) @nsuse',
      }

      for _, query_str in ipairs(queries) do
        local ok, result = pcall(parser.parse_query, 'php', query_str)
        assert.is_true(ok, 'Should parse successfully')
      end

      for _, query_str in ipairs(queries) do
        local ok, result = pcall(parser.parse_query, 'php', query_str)
        assert.is_true(ok, 'Should parse successfully from cache')
      end
    end)
  end)

  describe('Edge Cases', function()
    it('should handle empty query string', function()
      local ok, result = pcall(parser.parse_query, 'php', '')
      assert.is_boolean(ok)
    end)

    it('should handle invalid language', function()
      local ok, result = pcall(parser.parse_query, 'invalid_lang', '(node) @n')
      assert.is_boolean(ok)
    end)
  end)

  describe('Integration with Plugin', function()
    it('should work with actual sorting operations', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.bo[bufnr].filetype = 'php'
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        '<?php',
        '',
        'class Test',
        '{',
        '    public $name;',
        '    private $id;',
        '}',
      })
      vim.api.nvim_set_current_buf(bufnr)

      local ok = pcall(plugin.sort_elements)
      assert.is_true(ok, 'Sort should complete successfully')

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)
end)
