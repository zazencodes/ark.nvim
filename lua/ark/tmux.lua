-- Async tmux transport. Every operation has one total deadline and an
-- (err, result) callback scheduled on Neovim's main loop.
local M = {}
local uv = vim.uv
local DEFAULT_TIMEOUT = 3000
local CLEANUP_TIMEOUT = 1000
local queues = {}
local sequence = 0
local last_failure

local function now()
  return uv.hrtime() / 1e6
end

-- Each child has its own watchdog, including cleanup commands. Returning a
-- cancellation function lets the enclosing deadline stop a running child.
local function process(args, stdin, timeout, callback)
  local child, timer, done
  local function finish(err, stdout)
    if done then
      return
    end
    done = true
    if timer then
      timer:stop()
      timer:close()
    end
    vim.schedule(function()
      callback(err, stdout)
    end)
  end
  local function stop()
    if child then
      pcall(child.kill, child, 9)
    end
  end
  timer = uv.new_timer()
  timer:start(math.max(1, math.ceil(timeout)), 0, function()
    stop()
    finish(("tmux %s timed out; check that the tmux server is responsive"):format(args[1]))
  end)
  local ok, result = pcall(vim.system, vim.list_extend({ "tmux" }, args), {
    stdin = stdin,
    text = true,
    timeout = math.max(1, math.ceil(timeout)),
  }, function(output)
    if output.code == 124 then
      finish(("tmux %s timed out; check that the tmux server is responsive"):format(args[1]))
    elseif output.code ~= 0 then
      local detail = vim.trim(output.stderr or "")
      finish(("tmux %s failed (exit %s): %s"):format(args[1], output.code,
        detail ~= "" and detail or "no diagnostic output; check the target pane and tmux server"))
    else
      finish(nil, (output.stdout or ""):gsub("[\r\n]+$", ""))
    end
  end)
  if ok then
    child = result
  else
    finish("cannot start tmux: " .. tostring(result) .. "; check that tmux is installed and on PATH")
  end
  return function()
    if not done then
      stop()
      done = true
      timer:stop()
      timer:close()
    end
  end
end

local function operation(name, callback, opts)
  if type(callback) ~= "function" then
    error("ark: tmux " .. name .. " requires an (err, result) callback")
  end
  opts = opts or {}
  local timeout = opts.timeout_ms or DEFAULT_TIMEOUT
  if type(timeout) ~= "number" or timeout <= 0 or timeout % 1 ~= 0 or timeout == math.huge then
    error("ark: tmux timeout_ms must be a positive integer")
  end
  local op = { deadline = now() + timeout, cleanups = {} }
  local timer = uv.new_timer()
  function op:finish(err, result)
    if self.finished then
      return
    end
    self.finished = true
    if err and self.pending_spawn and (err:find("deadline", 1, true) or err:find("timed out", 1, true)) then
      err = err .. "; split-window may have created an untagged pane before timing out; inspect this tmux window and close the candidate"
    end
    timer:stop()
    timer:close()
    if self.cancel then
      self.cancel()
      self.cancel = nil
    end
    local function complete()
      if err then
        err = "ark: " .. name .. ": " .. err
        last_failure = { operation = name, message = err, time = os.time() }
      end
      if self.release then
        self.release()
      end
      vim.schedule(function()
        callback(err, result)
      end)
    end
    if not err or #self.cleanups == 0 then
      complete()
      return
    end
    local cleanup_deadline = now() + CLEANUP_TIMEOUT
    local function cleanup()
      local args = table.remove(self.cleanups)
      if not args then
        complete()
        return
      end
      local remaining = cleanup_deadline - now()
      if remaining <= 0 then
        err = err .. "; cleanup deadline exceeded; inspect tmux panes/buffers for leftover ark resources"
        complete()
        return
      end
      process(args, nil, remaining, function(cleanup_err)
        if cleanup_err then
          err = err .. "; cleanup: " .. cleanup_err
        end
        cleanup()
      end)
    end
    cleanup()
  end
  function op:run(args, stdin, next_step)
    if self.finished then
      return
    end
    local remaining = self.deadline - now()
    if remaining <= 0 then
      self:finish("deadline exceeded; check that the tmux server is responsive")
      return
    end
    self.cancel = process(args, stdin, remaining, function(err, stdout)
      if self.finished then
        return
      end
      self.cancel = nil
      if err then
        self:finish(err)
      else
        next_step(stdout)
      end
    end)
  end
  timer:start(timeout, 0, vim.schedule_wrap(function()
    op:finish(("deadline exceeded after %dms; check tmux responsiveness or pending operations"):format(timeout))
  end))
  return op
