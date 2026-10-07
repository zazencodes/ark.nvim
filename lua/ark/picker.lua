-- A multi-step Telescope picker. Each step replaces the list in the same
-- window, so the user never leaves the picker between steps.
--
-- step = { title, items = { { label, value }, ... }, selected?, select = function(value) }
-- where selected is the index of the item under the cursor when the step opens
-- (default: the first), and select returns the next step, or nil after the
-- final choice.
local M = {}

function M.run(step)
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local conf = require("telescope.config").values
  local finders = require("telescope.finders")
  local pickers = require("telescope.pickers")
  local themes = require("telescope.themes")

  local function finder(items)
    return finders.new_table({
      results = items,
      entry_maker = function(item)
        return { value = item.value, display = item.label, ordinal = item.label }
      end,
    })
  end

  pickers
    .new(themes.get_dropdown(), {
      prompt_title = step.title,
      finder = finder(step.items),
      sorter = conf.generic_sorter({}),
      -- Start on `selected` while the prompt is empty, and on the best match
      -- once the user types.
      selection_strategy = "closest",
      default_selection_index = step.selected,
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local entry = action_state.get_selected_entry()
          if not entry then
            return
          end
          local next_step = step.select(entry.value)
          if not next_step then
            return actions.close(prompt_bufnr)
          end
          step = next_step
          local picker = action_state.get_current_picker(prompt_bufnr)
          picker.default_selection_index = step.selected
          picker.layout.prompt.border:change_title(step.title)
          picker:refresh(finder(step.items), { reset_prompt = true })
        end)
        return true
      end,
    })
    :find()
end

return M
