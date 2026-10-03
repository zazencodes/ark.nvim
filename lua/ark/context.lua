-- Turns the current editor state into the dynamic context sent with each request.
local M = {}

local severity_names = { "ERROR", "WARN", "INFO", "HINT" }

-- range: { start_line, end_line }, 1-based and inclusive.
function M.build(buf, root, range)
  local path = vim.api.nvim_buf_get_name(buf)
  if path == "" then
    error("ark: buffer has no file on disk")
  end
  local file = vim.fs.relpath(root, path) or path

  local lines = {
    "<editor_context>",
    "workspace: " .. root,
    "file: " .. file,
    "filetype: " .. vim.bo[buf].filetype,
  }

  local first, last = range[1], range[2]
  table.insert(lines, ("selection: lines %d-%d"):format(first, last))
  table.insert(lines, "<selection>")
  for i, text in ipairs(vim.api.nvim_buf_get_lines(buf, first - 1, last, true)) do
    table.insert(lines, ("%d: %s"):format(first + i - 1, text))
  end
  table.insert(lines, "</selection>")

  local diagnostics = vim.tbl_filter(function(d)
    return d.lnum + 1 >= first and d.lnum + 1 <= last
  end, vim.diagnostic.get(buf))
  if #diagnostics > 0 then
    table.insert(lines, "diagnostics:")
    for _, d in ipairs(diagnostics) do
      local message = d.message:gsub("\n", " ")
      table.insert(lines, ("- line %d %s: %s"):format(d.lnum + 1, severity_names[d.severity], message))
    end
  end

  table.insert(lines, "</editor_context>")
  return table.concat(lines, "\n")
end

return M
