-- ============================================================================
-- lua/php-elements-sorter/actions.lua
-- Code actions - Refactored to use Result pattern
-- MEJORA #5: Result pattern para mejor manejo de errores
-- ============================================================================

local M = {}

local log = require('php-elements-sorter.utils.log')
local lsp = require('php-elements-sorter.utils.lsp')
local tbl = require('php-elements-sorter.utils.tbl')
local ui = require('php-elements-sorter.ui')
local Result = require('php-elements-sorter.utils.result')

--- Produce plugin-specific actions
---@return table actions List of code actions
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

--- Build safe diagnostic from Neovim diagnostic using Result
---@param nvim_diag table Neovim diagnostic
---@return table result Result with safe diagnostic or error
local function build_safe_diagnostic(nvim_diag)
  -- Check if diagnostic has LSP data
  local lsp_data = nvim_diag.user_data and nvim_diag.user_data.lsp

  if not lsp_data then
    return Result.err('Diagnostic missing LSP data')
  end

  if not lsp_data.range then
    return Result.err('Diagnostic missing range')
  end

  local range = lsp_data.range

  -- Validate range
  if not lsp.is_valid_range(range) then
    return Result.err('Invalid LSP range')
  end

  -- Build safe diagnostic
  return Result.ok({
    range = {
      start = { line = range.start.line, character = range.start.character },
      ['end'] = { line = range['end'].line, character = range['end'].character },
    },
    message = lsp_data.message or nvim_diag.message or '',
    severity = lsp_data.severity or nvim_diag.severity,
    code = lsp_data.code or nvim_diag.code,
    source = lsp_data.source or nvim_diag.source,
  })
end

--- Build safe diagnostics from Neovim diagnostics
---@param diagnostics table Neovim diagnostics
---@return table safe_diagnostics
local function build_safe_diagnostics(diagnostics)
  local safe = {}
  local skipped = 0

  for _, nvim_diag in ipairs(diagnostics) do
    local result = build_safe_diagnostic(nvim_diag)

    if Result.is_ok(result) then
      table.insert(safe, result.value)
    else
      skipped = skipped + 1
      log.debug('Skipped diagnostic: ' .. result.error)
    end
  end

  if skipped > 0 then
    log.debugf('Skipped %d diagnostics with invalid data', skipped)
  end

  return safe
end

--- Show actions using the available UI method
---@param actions table List of actions
---@param execute_fn function Execution callback
local function show_actions(actions, execute_fn)
  local used = ui.show_code_actions_with_telescope(actions, execute_fn)
  if not used then
    ui.show_code_actions_with_ui_select(actions, execute_fn)
  end
end

--- Execute workspace edit using Result pattern
---@param edit table Workspace edit
---@param encoding string LSP encoding
---@return table result
local function execute_workspace_edit(edit, encoding)
  return Result.try(function()
    vim.lsp.util.apply_workspace_edit(edit, encoding)
    return true
  end, 'workspace_edit')
end

--- Execute LSP command using Result pattern
---@param command table|string Command to execute
---@return table result
local function execute_lsp_command(command)
  return Result.try(function()
    if type(command) == 'string' then
      vim.lsp.buf.execute_command({ command = command })
    else
      vim.lsp.buf.execute_command(command)
    end
    return true
  end, 'lsp_command')
end

--- Execute custom plugin command using Result pattern
---@param command_name string Command name
---@return table result
local function execute_custom_command(command_name)
  -- Try from registered commands first
  local cmd_fn = vim.lsp.commands and vim.lsp.commands[command_name]
  if type(cmd_fn) == 'function' then
    return Result.try(cmd_fn, 'custom_command[registered]')
  end

  -- Try from plugin module
  return Result.try(function()
    local ok, plugin = pcall(require, 'php-elements-sorter')
    if not ok then
      error('Failed to load php-elements-sorter plugin')
    end

    local func_name = command_name:gsub('php_elements_sorter%.', '')
    if not plugin[func_name] or type(plugin[func_name]) ~= 'function' then
      error('Custom function not found: ' .. func_name)
    end

    plugin[func_name]()
    return true
  end, 'custom_command[plugin]')
end

--- Execute action (handles LSP action objects and plugin custom commands)
---@param action table Action to execute
local function execute_action(action)
  log.debugf(
    'Executing action: "%s" (is_custom: %s, is_lsp: %s)',
    action.title or 'unknown',
    tostring(action.is_custom or false),
    tostring(action.is_lsp or false)
  )

  local results = {}

  -- Execute workspace edit if present
  if action.edit then
    local encoding = lsp.get_encoding(vim.api.nvim_get_current_buf())
    log.debug('Applying workspace edit with encoding: ' .. encoding)

    local edit_result = execute_workspace_edit(action.edit, encoding)
    table.insert(results, edit_result)

    if Result.is_err(edit_result) then
      log.error('Workspace edit failed: ' .. edit_result.error)
    end
  end

  -- Execute LSP command if present and not custom
  if action.command and not action.is_custom then
    log.debug('Executing LSP command: ' .. vim.inspect(action.command))

    local cmd_result = execute_lsp_command(action.command)
    table.insert(results, cmd_result)

    if Result.is_err(cmd_result) then
      log.error('LSP command failed: ' .. cmd_result.error)
    end
  end

  -- Execute custom command if present
  if action.is_custom and action.command and action.command.command then
    local cmd_str = action.command.command
    log.debug('Executing custom command: ' .. cmd_str)

    local custom_result = execute_custom_command(cmd_str)
    table.insert(results, custom_result)

    if Result.is_err(custom_result) then
      log.error('Custom command failed: ' .. custom_result.error)
    end
  end

  -- Collect results
  local final_result = Result.collect(results)

  if Result.is_ok(final_result) then
    log.debug('Action executed successfully')
  else
    log.warn('Action execution had errors: ' .. final_result.error)
  end

  return final_result
