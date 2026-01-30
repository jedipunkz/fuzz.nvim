# fuzz.nvim

A simple Neovim plugin for quickly switching and creating git branches with fuzzy finding.

## Features

- Display current branch name in a popup window
- Fuzzy find local branches as you type
- Automatically detect if branch exists:
  - Existing branch → `git switch <branch>`
  - New branch → `git switch -c <branch>`

## Requirements

- Neovim >= 0.8
- Git

## Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "thirai/fuzz.nvim",
  config = function()
    require("fuzz").setup()
  end,
}
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "thirai/fuzz.nvim",
  config = function()
    require("fuzz").setup()
  end,
}
```

## Configuration

```lua
require("fuzz").setup({
  keymap = "<C-'>",      -- keymap to open the branch switcher
  pull_keymap = "<C-r>", -- keymap to git pull (in popup)
  push_keymap = "<C-y>", -- keymap to git push (in popup)
})
```

## Usage

1. Press `Ctrl+'` (or your configured keymap) in a git repository
2. The current branch name appears in the input field
3. Edit the name - matching branches are shown below with fuzzy filtering
4. Press `Enter` to switch/create the branch

### Keybindings (in popup)

| Key | Action |
|-----|--------|
| `Enter` | Switch to / create branch |
| `Esc` | Cancel |
| `Ctrl-n` | Select next candidate |
| `Ctrl-p` | Select previous candidate |
| `Tab` | Autocomplete with selected candidate |
| `Ctrl-r` | Git pull from origin (opens terminal for passphrase input) |
| `Ctrl-y` | Git push to origin (opens terminal for passphrase input) |

### Command

You can also use the `:Fuzz` command to open the branch switcher.

## License

MIT
