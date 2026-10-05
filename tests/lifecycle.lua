local directory = vim.fn.tempname()
vim.fn.mkdir(directory, "p")

local setup = [[
vim.opt.runtimepath:prepend(vim.fn.getcwd())
local api = vim.api
local rustel = require("rustel")
local directory = vim.env.RUSTEL_TEST_DIRECTORY
local log = directory .. "/process.log"
local function records(prefix)
  local count = 0
  for _, line in ipairs(vim.fn.filereadable(log) == 1 and vim.fn.readfile(log) or {}) do
    if line:sub(1, #prefix) == prefix then count = count + 1 end
  end
  return count
end
vim.cmd("edit " .. vim.fn.fnameescape(directory .. "/score.strudel"))
api.nvim_buf_set_lines(0, 0, -1, false, { 'note("c4").s("sine")' })
local score = api.nvim_get_current_win()
rustel.setup({ command = vim.fn.getcwd() .. "/tests/fake-rustel.py" })
rustel.start()
assert(vim.wait(3000, function() return records("ACCEPT") == 1 end, 10), "engine did not start")
assert(#api.nvim_list_wins() == 1, "inline visuals opened an extra window")
local function visuals()
  local namespace = api.nvim_get_namespaces()["rustel.view"]
  return namespace and api.nvim_buf_get_extmarks(api.nvim_win_get_buf(score), namespace, 0, -1, {}) or {}
end
assert(vim.wait(1000, function() return #visuals() > 0 end, 10), "inline visuals did not appear")
]]

local cases = {
  quit = [[
vim.cmd("quit")
error("one quit did not exit")
]],
  cancelled = [[
api.nvim_buf_set_lines(0, 0, -1, false, { 'note("d4").s("sine")' })
local ok = pcall(vim.cmd, "quit")
assert(not ok, "quit discarded unsaved score changes")
assert(#api.nvim_list_wins() == 1, "cancelled quit changed the windows")
assert(api.nvim_get_current_win() == score and vim.bo.modified, "cancelled quit lost the score")
vim.wait(100, function() return false end, 10)
assert(records("STOP") == 0, "cancelled quit stopped playback")
vim.cmd("quit!")
error("forced quit did not exit")
]],
  split = [[
vim.cmd("vnew")
local other = api.nvim_get_current_win()
api.nvim_set_current_win(score)
vim.cmd("quit")
assert(api.nvim_win_is_valid(other), "quit closed another editor window")
vim.wait(100, function() return false end, 10)
assert(records("STOP") == 0, "quit stopped playback while another editor remained")
api.nvim_set_current_win(other)
vim.cmd("quit")
error("quitting the final editor did not exit")
]],
  tab = [[
vim.cmd("tabnew")
local other = api.nvim_get_current_win()
api.nvim_set_current_win(score)
vim.cmd("quit")
assert(api.nvim_win_is_valid(other), "quit closed an unrelated tab")
vim.wait(100, function() return false end, 10)
assert(records("STOP") == 0, "quit stopped playback while another tab remained")
api.nvim_set_current_win(other)
vim.cmd("quit")
error("quitting the final editor tab did not exit")
]],
  toggle = [[
rustel.visuals()
assert(#visuals() == 0, "hiding visuals left inline drawings")
vim.wait(100, function() return false end, 10)
assert(#visuals() == 0, "hidden visuals reappeared")
assert(records("STOP") == 0, "hiding visuals stopped playback")
rustel.visuals()
assert(#visuals() > 0, "showing visuals did not restore the drawings")
assert(#api.nvim_list_wins() == 1, "showing visuals opened another window")
vim.cmd("quit")
error("quit after toggling visuals did not exit")
]],
}

local function check()
  local run = dofile("tests/support/run.lua")
  for name, body in pairs(cases) do
    local path = directory .. "/" .. name
    vim.fn.mkdir(path, "p")
    local script = path .. "/test.lua"
    vim.fn.writefile(vim.split(setup .. body, "\n", { plain = true }), script)
    local result = run({ vim.v.progpath, "--headless", "-u", "NONE", "-i", "NONE", "-n", "-l", script }, {
      RUSTEL_TEST_DIRECTORY = path,
      RUSTEL_TEST_LOG = path .. "/process.log",
      NVIM_LOG_FILE = path .. "/nvim.log",
    }, 5000)
    assert(result.code == 0, name .. ": " .. (result.stderr or result.stdout or "subprocess failed"))
    assert(vim.wait(1000, function()
      for _, line in ipairs(vim.fn.readfile(path .. "/process.log")) do
        if line:match("^STOP ") then return true end
      end
      return false
    end, 10), name .. ": engine remained running after exit")
  end
end

local ok, error = xpcall(check, debug.traceback)
vim.fn.delete(directory, "rf")
assert(ok, error)
print("lifecycle: ok")
