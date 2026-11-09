-- Standalone, credential-free: nvim --headless -u NONE -l tests/state.lua
vim.opt.rtp:prepend(vim.env.ARK_TEST_ROOT or vim.fn.getcwd())
local uv = vim.uv
local directory = vim.fn.tempname()
assert(vim.fn.mkdir(directory, "p") == 1)
local original_stdpath, original_module = vim.fn.stdpath, package.loaded["ark.state"]
vim.fn.stdpath = function(kind)
  if kind == "state" then return directory end
  return original_stdpath(kind)
end
package.loaded["ark.state"] = nil
local state = require("ark.state")
vim.fn.stdpath = original_stdpath
local path = directory .. "/ark.json"
local originals = {}
for _, name in ipairs({ "fs_open", "fs_write", "fs_rename", "fs_fsync" }) do originals[name] = uv[name] end
local function restore()
  for name, fn in pairs(originals) do uv[name] = fn end
end
local function write(text)
  assert(vim.fn.writefile({ text }, path) == 0)
end
local function contents()
  return table.concat(vim.fn.readfile(path), "\n")
end
local function fails(fn, pattern)
  local ok, err = pcall(fn)
  assert(not ok and tostring(err):find(pattern, 1, true), tostring(err))
end
local function no_temporary_files()
  local files = vim.fn.glob(path .. ".*", false, true)
  assert(#files == 0, "temporary state files leaked: " .. vim.inspect(files))
end
local ok, err = xpcall(function()
  assert(vim.deep_equal(state.load(), { harness = "claude" }))
  for _, invalid in ipairs({ "not JSON", "null", "[]", "true", '"claude"', '{}',
    '{"harness":null}', '{"harness":false}', '{"harness":""}',
    '{"harness":"   "}', '{"harness":"pi","model":[]}',
    '{"harness":"pi","effort":1}', '{"harness":"pi","unknown":"x"}' }) do
    write(invalid)
    fails(state.load, "invalid state")
    assert(contents() == invalid, "invalid state was silently rewritten")
  end
  local selection = { harness = "custom", model = "provider/model", effort = "high" }
  state.save(selection)
  assert(vim.deep_equal(state.load(), selection))
  local before = contents()
  fails(function() state.save({ harness = "pi", model = false }) end, "model must be a nonempty string")
  assert(contents() == before)
  -- A complete sibling file must exist before replacing the old valid JSON.
  local renamed = false
  uv.fs_rename = function(source, target)
    assert(source:match("^" .. vim.pesc(path) .. "%."))
    assert(target == path and contents() == before)
    local candidate = vim.json.decode(table.concat(vim.fn.readfile(source), "\n"))
    assert(candidate.harness == "codex")
    renamed = true
    return originals.fs_rename(source, target)
  end
  state.save({ harness = "codex" })
  assert(renamed and state.load().harness == "codex")
  restore()
  before = contents()
  for _, name in ipairs({ "fs_write", "fs_fsync", "fs_rename" }) do
    uv[name] = function() return nil, "injected " .. name .. " failure" end
    fails(function() state.save(selection) end, "injected " .. name .. " failure")
    assert(contents() == before, name .. " damaged prior state")
    no_temporary_files()
    restore()
  end
  uv.fs_write = function() return 1 end
  fails(function() state.save(selection) end, "incomplete write")
  assert(contents() == before)
  no_temporary_files()
  restore()
  -- Interleave two writers at the rename boundary. Each owns a distinct file;
  -- either complete selection may win, with no shared temporary-path collision.
  local paths, interleaved = {}, false
  uv.fs_rename = function(source, target)
    assert(not paths[source], "writers reused a temporary path")
    paths[source] = true
    if not interleaved then
      interleaved = true
      state.save({ harness = "pi", model = "nested" })
      assert(state.load().model == "nested")
    end
    return originals.fs_rename(source, target)
  end
  state.save(selection)
  assert(vim.tbl_count(paths) == 2)
  assert(vim.deep_equal(state.load(), selection))
  no_temporary_files()
  restore()
  uv.fs_open = function() return nil, "permission denied", "EACCES" end
  fails(state.load, "permission denied")
  restore()
  write('{"harness":"pi","effort":null}')
  fails(state.load, "nonempty string")
end, debug.traceback)
restore()
package.loaded["ark.state"] = original_module
vim.fn.delete(directory, "rf")
if not ok then error(err) end
print("PASS: state schema validation, atomic writes, failure cleanup and concurrent writers")
