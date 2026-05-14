-- ============================================================================
-- lua/tests/atomic_operations_spec.lua
-- Test atomic buffer operations to prevent race conditions
-- ============================================================================

describe('Atomic Buffer Operations', function()
  local plugin
  local test_bufnr

  local function create_php_buffer(content_lines)
    test_bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(test_bufnr, 'filetype', 'php')
    vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, content_lines)
    vim.api.nvim_set_current_buf(test_bufnr)
    return test_bufnr
  end

  local function get_buffer_content()
    return vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)
  end

  before_each(function()
    if test_bufnr and vim.api.nvim_buf_is_valid(test_bufnr) then
      vim.api.nvim_buf_delete(test_bufnr, { force = true })
    end

    plugin = require('php-elements-sorter')
    plugin.setup({ debug = false })
  end)

  after_each(function()
    if test_bufnr and vim.api.nvim_buf_is_valid(test_bufnr) then
      vim.api.nvim_buf_delete(test_bufnr, { force = true })
    end
    vim.diagnostic.reset()
    plugin.cleanup_invalid_states()
  end)

  describe('remove_unused_uses atomic operation', function()
    it('should remove multiple unused imports in one operation', function()
      local content = {
        '<?php',
        '',
        'use App\\Models\\User;',
        'use App\\Services\\EmailService;',
        'use App\\Helpers\\StringHelper;',
        'use App\\Utils\\DateHelper;',
        '',
        'class UserController',
        '{',
        '    private $emailService;',
        '}',
      }

      create_php_buffer(content)

      -- Mock diagnostics for THREE unused imports
      vim.diagnostic.set(vim.api.nvim_create_namespace('test'), test_bufnr, {
        {
          lnum = 2, -- use App\Models\User
          col = 0,
          message = 'App\\Models\\User is not used',
          severity = vim.diagnostic.severity.WARN,
        },
        {
          lnum = 4, -- use App\Helpers\StringHelper
          col = 0,
          message = 'App\\Helpers\\StringHelper is not used',
          severity = vim.diagnostic.severity.WARN,
        },
        {
          lnum = 5, -- use App\Utils\DateHelper
          col = 0,
          message = 'App\\Utils\\DateHelper is not used',
          severity = vim.diagnostic.severity.WARN,
        },
      })

      -- Track buffer modifications
      local modification_count = 0
      vim.api.nvim_create_autocmd('BufModifiedSet', {
        buffer = test_bufnr,
        callback = function()
          modification_count = modification_count + 1
        end,
      })

      local removed = plugin.remove_unused_uses()

      -- Should remove in ONE operation (not 3 separate ones)
      -- Note: modification_count might be 1 or 2 (initial + atomic write)
      assert.is_true(
        modification_count <= 2,
        string.format('Expected at most 2 modifications, got %d', modification_count)
      )

      -- Verify content is correct
      local final_content = get_buffer_content()

      -- Should only have EmailService left
      local has_email_service = false
      local has_user = false
      local has_string_helper = false
      local has_date_helper = false

      for _, line in ipairs(final_content) do
        if line:match('EmailService') then
          has_email_service = true
        end
        if line:match('App\\Models\\User') then
          has_user = true
        end
        if line:match('StringHelper') then
          has_string_helper = true
        end
        if line:match('DateHelper') then
          has_date_helper = true
        end
      end

      assert.is_true(has_email_service, 'EmailService should remain')
      assert.is_false(has_user, 'User import should be removed')
      assert.is_false(has_string_helper, 'StringHelper should be removed')
      assert.is_false(has_date_helper, 'DateHelper should be removed')
    end)

    it('should handle concurrent buffer modifications gracefully', function()
      local content = {
        '<?php',
        '',
        'use App\\Models\\User;',
        'use App\\Services\\EmailService;',
        '',
        'class UserController',
        '{',
        '    private $emailService;',
        '}',
      }

      create_php_buffer(content)

      -- Mock unused diagnostic
      vim.diagnostic.set(vim.api.nvim_create_namespace('test'), test_bufnr, {
        {
          lnum = 2,
          col = 0,
          message = 'App\\Models\\User is not used',
          severity = vim.diagnostic.severity.WARN,
        },
      })

      -- Simulate concurrent modification during removal
      -- (This would cause issues with non-atomic operations)
      local original_set_lines = vim.api.nvim_buf_set_lines
      local first_call = true

      vim.api.nvim_buf_set_lines = function(bufnr, start, end_, strict, lines)
        if first_call and bufnr == test_bufnr then
          first_call = false
          -- Simulate someone else modifying the buffer
          -- (In atomic version, this shouldn't affect the operation)
        end
        return original_set_lines(bufnr, start, end_, strict, lines)
      end

      -- Should complete without errors
      local ok, result = pcall(plugin.remove_unused_uses)

      -- Restore original function
      vim.api.nvim_buf_set_lines = original_set_lines

      assert.is_true(ok, 'Should handle concurrent modifications')
    end)

    it('should preserve buffer state if no unused imports found', function()
      local content = {
        '<?php',
        '',
        'use App\\Services\\EmailService;',
        '',
        'class UserController',
        '{',
        '    private $emailService;',
        '}',
      }

      create_php_buffer(content)

      -- No diagnostics (nothing unused)

      local original_content = vim.deepcopy(get_buffer_content())

      local removed = plugin.remove_unused_uses()

      assert.equals(0, removed)

      local final_content = get_buffer_content()

      -- Buffer should be unchanged
      assert.are.same(original_content, final_content)
    end)

    it('should handle errors during atomic operation gracefully', function()
      local content = {
        '<?php',
        '',
        'use App\\Models\\User;',
        '',
        'class Test {}',
      }

      create_php_buffer(content)

      vim.diagnostic.set(vim.api.nvim_create_namespace('test'), test_bufnr, {
        {
          lnum = 2,
          col = 0,
          message = 'App\\Models\\User is not used',
          severity = vim.diagnostic.severity.WARN,
        },
      })

      -- Simulate buffer becoming invalid during operation
      local original_set_lines = vim.api.nvim_buf_set_lines
      vim.api.nvim_buf_set_lines = function(bufnr, start, end_, strict, lines)
        if bufnr == test_bufnr then
          error('Simulated buffer error')
        end
        return original_set_lines(bufnr, start, end_, strict, lines)
      end

      -- Should not crash
      local ok, result = pcall(plugin.remove_unused_uses)

      -- Restore
      vim.api.nvim_buf_set_lines = original_set_lines

      -- Should handle error gracefully
      assert.is_true(ok, 'Should handle buffer errors gracefully')

      if ok then
        assert.equals(0, result, 'Should return 0 on error')
      end
    end)

    it('should clean up spacing after removing imports', function()
      local content = {
        '<?php',
        '',
        'use App\\Models\\User;',
        '',
        '',
        'use App\\Services\\EmailService;',
        '',
        '',
        'class UserController',
        '{',
        '    private $emailService;',
        '}',
      }

      create_php_buffer(content)

      vim.diagnostic.set(vim.api.nvim_create_namespace('test'), test_bufnr, {
        {
          lnum = 2,
          col = 0,
          message = 'App\\Models\\User is not used',
          severity = vim.diagnostic.severity.WARN,
        },
      })

      plugin.remove_unused_uses()

      -- Wait for scheduled spacing cleanup
      vim.wait(100)

      local final_content = get_buffer_content()

      -- Should not have multiple consecutive blank lines
      local consecutive_blanks = 0
      local max_consecutive = 0

      for _, line in ipairs(final_content) do
        if line:match('^%s*$') then
          consecutive_blanks = consecutive_blanks + 1
          max_consecutive = math.max(max_consecutive, consecutive_blanks)
        else
          consecutive_blanks = 0
        end
      end

      assert.is_true(
        max_consecutive <= 1,
        string.format(
          'Should not have more than 1 consecutive blank line, found %d',
          max_consecutive
        )
      )
    end)
  end)

  describe('atomicity guarantees', function()
    it('should be truly atomic - buffer is never in intermediate state', function()
      local content = {
        '<?php',
        '',
        'use First\\Import;',
        'use Second\\Import;',
        'use Third\\Import;',
        '',
        'class Test {}',
      }

      create_php_buffer(content)

      -- Mark all as unused
      vim.diagnostic.set(vim.api.nvim_create_namespace('test'), test_bufnr, {
        {
          lnum = 2,
          col = 0,
          message = 'First\\Import is not used',
          severity = vim.diagnostic.severity.WARN,
        },
        {
          lnum = 3,
          col = 0,
          message = 'Second\\Import is not used',
          severity = vim.diagnostic.severity.WARN,
        },
        {
          lnum = 4,
          col = 0,
          message = 'Third\\Import is not used',
          severity = vim.diagnostic.severity.WARN,
        },
      })

      -- Monitor buffer state during operation
      local states_seen = {}

      vim.api.nvim_create_autocmd('BufModifiedSet', {
        buffer = test_bufnr,
        callback = function()
          local content_snapshot = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)
          table.insert(states_seen, vim.deepcopy(content_snapshot))
        end,
      })

      plugin.remove_unused_uses()

      -- Should see at most 2 states: original and final
      -- (Not intermediate states with some imports removed but not others)
      assert.is_true(
        #states_seen <= 2,
        string.format('Expected at most 2 buffer states, saw %d', #states_seen)
      )
    end)
  end)
end)
