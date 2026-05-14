-- lua/php-elements-sorter/init.lua
-- Plugin entry point with per-buffer state management

local M = {}

local log = require('php-elements-sorter.utils.log')
local timer = require('php-elements-sorter.utils.timer')

-- Valid visibility values
local VALID_VISIBILITIES = { 'public', 'protected', 'private' }

-- Default configuration (shared across all buffers)
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
  debug = false,
}

-- Per-buffer state storage (cleanup via BufDelete autocmd)
local buffer_states = {}

-- Global cleanup timer ID
local cleanup_timer_id = nil
local setup_count = 0

-- Lazy-load modules
local sorters = nil
local actions = nil

local function get_sorters()
  if not sorters then
    sorters = require('php-elements-sorter.sorters')
  end
  return sorters
end

local function get_actions()
  if not actions then
    actions = require('php-elements-sorter.actions')
  end
  return actions
end

--- Validate configuration values
---@param config table Configuration to validate
---@return boolean valid, string? error_message
local function validate_config(config)
  if not config then
    return false, 'Config cannot be nil'
  end

  if type(config) ~= 'table' then
    return false, 'Config must be a table'
  end

  -- Validate default_visibility
  if config.default_visibility ~= nil then
    if type(config.default_visibility) ~= 'string' then
      return false, 'default_visibility must be a string'
    end

    if not vim.tbl_contains(VALID_VISIBILITIES, config.default_visibility) then
      return false,
          string.format(
            'Invalid default_visibility "%s". Must be one of: %s',
            config.default_visibility,
            table.concat(VALID_VISIBILITIES, ', ')
          )
    end
  end

  -- Validate boolean options
  local boolean_options = {
    'add_visibility_spacing',
    'sort_properties',
    'sort_traits',
    'sort_namespace_uses',
    'sort_constants',
    'remove_unused_imports',
    'add_newline_between_const_and_properties',
    'add_newline_after_namespace_uses',
    'add_newline_after_trait_uses',
    'debug',
    'auto_sort_on_save',
  }

  for _, opt in ipairs(boolean_options) do
    if config[opt] ~= nil and type(config[opt]) ~= 'boolean' then
      return false, string.format('Option "%s" must be a boolean', opt)
    end
  end

  return true, nil
end

--- Sanitize and merge user config with defaults
---@param user_config table? User configuration
---@return table config Sanitized configuration
local function sanitize_config(user_config)
  if not user_config then
    return vim.deepcopy(M.config)
  end

  -- Validate first
  local valid, err = validate_config(user_config)
  if not valid then
    log.error('Invalid configuration: ' .. err)
    log.warn('Using default configuration')
    return vim.deepcopy(M.config)
  end

  -- Merge with defaults
  local merged = vim.tbl_deep_extend('force', M.config, user_config)

  -- Re-validate merged config
  valid, err = validate_config(merged)
  if not valid then
    log.error('Configuration validation failed after merge: ' .. err)
    log.warn('Using default configuration')
    return vim.deepcopy(M.config)
  end

  return merged
end

