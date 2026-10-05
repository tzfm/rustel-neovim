local M = {}
local api, uv = vim.api, vim.uv or vim.loop
local protocol = require("rustel.protocol")
local errors = require("rustel.errors")
local highlights = require("rustel.highlights")
local state = require("rustel.state")
local view = require("rustel.view")
local config = { command = "rustel", args = {}, visuals = true, keys = true }
local active

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.ERROR, { title = "Rustel" })
end

local function clock()
  return uv.hrtime() / 1e9
end

local function save(buf)
  local ok, error = pcall(api.nvim_buf_call, buf, function() vim.cmd("update") end)
  if not ok then notify(tostring(error)) end
  return ok
end

local function cleanup(session, keep_view)
  if active ~= session then return end
  active = nil
  session.restart = nil
  if session.timer then
    session.timer:stop()
    session.timer:close()
  end
  if session.fallback then
    session.fallback:stop()
    session.fallback:close()
  end
  api.nvim_del_augroup_by_id(session.group)
  highlights.clear(session.buf)
  if not keep_view then view.close() end
end

local function terminate()
  if not active then view.close(); return end
  local session = active
  cleanup(session)
  if session.job then vim.fn.jobstop(session.job) end
end

local function report(session, message, repeat_error)
  if message and (repeat_error or message ~= session.last_error) then
    session.last_error = message
    errors.show(session.buf, message)
    notify(message)
  end
end

local function signal(session, name)
  local ok, pid = pcall(vim.fn.jobpid, session.job)
  return ok and pid > 0 and uv.kill(pid, name) == 0
end

local function cut_tail(session)
  session.hard = true
  if session.draining and not session.cut_short then
    session.cut_short = true
    signal(session, "sigterm")
  end
  if not session.fallback then
    session.fallback = uv.new_timer()
    session.fallback:start(2000, 0, vim.schedule_wrap(function()
      if active == session then signal(session, "sigkill") end
    end))
  end
end

local function receive(session, message)
  if active ~= session then return end
  if type(message.stopping) == "table" then
    session.draining = true
    if session.hard then cut_tail(session) end
  end
  report(session, state.ingest(session.state, message, clock()))
  if type(message.error) == "table" then report(session, message.error.message) end
  if type(message.reload) == "table" then
    local reload = message.reload
    if reload.status == "rejected" then
      report(session, reload.message or "Reload failed; the previous score is still playing.", true)
    elseif reload.status == "installed" and reload.target == "score" then
      session.last_error = nil
      errors.clear(session.buf)
    end
  end
  if type(message.live_error) == "table" and message.live_error.kind ~= "log"
    and message.live_error.kind ~= "sample_loading" then
    report(session, message.live_error.message)
  end
end

local function draw(session)
  if active ~= session or session.stopping then return end
  local buf = session.buf
  if not api.nvim_buf_is_valid(buf) then terminate(); return end
  local tick = api.nvim_buf_get_changedtick(buf)
  local format = vim.bo[buf].fileformat .. tostring(vim.bo[buf].endofline) .. tostring(vim.bo[buf].bomb)
    .. tostring(vim.bo[buf].fixendofline) .. tostring(vim.bo[buf].binary)
  if tick ~= session.tick or format ~= session.format then
    session.snapshot = highlights.snapshot(buf)
    session.tick, session.format = tick, format
  end
  local now = clock()
  local frame = state.tick(session.state, now)
  highlights.draw(buf, session.snapshot, frame.events, now)
  view.draw(frame, now, session.snapshot)
  if vim.fn.getcmdtype() ~= "" then vim.cmd("redraw") end
end

function M.setup(options)
  local version = vim.version()
  if version.major == 0 and version.minor < 9 then
    notify(("Rustel needs Neovim 0.9 or newer (this is %d.%d)."):format(version.major, version.minor))
  end
  config = vim.tbl_extend("force", config, options or {})
  require("rustel.keys").setup(config.keys)
end

