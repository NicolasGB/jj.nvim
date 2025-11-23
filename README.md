# jj.nvim

⚠️ **WORK IN PROGRESS** ⚠️

> **Note:** This project is pre-v1. Breaking changes may occur in the configuration, API, and features until v1.0.0 is released.

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
  - `diff` - Show changes with optional filtering by current file
  - `new` - Create a new change with optional parent selection
  - `edit` - Edit a change
  - `squash` - Squash the current diff to it's parent
  - `rebase` - Rebase changes to a destination
  - `bookmark create/delete` - Create and delete bookmarks
  - `undo` - Undo the last operation
  - `redo` - Redo the last undone operation
- Diff commands
  - `:Jdiff [revision]` - Vertical split diff against a jj revision
  - `:Jhdiff [revision]` - Horizontal split diff
- Picker for for [Snacks.nvim](https://github.com/folke/snacks.nvim)
  - `jj status` Displays the current changes diffs
  - `jj file_history` Displays a buffer's history changes and allows to edit it's change (including immutable changes)

## Enhanced integrations

Here are some cool features you can do with jj.nvim:

### Diff any change

You can diff any change in your log history by simply pressing `d` on its line, yeah just like that!
![Diff-from-log](https://github.com/NicolasGB/jj.nvim/raw/main/assets/diff-log.gif)

### Edit changes

Jumping up and down your log history ?

In your log ouptut press `CR` in a line to directly edit a `mutable` change.
If you are sure what your are doing press `S-CR` (Shift Enter) to edit a `immutable` change.
![Edit-from-log](https://github.com/NicolasGB/jj.nvim/raw/main/assets/edit-log.gif)

### Create new changes from the log buffer

You can create new changes directly from the log buffer with multiple options:

- `n` - Create a new change branching off the revision under the cursor
- `<C-n>` - Create a new change after the revision under the cursor
- `<S-n>` - Create a new change after while ignoring immutability constraints

### Undo/Redo from the log buffer

You can undo/redo changes directly from the log buffer:

- `<S-u>` - Undo the last operation
- `<S-r>` - Redo the last undone operation

### Open a changed file

Just press enter to open the a file from the `status` output in your current window.
![Open-status](https://github.com/NicolasGB/jj.nvim/raw/main/assets/enter-status.gif)

### Restore a changed file

Press `<S-x>` on a file from the `status` output and that's it, it's restored.

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

### Diff Commands

The plugin also provides `:Jdiff`, `:Jvdiff`, and `:Jhdiff` commands for diffing against specific revisions:

```sh
:Jdiff              " Vertical diff against @- (parent)
:Jdiff @-2          " Vertical diff against specific revision
:Jvdiff main        " Vertical diff against main bookmark
:Jhdiff trunk()     " Horizontal diff against trunk
```

## Default Config

```lua
{
  -- Setup snacks as a picker
  picker = {
    -- Here you can pass the options as you would for snacks.
    -- It will be used when using the picker
    snacks = {}
  },

  -- Customize syntax highlighting colors for the describe buffer
  highlights = {
    added = { fg = "#3fb950", ctermfg = "Green" },      -- Added files
    modified = { fg = "#56d4dd", ctermfg = "Cyan" },    -- Modified files
    deleted = { fg = "#f85149", ctermfg = "Red" },      -- Deleted files
    renamed = { fg = "#d29922", ctermfg = "Yellow" },   -- Renamed files
  },

  -- Configure cmd module (describe editor, keymaps)
  cmd = {
    -- Configure describe editor
    describe = {
      editor = {
        -- Choose the editor mode for describe command
        -- "buffer" - Opens a Git-style commit message buffer with syntax highlighting (default)
        -- "input" - Uses a simple vim.ui.input prompt
        type = "buffer",
        -- Customize keymaps for the describe editor buffer
        keymaps = {
          close = { "<Esc>", "<C-c>", "q" },  -- Keys to close editor without saving
        }
      }
    },

    -- Configure keymaps for command buffers
    keymaps = {
      -- Log buffer keymaps (set to nil to disable)
      log = {
        checkout = "<CR>",                  -- Edit revision under cursor
        checkout_immutable = "<S-CR>",      -- Edit revision (ignore immutability)
        describe = "d",                     -- Describe revision under cursor
        diff = "<S-d>",                     -- Diff revision under cursor
        edit = "e",                         -- Edit revision under cursor
        new = "n",                          -- Create new change branching off
        new_after = "<C-n>",                -- Create new change after revision
        new_after_immutable = "<S-n>",      -- Create new change after (ignore immutability)
        undo = "<S-u>",                     -- Undo last operation
        redo = "<S-r>",                     -- Redo last undone operation
      },
      -- Status buffer keymaps (set to nil to disable)
      status = {
        open_file = "<CR>",                 -- Open file under cursor
        restore_file = "<S-x>",             -- Restore file under cursor
      },
      -- Close keymaps (shared across all buffers)
      close = { "q", "<Esc>" },
    },
  }
}

```

### Describe Editor Modes

The `describe.editor.type` option lets you choose how you want to write commit descriptions:

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
  describe = {
    editor = {
      type = "input", -- Use simple input mode
    }
  }
})
```

You can also customize the keymaps for the describe editor buffer:

```lua
require("jj").setup({
  describe = {
    editor = {
      type = "buffer",
      keymaps = {
        close = { "q", "<Esc>", "<C-c>" }, -- Customize close keybindings
      }
    }
  }
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

## Lua API Usage

Beyond the `:J` command, you can call functions directly from Lua for more control. The example config below shows how to use them with custom keymaps.

### Log Command Options

The `log` function accepts an options table:

```lua
jj.log({
  summary = false,      -- Show summary of changes (default: false)
  reversed = false,     -- Reverse the log order (default: false)
  no_graph = false,     -- Hide the graph (default: false)
  limit = 20,          -- Limit number of entries (default: 20)
  revisions = "'all()'" -- Revision specifier (default: all reachable)
})

-- Examples:
jj.log({ limit = 50 })                    -- Show 50 entries
jj.log({ revisions = "'main::@'" })       -- Show commits between main and current
jj.log({ summary = true, limit = 100 })   -- Show summary with high limit
jj.log({ raw = "-r 'main::@' --summary --no-graph" }) -- Pass raw flags directly
```

### New Command Options

The `new` function accepts an options table:

```lua
jj.new({
  show_log = false,    -- Display log after creating new change (default: false)
  with_input = false,  -- Prompt for parent revision (default: false)
  args = ""           -- Additional arguments to pass to jj new
})

-- Examples:
jj.new({ show_log = true })                           -- Create new and show log
jj.new({ show_log = true, with_input = true })        -- Prompt for parent
jj.new({ args = "--before @" })                       -- Pass custom args
```

### Diff Split Views

Use the `diff` module for opening splits:

```lua
jj.diff.vsplit()             -- Vertical split diff against parent
jj.diff.vsplit({ rev = "main" })  -- Vertical split against specific revision
jj.diff.hsplit()             -- Horizontal split diff
jj.diff.hsplit({ rev = "@-2" })   -- Horizontal split against @-2
```

## Example config

```lua

{
  "nicolasgb/jj.nvim",
  dependencies = {
    "folke/snacks.nvim", -- Optional only if you use picker's
  },

  config = function()
    local jj = require("jj")
    jj.setup({
      cmd = {
        describe = {
          editor = {
            type = "buffer",
            keymaps = {
              close = { "q", "<Esc>", "<C-c>" },
            }
          }
        },
        keymaps = {
          log = {
            checkout = "<CR>",
            describe = "d",
            diff = "<S-d>",
          },
          status = {
            open_file = "<CR>",
            restore_file = "<S-x>",
          },
          close = { "q", "<Esc>" },
        },
      },
      highlights = {
        -- Customize colors if desired
        modified = { fg = "#89ddff" },
      }
    })



    -- Core commands
    vim.keymap.set("n", "<leader>jd", jj.describe, { desc = "JJ describe" })
    vim.keymap.set("n", "<leader>jl", jj.log, { desc = "JJ log" })
    vim.keymap.set("n", "<leader>je", jj.edit, { desc = "JJ edit" })
    vim.keymap.set("n", "<leader>jn", jj.new, { desc = "JJ new" })
    vim.keymap.set("n", "<leader>js", jj.status, { desc = "JJ status" })
    vim.keymap.set("n", "<leader>sj", jj.squash, { desc = "JJ squash" })
    vim.keymap.set("n", "<leader>ju", jj.undo, { desc = "JJ undo" })
    vim.keymap.set("n", "<leader>jy", jj.redo, { desc = "JJ redo" })
    vim.keymap.set("n", "<leader>jr", jj.rebase, { desc = "JJ rebase" })
    vim.keymap.set("n", "<leader>jb", jj.bookmark_create, { desc = "JJ bookmark create" })
    vim.keymap.set("n", "<leader>jB", jj.bookmark_delete, { desc = "JJ bookmark delete" })

    -- Diff commands
    vim.keymap.set("n", "<leader>dj", jj.diff.vsplit, { desc = "JJ diff vertical" })
    vim.keymap.set("n", "<leader>dJ", jj.diff.hsplit, { desc = "JJ diff horizontal" })

    -- Pickers
    vim.keymap.set("n", "<leader>gj", jj.picker.status, { desc = "JJ Picker status" })
    vim.keymap.set("n", "<leader>gl", jj.picker.file_history, { desc = "JJ Picker file history" })

    -- Some functions like `log` can take parameters
    vim.keymap.set("n", "<leader>jL", function()
      jj.log {
        revisions = "'all()'", -- equivalent to jj log -r ::
      }
    end, { desc = "JJ log all" })


    -- This is an alias i use for moving bookmarks its so good
    vim.keymap.set("n", "<leader>jt", function()
      jj.j "tug"
      jj.log {}
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
