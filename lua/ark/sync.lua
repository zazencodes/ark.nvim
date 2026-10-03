-- Reloads buffers whose files the agent changed on disk. `checktime` with
-- 'autoread' reloads unmodified buffers and warns about modified ones.
local M = {}

local timer

function M.start(interval)
  if timer then
    return
  end
  vim.o.autoread = true
  timer = assert(vim.uv.new_timer())
  timer:start(interval, interval, vim.schedule_wrap(function()
    local mode = vim.api.nvim_get_mode()
    if mode.blocking or mode.mode:sub(1, 1) == "c" or vim.fn.getcmdwintype() ~= "" then
      return
    end
    vim.cmd.checktime()
  end))
end

return M
