-- Standalone, credential-free: nvim --headless -u NONE -l tests/transport.lua
vim.opt.rtp:prepend(vim.env.ARK_TEST_ROOT or vim.fn.getcwd())
local original_system = vim.system
local original_tmux, original_pane = vim.env.TMUX, vim.env.TMUX_PANE
vim.env.TMUX, vim.env.TMUX_PANE = "ark-test", "%1"
local calls, buffers, pastes, killed = {}, {}, {}, {}
local handler
local metadata = {}
local function default(args, opts)
  local command = args[2]
  if command == "display-message" then
    local pane = args[5]
    return { stdout = pane .. "\t0\t/project\t" .. (metadata[pane] or "") }
  elseif command == "list-panes" then
    return { stdout = "%2\t0\t/project\n" }
  elseif command == "split-window" then
    return { stdout = "%9" }
  elseif command == "set-option" and args[6] == "@ark_selection" then
    metadata[args[5]] = args[7]
  elseif command == "load-buffer" then
    buffers[args[4]] = opts.stdin
  elseif command == "paste-buffer" then
    local buffer, pane = args[7], args[9]
    assert(buffers[buffer], "paste lost its buffer")
    pastes[#pastes + 1] = { pane = pane, text = buffers[buffer], buffer = buffer }
    buffers[buffer] = nil
  elseif command == "delete-buffer" then
    buffers[args[4]] = nil
  end
  return {}
end
local fake_runner = function(args, opts, callback)
  assert(args[1] == "tmux")
  calls[#calls + 1] = vim.deepcopy(args)
  local output = handler and handler(args, opts) or default(args, opts)
  local child = { kill = function(_, signal)
    assert(signal == 9)
    killed[#killed + 1] = args[2]
  end }
  if not output.hang then
    vim.defer_fn(function()
      callback({ code = output.code or 0, stdout = output.stdout or "", stderr = output.stderr or "" })
    end, output.delay or 1)
  end
  return child
end
vim.system = fake_runner
local tmux = require("ark.tmux")
local function reset()
  calls, buffers, pastes, killed, metadata = {}, {}, {}, {}, {}
  handler = nil
end
local function capture(invoke)
  local result = { count = 0 }
  invoke(function(err, value)
    result.count = result.count + 1
    result.err, result.value = err, value
  end)
  return result
end
local function wait(result)
  assert(vim.wait(2500, function() return result.count > 0 end, 1), "callback timed out")
  assert(result.count == 1, "callback ran more than once")
  return result.err, result.value
end
local function success(invoke)
  local err, result = wait(capture(invoke))
  assert(not err, err)
  return result
end
local function failure(invoke, pattern)
  local err = wait(capture(invoke))
  assert(err and err:find(pattern, 1, true), tostring(err))
  return err
end
local function has(command)
  for _, args in ipairs(calls) do
    if args[2] == command then return true end
  end
  return false
end
local ok, err = xpcall(function()
  assert(success(function(cb) tmux.find_pane("/project", cb) end) == "%2")
  assert(success(function(cb) tmux.find_pane("/missing", cb) end) == nil)
  reset()
  handler = function() return { stdout = "%2\t1\t/project" } end
  failure(function(cb) tmux.find_pane("/project", cb) end, "is dead")
  reset()
  handler = function() return { stdout = "%2\t0\t/project\n%3\t0\t/project" } end
  failure(function(cb) tmux.find_pane("/project", cb) end, "multiple agent panes")
  reset()
  handler = function() return { stdout = "%2\t1\t/project\t" } end
  failure(function(cb) tmux.send("%2", "hello", cb) end, "is dead")
  assert(not has("load-buffer"))
  reset()
  handler = function() return { code = 1, stderr = "can't find pane: %2" } end
  failure(function(cb) tmux.inspect("%2", cb) end, "can't find pane")
  reset()
  vim.system = function() error("ENOENT") end
  failure(function(cb) tmux.find_pane("/project", cb) end, "installed and on PATH")
  vim.system = fake_runner
  reset()
  -- A hung child must leave the editor responsive and callback exactly once.
  handler = function() return { hang = true } end
  local ticked = false
  vim.defer_fn(function() ticked = true end, 5)
  local pending = capture(function(cb) tmux.find_pane("/project", cb, { timeout_ms = 25 }) end)
  local timeout_err = wait(pending)
  assert(timeout_err:find("deadline", 1, true) or timeout_err:find("timed out", 1, true))
  assert(ticked and #killed == 1)
  vim.wait(40, function() return false end, 1)
  assert(pending.count == 1)
  local status = tmux.status()
  assert(status.last_failure.operation == "find_pane")
  status.last_failure.message = "mutated"
  assert(tmux.status().last_failure.message ~= "mutated")
  reset()
  -- A process completing after cancellation cannot invoke its callback again.
  handler = function() return { stdout = "%2\t0\t/project", delay = 60 } end
  pending = capture(function(cb) tmux.find_pane("/project", cb, { timeout_ms = 10 }) end)
  assert(wait(pending))
  vim.wait(80, function() return false end, 1)
  assert(pending.count == 1)
  reset()
  -- Cleanup gets a separate bounded deadline even if tmux stops responding.
  handler = function(args, opts)
    if args[2] == "paste-buffer" then return { code = 1, stderr = "paste failed" } end
    if args[2] == "delete-buffer" then return { hang = true } end
    return default(args, opts)
  end
  local cleanup_started = vim.uv.hrtime()
  local cleanup_error = failure(function(cb) tmux.paste("%2", "text", cb, { timeout_ms = 100 }) end, "paste failed")
  assert(cleanup_error:find("cleanup:", 1, true))
  assert((vim.uv.hrtime() - cleanup_started) / 1e6 < 1500, "cleanup exceeded bounded deadline")
  reset()
  -- Different panes may paste concurrently, but buffers must never collide.
  handler = function(args, opts)
    local output = default(args, opts)
    if args[2] == "load-buffer" then output.delay = 15 end
    return output
  end
  local first = capture(function(cb) tmux.send("%2", "alpha", cb) end)
  local second = capture(function(cb) tmux.send("%3", "beta", cb) end)
  assert(not wait(first))
  assert(not wait(second))
  assert(#pastes == 2 and pastes[1].buffer ~= pastes[2].buffer)
  local received = {}
  for _, item in ipairs(pastes) do received[item.pane] = item.text end
  assert(received["%2"] == "alpha" and received["%3"] == "beta")
  assert(vim.tbl_isempty(buffers))
  reset()
  -- Same-pane sends finish their Enter before a second paste starts.
  local a = capture(function(cb) tmux.send("%2", "one", cb) end)
  local b = capture(function(cb) tmux.send("%2", "two", cb) end)
  assert(not wait(a))
  assert(not wait(b))
  local actions = {}
  for _, args in ipairs(calls) do
    if args[2] ~= "display-message" then actions[#actions + 1] = args[2] end
  end
  assert(table.concat(actions, ",") == "load-buffer,paste-buffer,send-keys,load-buffer,paste-buffer,send-keys")
  reset()
  -- Queue time counts toward the caller's deadline and never starts expired work.
  handler = function(args, opts)
    local output = default(args, opts)
    if args[2] == "load-buffer" then output.delay = 60 end
    return output
  end
  a = capture(function(cb) tmux.send("%2", "one", cb, { timeout_ms = 500 }) end)
  b = capture(function(cb) tmux.send("%2", "two", cb, { timeout_ms = 10 }) end)
  assert(wait(b):find("deadline", 1, true))
  assert(not wait(a))
  assert(#pastes == 1 and pastes[1].text == "one")
  reset()
  -- The budget spans every subprocess, rather than restarting at each step.
  handler = function(args, opts)
    local output = default(args, opts)
    output.delay = 20
    return output
  end
  pending = capture(function(cb) tmux.send("%2", "bounded", cb, { timeout_ms = 45 }) end)
  local aggregate_error = wait(pending)
  assert(aggregate_error:find("deadline", 1, true) or aggregate_error:find("timed out", 1, true))
  assert(not has("send-keys"), "an expired send submitted its paste")
  vim.wait(60, function() return false end, 1)
  assert(pending.count == 1)
  reset()
  handler = function(args, opts)
    if args[2] == "paste-buffer" then return { code = 1, stderr = "pane disappeared" } end
    return default(args, opts)
  end
  failure(function(cb) tmux.paste("%2", "text", cb) end, "pane disappeared")
  assert(has("delete-buffer") and vim.tbl_isempty(buffers))
  reset()
  handler = function(args, opts)
    if args[2] == "split-window" then return { hang = true } end
    return default(args, opts)
  end
  failure(function(cb) tmux.spawn("/project", { "fake-agent" }, "40%", cb, { timeout_ms = 10 }) end,
    "may have created an untagged pane")
  assert(not has("kill-pane"), "a split timeout must never kill the existing pane")
  reset()
  handler = function(args, opts)
    if args[2] == "set-option" then return { code = 1, stderr = "tagging failed" } end
    return default(args, opts)
  end
  failure(function(cb) tmux.spawn("/project", { "fake-agent" }, "40%", cb) end, "tagging failed")
  assert(has("kill-pane"))
  for _, args in ipairs(calls) do
    if args[2] == "kill-pane" then assert(args[4] == "%9", "old pane was killed") end
  end
  reset()
  local selection = { harness = "pi", model = "example/model", effort = "high" }
  assert(success(function(cb) tmux.spawn("/project", { "fake-agent" }, "40%", cb, { selection = selection }) end) == "%9")
  local info = success(function(cb) tmux.inspect("%9", cb) end)
  assert(vim.deep_equal(info.selection, selection))
  assert(success(function(cb) tmux.focus("%9", cb) end))
  assert(has("select-window") and has("select-pane"))
  metadata["%9"] = '{"harness":false}'
  failure(function(cb) tmux.inspect("%9", cb) end, "invalid @ark_selection")
  reset()
  failure(function(cb) tmux.spawn("/project", {}, "40%", cb) end, "nonempty list")
  assert(not has("split-window"))
  failure(function(cb) tmux.kill("", cb) end, "invalid pane id")
  assert(not has("kill-pane"))
  reset()
  vim.env.TMUX = nil
  failure(function(cb) tmux.find_pane("/project", cb) end, "inside tmux")
end, debug.traceback)
vim.system = original_system
vim.env.TMUX, vim.env.TMUX_PANE = original_tmux, original_pane
if not ok then error(err) end
print("PASS: async transport deadlines, failures, concurrency, cleanup and metadata")
