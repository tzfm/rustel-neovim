vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.cmd("filetype plugin on")

local rustel = require("rustel")
local calls = {}
rustel.update = function() calls[#calls + 1] = { "update", vim.fn.mode() } end
rustel.stop = function() calls[#calls + 1] = { "stop", vim.fn.mode() } end
local bindings = { ["<C-CR>"] = "update", ["<C-s>"] = "update", ["<C-g>"] = "stop", ["<C-.>"] = "stop" }

local function mapping(mode, key)
  return vim.fn.maparg(key, mode, false, true)
end

local function press(mode, key)
  local input = mode == "i" and "i" .. key .. "<Esc>" or key
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(input, true, false, true), "xt", false)
end

local function defaults_absent()
  for _, mode in ipairs({ "n", "i" }) do
    for key in pairs(bindings) do
      assert(mapping(mode, key).buffer ~= 1, "unexpected binding: " .. mode .. " " .. key)
    end
  end
end

vim.cmd("enew")
vim.bo.filetype = "text"
defaults_absent()
vim.cmd("edit " .. vim.fn.fnameescape(vim.fn.tempname() .. ".strudel"))
assert(vim.bo.filetype == "rustel", "score filetype was not detected")
for _, mode in ipairs({ "n", "i" }) do
  for key, action in pairs(bindings) do
    assert(mapping(mode, key).buffer == 1, "missing buffer binding: " .. mode .. " " .. key)
    local before = #calls
    press(mode, key)
    assert(#calls == before + 1, "key did not dispatch: " .. mode .. " " .. key)
    assert(calls[#calls][1] == action and calls[#calls][2] == mode, "wrong action or editor mode")
    assert(mapping("x", key).buffer ~= 1, "visual-mode binding was added")
  end
end
for _, mode in ipairs({ "n", "i" }) do
  assert(mapping(mode, "<D-s>").buffer ~= 1 and mapping(mode, "<D-g>").buffer ~= 1, "Command defaults were added")
end

local custom = 0
local function user_binding() custom = custom + 1 end
local user_keys = { "<C-s>", "<D-s>", "<D-g>" }
for _, key in ipairs(user_keys) do
  vim.keymap.set("n", key, user_binding, { buffer = true })
end
rustel.setup({ keys = false })
for key, action in pairs(bindings) do
  assert(mapping("i", key).buffer ~= 1, "keys=false kept an insert binding")
  if action == "stop" then assert(mapping("n", key).buffer ~= 1, "keys=false kept a stop binding") end
end
for _, key in ipairs(user_keys) do
  assert(mapping("n", key).callback == user_binding, "disabling keys removed a user override")
  press("n", key)
end
assert(custom == #user_keys, "user override stopped working")
rustel.setup({ keys = true })
for _, key in ipairs(user_keys) do
  assert(mapping("n", key).callback == user_binding, "enabling keys overwrote a user override")
end
assert(mapping("i", "<C-s>").buffer == 1, "enabling keys did not attach to an open score")
assert(mapping("i", "<D-s>").buffer ~= 1 and mapping("i", "<D-g>").buffer ~= 1, "enabling keys added Command defaults")

vim.cmd("enew!")
local insert_keys = { "<C-g>", "<D-s>", "<D-g>" }
vim.keymap.set("n", "<C-CR>", user_binding, { buffer = true })
for _, key in ipairs(insert_keys) do
  vim.keymap.set("i", key, user_binding, { buffer = true })
end
vim.bo.filetype = "rustel"
assert(mapping("n", "<C-CR>").callback == user_binding, "filetype overwrote an existing normal binding")
for _, key in ipairs(insert_keys) do
  assert(mapping("i", key).callback == user_binding, "filetype overwrote an existing insert binding")
end
assert(mapping("n", "<C-s>").buffer == 1, "other defaults were not installed")
vim.bo.filetype = "text"
assert(mapping("n", "<C-s>").buffer ~= 1, "filetype change kept Rustel bindings")
assert(mapping("n", "<C-CR>").callback == user_binding, "filetype cleanup removed a user binding")
for _, key in ipairs(insert_keys) do
  assert(mapping("i", key).callback == user_binding, "filetype cleanup removed a user binding")
end

rustel.setup({ keys = false })
vim.cmd("enew!")
vim.bo.filetype = "rustel"
defaults_absent()
print("keys: ok")
vim.cmd("qa!")