end

local function start(op, pane, action)
  vim.schedule(function()
    if op.finished then
      return
    end
    if not pane then
      action()
      return
    end
    local queue = queues[pane] or {}
    queues[pane] = queue
    local entry = { op = op, action = action }
    table.insert(queue, entry)
    op.release = function()
      local first = queue[1] == entry
      for i, item in ipairs(queue) do
        if item == entry then
          table.remove(queue, i)
          break
        end
      end
      if #queue == 0 then
        queues[pane] = nil
      elseif first then
        local next_entry = queue[1]
        vim.schedule(function()
          if queue[1] == next_entry and not next_entry.op.finished then
            next_entry.action()
          end
        end)
      end
    end
    if #queue == 1 then
      action()
    end
  end)
end

local function nvim_pane(op)
  if not vim.env.TMUX or not vim.env.TMUX_PANE then
    op:finish("Neovim must be running inside tmux; start Neovim in a tmux pane")
    return
  end
  return vim.env.TMUX_PANE
end

local function valid_pane(op, pane)
  if type(pane) ~= "string" or not pane:match("^%%%d+$") then
    op:finish("invalid pane id; expected a tmux pane id such as %1")
    return false
  end
  return true
end

local function live(op, pane, callback)
  if not valid_pane(op, pane) then
    return
  end
  op:run({ "display-message", "-p", "-t", pane,
    "#{pane_id}\t#{pane_dead}\t#{@ark_root}\t#{@ark_selection}" }, nil, function(out)
    local id, dead, root, selection = out:match("^(%%%d+)\t([01])\t([^\t]*)\t(.*)$")
    if id ~= pane then
      op:finish("tmux returned invalid pane metadata for " .. pane)
    elseif dead == "1" then
      op:finish("pane " .. pane .. " is dead; close it with `tmux kill-pane -t " .. pane .. "` and retry")
    else
      local metadata
      if selection ~= "" then
        local ok, decoded = pcall(vim.json.decode, selection)
        if not ok or type(decoded) ~= "table" then
          op:finish("pane " .. pane .. " has invalid @ark_selection metadata; restart the agent pane")
          return
        end
        local valid = pcall(require("ark.state").validate, decoded)
        if not valid then
          op:finish("pane " .. pane .. " has invalid @ark_selection metadata; restart the agent pane")
          return
        end
        metadata = decoded
      end
      callback({ id = id, root = root ~= "" and root or nil, selection = metadata })
    end
  end)
end

function M.find_pane(root, callback, opts)
  local op = operation("find_pane", callback, opts)
  start(op, nil, function()
    local pane = nvim_pane(op)
    if not pane then
      return
    end
    op:run({ "list-panes", "-s", "-t", pane, "-F", "#{pane_id}\t#{pane_dead}\t#{@ark_root}" }, nil, function(out)
      local found
      for line in vim.gsplit(out, "\n", { plain = true }) do
        local id, dead, pane_root = line:match("^(%%%d+)\t([01])\t(.*)$")
        if pane_root == root then
          if dead == "1" then
            op:finish("pane " .. id .. " for " .. root .. " is dead; close it with `tmux kill-pane -t " .. id .. "` and retry")
            return
          end
          if found then
            op:finish("multiple agent panes for " .. root .. "; close the extra pane and retry")
            return
          end
          found = id
        end
      end
      op:finish(nil, found)
    end)
  end)
end

