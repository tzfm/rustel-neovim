vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.cmd("runtime plugin/rustel.lua")

local api = vim.api
local rustel = require("rustel")
local directory = vim.fn.tempname()
vim.fn.mkdir(directory, "p")
local path = directory .. "/score.strudel"
local log = directory .. "/process.log"
vim.env.RUSTEL_TEST_LOG = log
vim.env.RUSTEL_TEST_TAIL_SECONDS = "1.2"
local messages, jobs, exits, started_after = {}, {}, {}, {}
local restart_after
vim.notify = function(message) messages[#messages + 1] = message end
local jobstart = vim.fn.jobstart
vim.fn.jobstart = function(command, options)
  local on_exit = options.on_exit
  options.on_exit = function(job, code, event)
    exits[job] = code
    if on_exit then on_exit(job, code, event) end
  end
  local job = jobstart(command, options)
  jobs[#jobs + 1] = job
  started_after[job] = restart_after == nil or exits[restart_after] ~= nil
  return job
end
local unrelated = jobstart({ "python3", "-c", "import time; time.sleep(20)" })
assert(unrelated > 0, "could not start unrelated process")

local function wait_for(description, condition, timeout)
  assert(vim.wait(timeout or 3000, condition, 10), "timed out: " .. description)
end

local function recorded(message)
  for _, line in ipairs(vim.fn.filereadable(log) == 1 and vim.fn.readfile(log) or {}) do
    if line == message then return true end
  end
  return false
end

local function alive(job)
  return vim.fn.jobwait({ job }, 0)[1] == -1
end

local function marks(buffer)
  if not api.nvim_buf_is_valid(buffer) then return {} end
  local ns = api.nvim_get_namespaces()["rustel.view"]
  return ns and api.nvim_buf_get_extmarks(buffer, ns, 0, -1, { details = true }) or {}
end

local function visuals(buffer)
  local result = {}
  for _, mark in ipairs(marks(buffer)) do
    if mark[4].virt_lines then
      result[#result + 1] = { mark[2], mark[3], mark[4].virt_lines }
    end
  end
  return result
end

local function frame(buffer)
  wait_for("visual frame", function() return #visuals(buffer) > 0 end)
  return marks(buffer)
end

local function frozen(buffer, expected)
  assert(vim.deep_equal(marks(buffer), expected), "stop changed the frozen visual")
end

local function start()
  local count = #jobs
  rustel.start()
  assert(#jobs == count + 1, "start did not create exactly one process")
  local job = jobs[#jobs]
  local pid = vim.fn.jobpid(job)
  wait_for("process start", function() return recorded("START " .. pid) end)
  return job, pid
end

local function stopped(job, pid)
  wait_for("hard stop", function() return exits[job] ~= nil end, 700)
  assert(exits[job] == 143 and recorded("STOP " .. pid), "hard stop skipped process cleanup")
  assert(recorded("CUT " .. pid), "hard stop waited for the tail")
  assert(alive(unrelated), "stop killed an unrelated process")
end

vim.cmd("edit " .. vim.fn.fnameescape(path))
local buffer = api.nvim_get_current_buf()
api.nvim_buf_set_lines(buffer, 0, -1, false, { 'note("c4").s("sine")' })
rustel.setup({ command = vim.fn.getcwd() .. "/tests/fake-rustel.py", visuals = true, keys = false })

local function check()
  local job, pid = start()
  local last_frame = frame(buffer)
  rustel.stop()
  frozen(buffer, last_frame)
  wait_for("soft stop signal", function() return recorded("SOFT " .. pid) end)
  vim.wait(150, function() return false end, 10)
  assert(alive(job), "first stop cut the tail short")
  frozen(buffer, last_frame)
  wait_for("natural tail exit", function() return exits[job] ~= nil end)
  assert(exits[job] == 143 and recorded("STOP " .. pid), "tail did not exit cleanly after SIGTERM")
  frozen(buffer, last_frame)
  rustel.stop()
  vim.cmd("RustelStop!")
  frozen(buffer, last_frame)
  local drawing = visuals(buffer)
  vim.cmd("RustelVisuals")
  assert(#visuals(buffer) == 0, "toggle did not hide the frozen visual")
  vim.cmd("RustelVisuals")
  assert(vim.deep_equal(visuals(buffer), drawing), "toggle changed the frozen frame")
  assert(#messages == 0, "expected signal exit reported an error")

  job, pid = start()
  last_frame = frame(buffer)
  rustel.stop()
  wait_for("tail acknowledgement", function() return recorded("ACK " .. pid) end)
  vim.wait(30, function() return false end, 10)
  assert(alive(job), "process did not remain alive during the tail")
  frozen(buffer, last_frame)
  rustel.stop()
  stopped(job, pid)
  frozen(buffer, last_frame)

  job, pid = start()
  last_frame = frame(buffer)
  vim.cmd("RustelStop!")
  frozen(buffer, last_frame)
  stopped(job, pid)
  frozen(buffer, last_frame)

  job, pid = start()
  rustel.stop()
  rustel.stop()
  stopped(job, pid)

  job, pid = start()
  rustel.stop()
  wait_for("tail before update", function() return recorded("SOFT " .. pid) end)
  local source = 'note("e4").s("sine")'
  api.nvim_buf_set_lines(buffer, 0, -1, false, { source })
  vim.cmd("enew")
  local other = api.nvim_get_current_buf()
  api.nvim_buf_set_lines(other, 0, -1, false, { "unrelated edit" })
  local count = #jobs
  restart_after = job
  rustel.update()
  assert(#jobs == count, "update overlapped the old and new processes")
  assert(api.nvim_get_current_buf() == other, "update changed the current buffer")
  assert(vim.fn.readfile(path)[1] == source and not vim.bo[buffer].modified,
    "update during a tail did not save the playing buffer")
  assert(vim.bo[other].modified and api.nvim_buf_get_lines(other, 0, -1, false)[1] == "unrelated edit",
    "update touched an unrelated buffer")
  api.nvim_buf_set_lines(buffer, 0, 0, false, { "// still editing" })
  stopped(job, pid)
  wait_for("queued restart", function() return #jobs > count end)
  assert(#jobs == count + 1, "update during a tail did not restart playback once")
  local restarted = jobs[#jobs]
  restart_after = nil
  assert(started_after[restarted], "replacement started before the old process exited")
  wait_for("replacement process start", function()
    return recorded("START " .. vim.fn.jobpid(restarted))
  end)
  assert(alive(restarted), "update did not leave replacement playback running")
  assert(api.nvim_get_current_buf() == other, "queued restart changed the current buffer")
  assert(vim.bo[other].modified, "queued restart saved an unrelated buffer")
  assert(vim.bo[buffer].modified and vim.fn.readfile(path)[1] == source,
    "queued restart saved edits made after update")
  assert(api.nvim_buf_get_lines(buffer, 0, -1, false)[1] == "// still editing",
    "queued restart lost edits made after update")
  api.nvim_set_current_buf(buffer)
  wait_for("saved layout follows pending edits", function()
    local ns = api.nvim_get_namespaces()["rustel.view"]
    local marks = ns and api.nvim_buf_get_extmarks(buffer, ns, 0, -1, { details = true }) or {}
    return #marks == 1 and marks[1][2] == 1 and marks[1][4].virt_lines ~= nil
  end)
  local restarted_pid = vim.fn.jobpid(restarted)
  vim.cmd("RustelStop!")
  stopped(restarted, restarted_pid)

  api.nvim_set_current_buf(buffer)
  job, pid = start()
  rustel.stop()
  count = #jobs
  rustel.update()
  rustel.stop()
  stopped(job, pid)
  vim.wait(100, function() return false end, 10)
  assert(#jobs == count, "explicit stop did not cancel the queued restart")

  api.nvim_buf_set_lines(buffer, 0, -1, false, { "// first", "// second", source })
  job, pid = start()
  rustel.stop()
  local queued_path = directory .. "/queued.strudel"
  local queued = api.nvim_create_buf(true, false)
  api.nvim_buf_set_name(queued, queued_path)
  api.nvim_buf_set_lines(queued, 0, -1, false, { source })
  api.nvim_set_current_buf(queued)
  count = #jobs
  restart_after = job
  rustel.start()
  assert(#jobs == count, "queued buffer started before the old process exited")
  local anchor_ns = api.nvim_get_namespaces()["rustel.anchors"]
  local function queued_anchors()
    return api.nvim_buf_get_extmarks(queued, anchor_ns, 0, -1, { details = true })
  end
  local anchors = queued_anchors()
  assert(#anchors > 0, "queued buffer has no saved anchors")
  api.nvim_set_current_buf(buffer)
  api.nvim_buf_set_lines(buffer, 0, 1, false, { "// saved during the tail" })
  vim.cmd("write")
  vim.cmd("RustelVisuals")
  vim.cmd("RustelVisuals")
  assert(vim.deep_equal(queued_anchors(), anchors), "old buffer save or toggle changed queued anchors")
  api.nvim_buf_set_lines(queued, 0, 0, false, { "// pending edit" })
  stopped(job, pid)
  wait_for("queued buffer restart", function() return #jobs > count end)
  assert(#jobs == count + 1, "queued buffer did not start exactly once")
  restarted = jobs[#jobs]
  restart_after = nil
  assert(started_after[restarted], "queued buffer overlapped the old process")
  wait_for("queued score loaded", function() return recorded("ARG " .. api.nvim_buf_get_name(queued)) end)
  assert(api.nvim_get_current_buf() == buffer, "queued launch changed the current buffer")
  assert(vim.bo[queued].modified and vim.fn.readfile(queued_path)[1] == source,
    "queued launch saved pending edits")
  api.nvim_set_current_buf(queued)
  wait_for("queued anchors follow pending edits", function()
    local panels = visuals(queued)
    return #panels == 1 and panels[1][1] == 1
  end)
  restarted_pid = vim.fn.jobpid(restarted)
  vim.cmd("RustelStop!")
  stopped(restarted, restarted_pid)
  api.nvim_set_current_buf(buffer)
  api.nvim_buf_delete(queued, { force = true })

  vim.env.RUSTEL_TEST_IGNORE_STOP = "1"
  job, pid = start()
  vim.env.RUSTEL_TEST_IGNORE_STOP = nil
  last_frame = frame(buffer)
  local began = (vim.uv or vim.loop).hrtime()
  vim.cmd("RustelStop!")
  wait_for("ignored stop", function() return recorded("IGNORED " .. pid) end)
  wait_for("unresponsive process fallback", function() return exits[job] ~= nil end, 3000)
  local elapsed = ((vim.uv or vim.loop).hrtime() - began) / 1e9
  assert(exits[job] == 137 and not recorded("STOP " .. pid), "fallback did not kill the process")
  assert(elapsed >= 1.8 and elapsed < 3, "fallback did not allow the cleanup deadline")
  frozen(buffer, last_frame)
  rustel.stop()
  frozen(buffer, last_frame)
  assert(alive(unrelated), "stop without playback killed an unrelated process")
  api.nvim_buf_delete(buffer, { force = true })
  assert(#visuals(buffer) == 0, "buffer wipe left a frozen visual")
  vim.cmd("RustelVisuals")
  assert(#visuals(api.nvim_get_current_buf()) == 0, "buffer wipe kept the old frozen frame")
  assert(#messages == 0, "requested stop reported an error")
end

local ok, error = xpcall(check, debug.traceback)
rustel.stop(true)
vim.fn.jobstart = jobstart
for _, job in ipairs(jobs) do
  if alive(job) then vim.fn.jobstop(job) end
end
vim.fn.jobstop(unrelated)
vim.fn.jobwait(jobs, 2000)
vim.fn.jobwait({ unrelated }, 1000)
vim.env.RUSTEL_TEST_TAIL_SECONDS = nil
vim.env.RUSTEL_TEST_IGNORE_STOP = nil
vim.fn.delete(directory, "rf")
assert(ok, error)
print("stop: ok")
vim.cmd("qa!")
