# PHP Elements Sorter

The PHP Elements Sorter is a Neovim plugin that automatically sorts various PHP 
elements within a buffer, such as namespace uses, traits, constants, and 
properties. It can also remove unused imports and add spacing between 
elements with different visibility modifiers.

## Features

- Sort namespace uses
- Sort traits
- Sort constants
- Sort properties
- Remove unused imports
- Add spacing between elements with different visibility modifiers (e.g., public, protected, private)
- Configurable options to enable/disable specific sorting behaviors

## Installation

1. Install the plugin using your preferred Neovim plugin manager. For example, with [packer.nvim](https://github.com/wbthomason/packer.nvim):

   ```lua
   use 'RicardoRamirezR/php-elements-sorter.nvim'
   ```

2. In your Neovim configuration, set up the plugin:

   ```lua
   require('php-elements-sorter').setup({
     -- Optional configuration overrides
     sort_properties = true,
     sort_traits = true,
     sort_namespace_uses = true,
     sort_constants = true,
     remove_unused_imports = true,
     add_newline_between_const_and_properties = true,
     add_visibility_spacing = true,
     default_visibility = 'public',
   })
   ```

## Usage

The plugin automatically sorts the PHP elements whenever a PHP file is written 
(`BufWritePre` event). You can also manually run the sorting command by executing `:SortPHPElements` in your Neovim instance.

## Configuration

The plugin provides several configuration options that you can customize to suit your preferences. Here's a breakdown of the available options:

- `sort_properties`: Sort property declarations (default: `true`)
- `sort_traits`: Sort trait uses (default: `true`)
- `sort_namespace_uses`: Sort namespace uses (default: `true`)
- `sort_constants`: Sort constant declarations (default: `true`)
- `remove_unused_imports`: Remove unused imports (default: `true`)
- `add_newline_between_const_and_properties`: Add a newline between constant and property declarations (default: `true`)
- `add_visibility_spacing`: Add spacing between elements with different visibility modifiers (e.g., public, protected, private) (default: `true`)
- `default_visibility`: The default visibility modifier to use if none is specified (default: `'public'`)

## Contributing

Contributions are welcome! If you encounter any issues or have suggestions for improvements, please feel free to open an issue or submit a pull request.

## License

This project is licensed under the [MIT License](LICENSE).

