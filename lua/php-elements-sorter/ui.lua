-- lua/php-elements-sorter/ui.lua
-- UI helpers: Telescope + vim.ui.select with nice formatting
local M = {}

local has_plenary, plenary_strings = pcall(require, 'plenary.strings')
local has_telescope, _ = pcall(require, 'telescope')

--- Show code actions with Telescope using entry_display & widths
function M.show_code_actions_with_telescope(actions_list, on_select)
  if not has_telescope then
    return false
  end

  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local conf = require('telescope.config').values
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  local entry_display = require('telescope.pickers.entry_display')
  local strings = require('plenary.strings')

  local function make_indexed_with_widths(items)
    local indexed_items = {}
    local widths = { idx = 0, title = 0, client = 0 }

    for idx, action in ipairs(items) do
      local title = tostring(action.title or ''):gsub('\r\n', '\\r\\n'):gsub('\n', '\\n')
      local client = tostring(
        action.is_lsp and action.client_name
        or (action.is_custom and 'php-elements-sorter' or 'Unknown')
      )

      local entry = {
        idx = idx,
        title = title,
        client = client,
        action = action,
      }
      table.insert(indexed_items, entry)

      widths.idx = math.max(widths.idx, strings.strdisplaywidth(tostring(entry.idx)))
      widths.title = math.max(widths.title, strings.strdisplaywidth(entry.title))
      widths.client = math.max(widths.client, strings.strdisplaywidth(entry.client))
    end

    return indexed_items, widths
  end

  local indexed_actions, widths = make_indexed_with_widths(actions_list)

  local displayer = entry_display.create({
    separator = ' ',
    items = {
      { width = widths.idx + 1 },
      { width = widths.title },
      { width = widths.client },
    },
  })

  local make_display = function(entry)
    return displayer({
      { entry.value.idx .. ':', 'TelescopePromptPrefix' },
      { entry.value.title },
      { entry.value.client,     'TelescopeResultsComment' },
    })
  end

  pickers
      .new({}, {
        prompt_title = 'Code Actions (' .. #indexed_actions .. ' available)',
        finder = finders.new_table({
          results = indexed_actions,
          entry_maker = function(entry)
            return {
              value = entry,
              display = make_display,
              ordinal = entry.idx .. ' ' .. entry.title .. ' ' .. entry.client,
            }
          end,
        }),
        sorter = conf.generic_sorter({}),
        attach_mappings = function(prompt_bufnr)
          actions.select_default:replace(function()
            actions.close(prompt_bufnr)
            local selection = action_state.get_selected_entry()
            if selection and selection.value then
              on_select(selection.value.action)
            end
          end)
          return true
        end,
        layout_config = {
          prompt_position = 'top',
          width = 0.7,
          height = 0.7,
        },
        sorting_strategy = 'ascending',
      })
      :find()

  return true
end

--- Fallback UI: vim.ui.select
function M.show_code_actions_with_ui_select(actions_list, on_select)
  for i, a in ipairs(actions_list) do
    a._index = i
  end

  vim.ui.select(actions_list, {
    prompt = 'Code Actions (' .. #actions_list .. ' available):',
    format_item = function(item)
      local idx = item._index or 0
      local number_str = tostring(idx) .. ':'
      local title_str = tostring(item.title or '')
      local client_str = tostring(
        item.is_lsp and item.client_name or (item.is_custom and 'php-elements-sorter' or 'Unknown')
      )
      local total_width = 80
      local content_width = #number_str + #title_str
      local padding = math.max(0, total_width - content_width - #client_str)
      return string.format(
        '%s %s%s %s',
        number_str,
        title_str,
        string.rep(' ', padding),
        client_str
      )
    end,
  }, function(choice)
    if choice then
      on_select(choice)
    end
  end)
end

return M
