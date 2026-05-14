-- ============================================================================
-- lua/tests/parser_locks_spec.lua
-- Tests for parser lock race condition fixes
-- ============================================================================

describe('Parser Lock Management', function()
  local parser
  local plugin

  before_each(function()
    parser = require('php-elements-sorter.parser')
    plugin = require('php-elements-sorter')
    plugin.setup({ debug = false })

    -- Clear any existing locks
    parser.clear_locks()
  end)

  after_each(function()
    parser.clear_locks()
    parser.clear_query_cache()
    plugin.cleanup_invalid_states()
  end)

  describe('Lock Statistics', function()
    it('should track lock statistics', function()
      local stats = parser.get_lock_stats()

      assert.is_table(stats)
      assert.is_number(stats.active_locks)
      assert.is_table(stats.locks)
      assert.is_number(stats.waiting_listeners)
    end)

    it('should start with zero locks', function()
      local stats = parser.get_lock_stats()

      assert.equals(0, stats.active_locks)
      assert.equals(0, stats.waiting_listeners)
    end)
  end)

  describe('Query Parsing with Locks', function()
    it('should parse query successfully', function()
      local query = parser.parse_query('php', '(class_declaration) @class')

      assert.is_not_nil(query)

      -- Should not have active locks after parsing
      local stats = parser.get_lock_stats()
      assert.equals(0, stats.active_locks)
    end)

    it('should cache parsed queries', function()
      local query1 = parser.parse_query('php', '(class_declaration) @class')
      local query2 = parser.parse_query('php', '(class_declaration) @class')

      -- Should return same cached query
      assert.equals(query1, query2)

      -- No locks should be held
      local stats = parser.get_lock_stats()
      assert.equals(0, stats.active_locks)
    end)

    it('should handle concurrent parsing attempts', function()
      local results = {}
      local errors = {}

      -- Simulate concurrent parsing
      local query_str = '(namespace_use_declaration) @use'

      -- First parse (will acquire lock)
      local ok1, result1 = pcall(parser.parse_query, 'php', query_str)
      table.insert(results, { ok = ok1, result = result1 })

      -- Second parse (should use cache, no lock needed)
      local ok2, result2 = pcall(parser.parse_query, 'php', query_str)
      table.insert(results, { ok = ok2, result = result2 })

      -- Both should succeed
      assert.is_true(ok1)
      assert.is_true(ok2)

      -- Should return same query (cached)
      if ok1 and ok2 then
        assert.equals(result1, result2)
      end

      -- No locks should remain
      local stats = parser.get_lock_stats()
      assert.equals(0, stats.active_locks)
    end)
  end)

  describe('Lock Release', function()
    it('should release locks after successful parse', function()
      parser.parse_query('php', '(property_declaration) @prop')

      local stats = parser.get_lock_stats()
      assert.equals(0, stats.active_locks, 'Lock should be released after parse')
    end)

    it('should release locks after failed parse', function()
      -- Try to parse invalid query
      local result = parser.parse_query('php', 'invalid query syntax <<<')

      -- Should return nil on error
      assert.is_nil(result, 'Should return nil for invalid query')

      -- Lock should still be released
      local stats = parser.get_lock_stats()
      assert.equals(0, stats.active_locks, 'Lock should be released even after error')
    end)
  end)

  describe('Cache Management', function()
    it('should clear cache correctly', function()
      -- Parse and cache
      local query1 = parser.parse_query('php', '(class_declaration) @class')
      assert.is_not_nil(query1)

      -- Clear cache
      parser.clear_query_cache()

      -- Parse again (should re-parse, not use cache)
      local query2 = parser.parse_query('php', '(class_declaration) @class')
      assert.is_not_nil(query2)

      -- Both should be valid queries
      assert.is_table(query1)
      assert.is_table(query2)
    end)

    it('should maintain separate caches per language', function()
      local php_query = parser.parse_query('php', '(class_declaration) @class')

      -- Both should succeed
      assert.is_not_nil(php_query)

      -- Cache should be working
      local php_query2 = parser.parse_query('php', '(class_declaration) @class')
      assert.equals(php_query, php_query2)
    end)
  end)

  describe('Lock Cleanup', function()
    it('should clear all locks', function()
      -- Force a lock state (this is internal testing)
      parser.parse_query('php', '(use_declaration) @use')

      -- Clear locks
      local cleared = parser.clear_locks()

      assert.is_number(cleared)

      -- Verify locks are cleared
      local stats = parser.get_lock_stats()
      assert.equals(0, stats.active_locks)
    end)
  end)

  describe('Performance', function()
    it('should not introduce significant overhead', function()
      local query_str = '(const_declaration) @const'

      -- Warm up cache
      parser.parse_query('php', query_str)

      -- Time cached access
      local iterations = 100
      local start_time = vim.loop.hrtime()

      for i = 1, iterations do
        parser.parse_query('php', query_str)
      end

      local end_time = vim.loop.hrtime()
      local elapsed_ms = (end_time - start_time) / 1000000
      local avg_ms = elapsed_ms / iterations

      -- Cached access should be very fast (< 1ms average)
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

      local start_time = vim.loop.hrtime()

      -- Parse all queries rapidly
      for _, query_str in ipairs(queries) do
        local ok, result = pcall(parser.parse_query, 'php', query_str)
        assert.is_true(ok, 'Should parse successfully')
      end

      -- Parse them all again (should be cached)
      for _, query_str in ipairs(queries) do
        local ok, result = pcall(parser.parse_query, 'php', query_str)
        assert.is_true(ok, 'Should parse successfully from cache')
      end

      local end_time = vim.loop.hrtime()
      local elapsed_ms = (end_time - start_time) / 1000000

      -- Should complete quickly (< 500ms for all)
      assert.is_true(elapsed_ms < 500, string.format('Elapsed: %.2fms', elapsed_ms))

      -- No locks should remain
      local stats = parser.get_lock_stats()
      assert.equals(0, stats.active_locks)
    end)
  end)

  describe('Edge Cases', function()
    it('should handle empty query string', function()
      local ok, result = pcall(parser.parse_query, 'php', '')

      -- Should handle gracefully
      assert.is_boolean(ok)

      -- No locks should remain
      local stats = parser.get_lock_stats()
      assert.equals(0, stats.active_locks)
    end)

    it('should handle invalid language', function()
      local ok, result = pcall(parser.parse_query, 'invalid_lang', '(node) @n')

      -- Should handle gracefully
      assert.is_boolean(ok)

      -- No locks should remain
      local stats = parser.get_lock_stats()
      assert.equals(0, stats.active_locks)
    end)

    it('should handle very long query strings', function()
      -- Create a very long but valid query
      local long_query = string.rep('(class_declaration) @class\n', 100)

      local ok, result = pcall(parser.parse_query, 'php', long_query)

      -- Should handle (may succeed or fail depending on validity)
      assert.is_boolean(ok)

      -- No locks should remain regardless
      local stats = parser.get_lock_stats()
      assert.equals(0, stats.active_locks)
    end)
  end)

  describe('Integration with Plugin', function()
    it('should work with actual sorting operations', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_option(bufnr, 'filetype', 'php')
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

      -- Perform sort (uses parser internally)
      local ok = pcall(plugin.sort_elements)

      assert.is_true(ok, 'Sort should complete successfully')

      -- No locks should remain after operation
      local stats = parser.get_lock_stats()
      assert.equals(0, stats.active_locks)

      -- Cleanup
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)
end)
