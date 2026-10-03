local directory = vim.env.ARK_TEST_DIR
local function wait_for(predicate, message)
  assert(vim.wait(5000, predicate, 20), message)
end
local function read(name)
  return table.concat(vim.fn.readfile(directory .. "/" .. name, "b"), "\n")
end
local function ready()
  wait_for(function() return vim.fn.filereadable(directory .. "/ready") == 1 end, "fake agent did not start")
end
local tmux = require("ark.tmux")
local state = require("ark.state")
local function active_pane()
  return vim.trim(vim.system({ "tmux", "display-message", "-p", "#{pane_id}" }, { text = true }):wait().stdout)
end

local function test()
  local root = vim.fn.getcwd()
  assert(state.load().harness == "claude", "fresh state should select Claude")
  assert(vim.fn.exists(":ArkEdit") == 2)
  local ok, err = pcall(vim.cmd, "ArkEdit")
  assert(not ok and tostring(err):find("needs a range", 1, true))
  vim.bo.filetype = "text"
  vim.api.nvim_buf_set_lines(0, 0, 1, false, { "unsaved selection" })
  local namespace = vim.api.nvim_create_namespace("ark-test")
  vim.diagnostic.set(namespace, 0, {
    { lnum = 0, col = 0, severity = vim.diagnostic.severity.WARN, message = "selected diagnostic" },
    { lnum = 1, col = 0, severity = vim.diagnostic.severity.ERROR, message = "outside diagnostic" },
  })
  local request = "literal $HOME `echo unsafe` 'quotes'\nsecond request line"
  for _, kind in ipairs({ "claude", "codex", "agy", "pi" }) do
    state.save({ harness = kind, model = "example", effort = kind ~= "agy" and "high" or nil })
    vim.fn.delete(directory .. "/ready")
    vim.g.ark_test_request = request
    vim.cmd("1ArkEdit")
    ready()
    local argv = vim.json.decode(read("argv.json"))
    local prompt = argv[#argv]
    assert(prompt:find("file: sample.txt", 1, true))
    assert(prompt:find("1: unsaved selection", 1, true))
    assert(prompt:find("selected diagnostic", 1, true))
    assert(not prompt:find("outside diagnostic", 1, true))
    assert(prompt:find(request, 1, true), "prompt must preserve shell-like text")
    assert(read("saved.txt") == "unsaved selection\nsecond line\n", "save buffer before launching")
    if kind == "agy" then
      assert(argv[#argv - 1] == "-i")
      assert(prompt:find("You are a coding agent controlled from Neovim", 1, true))
    else
      assert(argv[1] == (kind == "claude" and "--append-system-prompt-file"
        or kind == "pi" and "--append-system-prompt" or "-c"))
    end
    local pane = assert(tmux.find_pane(root))
    assert(active_pane() == vim.env.TMUX_PANE, "edit must keep editor focus")
    require("ark").chat()
    assert(active_pane() == pane, "chat must focus the existing pane")
    tmux.focus(vim.env.TMUX_PANE)
    vim.fn.delete(directory .. "/stdin.bin")
    vim.cmd("1ArkEdit")
    wait_for(function() return vim.fn.filereadable(directory .. "/stdin.bin") == 1 end, "follow-up not received")
    wait_for(function()
      local bytes = read("stdin.bin")
      return bytes:find("\27[200~", 1, true) and bytes:find("\27[201~\r", 1, true)
    end, "follow-up must be one bracketed paste and Enter")
    assert(read("stdin.bin"):find(request, 1, true))
    assert(tmux.find_pane(root) == pane, "follow-up must reuse the agent pane")
    assert(tmux.find_pane(root .. "/other") == nil, "another project must not reuse this pane")
    tmux.kill(pane)
  end

  -- A fake agent edits on disk; the plugin's timer must reload the buffer.
  vim.cmd.stopinsert()
  assert(vim.fs.basename(vim.api.nvim_buf_get_name(0)) == "sample.txt", "edit must retain the file buffer")
  assert(not vim.bo.modified, "edit must save the file buffer")
  vim.fn.delete(directory .. "/ready")
  vim.cmd("ArkChat")
  ready()
  tmux.focus(vim.env.TMUX_PANE)
  vim.g.ark_test_request = "ARK_TEST_EDIT_FILE"
  vim.cmd("1ArkEdit")
  wait_for(function() return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == "agent edit" end, "buffer did not reload")

  -- Drive the real Telescope picker through all three steps.
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local function choose(value)
    wait_for(function() return vim.bo.filetype == "TelescopePrompt" end, "picker did not open")
    local buffer = vim.api.nvim_get_current_buf()
    local picker = action_state.get_current_picker(buffer)
    local index
    wait_for(function()
      if not picker.manager then return false end
      for i = 1, picker.manager:num_results() do
        if picker.manager:get_entry(i).value == value then index = i; return true end
      end
      return false
    end, "picker value missing: " .. tostring(value))
    picker:set_selection(index - 1)
    actions.select_default(buffer)
  end
  local function open_pi()
    vim.cmd("ArkHarness")
    choose("pi")
  end
  local previous_pane = assert(tmux.find_pane(root))
  open_pi()
  choose("example/plain")
  wait_for(function() return vim.bo.filetype ~= "TelescopePrompt" end, "plain model should skip effort picker")
  assert(state.load().model == "example/plain" and state.load().effort == nil)
  assert(tmux.find_pane(root) ~= previous_pane, "changing harness selection must restart the agent pane")
  open_pi()
  choose("example/reasoning")
  choose("high")
  wait_for(function() return vim.bo.filetype ~= "TelescopePrompt" end, "picker did not close")
  assert(state.load().effort == "high")
  open_pi()
  choose(nil)
  choose(nil)
  wait_for(function() return vim.bo.filetype ~= "TelescopePrompt" end, "default picker did not close")
  assert(state.load().model == nil and state.load().effort == nil)
  assert(vim.fs.basename(vim.api.nvim_buf_get_name(0)) == "sample.txt", "picker must restore the file buffer")
  assert(not vim.bo.modified, "picker must leave the file buffer unmodified")

  state.save({ harness = "pi", model = "example/reasoning", effort = "high" })
end

local ok, err = xpcall(test, debug.traceback)
vim.fn.writefile(vim.split(ok and "PASS" or err, "\n", { plain = true }), directory .. "/result")
