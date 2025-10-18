-- lua/php-elements-sorter/actions.lua
-- Collect LSP code actions, merge with plugin custom ones, show UI and execute selection

local M = {}
local log = require('php-elements-sorter.log')
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

--- Build safe diagnostics from Neovim diagnostics
local function build_safe_diagnostics(diagnostics)
  local safe = {}
  local skipped = 0

  for _, nvim_diag in ipairs(diagnostics) do
    local lsp_data = nvim_diag.user_data and nvim_diag.user_data.lsp
    if lsp_data and lsp_data.range then
      local start = lsp_data.range.start
      local end_pos = lsp_data.range['end']

      if
          start
          and end_pos
          and start.line ~= nil
          and start.character ~= nil
          and end_pos.line ~= nil
          and end_pos.character ~= nil
      then
        table.insert(safe, {
          range = {
            start = { line = start.line, character = start.character },
            ['end'] = { line = end_pos.line, character = end_pos.character },
          },
          message = lsp_data.message or nvim_diag.message or '',
          severity = lsp_data.severity or nvim_diag.severity,
          code = lsp_data.code or nvim_diag.code,
          source = lsp_data.source or nvim_diag.source,
        })
      else
        skipped = skipped + 1
      end
    else
      skipped = skipped + 1
    end
  end

  if skipped > 0 then
    log.debug(string.format('Skipped %d diagnostics with invalid LSP range data', skipped))
  end

  return safe
end

--- Show actions using the available UI method
local function show_actions(actions, execute_fn)
  local used = ui.show_code_actions_with_telescope(actions, execute_fn)
  if not used then
    ui.show_code_actions_with_ui_select(actions, execute_fn)
  end
end

--- Execute action (handles LSP action objects and plugin custom commands)
local function execute_action(action)
  log.debug(
    string.format(
      'Executing action: "%s" (is_custom: %s, is_lsp: %s)',
      action.title or 'unknown',
      tostring(action.is_custom or false),
      tostring(action.is_lsp or false)
    )
  )

  if action.edit then
    local ok, encoding = pcall(function()
      local client = vim.lsp.get_client_by_id(action.client_id)
      return client and client.offset_encoding or 'utf-16'
    end)
    encoding = encoding or 'utf-16'
    log.debug('Applying workspace edit with encoding: ' .. encoding)
    vim.lsp.util.apply_workspace_edit(action.edit, encoding)
  end

  if action.command and not action.is_custom then
    log.debug('Executing LSP command: ' .. vim.inspect(action.command))
    pcall(function()
      if type(action.command) == 'string' then
        vim.lsp.buf.execute_command({ command = action.command })
      else
        vim.lsp.buf.execute_command(action.command)
      end
    end)
  end

  if action.is_custom and action.command and action.command.command then
    local cmd_str = action.command.command
    log.debug('Executing custom command: ' .. cmd_str)

    local cmd_fn = vim.lsp.commands and vim.lsp.commands[cmd_str]
    if type(cmd_fn) == 'function' then
      pcall(cmd_fn)
      return
    end

    local ok, plugin = pcall(require, 'php-elements-sorter')
    if ok and plugin then
      local func_name = cmd_str:gsub('php_elements_sorter%.', '')
      if plugin[func_name] and type(plugin[func_name]) == 'function' then
        pcall(plugin[func_name])
      else
        log.debug('Custom function not found: ' .. func_name, vim.log.levels.WARN)
      end
    else
      log.debug('Failed to load php-elements-sorter plugin', vim.log.levels.WARN)
    end
  end
end

--- Build LSP request params
local function build_request_params(bufnr, encoding, ctx, opts)
  local current_win = vim.api.nvim_get_current_win()
  local ok_params, params = pcall(vim.lsp.util.make_range_params, current_win, encoding)

  if not ok_params or type(params) ~= 'table' then
    return nil, 'Failed to build LSP params: ' .. (ok_params and 'result not a table' or params)
  end

  local safe_context = {}

  if opts and opts.only then
    safe_context.only = opts.only
  end

  if ctx.diagnostics and vim.tbl_count(ctx.diagnostics) > 0 then
    local safe_diagnostics = build_safe_diagnostics(ctx.diagnostics)
    if #safe_diagnostics > 0 then
      safe_context.diagnostics = safe_diagnostics
    end
  end

  params.context = safe_context
  return params, nil
end

--- Gather LSP code actions and merge with plugin actions, then show UI
function M.code_action(state, ctx, opts)
  ctx = ctx or {}
  local bufnr = vim.api.nvim_get_current_buf()

  log.debug('Starting code_action for buffer ' .. bufnr)

  local first_client = vim.lsp.get_clients({ bufnr = bufnr })[1]
  local encoding = first_client and first_client.offset_encoding or 'utf-16'

  if not ctx.range then
    local ok_make, range_params = pcall(vim.lsp.util.make_range_params, encoding)
    if ok_make and range_params and range_params.range then
      ctx.range = range_params.range
    else
      ctx.range = { start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 0 } }
    end
  end
  ctx.diagnostics = ctx.diagnostics or vim.diagnostic.get(bufnr)

  -- Get plugin actions (always available)
  local actions = vim.deepcopy(plugin_actions())
  log.debug('Loaded ' .. #actions .. ' plugin actions')

  -- Early return if no class found (optional: consider removing this restriction)
  if not parser.has_class(state) then
    log.debug('No class found in buffer, showing plugin actions only')
    show_actions(actions, execute_action)
    return
  end

  -- Check for LSP clients that support code actions
  local clients = vim.lsp.get_clients({
    bufnr = bufnr,
    filter = function(client)
      return client.supports_method('textDocument/codeAction')
    end,
  })

  log.debug('Found ' .. #clients .. ' LSP clients supporting codeAction')

  -- If no LSP clients, show plugin actions only
  if #clients == 0 then
    log.debug('No LSP clients available, showing plugin actions only')
    show_actions(actions, execute_action)
    return
  end

  -- Build LSP request params
  local params, err = build_request_params(bufnr, encoding, ctx, opts)
  if not params then
    log.debug(
      'Failed to build LSP params: ' .. err .. ', showing plugin actions only',
      vim.log.levels.WARN
    )
    show_actions(actions, execute_action)
    return
  end

  log.debug('Requesting code actions from LSP clients')

  -- Request code actions from all LSP clients
  vim.lsp.buf_request_all(bufnr, 'textDocument/codeAction', params, function(results)
    local lsp_action_count = 0

    for client_id, res in pairs(results) do
      if res and res.result then
        local client = vim.lsp.get_client_by_id(client_id)
        local client_name = client and client.name or 'unknown'
        local count = #res.result

        log.debug(string.format('LSP client "%s" returned %d actions', client_name, count))
        lsp_action_count = lsp_action_count + count

        for _, act in ipairs(res.result) do
          act.client_id = client_id
          act.client_name = client_name
          act.is_lsp = true
          table.insert(actions, act)
        end
      elseif res and res.err then
        local client = vim.lsp.get_client_by_id(client_id)
        local client_name = client and client.name or 'unknown'
        log.debug(
          string.format('LSP client "%s" returned error: %s', client_name, vim.inspect(res.err)),
          vim.log.levels.WARN
        )
      end
    end

    log.debug(
      string.format(
        'Total actions available: %d (plugin: %d, LSP: %d)',
        #actions,
        #plugin_actions(),
        lsp_action_count
      )
    )

    -- Always show actions (plugin actions are always available)
    show_actions(actions, execute_action)
  end)
end

--- Get plugin-specific code actions
function M.get_code_actions(state)
  return plugin_actions()
end

return M
