-- Persist only the explicit harness selection; omitted model/effort select the
-- CLI defaults. Invalid state is surfaced rather than silently discarded.
local M = {}
local uv = vim.uv
local path = vim.fn.stdpath("state") .. "/ark.json"
local fields = { harness = true, model = true, effort = true }

function M.validate(selection)
  if type(selection) ~= "table" or vim.islist(selection) then
    error("ark: selection must be an object containing harness, model and effort")
  end
  for key, value in pairs(selection) do
    if not fields[key] then
      error("ark: unknown selection field: " .. tostring(key))
    end
    if type(value) ~= "string" or vim.trim(value) == "" then
      error("ark: selection " .. key .. " must be a nonempty string")
    end
  end
  if type(selection.harness) ~= "string" or vim.trim(selection.harness) == "" then
    error("ark: selection harness must be a nonempty string")
  end
  return selection
end

function M.load()
  local fd, err, code = uv.fs_open(path, "r", 384)
  if not fd then
    if code == "ENOENT" then
      return { harness = "claude" }
    end
    error("ark: cannot read state " .. path .. ": " .. tostring(err))
  end
  local stat, stat_err = uv.fs_fstat(fd)
  local data, read_err
  if stat then
    data, read_err = uv.fs_read(fd, stat.size, 0)
  end
  local closed, close_err = uv.fs_close(fd)
  if not stat or not data or not closed then
    error("ark: cannot read state " .. path .. ": " .. tostring(stat_err or read_err or close_err))
  end
  local ok, selection = pcall(vim.json.decode, data)
  if ok then
    ok, selection = pcall(M.validate, selection)
  end
  if not ok then
    error("ark: invalid state " .. path .. ": " .. tostring(selection) .. "; fix or remove this file and retry")
  end
  return selection
end

function M.save(selection)
  M.validate(selection)
  local data = vim.json.encode(selection) .. "\n"
  local directory = vim.fn.fnamemodify(path, ":h")
  local ok, err = pcall(vim.fn.mkdir, directory, "p")
  if not ok then
    error("ark: cannot create state directory " .. directory .. ": " .. tostring(err))
  end
  local fd, temporary = uv.fs_mkstemp(path .. ".XXXXXX")
  if not fd then
    error("ark: cannot create temporary state file beside " .. path .. ": " .. tostring(temporary))
  end
  local failure
  local written, write_err = uv.fs_write(fd, data, 0)
  if written ~= #data then
    failure = write_err or "incomplete write"
  end
  if not failure then
    local synced, sync_err = uv.fs_fsync(fd)
    if not synced then
      failure = sync_err
    end
  end
  local closed, close_err = uv.fs_close(fd)
  failure = failure or (not closed and close_err or nil)
  if not failure then
    local renamed, rename_err = uv.fs_rename(temporary, path)
    if not renamed then
      failure = rename_err
    end
  end
  if failure then
    local removed, remove_err = uv.fs_unlink(temporary)
    error("ark: cannot save state " .. path .. ": " .. tostring(failure)
      .. (not removed and ("; cannot remove temporary file " .. temporary .. ": " .. tostring(remove_err)) or ""))
  end
end

function M.describe(selection)
  M.validate(selection)
  return ("%s · %s · %s"):format(selection.harness, selection.model or "default model", selection.effort or "default effort")
end

return M
