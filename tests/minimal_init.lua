-- Minimal init for testing
local data_dir = vim.fn.stdpath('data') .. '/site/pack/vendor/start'
local treesitter_dir = data_dir .. '/nvim-treesitter'

-- Determine Plenary location (try lazy.nvim first, then vendor)
local plenary_dir = vim.fn.stdpath('data') .. '/lazy/plenary.nvim'
if vim.fn.isdirectory(plenary_dir) == 0 then
  plenary_dir = vim.fn.stdpath('data') .. '/site/pack/vendor/start/plenary.nvim'
end
-- Ensure data directory exists
vim.fn.mkdir(data_dir, 'p')

-- Clone plenary if not present
if vim.fn.isdirectory(plenary_dir) == 0 then
  vim.fn.system({
    'git',
    'clone',
    '--depth=1',
    'https://github.com/nvim-lua/plenary.nvim',
    plenary_dir,
  })
end
vim.opt.rtp:prepend(plenary_dir)

-- Clone nvim-treesitter if not present
if vim.fn.isdirectory(treesitter_dir) == 0 then
  vim.fn.system({
    'git',
    'clone',
    '--depth=1',
    'https://github.com/nvim-treesitter/nvim-treesitter',
    treesitter_dir,
  })
end
vim.opt.rtp:prepend(treesitter_dir)

-- Add current plugin to runtime path
vim.opt.rtp:append('.')

-- Try to setup treesitter
local function setup_treesitter()
  local ts_ok, ts_configs = pcall(require, 'nvim-treesitter.configs')
  if not ts_ok then
    print('Warning: nvim-treesitter not available')
    return false
  end

  -- Load treesitter runtime
  vim.cmd('silent! runtime! plugin/nvim-treesitter.lua')

  -- Setup treesitter
  ts_configs.setup({
    ensure_installed = {},
    sync_install = false,
    auto_install = false,
  })

  -- Check if PHP parser is available
  local parser_ok, parsers = pcall(require, 'nvim-treesitter.parsers')
  if parser_ok then
    local has_php = parsers.has_parser('php')
    if not has_php then
      print('PHP parser not installed. Attempting to install...')
      -- Try to install PHP parser
      local install_ok = pcall(vim.cmd, 'TSInstall php')
      if not install_ok then
        print('Warning: Could not install PHP parser automatically')
        print('Please run :TSInstall php manually')
        return false
      end
    else
      print('PHP parser is available')
    end
  else
    print('Warning: Could not check for PHP parser')
    return false
  end

  return true
end

-- Setup treesitter or provide mock
if not setup_treesitter() then
  print('Setting up treesitter mock for testing...')
  -- Mock treesitter modules if they're not available
  package.loaded['nvim-treesitter.parsers'] = {
    get_parser = function()
      return {
        parse = function()
          return {
            root = function()
              return {}
            end,
          }
        end,
        trees = function()
          return {}
        end,
      }
    end,
    has_parser = function()
      return false
    end,
  }

  package.loaded['nvim-treesitter'] = {
    get_parser = function()
      return {
        parse = function()
          return {}
        end,
      }
    end,
  }
end

-- Ensure PHP filetype is set correctly
vim.cmd([[
  augroup TestPHP
    autocmd!
    autocmd BufRead,BufNewFile *.php set filetype=php
  augroup END
]])

print('Minimal init loaded successfully')
print('Plenary path: ' .. plenary_dir)
print('Treesitter path: ' .. treesitter_dir)
print('Plugin path: ' .. vim.fn.getcwd())
