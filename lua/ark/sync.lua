-- Scoped disk synchronization. The caller owns pane liveness and calls
-- stop(root) when its agent goes away; this module never starts subprocesses.
--
-- start(root, interval_ms): register an absolute project root; repeated calls
-- update its interval. stop(root): unregister it; stop() unregisters all roots.
-- status(): detached {running, pending, roots = {[path] = interval_ms},
-- buffers = {[buf] = {buf, path, root}}, conflicts = {[buf] = change},
-- reloads = {[buf] = change}}. Changes contain {buf, path, root, reason}, where
-- reason is "changed" or "deleted". Reloads also contain previous_lines.
-- User events ArkSyncConflict / ArkSyncReload carry the same change as data.
-- Conflicts preserve both versions; reading/writing the buffer resolves them.
local M = {}

local roots, buffers, conflicts, reloads = {}, {}, {}, {}
local group, pending, generation = nil, false, 0

local function normalize(root)
  if type(root) ~= "string" or root:sub(1, 1) ~= "/" then
    error("ark: sync root must be an absolute path")
  end
  local path = vim.fn.resolve(vim.fs.normalize(root))
  return path == "/" and path or path:gsub("/+$", "")
end

local function owner(path)
  local selected
  for root in pairs(roots) do
    if (root == "/" or path:sub(1, #root + 1) == root .. "/")
      and (not selected or #root > #selected) then
      selected = root
    end
  end
  return selected
end

local function signature(path)
  local stat, message, code = vim.uv.fs_stat(path)
  if not stat then
    if code == "ENOENT" or code == "ENOTDIR" then
      return "missing"
    end
    error(("ark: cannot stat %s: %s"):format(path, message))
  end
  return table.concat({ stat.dev, stat.ino, stat.size, stat.mode,
    stat.mtime.sec, stat.mtime.nsec, stat.ctime.sec, stat.ctime.nsec }, ":")
end

local function forget(buf)
  buffers[buf], conflicts[buf], reloads[buf] = nil, nil, nil
end

local function track(buf, read)
  if not vim.api.nvim_buf_is_loaded(buf) or vim.bo[buf].buftype ~= "" then
    forget(buf)
    return
  end
  local name = vim.api.nvim_buf_get_name(buf)
  local path = name ~= "" and vim.fs.normalize(name) or ""
  local root = owner(path)
  if not root then
    forget(buf)
    return
  end
  local previous = buffers[buf]
  if not previous or previous.path ~= path or previous.root ~= root then
    forget(buf)
    buffers[buf] = { buf = buf, path = path, root = root, initial = true }
  end
  if read then
    local item = buffers[buf]
    item.signature, item.initial = signature(path), false
    conflicts[buf] = nil
  end
end

local function publish(item, kind, reason, previous_lines)
  local change = { buf = item.buf, path = item.path, root = item.root, reason = reason }
  if kind == "Reload" then
    change.previous_lines = previous_lines
    reloads[item.buf], conflicts[item.buf] = change, nil
  else
    conflicts[item.buf] = change
  end
  vim.api.nvim_exec_autocmds("User", {
    pattern = "ArkSync" .. kind,
    modeline = false,
    data = vim.deepcopy(change),
  })
end

local function check(item)
  local buf = item.buf
  if not vim.api.nvim_buf_is_loaded(buf) or vim.bo[buf].buftype ~= ""
    or vim.api.nvim_buf_get_name(buf) ~= item.path then
    track(buf)
    return
  end
  local current = signature(item.path)
  if not item.initial and current == item.signature then
    return
  end
  local initial = item.initial
  item.initial, item.signature = false, current
  if current == "missing" then
    -- Deletion must keep even a clean buffer available for recovery/review.
    publish(item, "Conflict", "deleted")
    return
  end
  if not initial and vim.bo[buf].modified then
    publish(item, "Conflict", "changed")
    return
  end

  -- FileChangedShell handles initial enrollment too: Neovim knows the disk
  -- timestamp from the original read, including changes before start(). The
  -- temporary, buffer-local handler avoids changing any autoread option.
  local before = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local conflict
  local autocmd = vim.api.nvim_create_autocmd("FileChangedShell", {
    buffer = buf,
    callback = function()
      if vim.bo[buf].modified or vim.v.fcs_reason == "deleted" then
        vim.v.fcs_choice = ""
        conflict = vim.v.fcs_reason == "deleted" and "deleted" or "changed"
      else
        vim.v.fcs_choice = "reload"
      end
    end,
  })
  local ok, err = pcall(vim.cmd.checktime, tostring(buf))
  vim.api.nvim_del_autocmd(autocmd)
  if not ok then
    error(("ark: checktime failed for %s: %s"):format(item.path, err))
  end
  if conflict then
    publish(item, "Conflict", conflict)
  elseif vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_get_changedtick(buf) ~= tick then
    publish(item, "Reload", "changed", before)
  end
end

local function enqueue(root)
  roots[root].due = true
  if pending then
    return
  end
  pending = true
  local scheduled_generation = generation
  vim.schedule(function()
    if scheduled_generation ~= generation then
      return
    end
    pending = false
    local mode = vim.api.nvim_get_mode()
    local blocked = mode.blocking or mode.mode:sub(1, 1) == "c" or vim.fn.getcmdwintype() ~= ""
    local due = {}
    for path, entry in pairs(roots) do
      due[path], entry.due = entry.due, false
    end
    if blocked then
      return
    end
    local ok, err = pcall(function()
      -- Snapshot ids: reload autocommands may add/remove tracked buffers.
      for _, buf in ipairs(vim.tbl_keys(buffers)) do
        local item = buffers[buf]
        if item and due[item.root] then
          check(item)
        end
      end
    end)
    if not ok then
      M.stop()
      error("ark: buffer sync failed: " .. tostring(err))
    end
  end)
end

local function watch()
  group = vim.api.nvim_create_augroup("ArkSync", { clear = true })
  vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost" }, {
    group = group,
    callback = function(event) track(event.buf, true) end,
  })
  vim.api.nvim_create_autocmd({ "BufEnter", "BufFilePost" }, {
    group = group,
    callback = function(event) track(event.buf) end,
  })
  vim.api.nvim_create_autocmd({ "BufUnload", "BufDelete", "BufWipeout" }, {
    group = group,
    callback = function(event) forget(event.buf) end,
  })
  vim.api.nvim_create_autocmd("VimLeavePre", { group = group, callback = function() M.stop() end })
end

function M.start(root, interval)
  root = normalize(root)
  if type(interval) ~= "number" or interval ~= interval or interval <= 0
    or interval == math.huge or interval % 1 ~= 0 then
    error("ark: sync interval must be a positive integer in milliseconds")
  end
  local entry = roots[root]
  if entry and entry.interval == interval then
    return
  end
  if not entry then
    local timer, err = vim.uv.new_timer()
    if not timer then
      error("ark: cannot create sync timer: " .. tostring(err))
    end
    entry = { timer = timer }
    roots[root] = entry
    if not group then watch() end
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do track(buf) end
  end
  entry.interval = interval
  local ok, err = entry.timer:start(interval, interval, function()
    if roots[root] == entry then enqueue(root) end
  end)
  if not ok then
    M.stop(root)
    error("ark: cannot start sync timer: " .. tostring(err))
  end
end

function M.stop(root)
  root = root and normalize(root)
  for path, entry in pairs(roots) do
    if not root or path == root then
      entry.timer:stop()
      entry.timer:close()
      roots[path] = nil
    end
  end
  if not next(roots) then
    generation, pending = generation + 1, false
    if group then vim.api.nvim_del_augroup_by_id(group) end
    group = nil
    buffers, conflicts, reloads = {}, {}, {}
  else
    for _, buf in ipairs(vim.tbl_keys(buffers)) do track(buf) end
  end
end

function M.status()
  local result = { running = next(roots) ~= nil, pending = pending,
    roots = {}, buffers = {}, conflicts = vim.deepcopy(conflicts), reloads = vim.deepcopy(reloads) }
  for root, entry in pairs(roots) do result.roots[root] = entry.interval end
  for buf, item in pairs(buffers) do
    result.buffers[buf] = { buf = buf, path = item.path, root = item.root }
  end
  return result
end

return M
