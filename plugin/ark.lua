if vim.g.loaded_ark then
  return
end
vim.g.loaded_ark = true

vim.api.nvim_create_user_command("ArkEdit", function(opts)
  if opts.range == 0 then
    error("ark: :ArkEdit needs a range (visual selection)")
  end
  require("ark").edit({ opts.line1, opts.line2 })
end, { range = true, desc = "Ask the agent to edit the selected lines" })

vim.api.nvim_create_user_command("ArkChat", function()
  require("ark").chat()
end, { desc = "Open the agent pane, starting it if needed" })

vim.api.nvim_create_user_command("ArkHarness", function()
  require("ark").pick_harness()
end, { desc = "Pick the harness, model, and effort" })
