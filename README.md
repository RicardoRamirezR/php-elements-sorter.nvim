# php-elements-sorter.nvim

A powerful Neovim plugin for automatically sorting and organizing PHP code elements using Tree-sitter.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Neovim](https://img.shields.io/badge/Neovim-0.9+-green.svg)](https://neovim.io)

## ✨ Features

- 🔤 **Sort namespace use statements** alphabetically
- 🧹 **Remove unused imports** automatically
- 📦 **Sort class properties** by visibility (private → protected → public)
- 🎯 **Sort constants** alphabetically
- 🔧 **Sort trait uses** alphabetically
- 🎨 **Smart spacing** between elements (configurable)
- ⚡ **Fast and reliable** using Tree-sitter
- 🔌 **LSP integration** with code actions
- 📊 **Statistics tracking** for debugging
- 🛡️ **Type-safe** with Result pattern
- ⏱️ **Memory-safe** timer management

## 📋 Requirements

- Neovim >= 0.9.0
- [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter)
- Tree-sitter PHP parser (`:TSInstall php`)

## 📦 Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  'your-username/php-elements-sorter.nvim',
  dependencies = {
    'nvim-treesitter/nvim-treesitter',
  },
  ft = 'php',
  config = function()
    require('php-elements-sorter').setup({
      -- Configuration options (see below)
    })
  end,
}
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'your-username/php-elements-sorter.nvim',
  requires = { 'nvim-treesitter/nvim-treesitter' },
  ft = 'php',
  config = function()
    require('php-elements-sorter').setup()
  end
}
```

### [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'nvim-treesitter/nvim-treesitter'
Plug 'your-username/php-elements-sorter.nvim'
```

Then in your `init.lua`:
```lua
require('php-elements-sorter').setup()
```

## ⚙️ Configuration

### Default Configuration

```lua
require('php-elements-sorter').setup({
  -- Add blank line when visibility changes (private → public)
  add_visibility_spacing = true,
  
  -- Sort class properties
  sort_properties = true,
  
  -- Sort trait uses
  sort_traits = true,
  
  -- Sort namespace use statements
  sort_namespace_uses = true,
  
  -- Sort constants
  sort_constants = true,
  
  -- Default visibility for elements without explicit visibility
  default_visibility = 'public', -- 'public' | 'protected' | 'private'
  
  -- Remove unused namespace use statements
  remove_unused_imports = true,
  
  -- Add newline between constants and properties
  add_newline_between_const_and_properties = true,
  
  -- Add newline after namespace use statements
  add_newline_after_namespace_uses = true,
  
  -- Add newline after trait uses
  add_newline_after_trait_uses = true,
  
  -- Enable debug logging
  debug = false,
  
  -- Auto-sort on save (disabled by default)
  auto_sort_on_save = false,
})
```

### Per-Buffer Configuration

You can override configuration for specific buffers:

```lua
local bufnr = vim.api.nvim_get_current_buf()
require('php-elements-sorter').set_buffer_config(bufnr, {
  sort_properties = false,
  debug = true,
})
```

## 🚀 Usage

### Commands

```vim
:SortPhpElements           " Sort all PHP elements (uses, traits, properties, constants)
:SortPhpNamespaceUses      " Sort only namespace use statements
:SortPhpClassElements      " Sort only class elements (properties, constants, traits)
:RemoveUnusedUses          " Remove unused use statements

" Diagnostic commands
:PhpSorterInfo             " Show plugin diagnostic information
:PhpSorterCleanup          " Clean up invalid buffer states
:PhpSorterValidateConfig   " Validate current configuration
:PhpSorterTimerStats       " Show timer statistics
```

### Lua API

```lua
local sorter = require('php-elements-sorter')

-- Sort all elements
local stats = sorter.sort_all()
print(vim.inspect(stats))
-- {
--   uses = 5,          -- Number of use statements sorted
--   removed = 2,       -- Number of unused imports removed
--   constants = 3,     -- Number of constants sorted
--   properties = 10,   -- Number of properties sorted
--   traits = 2         -- Number of traits sorted
-- }

-- Sort specific elements
sorter.sort_namespace_uses()
sorter.sort_elements()
sorter.remove_unused_uses()

-- Get plugin state
local info = sorter.get_state_info()
print(vim.inspect(info))
```

