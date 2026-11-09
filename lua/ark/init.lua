local config = require("ark.config")
local context = require("ark.context")
local picker = require("ark.picker")
local state = require("ark.state")
local sync = require("ark.sync")
local tmux = require("ark.tmux")
local status = require("ark.status")
local review = require("ark.review")
local M = {}
local busy, watching, probes = {}, {}, {}
local monitor

local function root_directory()
  return vim.fn.getcwd()
end

-- Every project has one in-flight workflow, including input/confirmation.
-- This also prevents pane discovery while a replacement has two tagged panes.
local function operation(root, run)
  if busy[root] then error("ark: another operation is pending for " .. root) end
  busy[root] = true
  local finished = false
  local function finish(err)
    if finished then return end
    finished = true
    busy[root] = nil
    if err then status.record(root, err); error(err) end
  end
  local function guarded(fn)
    return function(...)
      if finished then return end
      local ok, err = pcall(fn, ...)
      if not ok then
        if finished then error(err) else finish(err) end
      end
    end
  end
  guarded(run)(finish, guarded)
end

local function watch(root)
  review.setup()
  sync.start(root, config.options.checktime_interval)
  watching[root] = true
  if monitor then return end
  monitor = assert(vim.uv.new_timer())
  monitor:start(1000, 1000, vim.schedule_wrap(function()
    for project in pairs(watching) do
      if not busy[project] and not probes[project] then
        probes[project] = true
        tmux.find_pane(project, function(err, pane)
          probes[project] = nil
          if busy[project] then return end
          if err or not pane then
            watching[project] = nil
            sync.stop(project)
            if err then status.record(project, err) end
          end
        end)
      end
    end
    if not next(watching) and monitor then monitor:stop(); monitor:close(); monitor = nil end
  end))
end

function M.setup(opts)
  config.setup(opts)
  picker.clear_catalogs()
  review.setup()
  local mappings = {
    edit = { "x", ":ArkEdit<CR>", "edit selection" },
    chat = { "n", "<cmd>ArkChat<CR>", "open agent pane" },
    harness = { "n", "<cmd>ArkHarness<CR>", "pick harness, model, effort" },
    focus = { "n", "<cmd>ArkFocus<CR>", "focus agent pane" },
  }
  for name, mapping in pairs(mappings) do
    local key = config.options.keymaps[name]
    if key then vim.keymap.set(mapping[1], key, mapping[2], { silent = true, desc = "ark: " .. mapping[3] }) end
  end
end

