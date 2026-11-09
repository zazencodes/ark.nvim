-- Multi-step Telescope picker with cancellable asynchronous loading steps.
-- A step has title/items/select(value), or title/load(done) returning cancel().
-- load calls done(error, next_step). Closing the picker cancels pending work.
local M = {}
local catalogs = {}
local generation = 0

function M.clear_catalogs()
  generation = generation + 1
  catalogs = {}
end

local function validate_catalog(catalog)
  if type(catalog) ~= "table" or not vim.islist(catalog.models) then
    error("ark: catalog must contain a models list")
  end
  local function efforts(values)
    if values == nil then return end
    if not vim.islist(values) then error("ark: catalog efforts must be a list") end
    local seen = {}
    for _, value in ipairs(values) do
      if type(value) ~= "string" or value == "" or seen[value] then
        error("ark: catalog effort must be a unique nonempty string")
      end
      seen[value] = true
    end
  end
  local seen = {}
  for _, model in ipairs(catalog.models) do
    if type(model) ~= "table" or type(model.id) ~= "string" or model.id == "" or seen[model.id] then
      error("ark: catalog model must have a unique nonempty id")
    end
    seen[model.id] = true
    efforts(model.efforts)
  end
  efforts(catalog.default_efforts)
  return catalog
end

-- Only the selected adapter runs. Successful results live for this Neovim
-- session; refresh explicitly replaces the cached catalog.
function M.catalog(name, refresh, done)
  local config = require("ark.config")
  local adapter = config.harness(name)
  local cancelled, job = false, nil
  local requested_generation = generation
  local function complete(err, value)
    if cancelled then return end
    if requested_generation ~= generation then err, value = "ark: catalog configuration changed; reopen :ArkHarness", nil end
    if not err then catalogs[name] = vim.deepcopy(value) end
    done(err, value)
  end
  local function parse(stdout)
    local ok, value = pcall(function() return validate_catalog(adapter.catalog(stdout)) end)
    if not ok then return complete("ark: " .. name .. " catalog: " .. tostring(value)) end
    complete(nil, value)
  end
  if refresh then catalogs[name] = nil end
  if catalogs[name] then
    vim.schedule(function() complete(nil, vim.deepcopy(catalogs[name])) end)
  elseif not adapter.catalog_args then
    vim.schedule(function() if not cancelled then parse(nil) end end)
  else
    local argv = vim.list_extend(vim.deepcopy(adapter.cmd), adapter.catalog_args)
    local ok, result = pcall(vim.system, argv, { text = true, timeout = config.options.catalog_timeout_ms }, function(result)
      vim.schedule(function()
        if cancelled then return end
        if result.code ~= 0 then
          local detail = result.code == 124 and "timed out" or vim.trim(result.stderr or "")
          return complete(("ark: %s catalog failed (exit %s): %s"):format(name, result.code, detail))
        end
        parse(result.stdout)
      end)
    end)
    if ok then job = result else vim.schedule(function() complete("ark: " .. name .. " catalog: " .. tostring(result)) end) end
  end
  return function()
    cancelled = true
    if job then job:kill(15) end
  end
end

function M.run(initial, on_error)
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local conf = require("telescope.config").values
  local finders = require("telescope.finders")
  local pickers = require("telescope.pickers")
  local themes = require("telescope.themes")
  local step, cancel, closed = initial, nil, false

  local function finder(items)
    return finders.new_table({
      results = items or {},
      entry_maker = function(item)
        return { value = item.value, display = item.label, ordinal = item.label }
      end,
    })
  end

  pickers.new(themes.get_dropdown(), {
    prompt_title = step.title,
    finder = finder(step.items),
    sorter = conf.generic_sorter({}),
    selection_strategy = "closest",
    default_selection_index = step.selected,
    attach_mappings = function(prompt_bufnr)
      vim.api.nvim_create_autocmd("BufWipeout", { buffer = prompt_bufnr, once = true, callback = function()
        closed = true
        if cancel then cancel(); cancel = nil end
      end })
      local function fail(err)
        actions.close(prompt_bufnr)
        if on_error then on_error(err) else error(err) end
      end
      local show
      show = function(next_step)
        if closed then return end
        if cancel then cancel(); cancel = nil end
        if not next_step then return actions.close(prompt_bufnr) end
        step = next_step
        local current = action_state.get_current_picker(prompt_bufnr)
        current.default_selection_index = step.selected
        current.layout.prompt.border:change_title(step.title)
        current:refresh(finder(step.items), { reset_prompt = true })
        if step.load then
          cancel = step.load(function(err, loaded)
            if closed then return end
            cancel = nil
            if err then return fail(err) end
            show(loaded)
          end)
        end
      end
      actions.select_default:replace(function()
        if step.load then return end
        local entry = action_state.get_selected_entry()
        if not entry then return end
        local ok, next_step = pcall(step.select, entry.value)
        if not ok then return fail(next_step) end
        show(next_step)
      end)
      return true
    end,
  }):find()
end

return M
