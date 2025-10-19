local sorter = require('php-elements-sorter')

describe('PHP Elements Sorter', function()
  before_each(function()
    -- Create a new buffer for each test
    vim.cmd('enew')
    vim.bo.filetype = 'php'
  end)

  after_each(function()
    -- Clean up buffer
    vim.cmd('bwipeout!')
  end)

  describe('setup', function()
    it('should initialize without errors', function()
      assert.has_no.errors(function()
        sorter.setup()
      end)
    end)

    it('should accept custom config', function()
      assert.has_no.errors(function()
        sorter.setup({
          sort_properties = false,
          default_visibility = 'private',
          debug = false,
        })
      end)
    end)

    it('should merge user config with defaults', function()
      sorter.setup({
        sort_properties = false,
        debug = true,
      })

      -- Config should be updated
      assert.is_false(sorter.config.sort_properties)
      assert.is_true(sorter.config.debug)
      -- Default values should still exist
      assert.is_not_nil(sorter.config.sort_traits)
    end)
  end)

  describe('buffer state management', function()
    it('should create state for current buffer', function()
      sorter.setup()

      local config = sorter.get_buffer_config()
      assert.is_table(config)
      assert.is_not_nil(config.sort_properties)
    end)

    it('should allow buffer-specific config overrides', function()
      sorter.setup()

      local bufnr = vim.api.nvim_get_current_buf()
      sorter.set_buffer_config(bufnr, {
        sort_properties = false,
      })

      local config = sorter.get_buffer_config(bufnr)
      assert.is_false(config.sort_properties)
    end)

    it('should provide state info', function()
      sorter.setup()

      local info = sorter.get_state_info()
      assert.is_table(info)
      assert.is_number(info.active_buffers)
      assert.is_table(info.states)
    end)

    it('should cleanup invalid states', function()
      sorter.setup()

      local cleaned = sorter.cleanup_invalid_states()
      assert.is_number(cleaned)
    end)
  end)

  describe('command registration', function()
    it('should register SortPhpElements command', function()
      sorter.setup()

      local commands = vim.api.nvim_get_commands({})
      assert.is_not_nil(commands['SortPhpElements'])
    end)

    it('should register SortPhpNamespaceUses command', function()
      sorter.setup()

      local commands = vim.api.nvim_get_commands({})
      assert.is_not_nil(commands['SortPhpNamespaceUses'])
    end)

    it('should register RemoveUnusedUses command', function()
      sorter.setup()

      local commands = vim.api.nvim_get_commands({})
      assert.is_not_nil(commands['RemoveUnusedUses'])
    end)

    it('should register SortPhpClassElements command', function()
      sorter.setup()

      local commands = vim.api.nvim_get_commands({})
      assert.is_not_nil(commands['SortPhpClassElements'])
    end)

    it('should register PhpSorterInfo command', function()
      sorter.setup()

      local commands = vim.api.nvim_get_commands({})
      assert.is_not_nil(commands['PhpSorterInfo'])
    end)

    it('should register PhpSorterCleanup command', function()
      sorter.setup()

      local commands = vim.api.nvim_get_commands({})
      assert.is_not_nil(commands['PhpSorterCleanup'])
    end)
  end)

  describe('code actions', function()
    it('should provide code actions for PHP files', function()
      sorter.setup()

      local lines = {
        '<?php',
        '',
        'use Zebra\\Animal;',
        'use Apple\\Fruit;',
        '',
        'class Test {',
        '}',
      }
      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)

      local actions = sorter.get_code_actions()

      assert.is_table(actions)
      assert.is_true(#actions > 0)
    end)
  end)

  describe('namespace uses sorting', function()
    it('should execute sort_namespace_uses without errors', function()
      sorter.setup()

      local lines = {
        '<?php',
        '',
        'use Zebra\\Animal;',
        'use Apple\\Fruit;',
        'use Banana\\Fruit;',
        '',
        'class Test {',
        '}',
      }

      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)

      -- Should not error
      assert.has_no.errors(function()
        sorter.sort_namespace_uses()
      end)
    end)

    it('should execute via SortPhpNamespaceUses command', function()
      sorter.setup()

      local lines = {
        '<?php',
        '',
        'use Zebra\\Animal;',
        'use Apple\\Fruit;',
        '',
        'class Test {',
        '}',
      }

      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)

      assert.has_no.errors(function()
        vim.cmd('SortPhpNamespaceUses')
      end)
    end)

    it('should handle files with no use statements', function()
      sorter.setup()

      local lines = {
        '<?php',
        '',
        'class Test {',
        '}',
      }

      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)

      assert.has_no.errors(function()
        sorter.sort_namespace_uses()
      end)
    end)
  end)

  describe('remove unused uses', function()
    it('should execute without errors', function()
      sorter.setup()

      local lines = {
        '<?php',
        '',
        'use Used\\Class;',
        'use Unused\\Class;',
        '',
        'class Test {',
        '    public function test() {',
        '        return new Used\\Class();',
        '    }',
        '}',
      }

      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)

      assert.has_no.errors(function()
        sorter.remove_unused_uses()
      end)
    end)

    it('should execute via RemoveUnusedUses command', function()
      sorter.setup()

      local lines = {
        '<?php',
        '',
        'use Some\\Class;',
        '',
        'class Test {',
        '}',
      }

      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)

      assert.has_no.errors(function()
        vim.cmd('RemoveUnusedUses')
      end)
    end)
  end)

  describe('sort elements', function()
    it('should execute without errors', function()
      sorter.setup()

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

      assert.has_no.errors(function()
        sorter.sort_elements()
      end)
    end)

    it('should execute via SortPhpClassElements command', function()
      sorter.setup()

      local lines = {
        '<?php',
        '',
        'class Test {',
        '    const Z = 1;',
        '    const A = 2;',
        '}',
      }

      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)

      assert.has_no.errors(function()
        vim.cmd('SortPhpClassElements')
      end)
    end)
  end)

  describe('sort all', function()
    it('should execute without errors', function()
      sorter.setup()

      local lines = {
        '<?php',
        '',
        'namespace App\\Models;',
        '',
        'use Zebra\\Animal;',
        'use Apple\\Fruit;',
        '',
        'class User {',
        '    const STATUS_ACTIVE = 1;',
        '    ',
        '    private $zebra;',
        '    public $name;',
        '}',
      }

      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)

      assert.has_no.errors(function()
        sorter.sort_all()
      end)
    end)

    it('should execute via SortPhpElements command', function()
      sorter.setup()

      local lines = {
        '<?php',
        '',
        'class Test {',
        '}',
      }

      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)

      assert.has_no.errors(function()
        vim.cmd('SortPhpElements')
      end)
    end)
  end)

  describe('edge cases', function()
    it('should handle empty buffers', function()
      sorter.setup()

      vim.api.nvim_buf_set_lines(0, 0, -1, false, {})

      assert.has_no.errors(function()
        sorter.sort_all()
      end)
    end)

    it('should handle buffers with only PHP tag', function()
      sorter.setup()

      vim.api.nvim_buf_set_lines(0, 0, -1, false, { '<?php' })

      assert.has_no.errors(function()
        sorter.sort_all()
      end)
    end)

    it('should handle non-PHP buffers gracefully', function()
      sorter.setup()

      vim.bo.filetype = 'lua'

      assert.has_no.errors(function()
        vim.cmd('SortPhpElements')
      end)
    end)
  end)

  describe('diagnostic commands', function()
    it('should execute PhpSorterInfo without errors', function()
      sorter.setup()

      assert.has_no.errors(function()
        vim.cmd('PhpSorterInfo')
      end)
    end)

    it('should execute PhpSorterCleanup without errors', function()
      sorter.setup()

      assert.has_no.errors(function()
        vim.cmd('PhpSorterCleanup')
      end)
    end)
  end)
end)
