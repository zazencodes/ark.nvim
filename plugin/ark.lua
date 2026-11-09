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
end, { desc = "Open the agent window, starting it if needed" })

vim.api.nvim_create_user_command("ArkHarness", function(opts)
  require("ark").pick_harness(opts.bang)
end, { bang = true, desc = "Pick harness, model, effort (! refreshes its catalog)" })

vim.api.nvim_create_user_command("ArkStatus", function()
  require("ark").status()
end, { desc = "Show project, pane, runtime selection, preference and last error" })

vim.api.nvim_create_user_command("ArkReview", function()
  require("ark.review").open()
end, { desc = "Compare preserved editor and disk versions" })

vim.api.nvim_create_user_command("ArkResolve", function(opts)
  require("ark.review").resolve(opts.args)
end, { nargs = 1, complete = function() return { "disk", "buffer" } end, desc = "Resolve a disk conflict using disk or buffer after confirmation" })
