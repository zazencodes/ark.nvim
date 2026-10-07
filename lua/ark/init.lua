local config = require("ark.config")
local context = require("ark.context")
local picker = require("ark.picker")
local state = require("ark.state")
local sync = require("ark.sync")
local tmux = require("ark.tmux")

local M = {}

function M.setup(opts)
  config.setup(opts)
  local keymaps = config.options.keymaps
  if keymaps.edit then
    vim.keymap.set("x", keymaps.edit, ":ArkEdit<CR>", { silent = true, desc = "ark: edit selection" })
  end
  if keymaps.chat then
    vim.keymap.set("n", keymaps.chat, "<cmd>ArkChat<CR>", { desc = "ark: open agent pane" })
  end
  if keymaps.harness then
    vim.keymap.set("n", keymaps.harness, "<cmd>ArkHarness<CR>", { desc = "ark: pick harness, model, effort" })
  end
end

-- Sessions are keyed by Neovim's working directory, so each project or
-- worktree gets its own agent pane and conversation.
local function project_root()
  return vim.fn.getcwd()
end

-- Starts the selected harness in a new pane. `prompt` (optional) is passed as
-- the initial prompt argument via a temp file, which avoids waiting for the
-- harness UI to become ready and keeps large prompts out of tmux's command
-- message. `ctx` (optional) is appended to the instructions, so a new agent
-- knows the editor context without a paste racing its startup.
local function launch(root, prompt, ctx)
  local selection = state.load()
  local harness = config.harness(selection.harness)
  local argv = vim.deepcopy(harness.cmd)
  local instructions = table.concat(vim.fn.readfile(config.instructions_path), "\n")
  if ctx then
    instructions = instructions .. "\n\n" .. ctx
  end
  if harness.instructions_args then
    local path = config.instructions_path
    if ctx then
      path = vim.fn.tempname()
      assert(vim.fn.writefile(vim.split(instructions, "\n", { plain = true }), path) == 0)
    end
    vim.list_extend(argv, harness.instructions_args(path))
  else
    prompt = prompt and (instructions .. "\n\n" .. prompt) or instructions
  end
  if selection.model then
    vim.list_extend(argv, harness.model_args(selection.model))
  end
  if selection.effort then
    vim.list_extend(argv, harness.effort_args(selection.effort))
  end
  if prompt then
    if harness.prompt_flag then
      table.insert(argv, harness.prompt_flag)
    end
    local path = vim.fn.tempname()
    assert(vim.fn.writefile(vim.split(prompt, "\n", { plain = true }), path) == 0)
    argv = vim.list_extend({ "sh", "-c", 'p=$(cat "$0") && rm "$0" && exec "$@" "$p"', path }, argv)
  end
  return tmux.spawn(root, argv, config.options.pane.size)
end

local function dispatch(message)
  local root = project_root()
  local pane = tmux.find_pane(root)
  if pane then
    tmux.send(pane, message)
  else
    pane = launch(root, message)
  end
  sync.start(config.options.checktime_interval)
  vim.notify(("ark: sent to %s"):format(pane))
end

-- Prompts for an instruction and sends it with the selected lines.
-- range: { start_line, end_line }, 1-based and inclusive.
function M.edit(range)
  local buf = vim.api.nvim_get_current_buf()
  local root = project_root()
  local ctx = context.selection(buf, root, range)

  vim.ui.input({ prompt = "Ark edit: " }, function(input)
    if not input or vim.trim(input) == "" then
      return
    end
    -- The agent reads and edits the file on disk, so it must match the buffer.
    vim.api.nvim_buf_call(buf, function()
      vim.cmd("silent update")
    end)
    dispatch(ctx .. "\n\n<request>\n" .. input .. "\n</request>")
  end)
end