### LSP Code Actions

The plugin integrates with Neovim's LSP to provide code actions:

1. Place cursor in a PHP file
2. Trigger code actions: `<leader>ca` or `:lua vim.lsp.buf.code_action()`
3. Select from available actions:
   - Sort namespace uses
   - Remove unused use statements
   - Sort properties/constants/traits
   - Sort all PHP elements

### Keymaps Example

```lua
-- Add to your init.lua
vim.keymap.set('n', '<leader>ps', '<cmd>SortPhpElements<CR>', { desc = 'Sort PHP elements' })
vim.keymap.set('n', '<leader>pu', '<cmd>SortPhpNamespaceUses<CR>', { desc = 'Sort PHP uses' })
vim.keymap.set('n', '<leader>pr', '<cmd>RemoveUnusedUses<CR>', { desc = 'Remove unused uses' })
```

## 📖 Examples

### Before

```php
<?php

use Zebra\Animal;
use Apple\Fruit;
use Banana\Fruit;

class Product
{
    const STATUS_INACTIVE = 0;
    const STATUS_ACTIVE = 1;
    public $name;
    private $id;
    protected $description;
    private $price;
    public $category;
}
```

### After `:SortPhpElements`

```php
<?php

use Apple\Fruit;
use Banana\Fruit;
use Zebra\Animal;

class Product
{
    const STATUS_ACTIVE = 1;
    const STATUS_INACTIVE = 0;

    private $id;
    private $price;

    protected $description;

    public $category;
    public $name;
}
```

### Features Demonstrated:
- ✅ Use statements sorted alphabetically
- ✅ Constants sorted alphabetically
- ✅ Properties sorted by visibility (private → protected → public)
- ✅ Blank lines between visibility groups
- ✅ Blank line between constants and properties

## 🔧 Advanced Usage

### Timer Management

The plugin includes a sophisticated timer manager for debouncing and throttling operations:

```lua
local timer = require('php-elements-sorter.utils.timer')

-- Create a debounced timer (cancels previous with same key)
timer.debounce('my_operation', 500, function()
  print('Debounced!')
end)

-- Create a throttled timer (skips if already running)
timer.throttle('my_operation', 1000, function()
  print('Throttled!')
end)

-- Get timer statistics
local stats = timer.get_stats()
print(vim.inspect(stats))

-- Check for leaks
local report = timer.check_leaks()
if report.has_leaks then
  print('Warning: Potential timer leaks detected!')
end
```

### Result Pattern

The plugin uses a Result pattern for type-safe error handling:

```lua
local Result = require('php-elements-sorter.utils.result')

-- Create results
local success = Result.ok(42)
local failure = Result.err('Something went wrong')

-- Check results
if Result.is_ok(success) then
  print('Value:', success.value)
end

-- Chain operations
local result = Result.ok(10)
  :map(function(x) return x * 2 end)
  :and_then(function(x)
    return Result.ok(x + 5)
  end)

-- Pattern matching
Result.match(result, {
  ok = function(value)
    print('Success:', value)
  end,
  err = function(error)
    print('Error:', error)
  end
})
```

### LSP Validation

Comprehensive LSP range validation utilities:

```lua
local lsp = require('php-elements-sorter.utils.lsp')

-- Validate range
local range = {
  start = { line = 0, character = 0 },
  ['end'] = { line = 10, character = 20 }
}

local result = lsp.validate_range(range)
if Result.is_ok(result) then
  print('Valid range!')
end

-- Check if position is in range
local position = { line = 5, character = 10 }
local in_range = lsp.position_in_range(position, range)

-- Check if ranges overlap
local overlap = lsp.ranges_overlap(range1, range2)
```

## 🐛 Troubleshooting

