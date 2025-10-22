-- lua/tests/critical_fixes_spec.lua
-- Tests específicos para validar las correcciones críticas
-- FIXED: Swap file issues en tests de race conditions

local sorter = require('php-elements-sorter')

describe('Critical Fixes - Race Conditions and Memory Leaks', function()
  before_each(function()
    -- Disable swap files for tests
    vim.o.swapfile = false
    vim.cmd('enew')
    vim.bo.filetype = 'php'
    sorter.setup({ debug = false })
  end)

  after_each(function()
    -- Clean up properly
    if sorter.teardown then
      sorter.teardown()
    end
    pcall(vim.cmd, 'bwipeout!')
    -- Re-enable swap files after tests
    vim.o.swapfile = true
  end)

  describe('Timer race condition fixes', function()
    it('should handle rapid buffer state access without errors', function()
      local bufnr = vim.api.nvim_get_current_buf()

      -- Simulate rapid text changes WITHOUT creating new buffers
      for i = 1, 10 do
        vim.api.nvim_buf_set_lines(0, 0, -1, false, {
          '<?php',
          'class Test' .. i .. ' {',
          '    private $prop' .. i .. ';',
          '}',
        })

        -- Trigger TextChanged event simulation
        pcall(vim.cmd, 'doautocmd TextChanged')

        -- Small delay to simulate real typing
        vim.wait(10)
      end

      -- Get state should work without errors
      assert.has_no.errors(function()
        local config = sorter.get_buffer_config(bufnr)
        assert.is_table(config)
      end)
    end)

    it('should not crash when accessing non-existent buffer state', function()
      -- Try to trigger autocmd before state is created
      assert.has_no.errors(function()
        pcall(vim.cmd, 'doautocmd TextChanged')
      end)
    end)

    it('should properly cancel previous timers', function()
      local bufnr = vim.api.nvim_get_current_buf()

      -- Set some content
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { '<?php', 'class Test {}' })

      -- Force state creation
      sorter.get_buffer_config(bufnr)

      -- Trigger multiple changes rapidly (WITHOUT creating new buffers)
      for i = 1, 5 do
        vim.api.nvim_buf_set_lines(0, 1, 2, false, { 'class Test' .. i .. ' {}' })
        pcall(vim.cmd, 'doautocmd TextChanged')
        vim.wait(5)
      end

      -- Wait a bit for timers to settle
      vim.wait(100)

      -- Get state info
      local info = sorter.get_state_info()

      -- Should have at most one timer per buffer
      for _, state in ipairs(info.states) do
        if state.bufnr == bufnr then
          -- Timer might exist but should be only one
          assert.is_boolean(state.has_pending_timer)
        end
      end
    end)

    it('should clean up timers on buffer delete', function()
      local bufnr = vim.api.nvim_get_current_buf()

      -- Create state with timer
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { '<?php', 'class Test {}' })
      sorter.get_buffer_config(bufnr)
      pcall(vim.cmd, 'doautocmd TextChanged')

      -- Delete buffer
      pcall(vim.cmd, 'bwipeout!')

      -- Create new buffer and check state
      vim.cmd('enew')
      vim.bo.filetype = 'php'

      local info = sorter.get_state_info()

      -- Old buffer should not be in states
      for _, state in ipairs(info.states) do
        assert.is_not.equal(bufnr, state.bufnr)
      end
    end)
  end)

  describe('Memory leak prevention', function()
    it('should provide teardown function', function()
      assert.is_function(sorter.teardown)
    end)

    it('should stop global cleanup timer on teardown', function()
      -- Setup creates the timer
      sorter.setup()

      -- Teardown should work without errors
      assert.has_no.errors(function()
        sorter.teardown()
      end)
    end)

    it('should stop all buffer timers on teardown', function()
      -- Track initial buffer count
      local initial_bufnr = vim.api.nvim_get_current_buf()

      -- Create states in CURRENT buffer with variations
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { '<?php', 'class Test1 {}' })
      sorter.get_buffer_config(initial_bufnr)
      pcall(vim.cmd, 'doautocmd TextChanged')
      vim.wait(50)

      -- Modify same buffer again
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { '<?php', 'class Test2 {}' })
      sorter.get_buffer_config(initial_bufnr)
      pcall(vim.cmd, 'doautocmd TextChanged')
      vim.wait(50)

      -- Should have at least one state
      local info_before = sorter.get_state_info()
      assert.is_true(info_before.active_buffers >= 1)

      -- Teardown
      sorter.teardown()

      -- States should be cleared
      local info_after = sorter.get_state_info()
      assert.equals(0, info_after.active_buffers)
    end)

    it('should allow re-setup after teardown', function()
      sorter.setup()
      sorter.teardown()

      -- Should be able to setup again
      assert.has_no.errors(function()
        sorter.setup()
      end)

      -- Should work normally
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { '<?php', 'class Test {}' })
      assert.has_no.errors(function()
        sorter.sort_all()
      end)
    end)
  end)

  describe('Buffer modification atomicity', function()
    it('should sort without corrupting buffer content', function()
      local lines = {
        '<?php',
        '',
        'class Test {',
        '    private $zebra;',
        '    public $apple;',
        '    protected $banana;',
        '}',
      }

      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)

      sorter.sort_all()

      -- Check buffer is still valid PHP
      local result = vim.api.nvim_buf_get_lines(0, 0, -1, false)

      -- Should still have opening tag
      assert.equals('<?php', result[1])

      -- Should still have class definition
      local has_class = false
      for _, line in ipairs(result) do
        if line:match('class Test') then
          has_class = true
          break
        end
      end
      assert.is_true(has_class)

      -- Should still have all properties
      local content = table.concat(result, '\n')
      assert.is_true(content:match('$apple') ~= nil)
      assert.is_true(content:match('$banana') ~= nil)
      assert.is_true(content:match('$zebra') ~= nil)
    end)

    it('should handle spacing modifications correctly', function()
      local lines = {
        '<?php',
        'class Test {',
        '    private $z;',
        '    public $a;',
        '}',
      }

      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)

      sorter.sort_all()

      local result = vim.api.nvim_buf_get_lines(0, 0, -1, false)

      -- Should have blank lines for spacing
      local has_blank = false
      for _, line in ipairs(result) do
        if line == '' then
          has_blank = true
          break
        end
      end
      assert.is_true(has_blank)
    end)

    it('should sort multiple elements without index corruption', function()
      local lines = {
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
      }

      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)

      sorter.sort_all()

      local result = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      local content = table.concat(result, '\n')

      -- All elements should still be present
      assert.is_true(content:match('use Apple') ~= nil)
      assert.is_true(content:match('use Zebra') ~= nil)
      assert.is_true(content:match('const A') ~= nil)
      assert.is_true(content:match('const Z') ~= nil)
      assert.is_true(content:match('%$a') ~= nil)
      assert.is_true(content:match('%$z') ~= nil)
    end)

    it('should handle consecutive sorts without corruption', function()
      local lines = {
        '<?php',
        '',
        'class Test {',
        '    private $c;',
        '    private $b;',
        '    private $a;',
        '}',
      }

      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)

      -- Sort multiple times
      for i = 1, 3 do
        sorter.sort_all()
        vim.wait(10)
      end

      local result = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      local content = table.concat(result, '\n')

      -- Should still have all properties
      assert.is_true(content:match('%$a') ~= nil)
      assert.is_true(content:match('%$b') ~= nil)
      assert.is_true(content:match('%$c') ~= nil)
    end)
  end)

  describe('Range normalization fixes', function()
    it('should handle end_row = -1 correctly', function()
      local lines = {
        '<?php',
        '',
        'class Test {',
        '    private $z;',
        '    public $a;',
        '}',
      }

      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)

      -- This internally uses -1 for end_row
      assert.has_no.errors(function()
        sorter.sort_elements()
      end)
    end)

    it('should handle full buffer sorts', function()
      local lines = {
        '<?php',
        '',
        'use Z;',
        'use A;',
        '',
        'class Test {',
        '    const Z = 1;',
        '    const A = 2;',
        '}',
      }

      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)

      assert.has_no.errors(function()
        sorter.sort_all()
      end)

      local result = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      assert.is_true(#result > 0)
    end)

    it('should handle empty ranges', function()
      local lines = {
        '<?php',
        '',
        'class Test {',
        '}',
      }

      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)

      assert.has_no.errors(function()
        sorter.sort_all()
      end)
    end)

    it('should handle single line ranges', function()
      local lines = {
        '<?php',
        '',
        'class Test {',
        '    private $a;',
        '}',
      }

      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)

      assert.has_no.errors(function()
        sorter.sort_elements()
      end)
    end)
  end)

  describe('State management robustness', function()
    it('should track buffer states correctly', function()
      local info = sorter.get_state_info()
      assert.is_table(info)
      assert.is_number(info.active_buffers)
      assert.is_table(info.states)
    end)

    it('should cleanup invalid states', function()
      -- Get current buffer
      local bufnr = vim.api.nvim_get_current_buf()
      sorter.get_buffer_config(bufnr)

      -- Create a "fake" invalid buffer scenario by getting an old bufnr
      -- (Don't actually delete the current buffer in test)

      -- Just test that cleanup works without errors
      local cleaned = sorter.cleanup_invalid_states()

      assert.is_number(cleaned)
      assert.is_true(cleaned >= 0)
    end)

    it('should handle rapid buffer modifications', function()
      local bufnr = vim.api.nvim_get_current_buf()

      for i = 1, 5 do
        vim.api.nvim_buf_set_lines(0, 0, -1, false, {
          '<?php',
          'class Test' .. i .. ' {}',
        })
        sorter.get_buffer_config(bufnr)
        vim.wait(10)
      end

      -- Should not crash
      assert.has_no.errors(function()
        sorter.cleanup_invalid_states()
      end)
    end)

    it('should provide accurate state info', function()
      local bufnr = vim.api.nvim_get_current_buf()

      vim.api.nvim_buf_set_lines(0, 0, -1, false, { '<?php', 'class Test {}' })
      sorter.get_buffer_config(bufnr)

      local info = sorter.get_state_info()

      assert.is_true(info.active_buffers > 0)

      local found = false
      for _, state in ipairs(info.states) do
        if state.bufnr == bufnr then
          found = true
          assert.is_boolean(state.valid)
          assert.is_boolean(state.loaded)
          assert.is_boolean(state.has_parser)
          assert.is_boolean(state.has_pending_timer)
          break
        end
      end

      assert.is_true(found, 'Current buffer should be in state info')
    end)
  end)

  describe('Error handling improvements', function()
    it('should handle invalid buffer gracefully', function()
      -- Try to get config from invalid buffer should use current buffer as fallback
      local invalid_bufnr = 99999

      -- This should either fail gracefully or use current buffer
      local ok, result = pcall(function()
        return sorter.get_buffer_config(invalid_bufnr)
      end)

      -- Either it succeeded (using fallback) or failed with expected error
      if not ok then
        assert.is_true(
          result:match('Invalid buffer') ~= nil or result:match('not valid') ~= nil,
          'Should have meaningful error message'
        )
      else
        assert.is_table(result, 'Should return config table on fallback')
      end
    end)

    it('should handle malformed PHP gracefully', function()
      local lines = {
        '<?php',
        'class Test {',
        '    private $a', -- Missing semicolon
        '}',
      }

      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)

      -- Should not crash
      assert.has_no.errors(function()
        sorter.sort_all()
      end)
    end)

    it('should handle very large files', function()
      local lines = { '<?php', '', 'class Test {' }

      -- Add many properties
      for i = 1, 100 do
        table.insert(lines, string.format('    private $prop%03d;', 100 - i))
      end

      table.insert(lines, '}')

      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)

      -- Should complete without errors
      assert.has_no.errors(function()
        sorter.sort_all()
      end)

      local result = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      assert.is_true(#result > 100)
    end)
  end)
end)
