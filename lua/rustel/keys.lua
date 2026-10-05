local M = {}
local api = vim.api
local enabled = true
local function update() require("rustel").update() end
local function stop() require("rustel").stop() end
local bindings = {
  { "<C-CR>", update, "Save and update Rustel" },
  { "<C-s>", update, "Save and update Rustel" },
  { "<C-g>", stop, "Stop Rustel" },
  { "<C-.>", stop, "Stop Rustel" },
}

function M.attach(buf)
  if not enabled or vim.bo[buf].filetype ~= "rustel" then return end
  api.nvim_buf_call(buf, function()
    for _, mode in ipairs({ "n", "i" }) do
      for _, binding in ipairs(bindings) do
        if vim.fn.maparg(binding[1], mode, false, true).buffer ~= 1 then
          vim.keymap.set(mode, binding[1], binding[2], { buffer = buf, desc = binding[3] })
        end
      end
    end
  end)
end

function M.detach(buf)
  api.nvim_buf_call(buf, function()
    for _, mode in ipairs({ "n", "i" }) do
      for _, binding in ipairs(bindings) do
        local mapping = vim.fn.maparg(binding[1], mode, false, true)
        if mapping.buffer == 1 and mapping.callback == binding[2] then
          vim.keymap.del(mode, binding[1], { buffer = buf })
        end
      end
    end
  end)
end

function M.setup(value)
  enabled = value ~= false
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == "rustel" then
      if enabled then M.attach(buf) else M.detach(buf) end
    end
  end
end

return M
