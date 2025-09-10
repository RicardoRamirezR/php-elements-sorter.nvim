-- lua/php-elements-sorter/actions.lua
-- Collect LSP code actions, merge with plugin custom ones, show UI and execute selection

local M = {}
local parser = require('php-elements-sorter.parser')
local ui = require('php-elements-sorter.ui')

--- Produce plugin-specific actions
local function plugin_actions()
  return {
    {
      title = 'Sort namespace uses',
      kind = 'source.organizeImports',
      command = {
        title = 'Sort namespace uses',
        command = 'php_elements_sorter.sort_namespace_uses',
      },
      is_custom = true,
    },
    {
      title = 'Remove unused use statements',
      kind = 'source.organizeImports',
      command = {
        title = 'Remove unused use statements',
        command = 'php_elements_sorter.remove_unused_uses',
      },
      is_custom = true,
    },
    {
      title = 'Sort properties/constants/traits',
      kind = 'source.organizeImports',
      command = { title = 'Sort elements', command = 'php_elements_sorter.sort_elements' },
      is_custom = true,
    },
    {
      title = 'Sort all PHP elements',
      kind = 'source.organizeImports',
      command = { title = 'Sort all', command = 'php_elements_sorter.sort_all' },
      is_custom = true,
    },
  }
end

--- Execute action (handles LSP action objects and plugin custom commands)
local function execute_action(action)
  -- LSP-style action with edit
  if action.edit then
    local ok, encoding = pcall(function()
      -- best-effort find client encoding; default to utf-16
      local client = vim.lsp.get_client_by_id(action.client_id)
      return client and client.offset_encoding or 'utf-16'
    end)
    encoding = encoding or 'utf-16'
    vim.lsp.util.apply_workspace_edit(action.edit, encoding)
  end

  -- LSP style command
  if action.command and not action.is_custom then
    -- action.command may be a table or string
    pcall(function()
      if type(action.command) == 'string' then
        vim.lsp.buf.execute_command({ command = action.command })
      else
        vim.lsp.buf.execute_command(action.command)
      end
    end)
  end

  -- Custom plugin command: string like "php_elements_sorter.sort_all" registered in vim.lsp.commands
  if action.is_custom and action.command and action.command.command then
    local cmd_str = action.command.command
    local cmd_fn = vim.lsp.commands and vim.lsp.commands[cmd_str]
    if type(cmd_fn) == 'function' then
      pcall(cmd_fn)
      return
    end
    -- fallback: require plugin module and attempt to call function without prefix
    local ok, plugin = pcall(require, 'php-elements-sorter')
    if ok and plugin then
      local func_name = cmd_str:gsub('php_elements_sorter%.', '')
      if plugin[func_name] and type(plugin[func_name]) == 'function' then
        pcall(plugin[func_name])
      end
    end
  end
end

--- Gather LSP code actions and merge with plugin actions, then show UI
function M.code_action(state)
  -- If no class present, nothing to offer
  if not parser.has_class(state) then
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local clients = vim.lsp.get_clients({ bufnr = bufnr })

  local offer_plugin_actions = {}
  for _, a in ipairs(plugin_actions()) do
    table.insert(offer_plugin_actions, a)
  end

  -- If no LSP clients, show only plugin actions
  if #clients == 0 then
    local used = ui.show_code_actions_with_telescope(offer_plugin_actions, function(action)
      execute_action(action)
    end)
    if not used then
      ui.show_code_actions_with_ui_select(offer_plugin_actions, function(action)
        execute_action(action)
      end)
    end
    return
  end

  -- Build LSP params (cursor-based range)
  local params = (function()
    local pos = vim.api.nvim_win_get_cursor(0)
    local line = pos[1] - 1
    local line_content = vim.api.nvim_buf_get_lines(bufnr, line, line + 1, false)[1] or ''
    return {
      textDocument = vim.lsp.util.make_text_document_params(bufnr),
      range = {
        start = { line = line, character = 0 },
        ['end'] = { line = line, character = #line_content },
      },
      context = {
        diagnostics = vim.diagnostic.get(bufnr, { lnum = line }),
        only = nil,
      },
    }
  end)()

  -- Request all clients
  vim.lsp.buf_request_all(bufnr, 'textDocument/codeAction', params, function(results)
    local actions = {}
    -- plugin actions first (custom)
    for _, a in ipairs(offer_plugin_actions) do
      table.insert(actions, a)
    end

    -- collect LSP responses
    for client_id, res in pairs(results) do
      if res and res.result then
        local client = vim.lsp.get_client_by_id(client_id)
        local client_name = client and client.name or 'unknown'
        for _, act in ipairs(res.result) do
          act.client_id = client_id
          act.client_name = client_name
          act.is_lsp = true
          table.insert(actions, act)
        end
      end
    end

    if #actions == 0 then
      vim.notify('No code actions available', vim.log.levels.INFO)
      return
    end

    local used = ui.show_code_actions_with_telescope(actions, function(action)
      execute_action(action)
    end)
    if not used then
      ui.show_code_actions_with_ui_select(actions, function(action)
        execute_action(action)
      end)
    end
  end)
end

--- Expose plugin-only actions (used by init.get_code_actions compatibility)
function M.get_code_actions(state)
  return plugin_actions()
end

return M
