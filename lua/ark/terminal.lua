-- The terminal is only a viewer attached to a persistent tmux session.
-- Hiding or deleting it never sends an interrupt to the agent.
local M = {}
local current

local function geometry()
  local opts = require("ark.config").options.window
  local width = math.max(1, math.min(vim.o.columns - 2, math.floor(vim.o.columns * opts.width)))
  local height = math.max(1, math.min(vim.o.lines - 4, math.floor(vim.o.lines * opts.height)))
  return { relative = "editor", width = width, height = height,
    row = math.max(0, math.floor((vim.o.lines - height - 2) / 2)),
    col = math.max(0, math.floor((vim.o.columns - width - 2) / 2)),
    style = "minimal", border = "rounded", title = " Ark · Ctrl-C hides ", title_pos = "center" }
end

function M.hide()
  local focused = current and current.win == vim.api.nvim_get_current_win()
  if current and current.win and vim.api.nvim_win_is_valid(current.win) then
    vim.api.nvim_win_close(current.win, true)
  end
  if current then current.win = nil end
  if focused then vim.cmd.stopinsert() end
end

function M.open(pane, socket, session)
  if current and (current.pane ~= pane or not vim.api.nvim_buf_is_valid(current.buf)) then
    M.hide()
    if vim.api.nvim_buf_is_valid(current.buf) then vim.api.nvim_buf_delete(current.buf, { force = true }) end
    current = nil
  end
  if current then
    if current.win and vim.api.nvim_win_is_valid(current.win) then
      vim.api.nvim_set_current_win(current.win)
    else
      current.win = vim.api.nvim_open_win(current.buf, true, geometry())
    end
    vim.cmd.startinsert()
    return
  end
  local entry = { pane = pane, root = vim.fn.getcwd(), buf = vim.api.nvim_create_buf(false, true) }
  current = entry
  vim.bo[entry.buf].bufhidden = "hide"
  vim.api.nvim_create_autocmd("BufWipeout", { buffer = entry.buf, once = true, callback = function()
    -- Deleting a terminal stops its client job deliberately. Its exit callback
    -- must neither report that as a failure nor close a newer viewer.
    if current == entry then current = nil end
  end })
  entry.win = vim.api.nvim_open_win(entry.buf, true, geometry())
  vim.keymap.set({ "n", "t" }, "<C-c>", M.hide, { buffer = entry.buf, silent = true, desc = "ark: hide agent" })
  vim.keymap.set("n", "q", M.hide, { buffer = entry.buf, silent = true, desc = "ark: hide agent" })
  local job = vim.fn.jobstart({ "tmux", "-S", socket, "attach-session", "-t", session }, {
    term = true, env = { TMUX = "", TMUX_PANE = "" },
    on_exit = function(_, code)
      vim.schedule(function()
        if current ~= entry then return end
        M.hide()
        current = nil
        if vim.api.nvim_buf_is_valid(entry.buf) then vim.api.nvim_buf_delete(entry.buf, { force = true }) end
        if code ~= 0 then
          local err = "ark: agent viewer exited with code " .. code .. "; inspect :ArkStatus"
          require("ark.status").record(entry.root, err)
          error(err)
        end
      end)
    end,
  })
  if job <= 0 then
    M.hide()
    current = nil
    vim.api.nvim_buf_delete(entry.buf, { force = true })
    error("ark: could not attach agent terminal")
  end
  vim.cmd.startinsert()
end

local group = vim.api.nvim_create_augroup("ArkTerminal", { clear = true })
vim.api.nvim_create_autocmd("VimResized", { group = group, callback = function()
  if current and current.win and vim.api.nvim_win_is_valid(current.win) then
    vim.api.nvim_win_set_config(current.win, geometry())
  end
end })

return M