-- Prepare and validate everything before a running conversation can end.
-- Temporary files belong to this launch and are removed by the wrapper when
-- its child exits, or explicitly on launch/confirmation failure.
local function prepare(selection, prompt, ctx)
  local files = {}
  local function cleanup()
    for _, path in ipairs(files) do vim.fn.delete(path) end
  end
  local function temporary(text)
    local path = vim.fn.tempname()
    files[#files + 1] = path
    if vim.fn.writefile(vim.split(text, "\n", { plain = true }), path) ~= 0 then error("ark: could not write launch file") end
    return path
  end
  local ok, argv = pcall(function()
    local harness = config.harness(selection.harness)
    if vim.fn.executable(harness.cmd[1]) ~= 1 then error("ark: harness executable is missing: " .. harness.cmd[1]) end
    local args = vim.deepcopy(harness.cmd)
    local instructions = table.concat(vim.fn.readfile(config.instructions_path), "\n")
    if ctx then instructions = instructions .. "\n\n" .. ctx end
    local instructions_file = ""
    if harness.instructions_args then
      local path = config.instructions_path
      if ctx then instructions_file = temporary(instructions); path = instructions_file end
      vim.list_extend(args, harness.instructions_args(path))
    else
      prompt = prompt and (instructions .. "\n\n" .. prompt) or instructions
    end
    if selection.model then
      if not harness.model_args then error("ark: harness has no model_args adapter") end
      vim.list_extend(args, harness.model_args(selection.model))
    end
    if selection.effort then
      if not harness.effort_args then error("ark: harness has no effort_args adapter") end
      vim.list_extend(args, harness.effort_args(selection.effort))
    end
    local prompt_file = ""
    if prompt then
      if harness.prompt_flag then table.insert(args, harness.prompt_flag) end
      prompt_file = temporary(prompt)
    end
    for _, arg in ipairs(args) do
      if type(arg) ~= "string" or arg:find("\0", 1, true) then error("ark: launch arguments must be strings without NUL bytes") end
    end
    local script = [[instructions=$1; prompt_file=$2; shift 2
trap 'if [ -n "$instructions" ]; then rm -f -- "$instructions"; fi; if [ -n "$prompt_file" ]; then rm -f -- "$prompt_file"; fi' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
if [ -n "$prompt_file" ]; then
  p=$(cat -- "$prompt_file") || exit
  rm -f -- "$prompt_file"
  "$@" "$p"
else
  "$@"
fi]]
    return vim.list_extend({ "sh", "-c", script, "ark-launch", instructions_file, prompt_file }, args)
  end)
  if not ok then cleanup(); error(argv) end
  return { argv = argv, cleanup = cleanup, selection = vim.deepcopy(selection) }
end

local function spawn(root, launch, done)
  tmux.spawn(root, launch.argv, config.options.pane.size, function(err, pane)
    if err then launch.cleanup() end
    done(err, pane)
  end, { selection = launch.selection })
end

-- range is captured with its buffer and project before asynchronous input.
function M.edit(range)
  local root, buf = root_directory(), vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(buf)
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  context.validate(buf, range)
  range = vim.deepcopy(range)
  operation(root, function(finish, guarded)
    tmux.find_pane(root, guarded(function(err, pane)
      if err then sync.stop(root); return finish(err) end
      vim.ui.input({ prompt = "Ark edit: " }, guarded(function(input)
        if not input or vim.trim(input) == "" then return finish() end
        if not vim.api.nvim_buf_is_loaded(buf) or vim.api.nvim_buf_get_name(buf) ~= path
          or vim.api.nvim_buf_get_changedtick(buf) ~= tick then
          return finish("ark: selected buffer changed while entering the request; select it again")
        end
        vim.api.nvim_buf_call(buf, function() vim.cmd("silent update") end)
        if not vim.api.nvim_buf_is_loaded(buf) or vim.api.nvim_buf_get_name(buf) ~= path or vim.bo[buf].modified then
          return finish("ark: save did not leave the selected buffer synchronized with disk")
        end
        local ctx = context.selection(buf, root, range)
        local message = ctx .. "\n\n<request>\n" .. input .. "\n</request>"
        local function sent(send_err, destination)
          if send_err then return finish(send_err) end
          watch(root)
          vim.notify("ark: sent to " .. (pane or destination))
          finish()
        end
        if pane then
          tmux.send(pane, message, guarded(sent))
        else
          spawn(root, prepare(state.load(), message), guarded(sent))
        end
      end))
    end))
  end)
end

local function open_agent(include_context)
  local root, buf = root_directory(), vim.api.nvim_get_current_buf()
  local ctx
  if include_context and vim.bo[buf].buftype == "" and vim.api.nvim_buf_get_name(buf) ~= "" then ctx = context.file(buf, root) end
  operation(root, function(finish, guarded)
    local function focus(pane)
      tmux.focus(pane, guarded(function(err)
        if err then return finish(err) end
        watch(root)
        finish()
      end))
    end
    tmux.find_pane(root, guarded(function(err, pane)
      if err then sync.stop(root); return finish(err) end
      if pane then
        if ctx then tmux.paste(pane, ctx .. "\n\n", guarded(function(paste_err)
          if paste_err then return finish(paste_err) end
          focus(pane)
        end)) else focus(pane) end
      else
        spawn(root, prepare(state.load(), nil, ctx), guarded(function(spawn_err, candidate)
          if spawn_err then return finish(spawn_err) end
          focus(candidate)
        end))
      end
    end))
  end)
end

function M.chat() open_agent(true) end
function M.focus() open_agent(false) end

local function with_default(values, current, preferred)
  local items, selected = {}, nil
  for _, value in ipairs(vim.list_extend({ vim.NIL }, values)) do
    value = value ~= vim.NIL and value or nil
    local label = value or "default"
    if value == current then label = label .. " (current)"; selected = #items + 1
    elseif value == preferred and not selected then selected = #items + 1 end
    table.insert(items, { value = value, label = label })
  end
  return items, selected
end

function M.pick_harness(refresh)
  local root, current = root_directory(), state.load()
  local function finish(selection)
    if vim.deep_equal(state.load(), selection) then vim.notify("ark: selection unchanged"); return end
    operation(root, function(done, guarded)
      tmux.find_pane(root, guarded(function(err, pane)
        if err then sync.stop(root); return done(err) end
        if not pane then
          local launch = prepare(selection)
          launch.cleanup()
          state.save(selection)
          vim.notify("ark: " .. state.describe(selection))
          return done()
        end
        local previous = state.load()
        local launch = prepare(selection)
        local confirmation = "End conversation and replace agent"
        vim.ui.select({ "Cancel", confirmation }, {
          prompt = "Ark: changing to " .. state.describe(selection) .. " ends this pane's conversation",
        }, guarded(function(choice)
          if choice ~= confirmation then launch.cleanup(); return done() end
          spawn(root, launch, guarded(function(spawn_err, candidate)
            if spawn_err then return done(spawn_err) end
            local saved, save_err = pcall(state.save, selection)
            local function discard(message)
              tmux.kill(candidate, guarded(function(cleanup_err)
                launch.cleanup()
                done(message .. (cleanup_err and ("; candidate cleanup failed: " .. cleanup_err) or ""))
              end))
            end
            if not saved then return discard(tostring(save_err)) end
            tmux.kill(pane, guarded(function(kill_err)
              if kill_err then
                local restored, restore_err = pcall(state.save, previous)
                return discard(kill_err .. (not restored and ("; preference rollback failed: " .. tostring(restore_err)) or ""))
              end
              watch(root)
              vim.notify("ark: " .. state.describe(selection) .. " (agent pane replaced)")
              done()
            end))
          end))
        end))
      end))
    end)
  end
  local harness_items = { { value = current.harness, label = current.harness .. " (current)" } }
  for _, name in ipairs(config.harness_order()) do
    if name ~= current.harness then table.insert(harness_items, { value = name, label = name }) end
  end
  picker.run({ title = "Ark harness", items = harness_items, select = function(name)
    return { title = name .. " models (loading; Esc cancels)", load = function(done)
      return picker.catalog(name, refresh, function(err, models)
        if err then return done(err) end
        local same, efforts_for = name == current.harness, {}
        for _, model in ipairs(models.models) do efforts_for[model.id] = model.efforts end
        local model_items, selected = with_default(vim.tbl_map(function(m) return m.id end, models.models), same and current.model)
        done(nil, { title = name .. " model", items = model_items, selected = selected, select = function(model)
          local efforts = model and efforts_for[model] or (not model and models.default_efforts or nil)
          if not efforts or #efforts == 0 then finish({ harness = name, model = model }); return end
          local items, effort_selected = with_default(efforts, same and current.effort, "medium")
          return { title = name .. " effort", items = items, selected = effort_selected, select = function(effort)
            finish({ harness = name, model = model, effort = effort })
          end }
        end })
      end)
    end }
  end }, function(err) status.record(root, err); error(err) end)
end

function M.status()
  if busy[root_directory()] then error("ark: another operation is pending for " .. root_directory()) end
  status.open(root_directory())
end

-- Observable without starting subprocesses; useful for integrations and tests.
function M.is_busy(root) return busy[root or root_directory()] == true end

return M
