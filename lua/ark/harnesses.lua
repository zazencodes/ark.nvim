-- Built-in harness adapters. Each adapter owns everything CLI-specific:
--   cmd                     argv prefix that starts the harness
--   instructions_args(path) args that load the instructions file; when absent,
--                           the instructions are sent as part of the first prompt
--   prompt_flag             flag preceding the initial prompt (default: positional)
--   model_args(model)       args selecting a model
--   effort_args(effort)     args selecting an effort level
--   catalog_args            args appended to `cmd` that print the model catalog;
--                           nil when the catalog is static
--   catalog(stdout)         parses that output (nil for a static catalog) into
--                           { models = { { id, efforts? }, ... }, default_efforts? }
--                           where efforts lists the effort levels to offer for a
--                           model, and default_efforts those for the CLI default
--                           model; nil means no effort choice
local M = {}

local function read_file(path)
  local f = assert(io.open(path, "r"))
  local text = f:read("*a")
  f:close()
  return text
end

local claude_efforts = { "low", "medium", "high", "xhigh", "max" }

M.claude = {
  cmd = { "claude" },
  instructions_args = function(path)
    return { "--append-system-prompt-file", path }
  end,
  model_args = function(model)
    return { "--model", model }
  end,
  effort_args = function(effort)
    return { "--effort", effort }
  end,
  -- Claude Code has no model listing command. These aliases always resolve to
  -- the latest model of each family.
  catalog = function()
    return {
      models = vim.tbl_map(function(id)
        return { id = id, efforts = claude_efforts }
      end, { "fable", "opus", "sonnet", "haiku" }),
      default_efforts = claude_efforts,
    }
  end,
}

M.codex = {
  cmd = { "codex" },
  instructions_args = function(path)
    -- TOML multi-line literal string: no escaping needed.
    return { "-c", "developer_instructions='''" .. read_file(path) .. "'''" }
  end,
  model_args = function(model)
    return { "--model", model }
  end,
  effort_args = function(effort)
    return { "-c", ('model_reasoning_effort="%s"'):format(effort) }
  end,
  catalog_args = { "debug", "models" },
  -- Effort levels are per model, so the CLI default model gets no effort choice.
  catalog = function(stdout)
    local models = {}
    for _, m in ipairs(vim.json.decode(stdout).models) do
      if m.visibility == "list" then
        table.insert(models, {
          id = m.slug,
          efforts = vim.tbl_map(function(level)
            return level.effort
          end, m.supported_reasoning_levels),
        })
      end
    end
    return { models = models }
  end,
}

M.agy = {
  cmd = { "agy" },
  -- agy has no system prompt flag, and only takes an interactive initial
  -- prompt through -i.
  prompt_flag = "-i",
  model_args = function(model)
    return { "--model", model }
  end,
  catalog_args = { "models" },
  -- Model ids include the effort level (e.g. gemini-3.1-pro-high), so there is
  -- no separate effort choice.
  catalog = function(stdout)
    local models = {}
    for line in vim.gsplit(stdout, "\n", { plain = true }) do
      local id = line:match("^(%S+)\t")
      if id then
        table.insert(models, { id = id })
      end
    end
    return { models = models }
  end,
}

local pi_levels = { "off", "minimal", "low", "medium", "high", "xhigh", "max" }

M.pi = {
  cmd = { "pi" },
  instructions_args = function(path)
    return { "--append-system-prompt", path }
  end,
  model_args = function(model)
    return { "--model", model }
  end,
  effort_args = function(effort)
    return { "--thinking", effort }
  end,
  catalog_args = { "--list-models" },
  catalog = function(stdout)
    local models = {}
    local lines = vim.split(stdout, "\n", { trimempty = true })
    for i = 2, #lines do -- line 1 is the header
      local fields = vim.split(vim.trim(lines[i]), "%s+")
      table.insert(models, {
        id = fields[1] .. "/" .. fields[2],
        efforts = fields[5] == "yes" and pi_levels or nil,
      })
    end
    return { models = models, default_efforts = pi_levels }
  end,
}

return M