end

--- Build LSP range params using Result pattern
---@param bufnr number Buffer number
---@param encoding string LSP encoding
---@return table result Result with params or error
local function build_range_params(bufnr, encoding)
  local current_win = vim.api.nvim_get_current_buf()

  return Result.try(function()
    local params = vim.lsp.util.make_range_params(current_win, encoding)

    if type(params) ~= 'table' then
      error('Range params is not a table')
    end

    return params
  end, 'build_range_params')
end

--- Build context for LSP request using Result pattern
---@param ctx table Context
---@param opts table Options
---@return table result Result with context or error
local function build_safe_context(ctx, opts)
  return Result.try(function()
    local safe_context = {}

    if opts and opts.only then
      safe_context.only = opts.only
    end

    if ctx.diagnostics and tbl.count(ctx.diagnostics) > 0 then
      local safe_diagnostics = build_safe_diagnostics(ctx.diagnostics)
      if #safe_diagnostics > 0 then
        safe_context.diagnostics = safe_diagnostics
      end
    end

    return safe_context
  end, 'build_context')
end

--- Build complete LSP request params using Result pattern
---@param bufnr number Buffer number
---@param encoding string LSP encoding
---@param ctx table Context
---@param opts table Options
---@return table result Result with params or error
local function build_request_params(bufnr, encoding, ctx, opts)
  -- Build range params
  local params_result = build_range_params(bufnr, encoding)
  if Result.is_err(params_result) then
    return params_result
  end

  local params = params_result.value

  -- Build context
  local context_result = build_safe_context(ctx, opts)
  if Result.is_err(context_result) then
    return context_result
  end

  params.context = context_result.value

  return Result.ok(params)
end

--- Gather LSP code actions and merge with plugin actions, then show UI
---@param state table Plugin state
---@param ctx table Context
---@param opts table Options
function M.code_action(state, ctx, opts)
  ctx = ctx or {}
  local bufnr = vim.api.nvim_get_current_buf()

  log.debug('Starting code_action for buffer ' .. bufnr)

  local first_client = vim.lsp.get_clients({ bufnr = bufnr })[1]
  local encoding = first_client and first_client.offset_encoding or 'utf-16'

  -- Build context range
  if not ctx.range then
    local range_result = Result.from_vim_api(vim.lsp.util.make_range_params, encoding)

    if Result.is_ok(range_result) and range_result.value.range then
      ctx.range = range_result.value.range
    else
      ctx.range = lsp.default_range()
    end
  end

  ctx.diagnostics = ctx.diagnostics or vim.diagnostic.get(bufnr)

  -- Get plugin actions (always available)
  local actions = tbl.deep_copy(plugin_actions())
  log.debugf('Loaded %d plugin actions', #actions)

  -- Check for LSP clients that support code actions
  local clients = lsp.get_clients_for_method(bufnr, 'textDocument/codeAction')
  log.debugf('Found %d LSP clients supporting codeAction', #clients)

  -- If no LSP clients, show plugin actions only
  if #clients == 0 then
    log.debug('No LSP clients available, showing plugin actions only')
    show_actions(actions, execute_action)
    return
  end

  -- Build LSP request params using Result pattern
  local params_result = build_request_params(bufnr, encoding, ctx, opts)

  if Result.is_err(params_result) then
    log.warn(
      'Failed to build LSP params: ' .. params_result.error .. ', showing plugin actions only'
    )
    show_actions(actions, execute_action)
    return
  end

  local params = params_result.value

  log.debug('Requesting code actions from LSP clients')

  -- Request code actions from all LSP clients
  vim.lsp.buf_request_all(bufnr, 'textDocument/codeAction', params, function(results)
    local lsp_action_count = 0

    for client_id, res in pairs(results) do
      if res and res.result then
        local client_name = lsp.get_client_name(client_id)
        local count = #res.result

        log.debugf('LSP client "%s" returned %d actions', client_name, count)
        lsp_action_count = lsp_action_count + count

        for _, act in ipairs(res.result) do
          act.client_id = client_id
          act.client_name = client_name
          act.is_lsp = true
          table.insert(actions, act)
        end
      elseif res and res.err then
        local client_name = lsp.get_client_name(client_id)
        log.warn(
          string.format('LSP client "%s" returned error: %s', client_name, vim.inspect(res.err))
        )
      end
    end

    log.debugf(
      'Total actions available: %d (plugin: %d, LSP: %d)',
      #actions,
      #plugin_actions(),
      lsp_action_count
    )

    show_actions(actions, execute_action)
  end)
end

--- Get plugin-specific code actions
---@param state table Plugin state
---@return table actions
function M.get_code_actions(state)
  return plugin_actions()
end

return M
