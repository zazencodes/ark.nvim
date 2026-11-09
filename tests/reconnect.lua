local directory = vim.env.ARK_TEST_DIR
local ok, err = xpcall(function()
  local expected = vim.fn.readfile(directory .. "/agent-pane")[1]
  local done, pane, failure
  require("ark.tmux").find_pane(vim.fn.getcwd(), function(e, p) failure, pane, done = e, p, true end)
  assert(vim.wait(5000, function() return done end, 10))
  assert(not failure, failure)
  assert(pane == expected, "Neovim restart lost the background conversation")
  local before = table.concat(vim.fn.readfile(directory .. "/stdin.bin", "b"), "\n")
  require("ark").chat()
  assert(vim.wait(5000, function() return not require("ark").is_busy() end, 10))
  assert(vim.bo.buftype == "terminal", "restart must open the floating terminal")
  assert(vim.wait(5000, function()
    return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"):find("ARK_TEST_AGENT_READY", 1, true) ~= nil
  end, 10), "attached terminal must render the agent")
  assert(table.concat(vim.fn.readfile(directory .. "/stdin.bin", "b"), "\n") == before,
    "restarting Neovim must remember the agent's current file")
  vim.api.nvim_chan_send(vim.bo.channel, "after Neovim restart\r")
  assert(vim.wait(5000, function()
    local input = table.concat(vim.fn.readfile(directory .. "/stdin.bin", "b"), "\n")
    return input:find("after Neovim restart\r", 1, true) ~= nil
  end, 10), "reconnected terminal must reach the existing agent")
  require("ark.terminal").hide()
  assert(vim.fs.basename(vim.api.nvim_buf_get_name(0)) == "sample.txt")
end, debug.traceback)
vim.fn.writefile(vim.split(ok and "PASS" or err, "\n", { plain = true }), directory .. "/reconnect-result")
vim.cmd("qa!")
