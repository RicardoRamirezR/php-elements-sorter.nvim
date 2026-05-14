# php-elements-sorter.nvim

A Neovim plugin for automatically sorting and organizing PHP code elements using Tree-sitter.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Neovim](https://img.shields.io/badge/Neovim-0.9+-green.svg)](https://neovim.io)

## Features

- Sort namespace use statements alphabetically
- Remove unused imports automatically
- Sort class properties by visibility (private, protected, public)
- Sort constants alphabetically
- Sort trait uses alphabetically
- Smart spacing between elements (configurable)
- LSP integration with code actions
- Preview changes before applying

## Requirements

- Neovim >= 0.9.0
- [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter)
- Tree-sitter PHP parser (`:TSInstall php`)

## Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  'RicardoRamirezR/php-elements-sorter.nvim',
  dependencies = {
    'nvim-treesitter/nvim-treesitter',
  },
  ft = 'php',
  config = function()
    require('php-elements-sorter').setup()
  end,
}
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'RicardoRamirezR/php-elements-sorter.nvim',
  requires = { 'nvim-treesitter/nvim-treesitter' },
  ft = 'php',
  config = function()
    require('php-elements-sorter').setup()
  end
}
```

## Configuration

```lua
require('php-elements-sorter').setup({
  -- Add blank line when visibility changes (private -> public)
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

### Per-buffer configuration

```lua
local bufnr = vim.api.nvim_get_current_buf()
require('php-elements-sorter').set_buffer_config(bufnr, {
  sort_properties = false,
  debug = true,
})
```

## Usage

### Commands

| Command | Description |
|---------|-------------|
| `:SortPhpElements` | Sort all PHP elements (uses, traits, properties, constants) |
| `:SortPhpNamespaceUses` | Sort only namespace use statements |
| `:SortPhpClassElements` | Sort only class elements (properties, constants, traits) |
| `:RemoveUnusedUses` | Remove unused use statements |
| `:SortPhpElementsPreview` | Preview all sorting changes before applying |
| `:SortPhpNamespaceUsesPreview` | Preview namespace use sorting |
| `:SortPhpClassElementsPreview` | Preview class element sorting |

Diagnostic commands:

| Command | Description |
|---------|-------------|
| `:PhpSorterInfo` | Show plugin diagnostic information |
| `:PhpSorterCleanup` | Clean up invalid buffer states |
| `:PhpSorterValidateConfig` | Validate current configuration |
| `:PhpSorterTimerStats` | Show timer statistics |

### Lua API

```lua
local sorter = require('php-elements-sorter')

-- Sort all elements
local stats = sorter.sort_all()
-- returns { uses, removed, constants, properties, traits }

-- Sort specific elements
sorter.sort_namespace_uses()
sorter.sort_elements()
sorter.remove_unused_uses()

-- Preview before applying
sorter.preview_all()
sorter.preview_namespace_uses()
sorter.preview_elements()
```

### LSP Code Actions

The plugin integrates with Neovim's LSP to provide code actions in PHP files:

1. Place cursor in a PHP file
2. Trigger code actions: `:lua vim.lsp.buf.code_action()`
3. Select from available actions:
   - Sort namespace uses
   - Remove unused use statements
   - Sort properties/constants/traits
   - Sort all PHP elements

### Keymaps example

```lua
vim.keymap.set('n', '<leader>ps', '<cmd>SortPhpElements<CR>', { desc = 'Sort PHP elements' })
vim.keymap.set('n', '<leader>pu', '<cmd>SortPhpNamespaceUses<CR>', { desc = 'Sort PHP uses' })
vim.keymap.set('n', '<leader>pr', '<cmd>RemoveUnusedUses<CR>', { desc = 'Remove unused uses' })
vim.keymap.set('n', '<leader>pp', '<cmd>SortPhpElementsPreview<CR>', { desc = 'Preview PHP sorting' })
```

## Example

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

What changed:
- Use statements sorted alphabetically
- Constants sorted alphabetically
- Properties sorted by visibility (private, protected, public)
- Blank lines between visibility groups
- Blank line between constants and properties

## Troubleshooting

### Plugin not working

1. Check PHP parser is installed:
   ```vim
   :TSInstall php
   :checkhealth nvim-treesitter
   ```

2. Enable debug logging:
   ```lua
   require('php-elements-sorter').setup({ debug = true })
   ```

3. Check plugin state:
   ```vim
   :PhpSorterInfo
   ```

### LSP integration not working

1. Verify LSP is running:
   ```vim
   :LspInfo
   ```

2. Check code action support:
   ```lua
   local clients = vim.lsp.get_clients({ bufnr = 0 })
   for _, client in ipairs(clients) do
     print(client.name, client.supports_method('textDocument/codeAction'))
   end
   ```

## Testing

```bash
# Run all tests
nvim --headless -c "PlenaryBustedDirectory lua/tests/"

# Run specific test file
nvim --headless -c "PlenaryBustedFile lua/tests/result_pattern_spec.lua"
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Run tests
4. Open a Pull Request

### Development setup

```bash
git clone https://github.com/RicardoRamirezR/php-elements-sorter.nvim.git
cd php-elements-sorter.nvim

# Install dependencies for testing
git clone https://github.com/nvim-lua/plenary.nvim.git ~/.local/share/nvim/site/pack/vendor/start/plenary.nvim
git clone https://github.com/nvim-treesitter/nvim-treesitter.git ~/.local/share/nvim/site/pack/vendor/start/nvim-treesitter

# Run tests
nvim --headless -c "PlenaryBustedDirectory lua/tests/"
```

## License

MIT License - see [LICENSE](LICENSE) for details.
