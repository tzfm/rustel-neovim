if vim.g.loaded_rustel then return end
vim.g.loaded_rustel = true

for name, method in pairs({ Start = "start", Update = "update", Stop = "stop", Visuals = "visuals" }) do
  vim.api.nvim_create_user_command("Rustel" .. name, function(options)
    if method == "stop" then require("rustel").stop(options.bang)
    else require("rustel")[method]() end
  end, { bang = method == "stop" })
end