--- Get or create state for a specific buffer
---@param bufnr number|nil Buffer number (defaults to current buffer)
---@return table state Buffer-specific state
local function get_state(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Validate buffer
  if not vim.api.nvim_buf_is_valid(bufnr) then
    log.warn(string.format('Buffer %d is not valid, using current buffer', bufnr))
    bufnr = vim.api.nvim_get_current_buf()
  end

  -- Return existing state if available
  if buffer_states[bufnr] then
    return buffer_states[bufnr]
  end

  -- Create new state for this buffer
  local state = {
    bufnr = bufnr,
    root = nil,
    lang = nil,
    prev_type = nil,
    config = vim.deepcopy(M.config), -- Each buffer gets its own config copy
    created_at = os.time(),
    _invalidate_timer_id = nil,      -- Timer ID for debounced invalidation
  }

  buffer_states[bufnr] = state

  log.debug(string.format('Created state for buffer %d', bufnr))

  -- Auto-cleanup: Remove state when buffer is deleted
  vim.api.nvim_create_autocmd('BufDelete', {
    buffer = bufnr,
    once = true,
    callback = function()
      -- Stop any pending timer before cleanup
      if buffer_states[bufnr] and buffer_states[bufnr]._invalidate_timer_id then
        timer.stop(buffer_states[bufnr]._invalidate_timer_id)
      end
      buffer_states[bufnr] = nil
      log.debug(string.format('Cleaned up state for buffer %d', bufnr))
    end,
    desc = 'Cleanup php-elements-sorter state',
  })

  return state
end

--- Invalidate parser state for a buffer (call after buffer changes)
---@param bufnr number|nil Buffer number (defaults to current buffer)
local function invalidate_parser_state(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local state = buffer_states[bufnr]

  if state then
    state.root = nil
    state.lang = nil
    log.debug(string.format('Invalidated parser state for buffer %d', bufnr))
  end
end

--- Get diagnostic info about buffer states (for debugging)
---@return table info Diagnostic information
function M.get_state_info()
  local info = {
    active_buffers = 0,
    states = {},
    timer_stats = timer.get_stats(),
  }

  for bufnr, state in pairs(buffer_states) do
    info.active_buffers = info.active_buffers + 1
    table.insert(info.states, {
      bufnr = bufnr,
      valid = vim.api.nvim_buf_is_valid(bufnr),
      loaded = vim.api.nvim_buf_is_loaded(bufnr),
      has_parser = state.root ~= nil,
      lang = state.lang,
      age_seconds = os.time() - (state.created_at or 0),
      has_pending_timer = state._invalidate_timer_id ~= nil,
    })
  end

  return info
end

--- Force cleanup of invalid buffer states
function M.cleanup_invalid_states()
  local cleaned = 0

  for bufnr, state in pairs(buffer_states) do
    if not vim.api.nvim_buf_is_valid(bufnr) then
      -- Stop any pending timer before cleanup
      if state._invalidate_timer_id then
        timer.stop(state._invalidate_timer_id)
      end
      buffer_states[bufnr] = nil
      cleaned = cleaned + 1
    end
  end

  if cleaned > 0 then
    log.debug(string.format('Cleaned up %d invalid buffer states', cleaned))
  end

  return cleaned
end

--- Public wrappers that use per-buffer state
function M.sort_all_impl()
  local state = get_state()
  return get_sorters().sort_all_impl(state)
end

function M.sort_namespace_uses()
  local state = get_state()
  return get_sorters().sort_namespace_uses_impl(state)
end

function M.remove_unused_uses()
  local state = get_state()
  return get_sorters().remove_unused_namespace_uses_impl(state)
end

function M.sort_elements()
  local state = get_state()
  return get_sorters().process_and_sort_elements(state, 0, -1)
end

function M.sort_all()
  return M.sort_all_impl()
end

function M.get_code_actions()
  local state = get_state()
  return get_actions().get_code_actions(state)
end

function M.code_action(ctx, opts)
  local state = get_state()
  get_actions().code_action(state, ctx, opts)
end

--- Override buffer-local config for specific buffer
---@param bufnr number|nil Buffer number (defaults to current buffer)
---@param overrides table Config overrides
function M.set_buffer_config(bufnr, overrides)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Validate buffer
  if not vim.api.nvim_buf_is_valid(bufnr) then
    log.warn(string.format('Cannot set config for invalid buffer %d', bufnr))
    return
  end

  -- Validate overrides
  local valid, err = validate_config(overrides)
  if not valid then
    log.error('Invalid config overrides: ' .. err)
    return
  end

  local state = get_state(bufnr)
  state.config = vim.tbl_deep_extend('force', state.config, overrides)
  log.debug(string.format('Updated config for buffer %d', bufnr))
end

--- Get config for specific buffer
---@param bufnr number|nil Buffer number (defaults to current buffer)
---@return table config
function M.get_buffer_config(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Validate buffer - if invalid, return default config
  if not vim.api.nvim_buf_is_valid(bufnr) then
    log.warn(string.format('Buffer %d is not valid, returning default config', bufnr))
    return vim.deepcopy(M.config)
  end

  local state = get_state(bufnr)
  return vim.deepcopy(state.config)
end

--- Validate current configuration
---@return boolean valid, string? error
function M.validate_config()
  return validate_config(M.config)
end

--- Get timer statistics
---@return table stats
function M.get_timer_stats()
  return timer.get_stats()
end

--- Preview all sorting operations
function M.preview_all()
  local preview = require('php-elements-sorter.preview')
  return preview.preview_all()
end

--- Preview namespace uses sorting
function M.preview_namespace_uses()
  local preview = require('php-elements-sorter.preview')
  return preview.preview_namespace_uses()
end

--- Preview elements sorting
function M.preview_elements()
  local preview = require('php-elements-sorter.preview')
  return preview.preview_elements()
end

--- Check if preview mode is available
function M.preview_available()
  local preview = require('php-elements-sorter.preview')
  return preview.is_available()
end

-- Tracks whether we already patched vim.lsp.buf.code_action
local code_action_patched = false

--- Override vim.lsp.buf.code_action for PHP buffers.
--- Chains with previous value so other plugins that also wrap it still work.
local function setup_code_action_override()
  if code_action_patched then
    return
  end
  code_action_patched = true

  local prev_code_action = vim.lsp.buf.code_action

  vim.lsp.buf.code_action = function(opts)
    if vim.bo.filetype == 'php' then
      log.debug('Intercepting code_action for PHP buffer')
      M.code_action(opts)
    else
      prev_code_action(opts)
    end
  end

  log.debug('code_action override installed')
end

--- Register LSP command handlers
local function register_lsp_commands()
  vim.lsp.commands = vim.lsp.commands or {}

  local commands = {
    'sort_namespace_uses',
    'remove_unused_uses',
    'sort_elements',
    'sort_all',
  }

  for _, cmd in ipairs(commands) do
    local full_cmd = 'php_elements_sorter.' .. cmd
    vim.lsp.commands[full_cmd] = function()
      log.debug('LSP command invoked: ' .. full_cmd)
      M[cmd]()
    end
  end

  log.debug('Registered ' .. #commands .. ' LSP commands')
end

--- Create user commands
local function create_user_commands()
  local commands = {
    {
      name = 'SortPhpElements',
      func = function()
        M.sort_all()
      end,
      desc = 'Sort all PHP elements (uses, traits, properties, constants)',
    },
    {
      name = 'SortPhpNamespaceUses',
      func = function()
        M.sort_namespace_uses()
      end,
      desc = 'Sort namespace use statements',
    },
    {
      name = 'RemoveUnusedUses',
      func = function()
        M.remove_unused_uses()
      end,
      desc = 'Remove unused namespace use statements',
    },
    {
      name = 'SortPhpClassElements',
      func = function()
        M.sort_elements()
      end,
      desc = 'Sort class properties, constants, and traits',
    },
    {
      name = 'PhpSorterInfo',
      func = function()
        local info = M.get_state_info()
        print(vim.inspect(info))
      end,
      desc = 'Show php-elements-sorter diagnostic info',
    },
    {
      name = 'PhpSorterCleanup',
      func = function()
        local cleaned = M.cleanup_invalid_states()
        vim.notify(
          string.format('[php-elements-sorter] Cleaned %d invalid states', cleaned),
          vim.log.levels.INFO
        )
      end,
      desc = 'Cleanup invalid buffer states',
    },
    {
      name = 'PhpSorterValidateConfig',
      func = function()
        local valid, err = M.validate_config()
        if valid then
          vim.notify('[php-elements-sorter] Configuration is valid ✓', vim.log.levels.INFO)
        else
          vim.notify('[php-elements-sorter] Configuration error: ' .. err, vim.log.levels.ERROR)
        end
      end,
      desc = 'Validate current configuration',
    },
    {
      name = 'PhpSorterTimerStats',
      func = function()
        timer.print_stats()
      end,
      desc = 'Show timer statistics',
    },
    {
      name = 'SortPhpElementsPreview',
      func = function()
        local preview = require('php-elements-sorter.preview')
        if not preview.is_available() then
          vim.notify('[php-elements-sorter] Preview mode requires Neovim 0.6+', vim.log.levels.WARN)
          return
        end
        preview.preview_all()
      end,
      desc = 'Preview all PHP element sorting changes',
    },
    {
      name = 'SortPhpNamespaceUsesPreview',
      func = function()
        local preview = require('php-elements-sorter.preview')
        if not preview.is_available() then
          vim.notify('[php-elements-sorter] Preview mode requires Neovim 0.6+', vim.log.levels.WARN)
          return
        end
        preview.preview_namespace_uses()
      end,
      desc = 'Preview namespace use statement sorting',
    },
    {
      name = 'SortPhpClassElementsPreview',
      func = function()
        local preview = require('php-elements-sorter.preview')
        if not preview.is_available() then
          vim.notify('[php-elements-sorter] Preview mode requires Neovim 0.6+', vim.log.levels.WARN)
          return
        end
        preview.preview_elements()
      end,
      desc = 'Preview class element sorting',
    },
  }

  for _, cmd in ipairs(commands) do
    pcall(vim.api.nvim_create_user_command, cmd.name, cmd.func, {
      desc = cmd.desc,
    })
  end

  log.debug('Created ' .. #commands .. ' user commands')
end

--- Setup autocommands for PHP files
local function setup_autocommands()
  local group = vim.api.nvim_create_augroup('PhpElementsSorter', { clear = true })

  -- Optional: auto-sort on save (disabled by default)
  if M.config.auto_sort_on_save then
    vim.api.nvim_create_autocmd('BufWritePre', {
      group = group,
      pattern = '*.php',
      callback = function()
        log.debug('Auto-sorting on save')
        M.sort_all()
      end,
      desc = 'Auto-sort PHP elements on save',
    })
  end

  -- Invalidate parser state on buffer changes (using Timer Manager)
  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
    group = group,
    pattern = '*.php',
    callback = function(args)
      local bufnr = args.buf
      local state = buffer_states[bufnr]

      -- Exit early if state doesn't exist yet
      if not state then
        return
      end

      -- Use Timer Manager for debounced invalidation
      local timer_key = 'invalidate_parser_' .. bufnr
      local timer_id = timer.debounce(timer_key, 500, function()
        -- Double-check state still exists before invalidating
        if buffer_states[bufnr] then
          invalidate_parser_state(bufnr)
          buffer_states[bufnr]._invalidate_timer_id = nil
        end
      end)

      -- Store timer ID in state
      if timer_id then
        state._invalidate_timer_id = timer_id
      end
    end,
    desc = 'Invalidate parser state on buffer changes',
  })

  -- Periodic cleanup ONLY if we have PHP buffers
  -- Check every 5 minutes, but only cleanup if there are active PHP buffers
  vim.api.nvim_create_autocmd('BufEnter', {
    group = group,
    pattern = '*.php',
    callback = function()
      -- Start cleanup timer only once and only when a PHP buffer is active
      if not cleanup_timer_id then
        log.debug('Starting periodic cleanup timer (first PHP buffer)')

        cleanup_timer_id = timer.repeat_timer(300000, function()
          -- Only run if we have active PHP buffers
          local php_buffer_count = 0
          for bufnr in pairs(buffer_states) do
            if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].filetype == 'php' then
              php_buffer_count = php_buffer_count + 1
            end
          end

          if php_buffer_count > 0 then
            log.debug('Running periodic cleanup (active PHP buffers: ' .. php_buffer_count .. ')')
            M.cleanup_invalid_states()
            -- Clean timers older than 10 minutes (not 5, to avoid cleaning ourselves)
            timer.cleanup_old_timers(600)
          else
            log.debug('No active PHP buffers, stopping periodic cleanup')
            -- Stop the cleanup timer if no PHP buffers
            if cleanup_timer_id then
              timer.stop(cleanup_timer_id)
              cleanup_timer_id = nil
            end
          end
        end, -1, 'periodic_cleanup')
      end
    end,
    desc = 'Start periodic cleanup when PHP buffer is opened',
  })

  log.debug('Autocommands configured')
end

--- Teardown function to stop timers and cleanup
function M.teardown()
  log.debug('Tearing down php-elements-sorter')

  -- Stop periodic cleanup timer explicitly
  if cleanup_timer_id then
    timer.stop(cleanup_timer_id)
    cleanup_timer_id = nil
    log.debug('Stopped periodic cleanup timer')
  end

  -- Stop all other timers
  local stopped = timer.stop_all()
  log.debug(string.format('Stopped %d timers', stopped))

  -- Clear all buffer states
  for bufnr in pairs(buffer_states) do
    buffer_states[bufnr] = nil
  end

  log.debug('Teardown complete')
end

--- Setup plugin, register commands and LSP command shims
---@param user_config table?
function M.setup(user_config)
  setup_count = setup_count + 1

  -- Prevent multiple setups from creating duplicate timers
  if setup_count > 1 then
    log.debug('Setup called multiple times (' .. setup_count .. '), updating config only')
    M.config = sanitize_config(user_config)
    log.init(M.config)
    return M
  end

  -- Sanitize and validate user config
  M.config = sanitize_config(user_config)

  log.init(M.config)

  log.debug('Setting up php-elements-sorter plugin (first time)')

  -- Log configuration if debug is enabled
  if M.config.debug then
    log.debug('Configuration: ' .. vim.inspect(M.config))
  end

  -- Register LSP commands
  register_lsp_commands()

  -- Override code_action for PHP files
  setup_code_action_override()

  -- Create user commands
  create_user_commands()

  -- Setup autocommands
  setup_autocommands()

  log.debug('Plugin setup complete')

  -- Return module for convenience
  return M
end

return M
