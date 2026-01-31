-- Luacheck configuration for Neovim plugin
std = "luajit+nvim"

-- Neovim API globals
read_globals = {
  "vim",
}

-- Files to check
files = {
  "lua/",
  "plugin/",
}

-- Exclude patterns
exclude_files = {
  ".luarocks/",
}

-- Don't check for unused arguments (common in callbacks)
unused_args = false

-- Maximum line length
max_line_length = 120
