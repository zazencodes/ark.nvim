-- Review preserves both versions and fails loudly on filesystem errors.
vim.opt.rtp:prepend(vim.env.ARK_TEST_ROOT or vim.fn.getcwd())
local review = require("ark.review")
local directory = vim.fn.tempname()
vim.fn.mkdir(directory, "p")
local path = directory .. "/sample.txt"
vim.fn.writefile({ "original" }, path)
vim.cmd("edit " .. vim.fn.fnameescape(path))
local buf = vim.api.nvim_get_current_buf()
path = vim.api.nvim_buf_get_name(buf)
review.setup()
local original_stat, original_open = vim.uv.fs_stat, io.open
local confirm, options
vim.ui.select = function(values, _, cb) options, confirm = values, cb end
local function fails(fn, expected)
  local ok, err = pcall(fn)
  assert(not ok and tostring(err):find(expected, 1, true), tostring(err))
end
local function read() return vim.fn.readfile(path) end
local function current() return vim.api.nvim_buf_get_lines(buf, 0, -1, false) end
local function choose() confirm(options[2]) end
local ok, err = xpcall(function()
  fails(review.open, "no recorded disk change")
  vim.uv.fs_stat = function(name)
    if name == path then return nil, "permission denied", "EACCES" end
    return original_stat(name)
  end
  fails(function() review.record(buf, "changed") end, "cannot stat")
  vim.uv.fs_stat = original_stat
  io.open = function(name, mode)
    if name == path then return nil, "injected open error" end
    return original_open(name, mode)
  end
  fails(function() review.record(buf, "changed") end, "cannot open")
  io.open = function(name, mode)
    if name == path then return { read = function() return nil, "injected read error" end, close = function() return true end } end
    return original_open(name, mode)
  end
  fails(function() review.record(buf, "changed") end, "cannot read")
  io.open = function(name, mode)
    if name == path then return { read = function() return "bytes" end, close = function() return nil, "injected close error" end } end
    return original_open(name, mode)
  end
  fails(function() review.record(buf, "changed") end, "cannot close")
  io.open = original_open
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "editor edits" })
  vim.fn.writefile({ "disk edits" }, path)
  vim.api.nvim_exec_autocmds("User", { pattern = "ArkSyncConflict", data = { buf = buf, reason = "changed" } })
  review.open()
  local after = vim.api.nvim_get_current_buf()
  local before
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local candidate = vim.api.nvim_win_get_buf(win)
    if candidate ~= after then before = candidate end
  end
  assert(vim.api.nvim_buf_get_lines(before, 0, -1, false)[1] == "editor edits")
  assert(vim.api.nvim_buf_get_lines(after, 0, -1, false)[1] == "disk edits")
  assert(vim.b[after].ark_disk_bytes == "disk edits\n")
  assert(current()[1] == "editor edits" and read()[1] == "disk edits", "review changed either version")
  review.resolve("disk")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "later editor edits" })
  fails(choose, "changed during confirmation")
  assert(current()[1] == "later editor edits" and read()[1] == "disk edits")
  vim.api.nvim_set_current_buf(buf)
  review.resolve("disk")
  choose()
  assert(current()[1] == "disk edits" and not vim.bo[buf].modified)
  assert(vim.api.nvim_buf_get_lines(before, 0, -1, false)[1] == "editor edits", "resolution destroyed preserved editor version")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "chosen editor" })
  vim.fn.writefile({ "second disk" }, path)
  review.record(buf, "changed")
  review.resolve("buffer")
  choose()
  assert(read()[1] == "chosen editor" and current()[1] == "chosen editor")
  vim.fn.delete(path)
  review.record(buf, "deleted")
  fails(function() review.resolve("disk") end, "file was deleted")
  review.resolve("buffer")
  choose()
  assert(read()[1] == "chosen editor", "deleted file recovery failed")
  review.record(buf, "reloaded", { "before reload" })
  review.open()
  local found = false
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, 1, false)[1] == "before reload" then found = true end
  end
  assert(found, "clean reload lost previous lines")
end, debug.traceback)
vim.uv.fs_stat, io.open = original_stat, original_open
vim.fn.delete(directory, "rf")
if not ok then error(err) end
print("PASS: review snapshots/resolution, intervening edits, deleted-file recovery and filesystem errors")
