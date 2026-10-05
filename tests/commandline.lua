local directory = vim.fn.tempname()
vim.fn.mkdir(directory, "p")

local script = [[
vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.o.lines, vim.o.columns, vim.o.laststatus = 24, 80, 0
vim.o.incsearch = true
local api = vim.api
local rustel = require("rustel")
vim.cmd("edit " .. vim.fn.fnameescape(vim.env.RUSTEL_TEST_DIRECTORY .. "/score.strudel"))
api.nvim_buf_set_lines(0, 0, -1, false, { 'note("c4").s("sine")', "" })
rustel.setup({ command = vim.fn.getcwd() .. "/tests/fake-rustel.py" })
rustel.start()
assert(vim.wait(3000, function()
  local namespace = api.nvim_get_namespaces()["rustel.view"]
  return namespace and #api.nvim_buf_get_extmarks(0, namespace, 0, -1, {}) > 0
end, 10), "inline visuals did not appear")

local function snapshot()
  local cells = {}
  for row = 2, 8 do
    for column = 1, 80 do cells[#cells + 1] = vim.fn.screenstring(row, column) end
  end
  return {
    picture = table.concat(cells), command = vim.fn.getcmdline(), position = vim.fn.getcmdpos(),
    cursor = { vim.fn.screenrow(), vim.fn.screencol() }, buffer_cursor = api.nvim_win_get_cursor(0),
  }
end

local function later(delay, callback)
  vim.defer_fn(function()
    local ok, error = xpcall(callback, debug.traceback)
    if not ok then
      rustel.stop()
      io.stderr:write(error .. "\n")
      vim.cmd("cquit 1")
    end
  end, delay)
end

local cases = {
  { keys = ':echo "kept"<Left><Left>', kind = ":", command = 'echo "kept"', position = 10 },
  { keys = "/sine<Left>", kind = "/", command = "sine", position = 4 },
}
local function check(index)
  local case = cases[index]
  if not case then rustel.stop(); vim.cmd("qa!"); return end
  api.nvim_input(case.keys)
  later(100, function()
    local before = snapshot()
    assert(vim.fn.getcmdtype() == case.kind, "command input did not open")
    assert(before.command == case.command and before.position == case.position, "command input changed")
    assert(before.picture:find("pianoroll", 1, true), "inline panel is not visible")
    later(350, function()
      local after = snapshot()
      assert(vim.fn.getcmdtype() == case.kind, "redraw closed command input")
      assert(after.picture ~= before.picture, case.kind .. " froze the visible animation")
      assert(after.command == before.command and after.position == before.position, "redraw changed command input")
      assert(vim.deep_equal(after.cursor, before.cursor), "redraw moved the command cursor")
      assert(vim.deep_equal(after.buffer_cursor, before.buffer_cursor), "redraw moved the buffer cursor")
      api.nvim_input("<C-C>")
      later(100, function() check(index + 1) end)
    end)
  end)
end
later(100, function() check(1) end)
]]

local function check()
  local path = directory .. "/test.lua"
  vim.fn.writefile(vim.split(script, "\n", { plain = true }), path)
  local run = dofile("tests/support/run.lua")
  local result = run({ vim.v.progpath, "--headless", "-u", "NONE", "-i", "NONE", "-n",
    "-c", "lua local ok, err = pcall(dofile, vim.env.RUSTEL_TEST_DIRECTORY .. '/test.lua'); "
      .. "if not ok then print(err); vim.cmd('cquit 1') end",
  }, {
    RUSTEL_TEST_DIRECTORY = directory,
    RUSTEL_TEST_LOG = directory .. "/process.log",
    NVIM_LOG_FILE = directory .. "/nvim.log",
  }, 6000)
  local stopped = vim.wait(1000, function()
    local log = directory .. "/process.log"
    return vim.fn.filereadable(log) == 1
      and table.concat(vim.fn.readfile(log), "\n"):find("\nSTOP ", 1, true)
  end, 10)
  assert(result.code == 0, result.stderr or result.stdout or "subprocess failed")
  assert(stopped, "engine remained running after exit")
end

local ok, error = xpcall(check, debug.traceback)
vim.fn.delete(directory, "rf")
assert(ok, error)
print("commandline: ok")
