-- Preserve editor and disk versions before resolving any disk-change conflict.
local M = {}
local entries = {}
local serial = 0
local initialized = false

local function disk(path)
  local stat, stat_err, stat_code = vim.uv.fs_stat(path)
  if not stat then
    if stat_code == "ENOENT" or stat_code == "ENOTDIR" then return nil end
    error("ark: cannot stat review file: " .. tostring(stat_err))
  end
  local file, err = io.open(path, "rb")
  if not file then error("ark: cannot open review snapshot: " .. tostring(err)) end
  local bytes, read_err = file:read("*a")
  local closed, close_err = file:close()
  if not bytes then error("ark: cannot read review snapshot: " .. tostring(read_err)) end
  if not closed then error("ark: cannot close review snapshot: " .. tostring(close_err)) end
  return bytes
end

local function lines(bytes)
  if bytes == nil then return { "[file deleted on disk]" } end
  local value = vim.split(bytes, "\n", { plain = true })
  if value[#value] == "" and #value > 1 then table.remove(value) end
  for i, line in ipairs(value) do value[i] = line:gsub("\r$", "") end
  return value
end

local function snapshot(source, label, content)
  serial = serial + 1
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, ("ark://review/%d/%s/%s"):format(serial, label, vim.fs.basename(vim.api.nvim_buf_get_name(source))))
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = vim.bo[source].filetype
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)
  vim.bo[buf].modifiable = false
  vim.b[buf].ark_review_source = source
  return buf
end

function M.record(buf, reason, previous_lines)
  if not vim.api.nvim_buf_is_loaded(buf) then return end
  local path = vim.api.nvim_buf_get_name(buf)
  local bytes = disk(path)
  local editor = previous_lines or vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local entry = { buf = buf, path = path, reason = reason, bytes = bytes }
  entry.before = snapshot(buf, previous_lines and "before-reload" or "editor", editor)
  entry.after = snapshot(buf, bytes == nil and "deleted" or "disk", lines(bytes))
  -- Preserve exact disk bytes too, including newline and binary differences.
  vim.b[entry.after].ark_disk_bytes = bytes
  entries[buf] = entry
  return entry
end

function M.setup()
  if initialized then return end
  initialized = true
  local group = vim.api.nvim_create_augroup("ArkReview", { clear = true })
  vim.api.nvim_create_autocmd("User", { group = group, pattern = "ArkSyncConflict", callback = function(ev)
    M.record(ev.data.buf, ev.data.reason)
    vim.notify("ark: disk conflict preserved; use :ArkReview, then :ArkResolve disk or :ArkResolve buffer", vim.log.levels.WARN)
  end })
  vim.api.nvim_create_autocmd("User", { group = group, pattern = "ArkSyncReload", callback = function(ev)
    M.record(ev.data.buf, "reloaded", ev.data.previous_lines)
  end })
end

local function source()
  local buf = vim.api.nvim_get_current_buf()
  return vim.b[buf].ark_review_source or buf
end

function M.open()
  local buf = source()
  local entry = entries[buf]
  if not entry then error("ark: no recorded disk change for this buffer; Ark captures its own reloads and conflicts while sync is active") end
  vim.cmd("tabnew")
  vim.api.nvim_win_set_buf(0, entry.before)
  vim.cmd("diffthis")
  vim.cmd("rightbelow vnew")
  vim.api.nvim_win_set_buf(0, entry.after)
  vim.cmd("diffthis")
  vim.notify("ark: preserved editor/before version on left, disk version on right; resolve with :ArkResolve disk or :ArkResolve buffer")
end

function M.resolve(choice)
  if choice ~= "disk" and choice ~= "buffer" then error("ark: use :ArkResolve disk or :ArkResolve buffer") end
  local buf = source()
  local entry = entries[buf]
  if not entry then error("ark: no recorded disk change for this buffer; Ark captures its own reloads and conflicts while sync is active") end
  if not vim.api.nvim_buf_is_loaded(buf) or vim.api.nvim_buf_get_name(buf) ~= entry.path then
    error("ark: original review buffer is no longer available")
  end
  if choice == "disk" and entry.bytes == nil then error("ark: file was deleted; use :ArkResolve buffer to recreate it") end
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local bytes = disk(entry.path)
  if bytes ~= entry.bytes then error("ark: disk changed again; return to the file and run :checktime before reviewing") end
  local label = choice == "disk" and "Load disk version (replace buffer edits)" or "Write buffer version (replace disk contents)"
  vim.ui.select({ "Cancel", label }, { prompt = "Ark resolve: both versions are preserved in review buffers" }, function(value)
    if value ~= label then return end
    if not vim.api.nvim_buf_is_loaded(buf) or vim.api.nvim_buf_get_name(buf) ~= entry.path
      or vim.api.nvim_buf_get_changedtick(buf) ~= tick or disk(entry.path) ~= bytes then
      error("ark: buffer or disk changed during confirmation; review again")
    end
    M.record(buf, "before-resolution")
    vim.api.nvim_buf_call(buf, function()
      if choice == "disk" then vim.cmd("edit!") else vim.cmd("write!") end
    end)
    entries[buf] = nil
    vim.notify("ark: resolved using " .. choice .. " version; preserved snapshots remain available in the review tab")
  end)
end

return M
