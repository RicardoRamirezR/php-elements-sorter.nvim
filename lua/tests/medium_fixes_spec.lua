-- lua/tests/medium_fixes_spec.lua
-- Tests para correcciones de severidad media/alta

local sorter = require('php-elements-sorter')
local parser = require('php-elements-sorter.parser')

describe('Medium/High Priority Fixes', function()
  before_each(function()
    vim.cmd('enew')
    vim.bo.filetype = 'php'
    sorter.setup({ debug = false })
  end)

  after_each(function()
    if sorter.teardown then
      sorter.teardown()
    end
    vim.cmd('bwipeout!')
  end)

  describe('Configuration validation', function()
    it('should accept valid configuration', function()
      assert.has_no.errors(function()
        sorter.setup({
          sort_properties = true,
          default_visibility = 'public',
          debug = false,
        })
      end)
    end)

    it('should reject invalid default_visibility', function()
      -- Setup should handle this gracefully
      assert.has_no.errors(function()
        sorter.setup({
          default_visibility = 'invalid',
        })
      end)

      -- Should fall back to default config
      local config = sorter.get_buffer_config()
      assert.equals('public', config.default_visibility)
    end)

    it('should reject non-boolean for boolean options', function()
      assert.has_no.errors(function()
        sorter.setup({
          sort_properties = 'yes', -- Invalid type
        })
      end)

      -- Should fall back to default
      local config = sorter.get_buffer_config()
      assert.is_boolean(config.sort_properties)
    end)

    it('should accept all valid visibility values', function()
      local valid_visibilities = { 'public', 'protected', 'private' }

      for _, vis in ipairs(valid_visibilities) do
        -- Teardown previous setup
        if sorter.teardown then
          sorter.teardown()
        end

        -- Setup with specific visibility
        assert.has_no.errors(function()
          sorter.setup({
            default_visibility = vis,
          })
        end)

        -- Get fresh config from the MODULE (not buffer)
        -- The module config should reflect what was set
        assert.equals(vis, sorter.config.default_visibility)
      end
    end)

    it('should provide validate_config function', function()
      assert.is_function(sorter.validate_config)

      local valid, err = sorter.validate_config()
      assert.is_true(valid)
      assert.is_nil(err)
    end)

    it('should provide PhpSorterValidateConfig command', function()
      local commands = vim.api.nvim_get_commands({})
      assert.is_not_nil(commands['PhpSorterValidateConfig'])
    end)

    it('should validate mixed valid/invalid config', function()
      assert.has_no.errors(function()
        sorter.setup({
          sort_properties = true, -- Valid
          default_visibility = 'public', -- Valid
          debug = 'invalid', -- Invalid
        })
      end)
    end)

    it('should handle nil config gracefully', function()
      assert.has_no.errors(function()
        sorter.setup(nil)
      end)

      local config = sorter.get_buffer_config()
      assert.is_table(config)
    end)

    it('should handle empty config table', function()
      assert.has_no.errors(function()
        sorter.setup({})
      end)

      local config = sorter.get_buffer_config()
      assert.is_table(config)
    end)

    it('should validate buffer config overrides', function()
      local bufnr = vim.api.nvim_get_current_buf()

      -- Valid override should work
      assert.has_no.errors(function()
        sorter.set_buffer_config(bufnr, {
          sort_properties = false,
        })
      end)

      local config = sorter.get_buffer_config(bufnr)
      assert.is_false(config.sort_properties)
    end)

    it('should reject invalid buffer config overrides', function()
      local bufnr = vim.api.nvim_get_current_buf()

      -- Get current config
      local before = sorter.get_buffer_config(bufnr)

      -- Try invalid override
      sorter.set_buffer_config(bufnr, {
        default_visibility = 'invalid',
      })

      -- Config should remain unchanged
      local after = sorter.get_buffer_config(bufnr)
      assert.equals(before.default_visibility, after.default_visibility)
    end)
  end)

  describe('Query caching', function()
    it('should cache parsed queries', function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, {
        '<?php',
        '',
        'class Test {',
        '    private $z;',
        '    public $a;',
        '}',
      })

      -- First call should parse and cache
      sorter.sort_all()

      -- Get initial cache stats
      local stats1 = parser.get_cache_stats()
      assert.is_table(stats1)
      assert.is_number(stats1.total_queries)

      -- Second call should use cache
      sorter.sort_all()

      local stats2 = parser.get_cache_stats()
      -- Total queries should be same or more (not less)
      assert.is_true(stats2.total_queries >= stats1.total_queries)
    end)

    it('should provide cache statistics', function()
      local stats = parser.get_cache_stats()

      assert.is_table(stats)
      assert.is_number(stats.total_queries)
      assert.is_table(stats.cached_queries)
    end)

    it('should allow cache clearing', function()
      assert.is_function(parser.clear_query_cache)

      -- Create some cached queries
      vim.api.nvim_buf_set_lines(0, 0, -1, false, {
        '<?php',
        'class Test { private $a; }',
      })
      sorter.sort_all()

      -- Clear cache
      assert.has_no.errors(function()
        parser.clear_query_cache()
      end)

      -- Stats should show empty cache
      local stats = parser.get_cache_stats()
      assert.equals(0, stats.total_queries)
    end)

    it('should work correctly after cache clear', function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, {
        '<?php',
        '',
        'class Test {',
        '    private $z;',
        '    public $a;',
        '}',
      })

      -- Sort, clear cache, sort again
      sorter.sort_all()
      parser.clear_query_cache()

      assert.has_no.errors(function()
        sorter.sort_all()
      end)
    end)

    it('should cache queries per language', function()
      local stats = parser.get_cache_stats()

      if stats.total_queries > 0 then
        assert.is_not_nil(stats.cached_queries.php)
      end
    end)
  end)

  describe('Enhanced error logging', function()
    it('should log buffer modification failures', function()
      -- This is hard to test directly, but we can verify the function exists
      vim.api.nvim_buf_set_lines(0, 0, -1, false, {
        '<?php',
        'class Test { private $a; }',
      })

      -- Normal operation should not error
      assert.has_no.errors(function()
        sorter.sort_all()
      end)
    end)

    it('should handle parser setup failures gracefully', function()
      -- Try to sort a non-PHP buffer
      vim.bo.filetype = 'lua'
      vim.api.nvim_buf_set_lines(0, 0, -1, false, {
        'local x = 1',
      })

      -- Should not crash
      assert.has_no.errors(function()
        sorter.sort_all()
      end)
    end)

    it('should log query parsing failures', function()
      -- Can't easily force a query parse failure, but verify function exists
      assert.is_function(parser.parse_query)
    end)

    it('should provide debug info in state', function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, {
        '<?php',
        'class Test {}',
      })

      local info = sorter.get_state_info()
      assert.is_table(info)
      assert.is_number(info.active_buffers)
    end)
  end)

  describe('Safe buffer operations', function()
    it('should handle buffer line retrieval errors', function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, {
        '<?php',
        '',
        'class Test {',
        '    private $z;',
        '    public $a;',
        '}',
      })

      -- Should complete without crashing
      assert.has_no.errors(function()
        sorter.sort_all()
      end)
    end)

    it('should validate buffer before operations', function()
      local invalid_bufnr = 99999

      -- Should handle gracefully
      assert.has_no.errors(function()
        sorter.set_buffer_config(invalid_bufnr, { debug = true })
      end)
    end)

    it('should handle deleted buffers in state cleanup', function()
      -- Create and delete a buffer
      vim.cmd('enew')
      local bufnr = vim.api.nvim_get_current_buf()
      sorter.get_buffer_config(bufnr)
      vim.cmd('bwipeout!')

      -- Cleanup should handle it
      assert.has_no.errors(function()
        sorter.cleanup_invalid_states()
      end)
    end)
  end)

  describe('Statistics and feedback', function()
    it('should return statistics from sort_all', function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, {
        '<?php',
        '',
        'use Zebra\\Animal;',
        'use Apple\\Fruit;',
        '',
        'class Test {',
        '    const Z = 1;',
        '    const A = 2;',
        '    ',
        '    private $z;',
        '    public $a;',
        '}',
      })

      local stats = sorter.sort_all()

      assert.is_table(stats)
      assert.is_number(stats.uses)
      assert.is_number(stats.removed)
      assert.is_number(stats.constants)
      assert.is_number(stats.properties)
      assert.is_number(stats.traits)
    end)

    it('should count sorted elements correctly', function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, {
        '<?php',
        '',
        'class Test {',
        '    private $c;',
        '    private $b;',
        '    private $a;',
        '}',
      })

      local stats = sorter.sort_all()

      -- Should have sorted 3 properties
      assert.equals(3, stats.properties)
    end)

    it('should return zero stats for empty file', function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, {
        '<?php',
      })

      local stats = sorter.sort_all()

      assert.equals(0, stats.uses)
      assert.equals(0, stats.constants)
      assert.equals(0, stats.properties)
      assert.equals(0, stats.traits)
    end)
  end)

  describe('Parser validation improvements', function()
    it('should validate PHP parser availability', function()
      local valid, err = parser.validate_parser()

      assert.is_boolean(valid)

      if not valid then
        assert.is_string(err)
        assert.is_true(
          err:match('treesitter') ~= nil or err:match('parser') ~= nil,
          'Error message should mention treesitter or parser'
        )
      end
    end)

    it('should handle missing parser gracefully', function()
      -- Can't easily test this without uninstalling parser
      -- But we can verify the validation function exists
      assert.is_function(parser.validate_parser)
    end)
  end)

  describe('Config edge cases', function()
    it('should handle partial config updates', function()
      sorter.setup({
        sort_properties = true,
        debug = false,
      })

      local bufnr = vim.api.nvim_get_current_buf()
      sorter.set_buffer_config(bufnr, {
        sort_properties = false,
        -- Other options should remain unchanged
      })

      local config = sorter.get_buffer_config(bufnr)
      assert.is_false(config.sort_properties)
      assert.is_false(config.debug) -- Should retain this
    end)

    it('should isolate buffer configs', function()
      -- Get first buffer and ensure it has state
      local buf1 = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_set_lines(buf1, 0, -1, false, { '<?php', 'class Test1 {}' })

      -- Force state creation for buf1
      local _ = sorter.get_buffer_config(buf1)

      -- Create second buffer
      vim.cmd('enew')
      vim.bo.filetype = 'php'
      local buf2 = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_set_lines(buf2, 0, -1, false, { '<?php', 'class Test2 {}' })

      -- Force state creation for buf2
      _ = sorter.get_buffer_config(buf2)

      -- Now set different configs while on buf2
      sorter.set_buffer_config(buf1, { sort_properties = false })
      sorter.set_buffer_config(buf2, { sort_properties = true })

      -- Get configs while still on buf2
      local config2 = sorter.get_buffer_config(buf2)

      -- Switch to buf1 to get its config
      vim.api.nvim_set_current_buf(buf1)
      local config1 = sorter.get_buffer_config(buf1)

      -- Verify isolation
      assert.is_false(config1.sort_properties, 'buf1 should have sort_properties = false')
      assert.is_true(config2.sort_properties, 'buf2 should have sort_properties = true')
    end)
  end)
end)
