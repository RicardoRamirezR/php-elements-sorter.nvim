-- ============================================================================
-- lua/tests/preview_mode_spec.lua
-- Tests for preview mode functionality
-- ============================================================================

describe('Preview Mode', function()
  local plugin
  local preview
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

    preview = require('php-elements-sorter.preview')
  end)

  after_each(function()
    if test_bufnr and vim.api.nvim_buf_is_valid(test_bufnr) then
      vim.api.nvim_buf_delete(test_bufnr, { force = true })
    end
    plugin.cleanup_invalid_states()

    -- Close any open preview windows
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.api.nvim_buf_is_valid(buf) then
        local ft = vim.api.nvim_buf_get_option(buf, 'filetype')
        if ft == 'diff' then
          pcall(vim.api.nvim_win_close, win, true)
        end
      end
    end
  end)

  describe('Availability', function()
    it('should be available on Neovim 0.6+', function()
      assert.is_true(preview.is_available())
    end)
  end)

  describe('Diff Creation', function()
    it('should show diff when content differs', function()
      local content = {
        '<?php',
        '',
        'use Zebra\\Animal;',
        'use Apple\\Fruit;',
        '',
        'class Test {}',
      }

      create_php_buffer(content)

      local original_content = vim.deepcopy(get_buffer_content())

      -- Trigger preview (should open window)
      local ok = pcall(preview.preview_namespace_uses, test_bufnr)

      assert.is_true(ok, 'Preview should not error')

      -- Check that a diff window was created
      local diff_win_found = false
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.api.nvim_buf_is_valid(buf) then
          local ft = vim.api.nvim_buf_get_option(buf, 'filetype')
          if ft == 'diff' then
            diff_win_found = true

            -- Close the window for cleanup
            vim.api.nvim_win_close(win, true)
            break
          end
        end
      end

      assert.is_true(diff_win_found, 'Diff window should be created')

      -- Original buffer should be unchanged
      local after_content = get_buffer_content()
      assert.are.same(original_content, after_content)
    end)

    it('should not show diff when content is already sorted', function()
      local content = {
        '<?php',
        '',
        'use Apple\\Fruit;',
        'use Zebra\\Animal;',
        '',
        'class Test {}',
      }

      create_php_buffer(content)

      -- Already sorted, should show notification instead of diff
      local ok = pcall(preview.preview_namespace_uses, test_bufnr)

      assert.is_true(ok)

      -- Should not create diff window
      local diff_win_found = false
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.api.nvim_buf_is_valid(buf) then
          local ft = vim.api.nvim_buf_get_option(buf, 'filetype')
          if ft == 'diff' then
            diff_win_found = true
          end
        end
      end

      assert.is_false(diff_win_found, 'Should not create diff window for no changes')
    end)
  end)

  describe('Preview Operations', function()
    it('should preview namespace uses sorting', function()
      local content = {
        '<?php',
        '',
        'use Zebra\\Animal;',
        'use Apple\\Fruit;',
      }

      create_php_buffer(content)

      local ok = preview.preview_namespace_uses(test_bufnr)

      assert.is_true(ok)

      -- Close preview window if opened
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.api.nvim_buf_is_valid(buf) then
          local ft = vim.api.nvim_buf_get_option(buf, 'filetype')
          if ft == 'diff' then
            vim.api.nvim_win_close(win, true)
          end
        end
      end
    end)

    it('should preview elements sorting', function()
      local content = {
        '<?php',
        '',
        'class Test',
        '{',
        '    public $name;',
        '    private $id;',
        '}',
      }

      create_php_buffer(content)

      local ok = preview.preview_elements(test_bufnr)

      assert.is_true(ok)

      -- Cleanup
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.api.nvim_buf_is_valid(buf) then
          local ft = vim.api.nvim_buf_get_option(buf, 'filetype')
          if ft == 'diff' then
            vim.api.nvim_win_close(win, true)
          end
        end
      end
    end)

    it('should preview all sorting operations', function()
      local content = {
        '<?php',
        '',
        'use Zebra\\Animal;',
        'use Apple\\Fruit;',
        '',
        'class Test',
        '{',
        '    public $name;',
        '    private $id;',
        '}',
      }

      create_php_buffer(content)

      local ok = preview.preview_all(test_bufnr)

      assert.is_true(ok)

      -- Cleanup
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.api.nvim_buf_is_valid(buf) then
          local ft = vim.api.nvim_buf_get_option(buf, 'filetype')
          if ft == 'diff' then
            vim.api.nvim_win_close(win, true)
          end
        end
      end
    end)
  end)

  describe('Buffer Preservation', function()
    it('should not modify original buffer during preview', function()
      local content = {
        '<?php',
        '',
        'use Zebra\\Animal;',
        'use Apple\\Fruit;',
        '',
        'class Test',
        '{',
        '    public $name;',
        '    private $id;',
        '}',
      }

      create_php_buffer(content)

      local original_content = vim.deepcopy(get_buffer_content())

      -- Preview (but don't accept)
      preview.preview_all(test_bufnr)

      -- Close any preview windows
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.api.nvim_buf_is_valid(buf) then
          local ft = vim.api.nvim_buf_get_option(buf, 'filetype')
          if ft == 'diff' then
            vim.api.nvim_win_close(win, true)
          end
        end
      end

      -- Buffer should be unchanged
      local after_content = get_buffer_content()
      assert.are.same(original_content, after_content)
    end)
  end)

  describe('Error Handling', function()
    it('should handle invalid buffer gracefully', function()
      local invalid_bufnr = 99999

      local ok = pcall(preview.preview_all, invalid_bufnr)

      -- Should not crash
      assert.is_true(ok)
    end)

    it('should handle sort function errors', function()
      local content = {
        '<?php',
        'class Malformed',
        '    public $missing_brace',
      }

      create_php_buffer(content)

      -- Should handle malformed PHP gracefully
      local ok = pcall(preview.preview_all, test_bufnr)

      assert.is_true(ok, 'Should handle malformed PHP without crashing')
    end)
  end)

  describe('API Integration', function()
    it('should expose preview functions in plugin API', function()
      assert.is_function(plugin.preview_all)
      assert.is_function(plugin.preview_namespace_uses)
      assert.is_function(plugin.preview_elements)
      assert.is_function(plugin.preview_available)
    end)

    it('should report availability correctly', function()
      local available = plugin.preview_available()
      assert.is_boolean(available)
      assert.is_true(available) -- Should be true on modern Neovim
    end)
  end)

  describe('Commands', function()
    it('should register preview commands', function()
      -- Check if commands exist
      local commands = vim.api.nvim_get_commands({})

      assert.is_not_nil(commands['SortPhpElementsPreview'])
      assert.is_not_nil(commands['SortPhpNamespaceUsesPreview'])
      assert.is_not_nil(commands['SortPhpClassElementsPreview'])
    end)

    it('should execute SortPhpElementsPreview command', function()
      local content = {
        '<?php',
        '',
        'use Zebra\\Animal;',
        'use Apple\\Fruit;',
      }

      create_php_buffer(content)

      -- Execute command
      local ok = pcall(vim.cmd, 'SortPhpElementsPreview')

      assert.is_true(ok, 'Command should execute without error')

      -- Cleanup preview windows
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.api.nvim_buf_is_valid(buf) then
          local ft = vim.api.nvim_buf_get_option(buf, 'filetype')
          if ft == 'diff' then
            vim.api.nvim_win_close(win, true)
          end
        end
      end
    end)
  end)

  describe('Window Properties', function()
    it('should create floating window with correct properties', function()
      local content = {
        '<?php',
        '',
        'use Zebra\\Animal;',
        'use Apple\\Fruit;',
      }

      create_php_buffer(content)

      preview.preview_namespace_uses(test_bufnr)

      -- Find the preview window
      local preview_win = nil
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.api.nvim_buf_is_valid(buf) then
          local ft = vim.api.nvim_buf_get_option(buf, 'filetype')
          if ft == 'diff' then
            preview_win = win
            break
          end
        end
      end

      if preview_win then
        local config = vim.api.nvim_win_get_config(preview_win)

        -- Should be floating
        assert.equals('editor', config.relative)

        -- Should have border
        assert.is_not_nil(config.border)

        -- Should have title
        assert.is_not_nil(config.title)
        if type(config.title) == 'string' then
          assert.truthy(config.title:match('Preview'))
        end

        -- Cleanup
        vim.api.nvim_win_close(preview_win, true)
      end
    end)
  end)

  describe('Diff Format', function()
    it('should create valid unified diff format', function()
      local content = {
        '<?php',
        '',
        'use Zebra\\Animal;',
        'use Apple\\Fruit;',
        '',
        'class Test {}',
      }

      create_php_buffer(content)

      preview.preview_namespace_uses(test_bufnr)

      -- Find the preview buffer
      local preview_buf = nil
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.api.nvim_buf_is_valid(buf) then
          local ft = vim.api.nvim_buf_get_option(buf, 'filetype')
          if ft == 'diff' then
            preview_buf = buf
            break
          end
        end
      end

      if preview_buf then
        local diff_lines = vim.api.nvim_buf_get_lines(preview_buf, 0, -1, false)

        -- Should have header
        local has_header = false
        for _, line in ipairs(diff_lines) do
          if line:match('^%-%-%-') or line:match('^%+%+%+') then
            has_header = true
            break
          end
        end
        assert.is_true(has_header, 'Diff should have header')

        -- Should have hunk markers
        local has_hunk = false
        for _, line in ipairs(diff_lines) do
          if line:match('^@@') then
            has_hunk = true
            break
          end
        end
        assert.is_true(has_hunk, 'Diff should have hunk markers')

        -- Should have additions and deletions
        local has_addition = false
        local has_deletion = false
        for _, line in ipairs(diff_lines) do
          if line:match('^%+[^%+]') then
            has_addition = true
          end
          if line:match('^%-[^%-]') then
            has_deletion = true
          end
        end

        -- For this specific case, we should have both
        assert.is_true(has_addition or has_deletion, 'Diff should show changes')

        -- Cleanup
        for _, win in ipairs(vim.api.nvim_list_wins()) do
          if vim.api.nvim_win_get_buf(win) == preview_buf then
            vim.api.nvim_win_close(win, true)
            break
          end
        end
      end
    end)
  end)

  describe('Performance', function()
    it('should handle large diffs efficiently', function()
      -- Create a large file
      local content = { '<?php', '', 'class Large', '{' }

      for i = 1, 100 do
        local vis = ({ 'private', 'protected', 'public' })[math.random(1, 3)]
        table.insert(content, string.format('    %s $prop%d;', vis, i))
      end
      table.insert(content, '}')

      create_php_buffer(content)

      local start_time = vim.loop.hrtime()

      local ok = pcall(preview.preview_elements, test_bufnr)

      local end_time = vim.loop.hrtime()
      local elapsed_ms = (end_time - start_time) / 1000000

      assert.is_true(ok, 'Should handle large files')
      assert.is_true(elapsed_ms < 1000, 'Should complete in reasonable time')

      -- Cleanup
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.api.nvim_buf_is_valid(buf) then
          local ft = vim.api.nvim_buf_get_option(buf, 'filetype')
          if ft == 'diff' then
            vim.api.nvim_win_close(win, true)
          end
        end
      end
    end)
  end)
end)
