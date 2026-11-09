local directory = vim.env.ARK_TEST_DIR
local function wait_for(predicate, message)
  local complete = vim.wait(5000, predicate, 20)
  assert(complete, type(message) == "function" and message() or message)
end
local function read(name)
  return table.concat(vim.fn.readfile(directory .. "/" .. name, "b"), "\n")
end
local function ready()
  wait_for(function() return vim.fn.filereadable(directory .. "/ready") == 1 end, "fake agent did not start")
end
local tmux = require("ark.tmux")
local state = require("ark.state")
local function await(invoke)
  local done, failure, result
  invoke(function(err, value)
    assert(not done, "transport callback ran twice")
    done, failure, result = true, err, value
  end)
  wait_for(function() return done end, "transport callback did not complete")
  assert(not failure, failure)
  return result
end
local function find(root)
  return await(function(cb) tmux.find_pane(root, cb) end)
end
local function kill(pane)
  return await(function(cb) tmux.kill(pane, cb) end)
end
local function idle(root)
  wait_for(function() return not require("ark").is_busy(root) end, "workflow did not finish")
end
local function command(value)
  local root = vim.fn.getcwd()
  idle(root)
  local status = require("ark.status")
  local before = status.last_error(root)
  vim.cmd(value)
  idle(root)
  assert(vim.deep_equal(status.last_error(root), before), "unexpected workflow failure: " .. vim.inspect(status.last_error(root)))
end
local function active_pane()
  return vim.trim(vim.system({ "tmux", "display-message", "-p", "#{pane_id}" }, { text = true }):wait().stdout)
end

