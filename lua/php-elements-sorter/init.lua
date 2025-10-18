-- lua/php-elements-sorter/init.lua
-- Plugin entry point with per-buffer state management

local M = {}
local log = require('php-elements-sorter.log')

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

-- Per-buffer state storage with weak keys for garbage collection
local buffer_states = setmetatable({}, { __mode = 'k' })

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

--- Get or create state for a specific buffer
---@param bufnr number|nil Buffer number (defaults to current buffer)
---@return table state Buffer-specific state
local function get_state(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

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
  }

  buffer_states[bufnr] = state

  log.debug(string.format('Created state for buffer %d', bufnr))

  -- Auto-cleanup: Remove state when buffer is deleted
  vim.api.nvim_create_autocmd('BufDelete', {
    buffer = bufnr,
    once = true,
    callback = function()
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
    })
  end

  return info
end

--- Force cleanup of invalid buffer states
function M.cleanup_invalid_states()
  local cleaned = 0

  for bufnr, _ in pairs(buffer_states) do
    if not vim.api.nvim_buf_is_valid(bufnr) then
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
  get_sorters().sort_all_impl(state)
end

function M.sort_namespace_uses()
  local state = get_state()
  get_sorters().sort_namespace_uses_impl(state)
end

function M.remove_unused_uses()
  local state = get_state()
  get_sorters().remove_unused_namespace_uses_impl(state)
end

function M.sort_elements()
  local state = get_state()
  get_sorters().process_and_sort_elements(state, 0, -1)
end

function M.sort_all()
  M.sort_all_impl()
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
  local state = get_state(bufnr)
  state.config = vim.tbl_deep_extend('force', state.config, overrides)
  log.debug(string.format('Updated config for buffer %d', bufnr))
end

--- Get config for specific buffer
---@param bufnr number|nil Buffer number (defaults to current buffer)
---@return table config
function M.get_buffer_config(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local state = get_state(bufnr)
  return vim.deepcopy(state.config)
end

--- Setup code_action override for PHP files only
local function setup_code_action_override()
  -- Store original code_action
  local orig_code_action = vim.lsp.buf.code_action

  -- Create wrapper that checks filetype
  vim.lsp.buf.code_action = function(ctx, opts)
    local bufnr = vim.api.nvim_get_current_buf()
    local ft = vim.bo[bufnr].filetype

    if ft == 'php' then
      log.debug('Intercepting code_action for PHP buffer ' .. bufnr)
      M.code_action(ctx, opts)
    else
      -- Delegate to original for non-PHP files
      orig_code_action(ctx, opts)
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

  -- Invalidate parser state on buffer changes
  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
    group = group,
    pattern = '*.php',
    callback = function(args)
      -- Debounce: only invalidate after 500ms of inactivity
      local bufnr = args.buf
      local timer = vim.defer_fn(function()
        invalidate_parser_state(bufnr)
      end, 500)

      -- Cancel previous timer if exists
      if buffer_states[bufnr] and buffer_states[bufnr]._invalidate_timer then
        buffer_states[bufnr]._invalidate_timer:stop()
      end

      if buffer_states[bufnr] then
        buffer_states[bufnr]._invalidate_timer = timer
      end
    end,
    desc = 'Invalidate parser state on buffer changes',
  })

  -- Periodic cleanup of invalid states (every 5 minutes)
  vim.fn.timer_start(300000, function()
    M.cleanup_invalid_states()
  end, { ['repeat'] = -1 })

  log.debug('Autocommands configured')
end

--- Setup plugin, register commands and LSP command shims
---@param user_config table?
function M.setup(user_config)
  -- Merge user config
  M.config = vim.tbl_deep_extend('force', M.config, user_config or {})

  log.init(M.config)

  log.debug('Setting up php-elements-sorter plugin')

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