-- Focuses the project's agent pane, starting the selected harness if none is
-- running. When the current buffer is a file, a running agent gets its context
-- pasted into its input, unsent, ahead of whatever the user types next; a new
-- agent gets it with its instructions.
function M.chat()
  local buf = vim.api.nvim_get_current_buf()
  local root = project_root()
  local ctx
  if vim.bo[buf].buftype == "" and vim.api.nvim_buf_get_name(buf) ~= "" then
    ctx = context.file(buf, root)
  end
  local pane = tmux.find_pane(root)
  if pane then
    if ctx then
      tmux.paste(pane, ctx .. "\n\n")
    end
  else
    pane = launch(root, nil, ctx)
  end
  sync.start(config.options.checktime_interval)
  tmux.focus(pane)
end

-- Starts every harness's catalog command in the background. Returns a
-- function that yields the parsed catalog for a harness, waiting only if its
-- command has not finished yet. A failed command errors when that harness is
-- picked, not when the picker opens.
local function fetch_catalogs()
  local jobs = {}
  for name, harness in pairs(config.options.harnesses) do
    if harness.catalog_args then
      local argv = vim.list_extend(vim.deepcopy(harness.cmd), harness.catalog_args)
      local ok, job = pcall(vim.system, argv, { text = true })
      jobs[name] = { argv = argv, ok = ok, job = job }
    end
  end
  return function(name)
    local harness = config.harness(name)
    if not harness.catalog_args then
      return harness.catalog()
    end
    local job = jobs[name]
    local argv = table.concat(job.argv, " ")
    if not job.ok then
      error(("ark: `%s` failed: %s"):format(argv, job.job))
    end
    local result = job.job:wait()
    if result.code ~= 0 then
      error(("ark: `%s` failed: %s"):format(argv, vim.trim(result.stderr)))
    end
    return harness.catalog(result.stdout)
  end
end

-- Items for `values` with a leading "default" entry (nil = the CLI's own
-- default), marking `current`. Also returns the index of the current item, or
-- of `preferred` when nothing is current.
local function with_default(values, current, preferred)
  local items, selected = {}, nil
  for _, value in ipairs(vim.list_extend({ vim.NIL }, values)) do
    value = value ~= vim.NIL and value or nil
    local label = value or "default"
    if value == current then
      label = label .. " (current)"
      selected = #items + 1
    elseif value == preferred and not selected then
      selected = #items + 1
    end
    table.insert(items, { value = value, label = label })
  end
  return items, selected
end

-- Picks harness, model, and effort in one picker, saves the selection, and
-- restarts this project's agent pane (ending its conversation) if one is
-- running.
function M.pick_harness()
  local current = state.load()
  local catalog = fetch_catalogs()

  local function finish(selection)
    state.save(selection)
    local root = project_root()
    local pane = tmux.find_pane(root)
    if pane then
      tmux.kill(pane)
      launch(root)
    end
    vim.notify("ark: " .. state.describe(selection) .. (pane and " (agent pane restarted)" or ""))
  end

  -- The current harness first, then the rest in configured order.
  local harness_items = { { value = current.harness, label = current.harness .. " (current)" } }
  for _, name in ipairs(config.harness_order()) do
    if name ~= current.harness then
      table.insert(harness_items, { value = name, label = name })
    end
  end

  picker.run({
    title = "Ark harness",
    items = harness_items,
    select = function(name)
      local same = name == current.harness
      local models = catalog(name)
      local efforts_for = {}
      for _, model in ipairs(models.models) do
        efforts_for[model.id] = model.efforts
      end
      local model_items, model_selected = with_default(
        vim.tbl_map(function(m)
          return m.id
        end, models.models),
        same and current.model
      )
      return {
        title = name .. " model",
        items = model_items,
        selected = model_selected,
        select = function(model)
          local efforts
          if model then
            efforts = efforts_for[model]
          else
            efforts = models.default_efforts
          end
          if not efforts then
            return finish({ harness = name, model = model })
          end
          local effort_items, effort_selected = with_default(efforts, same and current.effort, "medium")
          return {
            title = name .. " effort",
            items = effort_items,
            selected = effort_selected,
            select = function(effort)
              finish({ harness = name, model = model, effort = effort })
            end,
          }
        end,
      }
    end,
  })
end

return M