### Plugin Not Working

1. **Check PHP parser is installed:**
   ```vim
   :TSInstall php
   :checkhealth nvim-treesitter
   ```

2. **Enable debug logging:**
   ```lua
   require('php-elements-sorter').setup({ debug = true })
   ```

3. **Check plugin state:**
   ```vim
   :PhpSorterInfo
   ```

### Performance Issues

1. **Check for timer leaks:**
   ```vim
   :PhpSorterTimerStats
   ```

2. **Clean up invalid states:**
   ```vim
   :PhpSorterCleanup
   ```

3. **Disable auto-sort on save if enabled:**
   ```lua
   require('php-elements-sorter').setup({
     auto_sort_on_save = false
   })
   ```

### LSP Integration Not Working

1. **Verify LSP is running:**
   ```vim
   :LspInfo
   ```

2. **Check code action support:**
   ```lua
   local clients = vim.lsp.get_clients({ bufnr = 0 })
   for _, client in ipairs(clients) do
     print(client.name, client.supports_method('textDocument/codeAction'))
   end
   ```

## 📊 Statistics and Diagnostics

### Get State Information

```lua
local info = require('php-elements-sorter').get_state_info()
print(vim.inspect(info))
-- {
--   active_buffers = 3,
--   states = {
--     { bufnr = 1, valid = true, has_parser = true, ... },
--     ...
--   },
--   timer_stats = {
--     active = 2,
--     created = 10,
--     stopped = 8,
--     completed = 7,
--     leaked = 0
--   }
-- }
```

### Validate Configuration

```lua
local valid, err = require('php-elements-sorter').validate_config()
if not valid then
  print('Config error:', err)
end
```

## 🧪 Testing

The plugin includes comprehensive test coverage:

```bash
# Run all tests
nvim --headless -c "PlenaryBustedDirectory lua/tests/"

# Run specific test file
nvim --headless -c "PlenaryBustedFile lua/tests/result_pattern_spec.lua"

# Test categories
lua/tests/php-elements-sorter_spec.lua    # Basic functionality
lua/tests/critical_fixes_spec.lua         # Race conditions & memory leaks
lua/tests/medium_fixes_spec.lua           # Configuration & caching
lua/tests/result_pattern_spec.lua         # Result pattern (45 tests)
lua/tests/lsp_validation_spec.lua         # LSP validation (55+ tests)
lua/tests/timer_manager_spec.lua          # Timer management (40 tests)
lua/tests/spacing_utils_spec.lua          # Spacing utilities (19 tests)
```

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Run tests (`nvim --headless -c "PlenaryBustedDirectory lua/tests/"`)
4. Commit your changes (`git commit -m 'Add amazing feature'`)
5. Push to the branch (`git push origin feature/amazing-feature`)
6. Open a Pull Request

### Development Setup

```bash
# Clone the repository
git clone https://github.com/your-username/php-elements-sorter.nvim.git
cd php-elements-sorter.nvim

# Install dependencies for testing
git clone https://github.com/nvim-lua/plenary.nvim.git ~/.local/share/nvim/site/pack/vendor/start/plenary.nvim
git clone https://github.com/nvim-treesitter/nvim-treesitter.git ~/.local/share/nvim/site/pack/vendor/start/nvim-treesitter

# Run tests
nvim --headless -c "PlenaryBustedDirectory lua/tests/"
```

## 📝 Changelog

See [CHANGELOG.md](CHANGELOG.md) for a detailed history of changes.

## 📄 License

MIT License - see [LICENSE](LICENSE) for details.

## 🙏 Acknowledgments

- [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) for Tree-sitter integration
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) for Lua utilities
- Inspired by various PHP formatting tools and IDE features

## 📚 Related Projects

- [prettier-plugin-php](https://github.com/prettier/plugin-php)
- [PHP-CS-Fixer](https://github.com/PHP-CS-Fixer/PHP-CS-Fixer)
- [phpactor](https://github.com/phpactor/phpactor)

---

**Made with ❤️ for the Neovim community**
