-- Notes:
-- Currently running like this lol:
-- LUA_PATH="./?.lua" v lsp-suspender.lua
-- :lua require("lsp-suspender").setup()
-- https://github.com/nvim-neorocks/nvim-best-practices
-- Fetch pid??
-- Use https://github.com/neovim/neovim/issues/14504#issuecomment-833940045
-- vim.lsp config.before_init callback gets initialized_params, can override process_id?
-- https://github.com/neovim/neovim/issues/14430
local M = {}

local augroup = vim.api.nvim_create_augroup("LspSuspender", { clear = true })

local suspended = false;
local stopped_clients = {}
local last_updated = 0;
local timer;

--- @class Config
local default_config = {
  poll_interval = 5,  -- 5 seconds,
  suspend_after = 10, -- 10 seconds
  --suspend_after = 60 * 1, -- 1 minute

  resume_events = {"InsertEnter"} -- More sensitive: {"FocusGained","BufEnter","CursorHold","CursorHoldI"}
}

--- @type Config
local config = nil


local function time()
  return vim.fn.localtime()
end

local function requested(_)
  last_updated = time()

  if suspended then
    M.resume_lsp()
    M.start()
  end
end

local function update()
  local now = time()
  if now - last_updated < config.suspend_after then
    return
  end

  M.suspend_lsp()
  M.stop()

  vim.api.nvim_create_autocmd(config.resume_events, {
    group = augroup,
    once = true,
    callback = function()
      requested()
    end
  })
end

local function list_lsp_processes()
  local ppid = vim.fn.getpid()

  -- Let's find the correspoding processes using pgrep -P $ppid -f "$cmd"
  -- FIXME: This is close, but nix-shell's get wrapped in an rc process so gotta go deeper
  local r = {}
  for _, client in pairs(vim.lsp.get_active_clients()) do
    local full_cmd = table.concat(client.config.cmd, " ")
    local pid = vim.fn.system("pgrep -P " .. ppid .. " -f \"" .. full_cmd .. "\"")
    table.insert(r, { pid = pid, cmd = full_cmd })
  end

  return r
end

function M.status()
  print(vim.inspect({
    suspended = suspended,
    last_updated = (time() - last_updated) .. " seconds ago",
    config = config,
    lsps = list_lsp_processes(),
  }))
end

function M.suspend_lsp()
  suspended = true
  stopped_clients = vim.lsp.get_clients();
  vim.notify("[lsp-suspender] Suspending LSP: " .. #stopped_clients .. " clients")
  for _, client in ipairs(stopped_clients) do
    vim.lsp.stop_client(client)
  end
end

function M.resume_lsp()
  if not suspended then
    vim.notify("[lsp-suspender] Resume skipped, not suspended")
    return
  end

  -- Print how many clients are being resumed
  vim.notify("[lsp-suspender] Resuming LSP: " .. #stopped_clients .. " clients")
  suspended = false

  for _, client in ipairs(stopped_clients) do
    vim.lsp.start_client(client)
  end
end

function M.stop()
  if timer then
    timer:close()
  end
  timer = nil;
end

function M.start()
  last_updated = time()

  if timer then
    M.stop()
  end

  -- Create a timer handle (implementation detail: uv_timer_t).
  timer = vim.uv.new_timer()

  local i = 0
  timer:start(0, config.poll_interval, vim.schedule_wrap(function()
    update()
  end))

  return timer
end

function M.setup(opts)
  if config then
    vim.notify("[lsp-suspender] config is already set", vim.log.levels.WARN)
  end

  -- Merge opts into configs
  config = vim.tbl_deep_extend("force", default_config, opts or {})

  vim.api.nvim_create_autocmd("LspNotify", { group = augroup, callback = requested })

  M.start()
end

return M;
