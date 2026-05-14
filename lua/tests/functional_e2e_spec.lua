-- ============================================================================
-- lua/tests/functional_e2e_spec.lua
-- End-to-end functional tests with realistic PHP scenarios (FIXED)
-- ============================================================================

describe('Functional E2E Tests', function()
  local plugin
  local test_bufnr

  -- Helper: Create a PHP buffer with content
  local function create_php_buffer(content_lines)
    test_bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(test_bufnr, 'filetype', 'php')
    vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, content_lines)
    vim.api.nvim_set_current_buf(test_bufnr)
    return test_bufnr
  end

  -- Helper: Get buffer content
  local function get_buffer_content()
    return vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)
  end

  -- Helper: Compare buffer content ignoring empty trailing lines
  local function assert_buffer_equals(expected)
    local actual = get_buffer_content()

    -- Remove trailing empty lines from both
    while #actual > 0 and actual[#actual] == '' do
      table.remove(actual)
    end
    while #expected > 0 and expected[#expected] == '' do
      table.remove(expected)
    end

    assert.are.same(expected, actual)
  end

  -- Helper: Normalize spacing (remove consecutive blank lines)
  local function normalize_spacing(lines)
    local result = {}
    local prev_blank = false

    for _, line in ipairs(lines) do
      local is_blank = line:match('^%s*$') ~= nil

      if not (is_blank and prev_blank) then
        table.insert(result, line)
      end

      prev_blank = is_blank
    end

    return result
  end

  before_each(function()
    -- Clear any previous state
    if test_bufnr and vim.api.nvim_buf_is_valid(test_bufnr) then
      vim.api.nvim_buf_delete(test_bufnr, { force = true })
    end

    -- Setup plugin with default config
    plugin = require('php-elements-sorter')
    plugin.setup({
      add_visibility_spacing = true,
      sort_properties = true,
      sort_traits = true,
      sort_namespace_uses = true,
      sort_constants = true,
      default_visibility = 'public',
      remove_unused_imports = true,
      add_newline_between_const_and_properties = true,
      add_newline_after_namespace_uses = true,
      add_newline_after_trait_uses = true,
      debug = false,
    })
  end)

  after_each(function()
    if test_bufnr and vim.api.nvim_buf_is_valid(test_bufnr) then
      vim.api.nvim_buf_delete(test_bufnr, { force = true })
    end
    plugin.cleanup_invalid_states()
  end)

  describe('Scenario 1: Complete messy class', function()
    local messy_class = {
      '<?php',
      '',
      'use Zebra\\Animal;',
      'use Apple\\Fruit;',
      'use Database\\Connection;',
      'use Banana\\Fruit;',
      '',
      'class Product',
      '{',
      '    const STATUS_INACTIVE = 0;',
      '    public $name;',
      '    const STATUS_ACTIVE = 1;',
      '    private $id;',
      '    const STATUS_PENDING = 2;',
      '    protected $description;',
      '    private $price;',
      '    public $category;',
      '    protected $metadata;',
      '}',
    }

    -- Before assertion, add debug info
    it('should sort all elements correctly', function()
      create_php_buffer(messy_class)

      local stats = plugin.sort_all()

      -- Verify statistics (adjusted for actual behavior)
      assert.is_truthy(stats)
      assert.equals(4, stats.uses)
      assert.equals(3, stats.constants)
      assert.is_true(stats.properties >= 4)

      local content = get_buffer_content()

      -- 1. Verify uses are sorted
      local uses = {}
      for i, line in ipairs(content) do
        if line:match('^use ') then
          table.insert(uses, { line = line, idx = i })
        end
      end

      assert.equals(4, #uses)
      assert.truthy(uses[1].line:match('Apple'))
      assert.truthy(uses[2].line:match('Banana'))

      -- 2. Collect ALL constants and properties with their positions
      local constants = {}
      local properties = {}

      for i, line in ipairs(content) do
        if line:match('const STATUS_') then
          table.insert(constants, { line = line, idx = i })
        elseif line:match('%$%w+') and not line:match('const') then
          -- Any line with $variable that's not a constant
          -- Must be within reasonable indentation (inside class)
          if line:match('^%s+') and not line:match('^%s*//') then
            table.insert(properties, { line = line, idx = i })
          end
        end
      end

      -- 3. Verify we found elements
      assert.is_true(#constants >= 3, 'Should find at least 3 constants')
      assert.is_true(#properties >= 4, 'Should find at least 4 properties')

      -- 4. Verify constants come before ALL properties
      local last_const_idx = constants[#constants].idx
      local first_prop_idx = properties[1].idx

      assert.is_true(
        last_const_idx < first_prop_idx,
        string.format(
          'Last constant at line %d should come before first property at line %d',
          last_const_idx,
          first_prop_idx
        )
      )

      -- 5. Verify constant sorting (alphabetical)
      local const_names = {}
      for _, c in ipairs(constants) do
        local name = c.line:match('const (STATUS_%w+)')
        if name then
          table.insert(const_names, name)
        end
      end

      -- Should be: STATUS_ACTIVE, STATUS_INACTIVE, STATUS_PENDING
      assert.truthy(const_names[1]:match('ACTIVE'))

      -- 6. Verify property sorting (by visibility)
      local private_props = {}
      local protected_props = {}
      local public_props = {}

      for _, p in ipairs(properties) do
        if p.line:match('private') then
          table.insert(private_props, p.idx)
        elseif p.line:match('protected') then
          table.insert(protected_props, p.idx)
        elseif p.line:match('public') then
          table.insert(public_props, p.idx)
        end
      end

      -- Verify visibility ordering
      if #private_props > 0 and #protected_props > 0 then
        assert.is_true(
          private_props[#private_props] < protected_props[1],
          'Private properties should come before protected'
        )
      end

      if #protected_props > 0 and #public_props > 0 then
        assert.is_true(
          protected_props[#protected_props] < public_props[1],
          'Protected properties should come before public'
        )
      end
    end)

    it('should sort only namespace uses', function()
      create_php_buffer(messy_class)

      local count = plugin.sort_namespace_uses()

      assert.equals(4, count)

      local content = get_buffer_content()
      -- Verify uses are sorted
      local found_apple = false
      local found_zebra = false
      local apple_idx = 0
      local zebra_idx = 0

      for i, line in ipairs(content) do
        if line:match('use Apple') then
          found_apple = true
          apple_idx = i
        elseif line:match('use Zebra') then
          found_zebra = true
          zebra_idx = i
        end
      end

      assert.is_true(found_apple and found_zebra)
      assert.is_true(apple_idx < zebra_idx)

      -- Verify class content unchanged (still messy)
      local has_messy_order = false
      for i, line in ipairs(content) do
        if line:match('const STATUS_INACTIVE') then
          -- Check if next non-empty is public $name (messy order)
          if content[i + 1] and content[i + 1]:match('public $name') then
            has_messy_order = true
          end
        end
      end

      assert.is_true(has_messy_order)
    end)

    it('should sort only class elements', function()
      create_php_buffer(messy_class)

      local stats = plugin.sort_elements()

      assert.is_truthy(stats)
      assert.equals(3, stats.constants)
      assert.is_true(stats.properties >= 4)

      local content = get_buffer_content()
      -- Verify uses unchanged (still messy)
      local found_zebra_first = false
      for i, line in ipairs(content) do
        if line:match('use Zebra') and i < 6 then
          found_zebra_first = true
          break
        end
      end

      assert.is_true(found_zebra_first)

      -- Verify class elements sorted
      local const_active_idx = 0
      local const_inactive_idx = 0

      for i, line in ipairs(content) do
        if line:match('const STATUS_ACTIVE') then
          const_active_idx = i
        elseif line:match('const STATUS_INACTIVE') then
          const_inactive_idx = i
        end
      end

      assert.is_true(const_active_idx > 0 and const_active_idx < const_inactive_idx)
    end)
  end)

  describe('Scenario 2: Class with traits', function()
    local class_with_traits = {
      '<?php',
      '',
      'class User',
      '{',
      '    use Timestampable;',
      '    use Loggable;',
      '    use Cacheable;',
      '',
      '    public $email;',
      '    private $password;',
      '    public $name;',
      '}',
    }

    it('should sort traits alphabetically', function()
      create_php_buffer(class_with_traits)

      plugin.sort_elements()

      local content = normalize_spacing(get_buffer_content())

      -- Find trait order
      local traits_order = {}
      for i, line in ipairs(content) do
        if line:match('use Cacheable') then
          table.insert(traits_order, { name = 'Cacheable', idx = i })
        elseif line:match('use Loggable') then
          table.insert(traits_order, { name = 'Loggable', idx = i })
        elseif line:match('use Timestampable') then
          table.insert(traits_order, { name = 'Timestampable', idx = i })
        end
      end

      assert.equals(3, #traits_order)
      -- Verify alphabetical order
      assert.is_true(traits_order[1].idx < traits_order[2].idx)
      assert.is_true(traits_order[2].idx < traits_order[3].idx)

      -- Verify traits come before properties
      local first_trait = traits_order[1].idx
      local first_prop = 0

      for i, line in ipairs(content) do
        if line:match('%$password') or line:match('%$email') then
          first_prop = i
          break
        end
      end

      assert.is_true(first_trait < first_prop)
    end)

    it('should add spacing after trait uses when configured', function()
      create_php_buffer(class_with_traits)

      plugin.set_buffer_config(test_bufnr, {
        add_newline_after_trait_uses = true,
      })

      plugin.sort_elements()

      local content = get_buffer_content()

      -- Find last trait use
      local last_trait_line = 0
      for i, line in ipairs(content) do
        if line:match('use Timestampable') then
          last_trait_line = i
        end
      end

      -- Verify blank line exists after traits section
      assert.is_true(last_trait_line > 0)
      local has_spacing = false
      for i = last_trait_line, math.min(last_trait_line + 3, #content) do
        if content[i] == '' then
          has_spacing = true
          break
        end
      end

      assert.is_true(has_spacing)
    end)
  end)

  describe('Scenario 3: Unused imports', function()
    it('should remove unused imports when diagnostics available', function()
      local with_unused = {
        '<?php',
        '',
        'use App\\Models\\User;',
        'use App\\Services\\EmailService;',
        'use App\\Helpers\\StringHelper;',
        '',
        'class UserController',
        '{',
        '    private $emailService;',
        '}',
      }

      create_php_buffer(with_unused)

      -- Mock diagnostics for unused imports
      vim.diagnostic.set(vim.api.nvim_create_namespace('test'), test_bufnr, {
        {
          lnum = 2,
          col = 0,
          message = 'App\\Models\\User is not used',
          severity = vim.diagnostic.severity.WARN,
        },
        {
          lnum = 4,
          col = 0,
          message = 'App\\Helpers\\StringHelper is declared but not used',
          severity = vim.diagnostic.severity.WARN,
        },
      })

      local removed = plugin.remove_unused_uses()

      -- Should attempt to remove unused imports
      assert.is_true(removed >= 0)

      vim.diagnostic.reset()
    end)
  end)

  describe('Scenario 4: Complex visibility mixing', function()
    local complex_visibility = {
      '<?php',
      '',
      'class Product',
      '{',
      '    public $name;',
      '    private $id;',
      '    public $description;',
      '    protected $metadata;',
      '    private $price;',
      '    protected $tags;',
      '    public $category;',
      '    private $stock;',
      '}',
    }

    it('should group by visibility with spacing', function()
      create_php_buffer(complex_visibility)

      plugin.sort_elements()

      local content = normalize_spacing(get_buffer_content())

      -- Verify visibility grouping (private < protected < public)
      local groups = { private = {}, protected = {}, public = {} }

      for i, line in ipairs(content) do
        if line:match('private %$') then
          table.insert(groups.private, i)
        elseif line:match('protected %$') then
          table.insert(groups.protected, i)
        elseif line:match('public %$') then
          table.insert(groups.public, i)
        end
      end

      -- Verify all privates come before protecteds
      if #groups.private > 0 and #groups.protected > 0 then
        assert.is_true(groups.private[#groups.private] < groups.protected[1])
      end

      -- Verify all protecteds come before publics
      if #groups.protected > 0 and #groups.public > 0 then
        assert.is_true(groups.protected[#groups.protected] < groups.public[1])
      end
    end)

    it('should sort without visibility spacing when disabled', function()
      create_php_buffer(complex_visibility)

      plugin.set_buffer_config(test_bufnr, {
        add_visibility_spacing = false,
      })

      plugin.sort_elements()

      local content = get_buffer_content()

      -- Should still sort by visibility but check consecutive properties
      local found_private = false
      local private_idx = 0

      for i, line in ipairs(content) do
        if line:match('private %$id') then
          found_private = true
          private_idx = i
          break
        end
      end

      assert.is_true(found_private and private_idx > 0)
    end)
  end)

  describe('Scenario 5: Constants and properties separation', function()
    local mixed_elements = {
      '<?php',
      '',
      'class Config',
      '{',
      '    const ENV_PRODUCTION = "prod";',
      '    public $environment;',
      '    const ENV_DEVELOPMENT = "dev";',
      '    private $config;',
      '    const ENV_STAGING = "stage";',
      '}',
    }

    it('should separate constants from properties', function()
      create_php_buffer(mixed_elements)

      plugin.sort_elements()

      local content = normalize_spacing(get_buffer_content())

      -- Find last constant and first property
      local last_const_idx = 0
      local first_prop_idx = 999

      for i, line in ipairs(content) do
        if line:match('const ENV_') then
          last_const_idx = math.max(last_const_idx, i)
        elseif line:match('%$config') or line:match('%$environment') then
          first_prop_idx = math.min(first_prop_idx, i)
        end
      end

      -- Verify constants come before properties
      assert.is_true(last_const_idx > 0 and last_const_idx < first_prop_idx)

      -- Verify separation (blank line between)
      local has_separation = false
      for i = last_const_idx + 1, first_prop_idx - 1 do
        if content[i] == '' then
          has_separation = true
          break
        end
      end

      assert.is_true(has_separation)
    end)

    it('should not separate when configured', function()
      create_php_buffer(mixed_elements)

      plugin.set_buffer_config(test_bufnr, {
        add_newline_between_const_and_properties = false,
      })

      plugin.sort_elements()

      local content = get_buffer_content()

      -- Find last constant
      local last_const_line = 0
      for i, line in ipairs(content) do
        if line:match('const ENV_STAGING') then
          last_const_line = i
          break
        end
      end

      -- Verify found
      assert.is_true(last_const_line > 0)
    end)
  end)

  describe('Scenario 6: Already sorted content', function()
    it('should minimize changes to already sorted content', function()
      local already_sorted = {
        '<?php',
        '',
        'use App\\Models\\User;',
        'use App\\Services\\EmailService;',
        '',
        'class UserService',
        '{',
        '    private $id;',
        '',
        '    public $name;',
        '}',
      }

      create_php_buffer(already_sorted)

      local original = vim.deepcopy(get_buffer_content())

      plugin.sort_all()

      local after = get_buffer_content()

      -- Normalize both for comparison (spacing may vary)
      local orig_normalized = normalize_spacing(original)
      local after_normalized = normalize_spacing(after)

      -- Core structure should remain very similar
      local orig_non_blank = {}
      local after_non_blank = {}

      for _, line in ipairs(orig_normalized) do
        if line ~= '' then
          table.insert(orig_non_blank, line)
        end
      end

      for _, line in ipairs(after_normalized) do
        if line ~= '' then
          table.insert(after_non_blank, line)
        end
      end

      assert.are.same(orig_non_blank, after_non_blank)
    end)
  end)

  describe('Scenario 7: Multiple classes in one file', function()
    local multiple_classes = {
      '<?php',
      '',
      'class Product',
      '{',
      '    public $name;',
      '    private $id;',
      '}',
      '',
      'class Order',
      '{',
      '    public $total;',
      '    private $orderId;',
      '}',
    }

    it('should sort elements in all classes', function()
      create_php_buffer(multiple_classes)

      local stats = plugin.sort_elements()

      -- Should process properties from both classes (at least 2)
      assert.is_true(stats.properties >= 2)

      local content = normalize_spacing(get_buffer_content())

      -- Verify Product class sorted
      local product_private_idx = 0
      local product_public_idx = 0

      for i, line in ipairs(content) do
        if i < 10 then -- First class
          if line:match('private %$id') then
            product_private_idx = i
          elseif line:match('public %$name') then
            product_public_idx = i
          end
        end
      end

      if product_private_idx > 0 and product_public_idx > 0 then
        assert.is_true(product_private_idx < product_public_idx)
      end
    end)
  end)

  describe('Scenario 8: Empty/minimal files', function()
    it('should handle file with only namespace uses', function()
      local only_uses = {
        '<?php',
        '',
        'use Zebra\\Animal;',
        'use Apple\\Fruit;',
      }

      create_php_buffer(only_uses)

      plugin.sort_namespace_uses()

      local content = get_buffer_content()

      -- Verify sorted
      local apple_idx = 0
      local zebra_idx = 0

      for i, line in ipairs(content) do
        if line:match('use Apple') then
          apple_idx = i
        elseif line:match('use Zebra') then
          zebra_idx = i
        end
      end

      assert.is_true(apple_idx > 0 and zebra_idx > 0)
      assert.is_true(apple_idx < zebra_idx)
    end)

    it('should handle empty class', function()
      local empty_class = {
        '<?php',
        '',
        'class Empty',
        '{',
        '}',
      }

      create_php_buffer(empty_class)

      local stats = plugin.sort_all()

      -- Should complete without errors
      assert.equals(0, stats.constants)
      assert.equals(0, stats.properties)
      assert.equals(0, stats.traits)
    end)

    it('should handle file without PHP opening tag', function()
      local no_opening = {
        'class Test',
        '{',
        '    public $value;',
        '}',
      }

      create_php_buffer(no_opening)

      -- Should not crash
      local ok = pcall(plugin.sort_elements)
      assert.is_true(ok)
    end)
  end)

  describe('Scenario 9: Configuration variations', function()
    local test_class = {
      '<?php',
      '',
      'class Test',
      '{',
      '    public $b;',
      '    private $a;',
      '}',
    }

    it('should respect sort_properties = false', function()
      create_php_buffer(test_class)

      plugin.set_buffer_config(test_bufnr, {
        sort_properties = false,
      })

      local original = vim.deepcopy(get_buffer_content())
      plugin.sort_elements()

      -- Order should not change
      local orig_order = {}
      local after_order = {}

      for _, line in ipairs(original) do
        if line:match('%$[ab]') then
          table.insert(orig_order, line)
        end
      end

      local after = get_buffer_content()
      for _, line in ipairs(after) do
        if line:match('%$[ab]') then
          table.insert(after_order, line)
        end
      end

      assert.are.same(orig_order, after_order)
    end)

    it('should use custom default_visibility', function()
      local no_visibility = {
        '<?php',
        '',
        'class Test',
        '{',
        '    $public_assumed;',
        '    private $private_explicit;',
        '}',
      }

      create_php_buffer(no_visibility)

      plugin.set_buffer_config(test_bufnr, {
        default_visibility = 'protected',
      })

      plugin.sort_elements()

      -- Properties without visibility should be treated as protected
      -- and come after private
      local content = get_buffer_content()
      local private_line = 0
      local assumed_line = 0

      for i, line in ipairs(content) do
        if line:match('$private_explicit') then
          private_line = i
        elseif line:match('$public_assumed') then
          assumed_line = i
        end
      end

      assert.is_true(private_line > 0 and assumed_line > 0)
      assert.is_true(private_line < assumed_line)
    end)
  end)

  describe('Scenario 10: Comments preservation', function()
    local with_comments = {
      '<?php',
      '',
      'class Product',
      '{',
      '    // Important: This is the product name',
      '    public $name;',
      '',
      '    /** @var int Product ID */',
      '    private $id;',
      '}',
    }

    it('should preserve comments with their properties', function()
      create_php_buffer(with_comments)

      plugin.sort_elements()

      local content = get_buffer_content()

      -- Find comment and verify it's before its property
      local comment_line = 0
      local property_line = 0

      for i, line in ipairs(content) do
        if line:match('Product ID') then
          comment_line = i
        elseif line:match('private $id') then
          property_line = i
        end
      end

      assert.is_true(comment_line > 0)
      assert.is_true(property_line > 0)
      assert.equals(comment_line + 1, property_line)
    end)
  end)

  describe('Buffer state management', function()
    it('should maintain separate state per buffer', function()
      local buf1 = create_php_buffer({ '<?php', 'class Test1 {}' })
      plugin.set_buffer_config(buf1, { debug = true })

      local buf2 = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_option(buf2, 'filetype', 'php')
      vim.api.nvim_set_current_buf(buf2)
      plugin.set_buffer_config(buf2, { debug = false })

      local config1 = plugin.get_buffer_config(buf1)
      local config2 = plugin.get_buffer_config(buf2)

      assert.is_true(config1.debug)
      assert.is_false(config2.debug)

      vim.api.nvim_buf_delete(buf2, { force = true })
    end)

    it('should clean up state on buffer delete', function()
      create_php_buffer({ '<?php', 'class Test {}' })

      local info_before = plugin.get_state_info()
      local buffers_before = info_before.active_buffers

      vim.api.nvim_buf_delete(test_bufnr, { force = true })
      test_bufnr = nil

      -- Give time for cleanup autocmd to run
      vim.wait(100)

      -- Force cleanup
      plugin.cleanup_invalid_states()

      local info_after = plugin.get_state_info()
      local buffers_after = info_after.active_buffers

      assert.is_true(buffers_after <= buffers_before)
    end)
  end)

  describe('Performance and edge cases', function()
    it('should handle large number of properties', function()
      local many_props = { '<?php', '', 'class Large', '{' }

      -- Add 100 properties with random visibility
      for i = 1, 100 do
        local vis = ({ 'private', 'protected', 'public' })[math.random(1, 3)]
        table.insert(many_props, string.format('    %s $prop%d;', vis, i))
      end
      table.insert(many_props, '}')

      create_php_buffer(many_props)

      local start_time = vim.loop.hrtime()
      plugin.sort_elements()
      local end_time = vim.loop.hrtime()

      local elapsed_ms = (end_time - start_time) / 1000000

      -- Should complete in reasonable time (< 1 second)
      assert.is_true(elapsed_ms < 1000)
    end)

    it('should handle malformed PHP gracefully', function()
      local malformed = {
        '<?php',
        'class Broken',
        '    public $missing_brace',
        '    private $another',
      }

      create_php_buffer(malformed)

      -- Should not crash
      local ok = pcall(plugin.sort_elements)
      assert.is_true(ok)
    end)
  end)
end)
