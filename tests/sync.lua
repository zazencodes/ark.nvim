-- Credential-free focused checks and work-count benchmark:
-- nvim --headless -u NONE -l tests/sync.lua
local repo = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
vim.opt.rtp:prepend(repo)
vim.o.swapfile = false
vim.o.autoread = false
local sync = require("ark.sync")
local directory = vim.fn.resolve(vim.fn.tempname())
local root, other = directory .. "/project", directory .. "/project-extra"
vim.fn.mkdir(root .. "/nested", "p")
vim.fn.mkdir(other, "p")
local originals = { timer = vim.uv.new_timer, schedule = vim.schedule,
  stat = vim.uv.fs_stat, checktime = vim.cmd.checktime,
  list = vim.api.nvim_list_bufs, mode = vim.api.nvim_get_mode,
  cmdwin = vim.fn.getcmdwintype }
local timers, queue = {}, {}
local counts = { stat = 0, checktime = 0, list = 0 }
vim.uv.new_timer = function()
  local timer = { stopped = false, closed = false }
  function timer:start(timeout, interval, callback)
    self.timeout, self.interval, self.callback = timeout, interval, callback
    self.stopped = false
    return 0
  end
  function timer:stop() self.stopped = true; return 0 end
  function timer:close() self.closed = true end
  timers[#timers + 1] = timer
  return timer
end
vim.schedule = function(callback) queue[#queue + 1] = callback end
vim.uv.fs_stat = function(...)
  counts.stat = counts.stat + 1
  return originals.stat(...)
end
vim.cmd.checktime = function(...)
  counts.checktime = counts.checktime + 1
  return originals.checktime(...)
end
vim.api.nvim_list_bufs = function(...)
  counts.list = counts.list + 1
  return originals.list(...)
end
local events = {}
vim.api.nvim_create_autocmd("User", {
  pattern = { "ArkSyncConflict", "ArkSyncReload" },
  callback = function(event) events[#events + 1] = { name = event.match, data = event.data } end,
})
local function write(path, lines) assert(vim.fn.writefile(lines, path) == 0) end
local function load(path, lines)
  write(path, lines or { "original" })
  local buf = vim.fn.bufadd(path)
  vim.fn.bufload(buf)
  vim.bo[buf].buflisted = true
  return buf
end
local function lines(buf) return vim.api.nvim_buf_get_lines(buf, 0, -1, false) end
local function drain()
  local scheduled = queue
  queue = {}
  for _, callback in ipairs(scheduled) do callback() end
end
local function tick(repeats)
  for _ = 1, repeats or 1 do
    for _, timer in ipairs(timers) do
      if not timer.stopped and not timer.closed then timer.callback() end
    end
  end
  drain()
end
local function equal(actual, expected, message)
  assert(vim.deep_equal(actual, expected), (message or "mismatch") .. ": " .. vim.inspect(actual))
end
local function fails(callback, text)
  local ok, err = pcall(callback)
  assert(not ok and tostring(err):find("ark: " .. text, 1, true), tostring(err))
end
local function reset_counts() counts = { stat = 0, checktime = 0, list = 0 } end

local function test()
  fails(function() sync.start(50) end, "sync root")
  fails(function() sync.start(root, 0) end, "sync interval")
  fails(function() sync.start(root, 0.5) end, "sync interval")
  fails(function() sync.start(root, math.huge) end, "sync interval")
  local a = load(root .. "/a.txt")
  local b = load(other .. "/b.txt")
  local hidden = load(root .. "/hidden.txt")
  local unloaded = vim.fn.bufadd(root .. "/unloaded.txt")
  local scratch = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(scratch, root .. "/scratch")
  vim.bo[a].autoread = false
  vim.bo[b].autoread = false
  write(root .. "/a.txt", { "changed before start" })
  sync.start(root .. "/", 10)
  sync.start(root, 10)
  equal(#timers, 1, "start must be idempotent")
  equal(vim.tbl_count(sync.status().buffers), 2, "only loaded scoped file buffers")
  assert(not sync.status().buffers[unloaded] and not sync.status().buffers[scratch])
  tick()
  equal(lines(a), { "changed before start" }, "pre-start change must reload")
  equal(events[#events].data.previous_lines, { "original" })
  assert(not vim.o.autoread and not vim.bo[a].autoread and not vim.bo[b].autoread)

  reset_counts()
  tick(1000)
  equal(counts, { stat = 2, checktime = 0, list = 0 }, "coalesced idle work")
  local previous_events = #events
  write(root .. "/hidden.txt", { "background buffer changed" })
  write(other .. "/b.txt", { "outside scope changed" })
  tick()
  equal(lines(hidden), { "background buffer changed" }, "hidden buffer reload")
  equal(lines(b), { "original" }, "sibling-prefix root must be excluded")
  equal(#events, previous_events + 1)
  local reload = sync.status().reloads[hidden]
  equal(reload.previous_lines, { "original" })
  equal(reload.path, root .. "/hidden.txt")
  reload.previous_lines[1] = "caller mutation"
  equal(sync.status().reloads[hidden].previous_lines, { "original" }, "detached status")

  vim.api.nvim_buf_set_lines(a, 0, -1, false, { "unsaved local edit" })
  write(root .. "/a.txt", { "external conflict contents" })
  tick()
  equal(lines(a), { "unsaved local edit" }, "conflict must preserve edits")
  equal(vim.fn.readfile(root .. "/a.txt"), { "external conflict contents" }, "conflict preserves disk")
  equal(events[#events].name, "ArkSyncConflict")
  equal(sync.status().conflicts[a], { buf = a, path = root .. "/a.txt", root = root, reason = "changed" })
  previous_events = #events
  tick(10)
  equal(#events, previous_events, "same conflict is emitted once")
  write(root .. "/a.txt", { "second external conflict" })
  tick()
  equal(#events, previous_events + 1, "new disk version emits another conflict")
  vim.api.nvim_buf_call(a, function() vim.cmd("silent edit!") end)
  assert(not sync.status().conflicts[a], "explicit read resolves conflict")
  equal(lines(a), { "second external conflict" })

  vim.fn.delete(root .. "/hidden.txt")
  tick()
  equal(sync.status().conflicts[hidden].reason, "deleted")
  equal(lines(hidden), { "background buffer changed" }, "deletion preserves clean buffer")
  write(root .. "/hidden.txt", { "restored file" })
  tick()
  equal(lines(hidden), { "restored file" })
  assert(not sync.status().conflicts[hidden])

  local fresh = load(root .. "/fresh.txt")
  write(root .. "/fresh.txt", { "new buffer disk change" })
  tick()
  equal(lines(fresh), { "new buffer disk change" }, "newly loaded buffer is tracked")
  vim.api.nvim_buf_set_name(fresh, other .. "/renamed.txt")
  assert(not sync.status().buffers[fresh], "rename out of root removes buffer")
  vim.api.nvim_buf_delete(fresh, { force = true })
  vim.api.nvim_buf_delete(hidden, { force = true })
  assert(not sync.status().buffers[hidden] and not sync.status().reloads[hidden])

  sync.start(other, 20)
  tick()
  equal(lines(b), { "outside scope changed" }, "second root enrolled")
  sync.start(root, 25)
  equal(timers[1].interval, 25, "interval update reuses timer")
  local nested = load(root .. "/nested/file.txt")
  sync.start(root .. "/nested", 30)
  equal(sync.status().buffers[nested].root, root .. "/nested", "longest root owns buffer")
  sync.stop(root .. "/nested")
  equal(sync.status().buffers[nested].root, root, "nested stop transfers ownership")
  sync.stop(root)
  assert(timers[1].closed and sync.status().running and not sync.status().buffers[a])
  equal(vim.tbl_count(sync.status().buffers), 1)

  -- A stopped generation cannot run queued work or touch a restarted root.
  timers[2].callback()
  assert(sync.status().pending)
  sync.stop()
  assert(not sync.status().running and not sync.status().pending and timers[2].closed)
  equal(vim.fn.exists("#ArkSync"), 0, "autocommand group cleaned up")
  sync.start(root, 10)
  reset_counts()
  drain()
  equal(counts, { stat = 0, checktime = 0, list = 0 }, "cancelled scheduled callback")
  tick()
  vim.api.nvim_get_mode = function() return { mode = "c", blocking = false } end
  reset_counts()
  tick()
  equal(counts.stat, 0, "command-line mode is deferred")
  vim.api.nvim_get_mode = originals.mode
  vim.fn.getcmdwintype = function() return ":" end
  tick()
  equal(counts.stat, 0, "command window is deferred")
  vim.fn.getcmdwintype = originals.cmdwin
  vim.api.nvim_get_mode = function() return { mode = "n", blocking = true } end
  tick()
  equal(counts.stat, 0, "blocking mode is deferred")
  vim.api.nvim_get_mode = originals.mode
  tick()
  assert(counts.stat > 0, "normal mode resumes")
  sync.stop()

  -- Initial enrollment must detect a conflict that predates start().
  vim.api.nvim_buf_set_lines(a, 0, -1, false, { "local before enrollment" })
  write(root .. "/a.txt", { "external before enrollment" })
  sync.start(root, 10)
  tick()
  equal(sync.status().conflicts[a].reason, "changed")
  equal(lines(a), { "local before enrollment" })
  vim.api.nvim_buf_call(a, function() vim.cmd("silent write!") end)
  assert(not sync.status().conflicts[a], "explicit write resolves conflict")
  sync.stop()

  -- Work regression: count old global checktime invocations versus new scoped
  -- stats/commands with many loaded files. Neovim can defer global checktime
  -- in headless Lua, so this deliberately makes no native-I/O or CPU claim.
  for _, buf in ipairs(originals.list()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == "" then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end
  local perf_root = directory .. "/perf"
  vim.fn.mkdir(perf_root, "p")
  local scoped = load(perf_root .. "/one.txt")
  for i = 1, 255 do load(other .. "/perf-" .. i .. ".txt") end
  local rounds = 100
  reset_counts()
  for _ = 1, rounds do vim.cmd.checktime() end
  equal(counts.checktime, rounds, "old callback invokes global checktime every tick")
  sync.start(perf_root, 10)
  tick()
  reset_counts()
  for _ = 1, rounds do tick() end
  equal(counts, { stat = rounds, checktime = 0, list = 0 }, "steady-state scope work")
  equal(vim.tbl_count(sync.status().buffers), 1)
  write(perf_root .. "/one.txt", { "changed scoped file" })
  reset_counts()
  tick()
  equal(counts.checktime, 1, "one changed file means one scoped checktime")
  equal(lines(scoped), { "changed scoped file" })
  sync.stop()
  reset_counts()
  tick(100)
  equal(counts, { stat = 0, checktime = 0, list = 0 }, "stopped idle work")
  print(("WORK: 256 loaded files, %d ticks: old %d global checktime invocations; "
    .. "scoped %d stats / 0 checktime / 0 enumerations; stopped 0 work")
    :format(rounds, rounds, rounds))

  -- Real libuv/scheduler smoke test in addition to deterministic fake ticks.
  vim.uv.new_timer, vim.schedule = originals.timer, originals.schedule
  sync.start(perf_root, 5)
  write(perf_root .. "/one.txt", { "real timer reload" })
  assert(vim.wait(1000, function() return lines(scoped)[1] == "real timer reload" end, 5), "real timer did not reload")
  vim.api.nvim_exec_autocmds("VimLeavePre", { modeline = false })
  assert(not sync.status().running, "exit cleanup")
  assert(not vim.o.autoread and not vim.bo[scoped].autoread)
  print("PASS: scoped sync, conflicts/reloads, lifecycle, coalescing, options, modes, performance, real timer")
end

local ok, err = xpcall(test, debug.traceback)
sync.stop()
vim.uv.new_timer, vim.schedule, vim.uv.fs_stat = originals.timer, originals.schedule, originals.stat
vim.cmd.checktime, vim.api.nvim_list_bufs = originals.checktime, originals.list
vim.api.nvim_get_mode, vim.fn.getcmdwintype = originals.mode, originals.cmdwin
vim.fn.delete(directory, "rf")
if not ok then error(err) end
