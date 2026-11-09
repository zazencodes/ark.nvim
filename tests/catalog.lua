-- Credential-free async catalog lifecycle checks.
vim.opt.rtp:prepend(vim.env.ARK_TEST_ROOT or vim.fn.getcwd())
local picker, config = require("ark.picker"), require("ark.config")
local directory = vim.fn.tempname()
vim.fn.mkdir(directory, "p")
local count = directory .. "/count"
local script = directory .. "/catalog.py"
vim.fn.writefile({
  "import pathlib,sys,time", "p=pathlib.Path(sys.argv[1])", "p.write_text(p.read_text()+'x' if p.exists() else 'x')",
  "time.sleep(float(sys.argv[2]))", "print('model')",
}, script)
local function adapter(delay, parse)
  return { cmd = { "python3", script, count, tostring(delay) }, catalog_args = { "models" }, catalog = parse or function(stdout)
    assert(stdout:find("model", 1, true))
    return { models = { { id = "model", efforts = { "low", "high" } } } }
  end }
end
config.options.harnesses = { selected = adapter(0.1), unselected = adapter(0), broken = adapter(0, function() return { models = { { id = "" } } } end) }
config.options.catalog_timeout_ms = 1000
local function request(name, refresh)
  local completed, err, catalog = false, nil, nil
  picker.catalog(name, refresh, function(e, value) completed, err, catalog = true, e, value end)
  assert(vim.wait(2000, function() return completed end, 5), "catalog callback missing")
  return err, catalog
end
local ok, err = xpcall(function()
  local ticked = false
  vim.defer_fn(function() ticked = true end, 10)
  local failure, value = request("selected")
  assert(not failure and value.models[1].id == "model" and ticked, "catalog blocked event loop")
  assert(table.concat(vim.fn.readfile(count), "") == "x", "unselected catalog ran")
  local _, cached = request("selected")
  cached.models[1].id = "mutated"
  assert(table.concat(vim.fn.readfile(count), "") == "x", "cache missed")
  local _, isolated = request("selected")
  assert(isolated.models[1].id == "model", "cache exposed mutable value")
  request("selected", true)
  assert(table.concat(vim.fn.readfile(count), "") == "xx", "explicit refresh missed")
  assert(request("broken"):find("unique nonempty id", 1, true), "malformed catalog accepted")
  config.options.harnesses.slow = adapter(2)
  config.options.catalog_timeout_ms = 50
  assert(request("slow"):find("timed out", 1, true), "catalog deadline missing")
  local called = false
  local cancel = picker.catalog("slow", true, function() called = true end)
  cancel()
  vim.wait(150, function() return false end, 5)
  assert(not called, "cancelled catalog called completion")
  config.options.catalog_timeout_ms = 1000
  local generation_error, generation_done
  picker.catalog("selected", true, function(e) generation_error, generation_done = e, true end)
  picker.clear_catalogs()
  assert(vim.wait(1500, function() return generation_done end, 5))
  assert(generation_error:find("configuration changed", 1, true), "old request survived configuration reset")
  local before_reset = table.concat(vim.fn.readfile(count), "")
  request("selected")
  assert(#table.concat(vim.fn.readfile(count), "") == #before_reset + 1, "old callback repopulated cleared cache")
  config.options.harnesses.missing = { cmd = { directory .. "/missing" }, catalog_args = { "models" }, catalog = function() error("must not parse") end }
  assert(request("missing"), "missing executable succeeded")
end, debug.traceback)
vim.fn.delete(directory, "rf")
if not ok then error(err) end
print("PASS: selected-only nonblocking catalogs, cache/refresh, malformed output, timeout and cancellation")
