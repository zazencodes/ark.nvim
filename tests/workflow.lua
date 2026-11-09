-- Focused workflow failure/transaction checks, without tmux or agent CLIs.
vim.opt.rtp:prepend(vim.env.ARK_TEST_ROOT or vim.fn.getcwd())
local directory = vim.fn.tempname()
vim.fn.mkdir(directory, "p")
local root = vim.fn.getcwd()
local selection, saved = { harness = "test" }, 0
local calls, pane, find_error, save_error, kill_error = {}, "%old", nil, false, false
local input, confirmation, pending_find
local fake_state = {
  load = function() return vim.deepcopy(selection) end,
  save = function(value)
    calls[#calls + 1] = "save:" .. value.harness
    if save_error then error("ark: injected state save failure") end
    selection, saved = vim.deepcopy(value), saved + 1
  end,
  describe = function(value) return value.harness .. ":" .. (value.model or "default") end,
}
local fake_tmux = {
  status = function() return {} end,
  find_pane = function(project, cb)
    calls[#calls + 1] = "find:" .. project
    if pending_find then pending_find = cb else cb(find_error, pane) end
  end,
  send = function(destination, message, cb)
    calls[#calls + 1] = "send:" .. destination
    calls.message = message
    cb(nil, true)
  end,
  paste = function(_, _, cb) calls[#calls + 1] = "paste"; cb(nil, true) end,
  focus = function(_, cb) calls[#calls + 1] = "focus"; cb(nil, true) end,
  spawn = function(_, _, _, cb) calls[#calls + 1] = "spawn"; cb(nil, "%candidate") end,
  kill = function(target, cb)
    calls[#calls + 1] = "kill:" .. target
    cb(kill_error and target == "%old" and "ark: injected old kill failure" or nil, true)
  end,
}
package.loaded["ark.state"] = fake_state
package.loaded["ark.tmux"] = fake_tmux
package.loaded["ark.sync"] = { start = function() end, stop = function() end, status = function() return { roots = {} } end }
vim.ui.input = function(_, cb) input = cb end
vim.ui.select = function(_, _, cb) confirmation = cb end
local ark, config, picker = require("ark"), require("ark.config"), require("ark.picker")
ark.setup({ keymaps = { edit = false, chat = false, harness = false } })
local function adapter(cmd)
  return { cmd = { cmd }, catalog = function() return { models = {} } end }
end
config.options.harnesses = { test = adapter("sh"), other = adapter("sh"), missing = adapter(directory .. "/missing") }
config.options.harness_order = { "test", "other", "missing" }
local step
picker.run = function(value) step = value end
local function choose_harness(name)
  ark.pick_harness()
  local loading = step.select(name)
  local completed
  loading.load(function(err, next_step) assert(not err, err); step, completed = next_step, true end)
  assert(vim.wait(1000, function() return completed end, 5))
  step.select(nil)
end
local function fails(fn, expected)
  local ok, err = pcall(fn)
  assert(not ok and tostring(err):find(expected, 1, true), tostring(err))
  assert(not ark.is_busy(root), "failed operation remained busy")
end
local function has(value) return vim.list_contains(calls, value) end
local function reset()
  calls, selection, saved = {}, { harness = "test" }, 0
  pane, find_error, save_error, kill_error, confirmation = "%old", nil, false, false, nil
  vim.cmd("cd " .. vim.fn.fnameescape(root))
end
local file = directory .. "/sample.txt"
vim.fn.writefile({ "original", "second" }, file)
vim.cmd("edit " .. vim.fn.fnameescape(file))
local buf = vim.api.nvim_get_current_buf()
local ok, err = xpcall(function()
  ark.edit({ 1, 1 })
  assert(ark.is_busy(root))
  input(nil)
  assert(not ark.is_busy(root) and not calls.message, "cancel sent context")
  reset()
  ark.edit({ 1, 1 })
  vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "intervening edit" })
  fails(function() input("change it") end, "buffer changed")
  assert(not calls.message)
  assert(require("ark.status").last_error(root).message:find("buffer changed", 1, true))
  reset()
  choose_harness("test")
  assert(#calls == 0 and saved == 0 and not confirmation, "same-selection changed state")
  reset()
  fails(function() choose_harness("missing") end, "executable is missing")
  assert(not has("spawn") and not has("kill:%old") and not confirmation)
  reset()
  choose_harness("other")
  assert(confirmation and ark.is_busy(root))
  confirmation("Cancel")
  assert(not ark.is_busy(root) and not has("spawn") and saved == 0)
  reset()
  choose_harness("other")
  save_error = true
  fails(function() confirmation("End conversation and replace agent") end, "state save failure")
  assert(has("spawn") and has("kill:%candidate") and not has("kill:%old"))
  assert(selection.harness == "test")
  reset()
  choose_harness("other")
  kill_error = true
  fails(function() confirmation("End conversation and replace agent") end, "old kill failure")
  assert(selection.harness == "test" and has("kill:%candidate"), "replacement failed to roll back")
  reset()
  choose_harness("other")
  confirmation("End conversation and replace agent")
  assert(selection.harness == "other")
  assert(table.concat(calls, ","):find("spawn,save:other,kill:%%old"), "unsafe replacement order")
  reset()
  ark.focus()
  assert(has("focus") and not has("paste"), "focus pasted context")
  reset()
  -- Simulate a scheduled transport callback: an error must escape its guarded
  -- wrapper, be recorded, and release the project lock.
  pending_find = true
  ark.focus()
  local callback = pending_find
  pending_find = nil
  local emitted
  vim.schedule(function()
    local success, failure = pcall(callback, "ark: scheduled discovery failure")
    assert(not success, "guarded transport error was swallowed")
    emitted = failure
  end)
  assert(vim.wait(1000, function() return emitted ~= nil end, 5))
  assert(tostring(emitted):find("scheduled discovery failure", 1, true) and not ark.is_busy(root))
  assert(require("ark.status").last_error(root).message:find("scheduled discovery failure", 1, true))
end, debug.traceback)
vim.cmd("cd " .. vim.fn.fnameescape(root))
vim.fn.delete(directory, "rf")
if not ok then error(err) end
print("PASS: workflow cancellation/stale context, same-selection, missing executable, safe replacement/rollback, focus and async errors")