local function launch(buf, path)
  local session = {
    buf = buf, path = path, state = state.new(),
    group = api.nvim_create_augroup("rustel-session", { clear = true }),
  }
  active = session
  errors.clear(buf)
  view.open(buf, config.visuals)
  view.remember(highlights.snapshot(buf))
  local stdout = protocol.stream(function(message) receive(session, message) end)
  local stderr = protocol.stream(function(message) receive(session, message) end, function(line)
    session.stderr = line
  end)
  local command = { config.command, path, "--watch", "--ui-events" }
  vim.list_extend(command, config.args)
  local ok, job = pcall(vim.fn.jobstart, command, {
    cwd = vim.fn.fnamemodify(path, ":h"),
    on_stdout = function(_, data) if active == session then stdout(data) end end,
    on_stderr = function(_, data) if active == session then stderr(data) end end,
    on_exit = function(_, code)
      if active ~= session then return end
      stdout({ "", "" }); stderr({ "", "" })
      local restart = session.restart
      if restart and not api.nvim_buf_is_loaded(restart.buf) then restart = nil end
      cleanup(session, session.stopping or restart ~= nil)
      if code ~= 0 and not session.stopping then
        report(session, session.stderr or ("Rustel exited with code " .. code))
      end
      if restart then launch(restart.buf, restart.path) end
    end,
  })
  if not ok or job <= 0 then
    cleanup(session)
    notify("Could not start Rustel: " .. tostring(job)); return
  end
  session.job = job
  api.nvim_set_hl(0, "RustelActive", { default = true, link = "IncSearch" })
  api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = session.group, buffer = buf, callback = terminate,
  })
  api.nvim_create_autocmd("VimLeavePre", {
    group = session.group, callback = terminate,
  })
  api.nvim_create_autocmd("BufWritePost", {
    group = session.group, buffer = buf,
    callback = function()
      if session.stopping and (not session.restart or session.restart.buf ~= buf) then return end
      session.last_error = nil
      view.remember(highlights.snapshot(buf))
    end,
  })
  session.timer = uv.new_timer()
  session.timer:start(0, 33, vim.schedule_wrap(function() draw(session) end))
end

function M.start()
  local buf = api.nvim_get_current_buf()
  local path = api.nvim_buf_get_name(buf)
  if active and not active.stopping and active.buf == buf and active.path == path then M.update(); return end
  if path == "" or vim.bo[buf].buftype ~= "" then
    notify("Open a saved score file first."); return
  end
  local encoding = vim.bo[buf].fileencoding
  if encoding ~= "" and encoding ~= "utf-8" then
    notify("Rustel scores must use UTF-8."); return
  end
  if vim.fn.executable(config.command) ~= 1 then
    notify("Cannot find Rustel: " .. config.command); return
  end
  if not save(buf) then return end
  if active and active.stopping then
    active.restart = { buf = buf, path = path }
    view.open(buf, config.visuals)
    view.remember(highlights.snapshot(buf))
    cut_tail(active)
    return
  end
  terminate()
  launch(buf, path)
end

function M.update()
  if not active then M.start(); return end
  if active.stopping then api.nvim_buf_call(active.buf, M.start); return end
  if api.nvim_buf_get_name(active.buf) ~= active.path then
    api.nvim_buf_call(active.buf, M.start)
    return
  end
  save(active.buf)
end

-- Stop sequence:
--
--   play --stop--> sound finishes (SIGTERM, visuals frozen)
--   sound finishes --stop--> cut (SIGTERM, then SIGKILL after 2 seconds)
--   sound finishes --update--> next score starts after the old process exits
--   that wait --stop--> cancel the next score
function M.stop(immediate)
  if not active then return end
  local session = active
  local hard = immediate or session.stopping
  local first = not session.stopping
  session.restart = nil
  session.stopping = true
  session.timer:stop()
  highlights.clear(session.buf)
  if first then view.freeze() end
  if first and not signal(session, "sigterm") then
    cleanup(session, true)
    vim.fn.jobstop(session.job)
    return
  end
  if hard then cut_tail(session) end
end

function M.visuals()
  local buf = active and (active.restart and active.restart.buf or active.buf) or api.nvim_get_current_buf()
  view.toggle(buf)
  if active then draw(active) end
end

return M
