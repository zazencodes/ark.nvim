local M = {}

local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h:h")

-- Static behavioral instructions given to every harness at launch.
M.instructions_path = plugin_root .. "/instructions.md"

M.defaults = {
  -- Adapters for the harnesses offered by :ArkHarness. See ark/harnesses.lua.
  harnesses = require("ark.harnesses"),
  -- Order of the harnesses in :ArkHarness, below the current one. Must list
  -- every configured harness.
  harness_order = { "claude", "codex", "pi", "agy" },
  -- Set by setup(). Set a key to false to leave it unmapped.
  keymaps = {
    edit = "<leader>ai",
    chat = "<leader>ao",
    harness = "<leader>ah",
  },
  window = { width = 0.85, height = 0.8 },
  -- How often (ms) Neovim checks for files changed on disk by the agent.
  checktime_interval = 1000,
  catalog_timeout_ms = 10000,
}

M.options = vim.deepcopy(M.defaults)

local function positive_integer(value)
  return type(value) == "number" and value > 0 and value % 1 == 0
end

local function argv(value, label)
  if type(value) ~= "table" or not vim.islist(value) or #value == 0 then
    error("ark: " .. label .. " must be a nonempty argv list")
  end
  for _, arg in ipairs(value) do
    if type(arg) ~= "string" or arg == "" or arg:find("\0", 1, true) then
      error("ark: " .. label .. " arguments must be nonempty strings without NUL bytes")
    end
  end
end

function M.harness(name)
  local harness = M.options.harnesses[name]
  if type(harness) ~= "table" then error("ark: unknown or invalid harness " .. tostring(name)) end
  argv(harness.cmd, "harness " .. name .. " cmd")
  if type(harness.catalog) ~= "function" then error("ark: harness " .. name .. " needs catalog()") end
  for _, field in ipairs({ "instructions_args", "model_args", "effort_args" }) do
    if harness[field] ~= nil and type(harness[field]) ~= "function" then
      error("ark: harness " .. name .. " " .. field .. " must be a function")
    end
  end
  if harness.catalog_args ~= nil then argv(harness.catalog_args, "harness " .. name .. " catalog_args") end
  if harness.prompt_flag ~= nil and (type(harness.prompt_flag) ~= "string" or harness.prompt_flag == "") then
    error("ark: harness " .. name .. " prompt_flag must be a nonempty string")
  end
  return harness
end

function M.harness_order()
  local order = M.options.harness_order
  if type(order) ~= "table" or not vim.islist(order) or #order == 0 then error("ark: harness_order must be a nonempty list") end
  local seen = {}
  for _, name in ipairs(order) do
    if type(name) ~= "string" or seen[name] then error("ark: harness_order entries must be unique harness names") end
    seen[name] = true
    M.harness(name)
  end
  for name in pairs(M.options.harnesses) do
    if not seen[name] then error(("ark: harness %q is missing from harness_order"):format(name)) end
  end
  return order
end

function M.validate()
  for _, key in ipairs({ "checktime_interval", "catalog_timeout_ms" }) do
    if not positive_integer(M.options[key]) then error("ark: " .. key .. " must be a positive integer") end
  end
  if type(M.options.harnesses) ~= "table" then error("ark: harnesses must be a table") end
  M.harness_order()
  if type(M.options.keymaps) ~= "table" then error("ark: keymaps must be a table") end
  for name, key in pairs(M.options.keymaps) do
    if M.defaults.keymaps[name] == nil then error("ark: unknown keymap " .. tostring(name)) end
    if key ~= false and (type(key) ~= "string" or key == "") then error("ark: keymaps must be nonempty strings or false") end
  end
  if M.options.pane ~= nil then error("ark: pane was removed; configure window.width and window.height") end
  if type(M.options.window) ~= "table" then error("ark: window must be a table") end
  for _, dimension in ipairs({ "width", "height" }) do
    local value = M.options.window[dimension]
    if type(value) ~= "number" or not (value > 0 and value <= 1) then
      error("ark: window." .. dimension .. " must be a fraction greater than 0 and at most 1")
    end
  end
end

function M.setup(opts)
  if opts ~= nil and type(opts) ~= "table" then error("ark: setup options must be a table") end
  local previous = M.options
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  local ok, err = pcall(M.validate)
  if not ok then M.options = previous; error(err) end
end

return M
