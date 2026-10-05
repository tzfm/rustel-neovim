vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.cmd("runtime plugin/rustel.lua")

local rustel = require("rustel")
local directory = vim.fn.tempname()
vim.fn.mkdir(directory, "p")
local path = directory .. "/score.strudel"
local log = directory .. "/process.log"
vim.env.RUSTEL_TEST_LOG = log
local messages = {}
vim.notify = function(message)
  messages[#messages + 1] = message
end
local error_namespace = vim.api.nvim_get_namespaces()["rustel.errors"]

local function error_count()
  return #vim.tbl_filter(function(message) return message == "bad score" end, messages)
end

local function visible_error(buffer)
  local errors = vim.diagnostic.get(buffer, { namespace = error_namespace })
  assert(#errors == 1 and errors[1].message == "bad score", "reload error did not persist")
  local virtual_text = vim.diagnostic.get_namespace(error_namespace).user_data.virt_text_ns
  local marks = virtual_text
    and vim.api.nvim_buf_get_extmarks(buffer, virtual_text, 0, -1, { details = true }) or {}
  assert(#marks > 0 and marks[1][4].virt_text, "reload error is not visible in the buffer")
end

local function wait_for(description, condition)
  assert(vim.wait(3000, condition, 10), "timed out: " .. description)
end

local function records(prefix)
  local count = 0
  for _, line in ipairs(vim.fn.filereadable(log) == 1 and vim.fn.readfile(log) or {}) do
    if line:sub(1, #prefix) == prefix then
      count = count + 1
    end
  end
  return count
end

local function settle(milliseconds)
  vim.wait(milliseconds or 120, function() return false end, 10)
end

local function marks(buffer)
  local namespace = vim.api.nvim_get_namespaces()["rustel-active"]
  return namespace and vim.api.nvim_buf_get_extmarks(buffer, namespace, 0, -1, { details = true }) or {}
end

local function visuals(buffer)
  local namespace = vim.api.nvim_get_namespaces()["rustel.view"]
  local current = namespace and vim.api.nvim_buf_is_valid(buffer)
    and vim.api.nvim_buf_get_extmarks(buffer, namespace, 0, -1, { details = true }) or {}
  return vim.tbl_filter(function(mark) return mark[4].virt_lines and #mark[4].virt_lines > 0 end, current)
end

local function panel(buffer, row)
  local current = visuals(buffer)
  assert(#current == 1, "expected one inline visual")
  assert(current[1][2] == row, "inline visual is on the wrong line")
  return current[1][4].virt_lines
end

local function edit(buffer, first, last, lines)
  vim.api.nvim_buf_set_lines(buffer, first, last, false, lines)
  vim.api.nvim_exec_autocmds("TextChanged", { buffer = buffer })
end

local function replace(buffer, lines)
  edit(buffer, 0, -1, lines)
end

local source = { "// café", 'const title = "é"; note("c4").s("sine")' }
vim.cmd("enew")
local buffer = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_name(buffer, path)
replace(buffer, source)
rustel.setup({ command = vim.fn.getcwd() .. "/tests/fake-rustel.py", visuals = true })

local function check()
  for _, name in ipairs({ "RustelStart", "RustelUpdate", "RustelStop", "RustelVisuals" }) do
    assert(vim.fn.exists(":" .. name) == 2, name .. " command missing")
  end
  rustel.start()
  assert(vim.fn.readfile(path)[2] == source[2], "start did not save the source")
  wait_for("first accepted source", function() return records("ACCEPT") == 1 end)
  assert(records("ARG --watch") == 1 and records("ARG --ui-events") == 1, "missing live playback flags")
  assert(records("ARG --no-save-session") == 0, "session recording disabled by default")
  assert(#marks(buffer) == 0, "stale revision or future onset highlighted early")
  wait_for("active UTF-8 ranges", function() return #marks(buffer) == 2 end)
  local expected = {}
  for _, token in ipairs({ "é", "c4" }) do
    local start = assert(source[2]:find(token, 1, true)) - 1
    expected[start] = start + #token
  end
  for _, mark in ipairs(marks(buffer)) do
    assert(mark[2] == 1 and expected[mark[3]] == mark[4].end_col, "wrong UTF-8 byte range")
    assert(mark[4].end_row == 1, "wrong highlight end row")
  end
  wait_for("inline visuals", function() return #visuals(buffer) > 0 end)
  assert(#vim.api.nvim_list_wins() == 1, "inline visuals opened another window")
  assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), source), "visuals changed the score")
  assert(not vim.bo[buffer].modified, "visuals marked the score modified")

  vim.api.nvim_set_current_buf(buffer)
  rustel.start()
  settle()
  assert(records("START") == 1, "starting the same buffer spawned another process")
  edit(buffer, 0, 1, { "// changed" })
  settle()
  assert(#marks(buffer) == 0, "dirty source kept stale highlights")
  local drawing = panel(buffer, 1)
  wait_for("dirty visuals keep animating", function()
    local current = visuals(buffer)
    return #current == 1 and not vim.deep_equal(current[1][4].virt_lines, drawing)
  end)
  edit(buffer, 1, 1, { "// inserted" })
  settle()
  panel(buffer, 2)
  assert(#marks(buffer) == 0, "inserted line kept stale highlights")
  edit(buffer, 1, 2, {})
  settle()
  panel(buffer, 1)
  assert(#marks(buffer) == 0, "deleted line kept stale highlights")
  assert(records("ACCEPT") == 1, "unsaved edits reloaded playback")
  edit(buffer, 0, 1, { source[1] })
  wait_for("restored source highlights", function() return #marks(buffer) == 2 end)

  edit(buffer, 0, 1, { "// BAD" })
  rustel.update()
  wait_for("rejected reload", function() return records("REJECT") == 1 end)
  settle()
  assert(#marks(buffer) == 0, "rejected source kept stale highlights")
  panel(buffer, 1)
  assert(error_count() == 1, "reload error was not reported once")
  visible_error(buffer)
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  vim.api.nvim_exec_autocmds("CursorMoved", { buffer = buffer })
  vim.cmd("redraw")
  settle()
  visible_error(buffer)
  edit(buffer, 0, 1, { "// BAD again" })
  rustel.update()
  wait_for("repeated rejected reload", function() return records("REJECT") == 2 end)
  assert(error_count() == 2, "identical reload error was suppressed")
  visible_error(buffer)
  local other_namespace = vim.api.nvim_create_namespace("test.other")
  vim.diagnostic.set(other_namespace, buffer, { { lnum = 0, col = 0, message = "other diagnostic" } })
  local other_buffer = vim.api.nvim_create_buf(false, true)
  vim.diagnostic.set(error_namespace, other_buffer, { { lnum = 0, col = 0, message = "other score" } })
  edit(buffer, 0, 1, { "// accepted again" })
  edit(buffer, 2, 2, { ".gain(0.5)" })
  settle()
  panel(buffer, 1)
  assert(#marks(buffer) == 0, "pending reload kept stale highlights")
  rustel.update()
  edit(buffer, 0, 0, { "// typing after save" })
  wait_for("accepted reload", function() return records("ACCEPT") == 2 end)
  assert(#vim.diagnostic.get(buffer, { namespace = error_namespace }) == 0, "accepted reload kept the error")
  assert(#vim.diagnostic.get(buffer, { namespace = other_namespace }) == 1, "cleared another diagnostic source")
  assert(#vim.diagnostic.get(other_buffer, { namespace = error_namespace }) == 1, "cleared another buffer's error")
  vim.diagnostic.reset(other_namespace, buffer)
  vim.api.nvim_buf_delete(other_buffer, { force = true })
  assert(#marks(buffer) == 0, "new generation highlighted before its onset")
  wait_for("accepted reload reanchors visuals", function()
    local current = visuals(buffer)
    return #current == 1 and current[1][2] == 3
  end)
  settle(400)
  assert(#marks(buffer) == 0, "editing after save kept stale highlights")
  assert(vim.bo[buffer].modified, "accepted reload lost edits made after saving")
  edit(buffer, 0, 1, {})
  wait_for("new generation highlights", function() return #marks(buffer) == 2 end)
  panel(buffer, 2)

  edit(buffer, 0, 1, { "// BAD after recovery" })
  rustel.update()
  wait_for("error after recovery", function() return records("REJECT") == 3 end)
  assert(error_count() == 3, "identical error after recovery was suppressed")
  visible_error(buffer)
  edit(buffer, 0, 1, { "// accepted again" })
  rustel.update()
  wait_for("recovery after repeated error", function() return records("ACCEPT") == 3 end)
  assert(#vim.diagnostic.get(buffer, { namespace = error_namespace }) == 0, "recovery kept the error")

  rustel.stop()
  wait_for("process stop", function() return records("STOP") == 1 end)
  assert(#marks(buffer) == 0, "stop left highlights behind")
  panel(buffer, 2)
  assert(#vim.api.nvim_list_wins() == 1, "stop changed the editor windows")
  rustel.setup({ args = { "--no-save-session" } })
  rustel.start()
  wait_for("restart", function() return records("START") == 2 end)
  assert(records("ARG --no-save-session") == 1, "configured session recording opt-out was not passed")
  wait_for("restart highlights", function() return #marks(buffer) == 2 end)
  vim.api.nvim_buf_delete(buffer, { force = true })
  wait_for("buffer deletion stops playback", function() return records("STOP") == 2 end)
  assert(#vim.api.nvim_list_wins() == 1, "buffer deletion left an extra window")

  vim.cmd("edit " .. vim.fn.fnameescape(path))
  rustel.setup({ visuals = false })
  rustel.start()
  wait_for("third start", function() return records("START") == 3 end)
  buffer = vim.api.nvim_get_current_buf()
  assert(#visuals(buffer) == 0, "visuals=false added inline drawings")
  vim.cmd("RustelVisuals")
  wait_for("RustelVisuals shows drawings", function() return #visuals(buffer) > 0 end)
  vim.cmd("RustelVisuals")
  assert(#visuals(buffer) == 0, "RustelVisuals did not hide the drawings")
  vim.api.nvim_exec_autocmds("VimLeavePre", {})
  wait_for("editor exit stops playback", function() return records("STOP") == 3 end)

  rustel.start()
  wait_for("start before renaming", function() return records("START") == 4 end)
  for index, action in ipairs({ rustel.update, rustel.start }) do
    vim.cmd("saveas " .. vim.fn.fnameescape(directory .. "/renamed-" .. index .. ".strudel"))
    replace(vim.api.nvim_get_current_buf(), { "// renamed " .. index, source[2] })
    action()
    wait_for("renamed file starts playback", function() return records("START") == 4 + index end)
    wait_for("old file stops playback", function() return records("STOP") == 3 + index end)
    wait_for("renamed source highlights", function() return #marks(vim.api.nvim_get_current_buf()) == 2 end)
  end
  rustel.stop()
  wait_for("renamed file stops playback", function() return records("STOP") == 6 end)

  rustel.setup({ command = directory .. "/missing-rustel", visuals = false })
  local before = #messages
  local ok, error = pcall(rustel.start)
  assert(ok, "missing executable threw: " .. tostring(error))
  assert(#messages > before, "missing executable was not reported")
  assert(records("START") == 6, "missing executable started a process")
end

local ok, error = xpcall(check, debug.traceback)
rustel.stop()
vim.wait(1000, function() return records("START") == records("STOP") end, 10)
vim.fn.delete(directory, "rf")
if not ok then
  io.stderr:write(error .. "\n")
  vim.cmd("cquit 1")
end
print("live: ok")
vim.cmd("qa!")
