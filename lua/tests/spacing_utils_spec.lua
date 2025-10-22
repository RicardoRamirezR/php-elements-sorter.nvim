-- lua/tests/spacing_utils_spec.lua
-- Tests para las nuevas spacing utilities (Mejora #4)

local spacing_utils = require('php-elements-sorter.utils.spacing')

describe('Spacing Utils - Mejora #4', function()
  local bufnr

  before_each(function()
    vim.cmd('enew')
    bufnr = vim.api.nvim_get_current_buf()
    vim.bo[bufnr].filetype = 'php'
  end)

  after_each(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.cmd('bwipeout!')
    end
  end)

  describe('ensure_blank_before', function()
    it('should insert blank line when previous line is not empty', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        '<?php',
        'class Test {',
      })

      local inserted = spacing_utils.ensure_blank_before(bufnr, 1)

      assert.is_true(inserted)

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.equals(3, #lines)
      assert.equals('', lines[2])
    end)

    it('should not insert blank line when previous line is empty', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        '<?php',
        '',
        'class Test {',
      })

      local inserted = spacing_utils.ensure_blank_before(bufnr, 2)

      assert.is_false(inserted)

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.equals(3, #lines)
    end)

    it('should not insert blank line at buffer start', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        '<?php',
      })

      local inserted = spacing_utils.ensure_blank_before(bufnr, 0)

      assert.is_false(inserted)
    end)
  end)

  describe('ensure_blank_after', function()
    it('should insert blank line when next line is not empty', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        '<?php',
        'class Test {',
      })

      local inserted = spacing_utils.ensure_blank_after(bufnr, 1)

      assert.is_true(inserted)

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.equals(3, #lines)
      assert.equals('', lines[2])
    end)

    it('should not insert blank line when next line is empty', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        '<?php',
        '',
        'class Test {',
      })

      local inserted = spacing_utils.ensure_blank_after(bufnr, 1)

      assert.is_false(inserted)

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.equals(3, #lines)
    end)

    it('should insert blank line at end of buffer', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        '<?php',
        'class Test {',
      })

      local inserted = spacing_utils.ensure_blank_after(bufnr, 2)

      assert.is_true(inserted)

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.equals(3, #lines)
      assert.equals('', lines[3])
    end)
  end)

  describe('ensure_spacing_around_block', function()
    it('should add spacing before and after block', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        '<?php',
        'use SomeClass;',
        'class Test {',
      })

      local offset = spacing_utils.ensure_spacing_around_block(bufnr, 1, 2)

      assert.equals(2, offset)

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.equals(5, #lines)
      assert.equals('', lines[2]) -- Before
      assert.equals('', lines[4]) -- After
    end)

    it('should add only before when after already has blank', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        '<?php',
        'use SomeClass;',
        '',
        'class Test {',
      })

      local offset = spacing_utils.ensure_spacing_around_block(bufnr, 1, 2)

      assert.equals(1, offset)

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.equals(5, #lines)
    end)

    it('should not add spacing when both already present', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        '<?php',
        '',
        'use SomeClass;',
        '',
        'class Test {',
      })

      local offset = spacing_utils.ensure_spacing_around_block(bufnr, 2, 3)

      assert.equals(0, offset)

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.equals(5, #lines)
    end)
  end)

  describe('check_spacing_needs', function()
    it('should detect both spacing needs', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        '<?php',
        'use SomeClass;',
        'class Test {',
      })

      local needs_before, needs_after = spacing_utils.check_spacing_needs(bufnr, 1, 2)

      assert.is_true(needs_before)
      assert.is_true(needs_after)
    end)

    it('should detect no spacing needs', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        '<?php',
        '',
        'use SomeClass;',
        '',
        'class Test {',
      })

      local needs_before, needs_after = spacing_utils.check_spacing_needs(bufnr, 2, 3)

      assert.is_false(needs_before)
      assert.is_false(needs_after)
    end)
  end)

  describe('build_with_spacing', function()
    it('should build content with spacing added', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        '<?php',
        'use SomeClass;',
        'class Test {',
      })

      local content = { 'use Another;' }
      local final = spacing_utils.build_with_spacing(bufnr, 1, 2, content)

      assert.equals(3, #final)
      assert.equals('', final[1]) -- Blank before
      assert.equals('use Another;', final[2])
      assert.equals('', final[3]) -- Blank after
    end)

    it('should not add spacing when not needed', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        '<?php',
        '',
        'use SomeClass;',
        '',
        'class Test {',
      })

      local content = { 'use Another;' }
      local final = spacing_utils.build_with_spacing(bufnr, 2, 3, content)

      assert.equals(1, #final)
      assert.equals('use Another;', final[1])
    end)
  end)

  describe('remove_duplicate_blanks', function()
    it('should remove consecutive blank lines', function()
      local lines = {
        '<?php',
        '',
        '',
        '',
        'class Test {',
        '',
        '',
        '}',
      }

      local cleaned = spacing_utils.remove_duplicate_blanks(lines)

      assert.equals(5, #cleaned)
      assert.equals('<?php', cleaned[1])
      assert.equals('', cleaned[2])
      assert.equals('class Test {', cleaned[3])
      assert.equals('', cleaned[4])
      assert.equals('}', cleaned[5])
    end)

    it('should preserve single blank lines', function()
      local lines = {
        '<?php',
        '',
        'class Test {',
        '',
        '}',
      }

      local cleaned = spacing_utils.remove_duplicate_blanks(lines)

      assert.equals(5, #cleaned)
      assert.same(lines, cleaned)
    end)

    it('should handle lines with no blanks', function()
      local lines = {
        '<?php',
        'class Test {',
        '}',
      }

      local cleaned = spacing_utils.remove_duplicate_blanks(lines)

      assert.equals(3, #cleaned)
      assert.same(lines, cleaned)
    end)
  end)

  describe('normalize_spacing_in_range', function()
    it('should normalize duplicate blanks in range', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        '<?php',
        '',
        '',
        '',
        'class Test {',
        '',
        '',
        '}',
      })

      spacing_utils.normalize_spacing_in_range(bufnr, 0, -1)

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

      -- Should have removed duplicate blanks
      assert.is_true(#lines < 8)

      -- Count blank lines
      local blank_count = 0
      for i = 1, #lines - 1 do
        if lines[i] == '' and lines[i + 1] == '' then
          blank_count = blank_count + 1
        end
      end

      assert.equals(0, blank_count, 'Should have no consecutive blanks')
    end)

    it('should not modify when already normalized', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        '<?php',
        '',
        'class Test {',
        '',
        '}',
      })

      local before = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

      spacing_utils.normalize_spacing_in_range(bufnr, 0, -1)

      local after = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

      assert.same(before, after)
    end)
  end)

  describe('integration with real PHP code', function()
    it('should handle spacing around use statements', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        '<?php',
        'namespace App;',
        'use Some\\Class;',
        'use Another\\Class;',
        'class Test {',
      })

      -- Ensure spacing around use block
      spacing_utils.ensure_spacing_around_block(bufnr, 2, 4)

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

      -- Should have blank lines around use statements
      assert.equals('', lines[3]) -- Before first use
      assert.equals('', lines[6]) -- After last use
    end)

    it('should handle spacing around properties', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        '<?php',
        'class Test {',
        '    private $a;',
        '    public $b;',
        '}',
      })

      -- Ensure spacing around property block
      spacing_utils.ensure_spacing_around_block(bufnr, 2, 4)

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

      assert.equals('', lines[3]) -- Before properties
      assert.equals('', lines[6]) -- After properties
    end)
  end)
end)
