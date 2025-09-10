# PHP Elements Sorter

**PHP Elements Sorter** is a Neovim plugin written in Lua that organizes and improves the readability of your PHP classes by sorting and formatting different elements consistently.  
It uses [Tree-sitter](https://tree-sitter.github.io/tree-sitter/) to parse PHP code and provides **code actions** for an LSP-like workflow.

## ✨ Features

- Sort `namespace use` statements
- Remove unused `namespace use` statements
- Sort traits, constants, and properties
- Add spacing:
  - Between different visibility modifiers (`public`, `protected`, `private`)
  - Between constants and properties
  - Between namespace uses and the class definition
  - Between traits/properties and methods
- Configurable defaults
- Integrated **Code Actions**:
  - Sort namespace uses
  - Remove unused namespace uses
  - Sort traits/constants/properties
  - Sort all PHP elements
- Works standalone or alongside your LSP (e.g., Intelephense, PHP Actor)
- Telescope integration for a polished UI (falls back to `vim.ui.select` if Telescope is not available)

---

## 📦 Installation

With [packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use 'ricardoramirezr/php-elements-sorter.nvim'
```

---

## ⚙️ Setup

In your Neovim config:

```lua
require('php-elements-sorter').setup({
  -- Sorting options
  sort_properties = true,
  sort_traits = true,
  sort_namespace_uses = true,
  sort_constants = true,

  -- Imports
  remove_unused_imports = true,

  -- Spacing options
  add_newline_between_const_and_properties = true,
  add_visibility_spacing = true,
  add_newline_after_namespace_uses = true,
  add_newline_after_trait_uses = true,

  -- Default visibility for properties without modifiers
  default_visibility = 'public',
})
```

---

## 🚀 Usage

### Commands

- `:SortPhpElements` → Sort **all PHP elements** in the current buffer

### Code Actions

When editing a PHP file, trigger code actions `gra`. You’ll see:

1. **Sort namespace uses**  
2. **Remove unused namespace uses**  
3. **Sort properties/constants/traits**  
4. **Sort all PHP elements**

If [Telescope](https://github.com/nvim-telescope/telescope.nvim) is installed, the actions appear in a searchable picker.  
Otherwise, they are shown via the built-in `vim.ui.select`.

---

## ⚙️ Configuration Options

- `sort_properties`: Sort property declarations (default: `true`)  
- `sort_traits`: Sort trait uses (default: `true`)  
- `sort_namespace_uses`: Sort namespace uses (default: `true`)  
- `sort_constants`: Sort constant declarations (default: `true`)  
- `remove_unused_imports`: Remove unused imports (default: `true`)  
- `add_newline_between_const_and_properties`: Add a newline between constant and property declarations (default: `true`)  
- `add_visibility_spacing`: Add spacing between elements with different visibility modifiers (default: `true`)  
- `add_newline_after_namespace_uses`: Add a newline after the last namespace use block (default: `true`)  
- `add_newline_after_trait_uses`: Add a newline after the last trait use (default: `true`)  
- `default_visibility`: The default visibility modifier for properties without explicit visibility (default: `'public'`)  

---

## 🤝 Contributing

Contributions are welcome! If you encounter issues or have ideas for improvements, please open an issue or submit a PR.

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).

