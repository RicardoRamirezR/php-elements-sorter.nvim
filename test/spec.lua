local sorter = require('php-elements-sorter')

describe('PHP Elements Sorter', function()
  before_each(function()
    sorter.setup()
  end)

  it('should sort namespace uses', function()
    local namespace_uses = {
      { node = { type = 'namespace_use_declaration' }, node_lines = { 'use Foo\\Bar;' } },
      { node = { type = 'namespace_use_declaration' }, node_lines = { 'use Foo\\Baz;' } },
    }
    local sorted_uses = sorter.sort_and_update(namespace_uses, function(a, b)
      return sorter.compare_nodes(a, b, false)
    end, false)
    assert.equal(sorted_uses, true)
    assert.are_same({ 'use Foo\\Baz;', 'use Foo\\Bar;' }, namespace_uses[1].node_lines)
  end)

  it('should remove unused imports', function()
    local removes = {
      {
        node = {
          start = function()
            return 1
          end,
        },
        comment = {
          start = function()
            return 0
          end,
        }
      },
    }
    sorter.remove_from_buffer(removes)
    -- Assert that the buffer has been updated
  end)

  it('should add visibility spacing', function()
    local properties = {
      {
        node = { type = 'property_declaration' },
        comment_lines = {},
        node_lines = { 'private $foo;' },
      },
      {
        node = { type = 'property_declaration' },
        comment_lines = {},
        node_lines = { 'public $bar;' },
      },
    }
    local sorted_properties = sorter.sort_and_update(properties, function(a, b)
      return sorter.compare_nodes(a, b, true)
    end, true)
    assert.equal(sorted_properties, true)
    assert.are_same({ '', 'private $foo;', 'public $bar;' }, properties[1].node_lines)
  end)
end)
