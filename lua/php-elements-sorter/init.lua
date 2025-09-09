-- lua/php-elements-sorter/init.lua
-- Plugin entry point and public API
local M = {}

-- Default configuration
M.config = {
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
}

-- internal state (kept on module so we can pass `M` as state)
M.bufnr = nil
M.root = nil
M.lang = nil
M.prev_type = nil

-- expose modules (they expect a state table as first param)
local parser = require('php-elements-sorter.parser')
local sorters = require('php-elements-sorter.sorters')
local spacing = require('php-elements-sorter.spacing')
local actions = require('php-elements-sorter.actions')

--- Public wrappers to pass state
function M.sort_all_impl()
  sorters.sort_all_impl(M)
end

function M.sort_namespace_uses()
  sorters.sort_namespace_uses_impl(M)
end

function M.remove_unused_uses()
  sorters.remove_unused_namespace_uses_impl(M)
end

function M.sort_elements()
  sorters.process_and_sort_elements(M, 0, -1)
end

function M.sort_all()
  M.sort_all_impl()
end

function M.get_code_actions()
  return actions.get_code_actions(M)
end

function M.code_action()
  actions.code_action(M)
end

--- Setup plugin, register commands and LSP command shims
---@param user_config table?
function M.setup(user_config)
  M.config = vim.tbl_deep_extend('force', M.config, user_config or {})

  -- Register lsp.commands shim so LSP -> plugin calls work
  vim.lsp.commands = vim.lsp.commands or {}
  vim.lsp.commands['php_elements_sorter.sort_namespace_uses'] = function()
    M.sort_namespace_uses()
  end
  vim.lsp.commands['php_elements_sorter.remove_unused_uses'] = function()
    M.remove_unused_uses()
  end
  vim.lsp.commands['php_elements_sorter.sort_elements'] = function()
    M.sort_elements()
  end
  vim.lsp.commands['php_elements_sorter.sort_all'] = function()
    M.sort_all()
  end

  -- Override buf.code_action when filetype == php to show our combined UI
  local ok, orig_code_action = pcall(function()
    return vim.lsp.buf.code_action
  end)
  if ok and orig_code_action then
    vim.lsp.buf.code_action = function(ctx, opts)
      if vim.bo.filetype == 'php' then
        M.code_action()
      else
        orig_code_action(ctx, opts)
      end
    end
  else
    -- If unable to get original, just set our implementation for php
    vim.lsp.buf.code_action = function(ctx, opts)
      if vim.bo.filetype == 'php' then
        M.code_action()
      end
    end
  end

  -- Create user command
  pcall(vim.api.nvim_create_user_command, 'SortPhpElements', function()
    M.sort_all()
  end, {})

  -- Return module for convenience
  return M
end

return M
