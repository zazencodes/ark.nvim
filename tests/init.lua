vim.opt.rtp:prepend(vim.env.ARK_TEST_ROOT)
vim.opt.rtp:append(vim.env.ARK_TEST_DIR .. "/telescope.nvim")
vim.opt.rtp:append(vim.env.ARK_TEST_DIR .. "/plenary.nvim")
vim.o.swapfile = false
local adapters = {}
for _, name in ipairs({ "claude", "codex", "agy", "pi" }) do
  adapters[name] = { cmd = { vim.env.ARK_TEST_PYTHON, vim.env.ARK_TEST_ROOT .. "/tests/fake_agent.py", name } }
end
require("ark").setup({ harnesses = adapters, checktime_interval = 50 })
vim.ui.input = function(_, callback)
  callback(vim.g.ark_test_request)
end
