local M = {}
local namespace = vim.api.nvim_create_namespace("rustel.errors")

vim.diagnostic.config({
  virtual_text = { prefix = "Rustel:" },
  underline = false,
  update_in_insert = true,
}, namespace)

function M.show(buf, message)
  if not vim.api.nvim_buf_is_loaded(buf) then return end
  -- A live error has no source position.
  vim.diagnostic.set(namespace, buf, {
    { lnum = 0, col = 0, message = message, severity = vim.diagnostic.severity.ERROR, source = "Rustel" },
  })
end

function M.clear(buf)
  vim.diagnostic.reset(namespace, buf)
end

return M