local function test()
  local root = vim.fn.getcwd()
  assert(state.load().harness == "claude", "fresh state should select Claude")
  assert(vim.fn.exists(":ArkEdit") == 2)
  assert(vim.fn.exists(":ArkFocus") == 0, "ArkFocus was removed")
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
    command("1ArkEdit")
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
    local pane = assert(find(root))
    local runtime = await(function(cb) tmux.inspect(pane, cb) end)
    assert(runtime.selection.harness == kind and runtime.selection.model == "example")
    assert(active_pane() == vim.env.TMUX_PANE, "edit must keep editor focus")
    vim.fn.delete(directory .. "/stdin.bin")
    command("ArkChat")
    assert(vim.bo.buftype == "terminal", "chat must open a terminal")
    assert(vim.api.nvim_win_get_config(0).relative == "editor", "chat must float")
    assert(active_pane() == vim.env.TMUX_PANE, "chat must keep outer tmux focus")
    local viewer = vim.api.nvim_get_current_buf()
    vim.wait(40, function() return false end, 5)
    assert(vim.fn.filereadable(directory .. "/stdin.bin") == 0, "chat after edit must not duplicate file context")
    require("ark.terminal").hide()
    vim.fn.writefile({ "other file" }, directory .. "/other.txt")
    vim.cmd("edit other.txt")
    command("ArkChat")
    wait_for(function()
      return vim.fn.filereadable(directory .. "/stdin.bin") == 1
        and read("stdin.bin"):find("file: other.txt", 1, true)
    end, "switching files must insert the new context")
    require("ark.terminal").hide()
    vim.cmd("edit sample.txt")
    command("ArkChat")
    wait_for(function()
      return vim.fn.filereadable(directory .. "/stdin.bin") == 1
        and read("stdin.bin"):find("\27[200~<editor_context>\nfile: sample.txt\n</editor_context>\n\n\27[201~", 1, true)
    end, "chat must paste the file context")
    assert(not read("stdin.bin"):find("\r", 1, true), "chat must not submit the file context")
    require("ark.terminal").hide()
    local context_bytes = read("stdin.bin")
    command("ArkChat")
    assert(vim.api.nvim_get_current_buf() == viewer, "summon must reuse the terminal")
    assert(find(root) == pane, "hide must keep the agent alive")
    vim.wait(40, function() return false end, 5)
    assert(read("stdin.bin") == context_bytes, "reopening the same file must not paste context")
    -- Exercise the real nested tmux client, not just the floating window.
    vim.api.nvim_chan_send(vim.bo[viewer].channel, "interactive follow-up\r")
    wait_for(function() return read("stdin.bin"):find("interactive follow-up\r", 1, true) end,
      "floating terminal must send interactive input to the same agent")
    local hide = vim.fn.maparg("<C-c>", "t", false, true).callback
    assert(type(hide) == "function", "terminal Ctrl-C must hide the viewer")
    hide()
    assert(vim.fs.basename(vim.api.nvim_buf_get_name(0)) == "sample.txt", "hide must restore the file")
    assert(not read("stdin.bin"):find("\3", 1, true), "hiding must not interrupt the agent")
    assert(find(root) == pane, "hiding must retain the background agent")
    -- Destroying a viewer also leaves the underlying process reconnectable.
    vim.api.nvim_buf_delete(viewer, { force = true })
    command("ArkChat")
    assert(vim.api.nvim_get_current_buf() ~= viewer, "deleted viewer must be recreated")
    assert(find(root) == pane, "recreated viewer must use the existing agent")
    local resized = vim.api.nvim_get_current_win()
    vim.api.nvim_exec_autocmds("VimResized", {})
    assert(vim.api.nvim_win_get_config(resized).width == math.floor(vim.o.columns * 0.85))
    require("ark.terminal").hide()
    vim.fn.delete(directory .. "/stdin.bin")
    command("1ArkEdit")
    wait_for(function() return vim.fn.filereadable(directory .. "/stdin.bin") == 1 end, "follow-up not received")
    wait_for(function()
      local bytes = read("stdin.bin")
      return bytes:find("\27[200~", 1, true) and bytes:find("\27[201~\r", 1, true)
    end, "follow-up must be one bracketed paste and Enter")
    assert(read("stdin.bin"):find(request, 1, true))
    assert(find(root) == pane, "follow-up must reuse the agent pane")
    assert(find(root .. "/other") == nil, "another project must not reuse this pane")
    kill(pane)
  end

  -- Build context after BufWritePre formatting and retain the captured project
  -- when an asynchronous input provider changes Neovim's working directory.
  local other_root = directory .. "/other project"
  vim.fn.mkdir(other_root, "p")
  vim.fn.delete(directory .. "/ready")
  vim.api.nvim_buf_set_lines(0, 0, 1, false, { "unformatted selection" })
  vim.api.nvim_create_autocmd("BufWritePre", { buffer = 0, once = true, callback = function()
    vim.api.nvim_buf_set_lines(0, 0, 1, false, { "formatted selection" })
  end })
  local original_input = vim.ui.input
  vim.ui.input = function(_, callback)
    vim.cmd.cd(other_root)
    callback("capture original project")
  end
  command("1ArkEdit")
  vim.ui.input = original_input
  ready()
  local formatted_argv = vim.json.decode(read("argv.json"))
  local formatted_prompt = formatted_argv[#formatted_argv]
  assert(formatted_prompt:find("1: formatted selection", 1, true), "context must use saved formatter output")
  assert(not formatted_prompt:find("unformatted selection", 1, true))
  assert(formatted_prompt:find("workspace: " .. root, 1, true), "request must retain its captured project")
  assert(read("saved.txt") == "formatted selection\nsecond line\n")
  assert(find(other_root) == nil, "directory changes must not redirect a pending request")
  kill(assert(find(root)))
  vim.cmd.cd(root)

  -- A fake agent edits on disk; the plugin's timer must reload the buffer.
  vim.cmd.stopinsert()
  assert(vim.fs.basename(vim.api.nvim_buf_get_name(0)) == "sample.txt", "edit must retain the file buffer")
  assert(not vim.bo.modified, "edit must save the file buffer")
  vim.fn.delete(directory .. "/ready")
  vim.fn.delete(directory .. "/stdin.bin")
  command("ArkChat")
  ready()
  local argv = vim.json.decode(read("argv.json"))
  assert(argv[1] == "--append-system-prompt" and argv[#argv] == "high", "a new chat must not start with a prompt")
  local instructions = table.concat(vim.fn.readfile(argv[2]), "\n")
  assert(instructions:find("You are a coding agent controlled from Neovim", 1, true))
  assert(instructions:find("\n\n<editor_context>\nfile: sample.txt\n</editor_context>$"),
    "a new chat must get the file context with its instructions")
  assert(vim.fn.filereadable(directory .. "/stdin.bin") == 0, "a new chat must not paste")
  require("ark.terminal").hide()
  vim.g.ark_test_request = "ARK_TEST_EDIT_FILE"
  command("1ArkEdit")
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
    idle()
  end
  local function open_pi()
    vim.cmd("ArkHarness")
    choose("pi")
  end
  local previous_pane = assert(find(root))
  open_pi()
  choose("example/plain")
  wait_for(function() return vim.bo.filetype ~= "TelescopePrompt" end, "plain model should skip effort picker")
  assert(state.load().model == "example/plain" and state.load().effort == nil)
  assert(find(root) ~= previous_pane, "changing harness selection must restart the agent pane")
  open_pi()
  choose("example/reasoning")
  choose("high")
  wait_for(function() return vim.bo.filetype ~= "TelescopePrompt" end, "picker did not close")
  assert(state.load().effort == "high")
  local unchanged_pane, unchanged_state = assert(find(root)), state.load()
  local confirmations = _G.ark_test_confirmations
  open_pi()
  choose("example/reasoning")
  choose("high")
  assert(find(root) == unchanged_pane and vim.deep_equal(state.load(), unchanged_state),
    "same selection must retain pane and state")
  assert(_G.ark_test_confirmations == confirmations, "same selection must not ask for confirmation")
  vim.g.ark_test_confirm = false
  open_pi()
  choose("example/plain")
  vim.g.ark_test_confirm = nil
  assert(find(root) == unchanged_pane and vim.deep_equal(state.load(), unchanged_state),
    "cancelled replacement must retain pane and state")
  assert(_G.ark_test_confirmations == confirmations + 1, "replacement must ask for confirmation")
  open_pi()
  choose(nil)
  choose(nil)
  wait_for(function() return vim.bo.filetype ~= "TelescopePrompt" end, "default picker did not close")
  assert(state.load().model == nil and state.load().effort == nil)
  assert(vim.fs.basename(vim.api.nvim_buf_get_name(0)) == "sample.txt", "picker must restore the file buffer")
  assert(not vim.bo.modified, "picker must leave the file buffer unmodified")

  -- The current harness leads, and each step opens on the current value, or
  -- on medium for an effort with no current value.
  -- Waits until the picker shows `values` in order with the cursor on `selected`.
  local function expect(values, selected)
    wait_for(function() return vim.bo.filetype == "TelescopePrompt" end, "picker did not open")
    local picker = action_state.get_current_picker(vim.api.nvim_get_current_buf())
    local shown
    wait_for(function()
      if not picker.manager or not picker:get_selection() then return false end
      shown = {}
      for i = 1, picker.manager:num_results() do
        table.insert(shown, picker.manager:get_entry(i).value or "default")
      end
      return table.concat(shown, ",") == table.concat(values, ",")
        and (picker:get_selection().value or "default") == selected
    end, function()
      return "picker shows " .. table.concat(shown or {}, ",") .. ", want " .. table.concat(values, ",")
        .. " at " .. selected .. "; selected=" .. vim.inspect(picker:get_selection())
    end)
  end
  state.save({ harness = "pi", model = "example/reasoning", effort = "high" })
  local pi_efforts = { "default", "off", "minimal", "low", "medium", "high", "xhigh", "max" }
  vim.cmd("ArkHarness")
  expect({ "pi", "claude", "codex", "agy" }, "pi")
  choose("pi")
  expect({ "default", "example/plain", "example/reasoning" }, "example/reasoning")
  choose("example/reasoning")
  expect(pi_efforts, "high")
  choose("high")
  wait_for(function() return vim.bo.filetype ~= "TelescopePrompt" end, "picker did not close")
  vim.cmd("ArkHarness")
  choose("claude")
  expect({ "default", "fable", "opus", "sonnet", "haiku" }, "default")
  choose("opus")
  expect({ "default", "low", "medium", "high", "xhigh", "max" }, "medium")
  choose("medium")
  wait_for(function() return vim.bo.filetype ~= "TelescopePrompt" end, "picker did not close")
  vim.cmd("ArkHarness")
  expect({ "claude", "codex", "pi", "agy" }, "claude")
  actions.close(vim.api.nvim_get_current_buf())
  wait_for(function() return vim.bo.filetype ~= "TelescopePrompt" end, "picker did not close")

  state.save({ harness = "pi", model = "example/reasoning", effort = "high" })
  command("ArkChat")
  require("ark.terminal").hide()
  vim.fn.writefile({ assert(find(root)) }, directory .. "/agent-pane")
end

local ok, err = xpcall(test, debug.traceback)
vim.fn.writefile(vim.split(ok and "PASS" or err, "\n", { plain = true }), directory .. "/result")
vim.cmd("qa!")