function M.inspect(pane, callback, opts)
  local op = operation("inspect", callback, opts)
  start(op, nil, function()
    live(op, pane, function(info)
      op:finish(nil, info)
    end)
  end)
end

function M.spawn(root, argv, size, callback, opts)
  local op = operation("spawn", callback, opts)
  start(op, nil, function()
    local parent = nvim_pane(op)
    if not parent then
      return
    end
    if type(root) ~= "string" or root == "" then
      op:finish("spawn root must be a nonempty directory path")
      return
    end
    if type(argv) ~= "table" or not vim.islist(argv) or #argv == 0 then
      op:finish("spawn argv must be a nonempty list of strings")
      return
    end
    for _, arg in ipairs(argv) do
      if type(arg) ~= "string" or arg:find("\0", 1, true) then
        op:finish("spawn argv must contain strings without NUL bytes")
        return
      end
    end
    if type(size) ~= "string" and type(size) ~= "number" then
      op:finish("spawn size must be a tmux pane size such as 40%")
      return
    end
    if opts and opts.selection then
      local ok, err = pcall(require("ark.state").validate, opts.selection)
      if not ok then
        op:finish(tostring(err))
        return
      end
    end
    local args = { "split-window", "-h", "-d", "-l", size, "-t", parent, "-c", root, "-P", "-F", "#{pane_id}" }
    op.pending_spawn = true
    op:run(vim.list_extend(args, argv), nil, function(id)
      op.pending_spawn = false
      if not id:match("^%%%d+$") then
        op:finish("split-window returned an invalid pane id; inspect tmux for an untagged candidate pane")
        return
      end
      table.insert(op.cleanups, { "kill-pane", "-t", id })
      live(op, id, function()
        op:run({ "set-option", "-p", "-t", id, "@ark_root", root }, nil, function()
          local function ready()
            live(op, id, function()
              op:finish(nil, id)
            end)
          end
          if opts and opts.selection then
            op:run({ "set-option", "-p", "-t", id, "@ark_selection", vim.json.encode(opts.selection) }, nil, ready)
          else
            ready()
          end
        end)
      end)
    end)
  end)
end

local function paste(op, pane, text, callback)
  sequence = sequence + 1
  local buffer = ("ark-%s-%s-%d"):format(uv.os_getpid(), tostring(uv.hrtime()), sequence)
  local cleanup = { "delete-buffer", "-b", buffer }
  table.insert(op.cleanups, cleanup)
  op:run({ "load-buffer", "-b", buffer, "-" }, text, function()
    op:run({ "paste-buffer", "-p", "-r", "-d", "-b", buffer, "-t", pane }, nil, function()
      for i, item in ipairs(op.cleanups) do
        if item == cleanup then
          table.remove(op.cleanups, i)
          break
        end
      end
      callback()
    end)
  end)
end

local function input(name, pane, text, callback, opts)
  local op = operation(name, callback, opts)
  start(op, pane, function()
    live(op, pane, function()
      paste(op, pane, text, function()
        if name == "send" then
          op:run({ "send-keys", "-t", pane, "Enter" }, nil, function()
            op:finish(nil, true)
          end)
        else
          op:finish(nil, true)
        end
      end)
    end)
  end)
end

function M.paste(pane, text, callback, opts)
  input("paste", pane, text, callback, opts)
end

function M.send(pane, text, callback, opts)
  input("send", pane, text, callback, opts)
end

function M.kill(pane, callback, opts)
  local op = operation("kill", callback, opts)
  start(op, pane, function()
    if not valid_pane(op, pane) then
      return
    end
    op:run({ "kill-pane", "-t", pane }, nil, function()
      op:finish(nil, true)
    end)
  end)
end

function M.focus(pane, callback, opts)
  local op = operation("focus", callback, opts)
  start(op, pane, function()
    live(op, pane, function()
      op:run({ "select-window", "-t", pane }, nil, function()
        op:run({ "select-pane", "-t", pane }, nil, function()
          op:finish(nil, true)
        end)
      end)
    end)
  end)
end

function M.status()
  return { last_failure = last_failure and vim.deepcopy(last_failure) or nil }
end

return M
