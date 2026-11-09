local M = {}

function M.check()
  local health = vim.health
  health.start("ark.nvim")
  if vim.fn.has("nvim-0.11.7") == 1 then health.ok("Neovim >= 0.11.7") else health.error("Neovim >= 0.11.7 is required") end
  for _, dependency in ipairs({ "telescope", "plenary" }) do
    local ok = pcall(require, dependency)
    if ok then health.ok(dependency .. " is installed") else health.error("Install " .. dependency .. ".nvim") end
  end
  if vim.fn.executable("tmux") == 1 then health.ok("tmux is executable") else health.error("Install tmux and put it on PATH") end
  if vim.env.TMUX and vim.env.TMUX_PANE then health.ok("Neovim is inside tmux") else health.error("Start Neovim inside tmux") end
  local config = require("ark.config")
  local ok, err = pcall(function()
    config.validate()
    local selection = require("ark.state").load()
    local adapter = config.harness(selection.harness)
    if vim.fn.executable(adapter.cmd[1]) ~= 1 then error("ark: selected harness executable is missing: " .. adapter.cmd[1]) end
    health.ok("Saved preference: " .. require("ark.state").describe(selection))
    if vim.fn.filereadable(config.instructions_path) ~= 1 then error("ark: instructions file is unreadable: " .. config.instructions_path) end
    health.ok("Instructions file is readable")
  end)
  if not ok then health.error(tostring(err)) end
  local failure = require("ark.tmux").status().last_failure
  if failure then health.warn("Last transport failure: " .. failure.message) end
  health.info("Use :ArkStatus for the current project, live pane, runtime selection and last error")
end

return M
