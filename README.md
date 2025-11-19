# jj.nvim

⚠️ **WORK IN PROGRESS** ⚠️

A Neovim plugin for [Jujutsu (jj)](https://github.com/jj-vcs/jj) version control system.

## About

This plugin aims to be something like vim-fugitive but for driving the jj-vcs CLI. The goal is to eventually provide features similar to git status, diffs, and pickers for managing Jujutsu repositories directly from Neovim.

![Demo](https://github.com/NicolasGB/jj.nvim/raw/main/assets/demo.gif)

## Current Features

- Basic jj command execution through `:J` command
- Terminal-based output display for jj commands
- Support jj subcommands including your aliases through the cmdline.
- First class citizens with ui integration
  - `describe` / `desc` - Set change descriptions with a Git-style commit message editor
  - `status` / `st` - Show repository status
  - `log` - Display log history with configurable options
  - `diff` - Show changes
  - `new` - Create a new change
  - `edit` - Edit a change
  - `squash` - Squash the current diff to it's parent
  - `undo` - Undo the last operation
  - `redo` - Redo the last undone operation
- Picker for for [Snacks.nvim](https://github.com/folke/snacks.nvim)
  - `jj status` Displays the current changes diffs
  - `jj file_history` Displays a buffer's history changes and allows to edit it's change (including immutable changes)

## Enhanced integrations

Here are some cool features you can do with jj.nvim

### Diff any change

You can diff any change in your log history by simply pressing `d` on it's line, yeah just like that!
![Diff-from-log](https://github.com/NicolasGB/jj.nvim/raw/main/assets/diff-log.gif)

### Edit mutable changes

Jumping up and down your log history ?

In your log ouptut press `CR` in a line to directly edit a `mutable` change.
![Edit-from-log](https://github.com/NicolasGB/jj.nvim/raw/main/assets/edit-log.gif)

### Create new changes from the log buffer

You can create new changes directly from the log buffer with multiple options:

- `n` - Create a new change branching off the revision under the cursor
- `<C-n>` - Create a new change after the revision under the cursor
- `<S-n>` - Create a new change after while ignoring immutability constraints

### Undo/Redo from the log buffer

You can undo/redo changes directly from the log buffer:

- `u` - Undo the last operation
- `r` - Redo the last undone operation

### Open a changed file

Just press enter to open the a file from the `status` output in your current window.
![Open-status](https://github.com/NicolasGB/jj.nvim/raw/main/assets/enter-status.gif)

### Restore a changed file

Press `X` on a file from the `status` output and that's it, it's restored.

![Restore-status](https://github.com/NicolasGB/jj.nvim/raw/main/assets/x-status.gif)

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "nicolasgb/jj.nvim",
  config = function()
    require("jj").setup({})
  end,
}
```

## Cmdline Usage

The plugin provides a `:J` command that accepts jj subcommands:

```sh
:J status
:J log
:J describe "Your change description"
:J new
:J # This will use your defined default command
:J <your-alias>
```

## Setup config

```lua
{
  -- Setup snacks as a picker
  picker = {
    -- Here you can pass the options as you would for snacks.
    -- It will be used when using the picker
    snacks = {

    }
  },

  -- Choose the editor mode for describe command
  -- "buffer" - Opens a Git-style commit message buffer with syntax highlighting (default)
  -- "input" - Uses a simple vim.ui.input prompt
  describe_editor = "buffer",

  -- Customize syntax highlighting colors for the describe buffer
  highlights = {
    added = { fg = "#3fb950", ctermfg = "Green" },      -- Added files
    modified = { fg = "#56d4dd", ctermfg = "Cyan" },    -- Modified files
    deleted = { fg = "#f85149", ctermfg = "Red" },      -- Deleted files
    renamed = { fg = "#d29922", ctermfg = "Yellow" },   -- Renamed files
  }
}

```

### Describe Editor Modes

The `describe_editor` option lets you choose how you want to write commit descriptions:

- **`"buffer"`** (default) - Opens a full buffer editor similar to Git's commit message editor
  - Shows file changes with syntax highlighting
  - Multi-line editing with proper formatting
  - Close with `q` or `<Esc>`, save with `:w` or `:wq`
- **`"input"`** - Simple single-line input prompt
  - Quick and minimal
  - Good for short, single-line descriptions
  - Uses `vim.ui.input()` which can be customized by UI plugins like dressing.nvim

Example:

```lua
require("jj").setup({
  describe_editor = "input", -- Use simple input mode
})
```

### Highlight Customization

The `highlights` option allows you to customize the colors used in the describe buffer's file status display. Each highlight accepts standard Neovim highlight attributes:

- `fg` - Foreground color (hex or color name)
- `bg` - Background color
- `ctermfg` - Terminal foreground color
- `ctermbg` - Terminal background color
- `bold`, `italic`, `underline` - Text styles

Example with custom colors:

```lua
require("jj").setup({
  highlights = {
    modified = { fg = "#89ddff", bold = true },
    added = { fg = "#c3e88d", ctermfg = "LightGreen" },
  }
})
```

## Example config

```lua
{
  "nicolasgb/jj.nvim",
  dependencies = {
    "folke/snacks.nvim", -- Optional only if you use picker's
  },
  config = function()
    require("jj").setup({
      highlights = {
        -- Customize colors if desired
        modified = { fg = "#89ddff" },
      }
    })

    local cmd = require("jj.cmd")
    vim.keymap.set("n", "<leader>jd", cmd.describe, { desc = "JJ describe" })
    vim.keymap.set("n", "<leader>jl", cmd.log, { desc = "JJ log" })
    vim.keymap.set("n", "<leader>je", cmd.edit, { desc = "JJ edit" })
    vim.keymap.set("n", "<leader>jn", cmd.new, { desc = "JJ new" })
    vim.keymap.set("n", "<leader>js", cmd.status, { desc = "JJ status" })
    vim.keymap.set("n", "<leader>dj", cmd.diff, { desc = "JJ diff" })
    vim.keymap.set("n", "<leader>sj", cmd.squash, { desc = "JJ squash" })
    vim.keymap.set("n", "<leader>ju", cmd.undo, { desc = "JJ undo" })
    vim.keymap.set("n", "<leader>jy", cmd.redo, { desc = "JJ redo" })

    -- Pickers
    local picker = require("jj.picker")
    vim.keymap.set("n", "<leader>gj", picker.status, { desc = "JJ Picker status" })
    vim.keymap.set("n", "<leader>gl", picker.file_history, { desc = "JJ Picker file history" })

    -- Some functions like `describe` or `log` can take parameters
    vim.keymap.set("n", "<leader>jL", function()
      jj.log {
        revisions = "'all()'", -- equivalent to jj log -r ::
      }
    end, { desc = "JJ log all" })

    -- This is an alias i use for moving bookmarks its so good
    vim.keymap.set("n", "<leader>jt", function()
      cmd.j "tug"
      cmd.log {}
    end, { desc = "JJ tug" })
  end,
}

```

## Requirements

- [Jujutsu](https://github.com/jj-vcs/jj) installed and available in PATH

## Contributing

This is an early-stage project. Contributions are welcome, but please be aware that the API and features are likely to change significantly.

## Documentation

Once the plugin is more complete i'll write docs for each of the commands.

## FAQ

- Telescope Suport? Planned but i don't use it, it's already thought of by design, will implement it at some point or if someone submits a PR i'll accept it gladly.

## License

[MIT](License)
