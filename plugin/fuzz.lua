if vim.g.loaded_fuzz then
  return
end
vim.g.loaded_fuzz = true

vim.api.nvim_create_user_command("Fuzz", function()
  require("fuzz").open()
end, { desc = "Open Git Branch Switcher" })
