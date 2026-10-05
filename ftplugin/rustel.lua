if vim.b.did_ftplugin then
  return
end
vim.b.did_ftplugin = true

vim.bo.commentstring = "// %s"
vim.bo.comments = "s1:/*,mb:*,ex:*/,://"
require("rustel.keys").attach(0)
vim.b.undo_ftplugin = "setlocal commentstring< comments< | lua require('rustel.keys').detach(0)"
