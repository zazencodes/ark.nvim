-- The harness selection (harness, model, effort), persisted across Neovim
-- sessions. A nil model or effort means the harness CLI's own default.
local M = {}

local path = vim.fn.stdpath("state") .. "/ark.json"

function M.load()
  if vim.fn.filereadable(path) == 0 then
    return { harness = "claude" }
  end
  return vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
end

function M.save(selection)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  assert(vim.fn.writefile({ vim.json.encode(selection) }, path) == 0)
end

function M.describe(selection)
  return ("%s · %s · %s"):format(selection.harness, selection.model or "default model", selection.effort or "default effort")
end

return M
