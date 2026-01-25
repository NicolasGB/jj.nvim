# jj.nvim

⚠️ **WORK IN PROGRESS** ⚠️

> **Note:** This project is pre-v1. Breaking changes may occur in the configuration, API, and features until v1.0.0 is released.

`jj.nvim` brings [Jujutsu (jj)](https://github.com/jj-vcs/jj) to your editor. Execute jj commands directly from Neovim with rich UI integration, custom editors for commit messages, interactive diff viewing from the log, live rebasing with preview, status browsing with file restoration, and one-click PR/MR opening. It's jj for Neovim without leaving your workflow.

![Demo](https://github.com/NicolasGB/jj.nvim/raw/main/assets/demo.gif)

## Table of Contents

- [Current Features](#current-features)
- [Enhanced Integrations](#enhanced-integrations)
  - [View change summary from the log buffer](#view-change-summary-from-the-log-buffer)
  - [Diff any change](#diff-any-change)
  - [Describe a change](#describe-a-change)
  - [Edit changes](#edit-changes)
  - [Create new changes from the log buffer](#create-new-changes-from-the-log-buffer)
  - [Undo/Redo from the log buffer](#undoredo-from-the-log-buffer)
  - [Abandon changes from the log buffer](#abandon-changes-from-the-log-buffer)
  - [Fetch and push from the log buffer](#fetch-and-push-from-the-log-buffer)
  - [Manage bookmarks from the log buffer](#manage-bookmarks-from-the-log-buffer)
  - [Squash changes from the log buffer](#squash-changes-from-the-log-buffer)
  - [Rebase changes from the log buffer](#rebase-changes-from-the-log-buffer)
  - [Open a PR/MR from the log buffer](#open-a-prmr-from-the-log-buffer)
  - [Open a changed file](#open-a-changed-file)
  - [Restore a changed file](#restore-a-changed-file)
- [Installation](#installation)
- [Cmdline Usage](#cmdline-usage)
  - [Diff Commands](#diff-commands)
- [Default Config](#default-config)
- [Configuration Examples](#configuration-examples)
  - [New Command Options](#new-command-options)
  - [Push Command Options](#push-command-options)
  - [Bookmark Management Command Options](#bookmark-management-command-options)
  - [Open PR/MR Command Options](#open-prmr-command-options)
  - [Diff Module](#diff-module)
    - [Functions](#functions)
    - [Log Buffer Integration](#log-buffer-integration)
  - [Custom Diff Backends](#custom-diff-backends)
  - [Annotations](#annotations)
- [Example config](#example-config)
- [Requirements](#requirements)
- [Contributing](#contributing)
- [Documentation](#documentation)
- [FAQ](#faq)
- [License](#license)

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
  - `squash` - Squash the current diff to its parent or interactive squash mode from the log buffer
  - `rebase` - Rebase changes to a destination
  - `bookmark create/delete` - Create and delete bookmarks
  - `undo` - Undo the last operation
  - `redo` - Redo the last undone operation
  - `open_pr` - Open a PR/MR on your remote (GitHub, GitLab, Gitea, Forgejo, etc.)
  - `annotate` / `annotate_line` - View file blame and line history with change ID, author, and timestamp
  - `commit` - Describe the current change and create a new one after
  - Diff commands
  - `:Jdiff [revision]` - Vertical split diff against a jj revision
  - `:Jhdiff [revision]` - Horizontal split diff
- Picker for [Snacks.nvim](https://github.com/folke/snacks.nvim)
  - `jj status` Displays the current changes diffs
  - `jj file_history` Displays a buffer's history changes and allows to edit its change (including immutable changes)

## Enhanced integrations

Here are some cool features you can do with jj.nvim:

### View change summary from the log buffer

Quickly preview the files changed in any revision without leaving the log:

- `<S-k>` - Show a tooltip with the revision's changed files
- `<S-k>` - To enter the tooltip buffer

From the summary view, you can:

- `<S-d>` - Diff the file under cursor at that revision
- `<CR>` - Edit the revision and open the file
- `<S-CR>` - Edit the revision (ignoring immutability) and open the file

![Summary-from-log](https://github.com/NicolasGB/jj.nvim/raw/main/assets/summary.gif)

### Diff any change

You can diff any change in your log history by pressing `<S-d>` on its line or on a summary file change. You can also visually select multiple changes to diff between the first and last selected.

> [!NOTE]
> Integrates with your preferred diff plugin or uses your native jj diff config. See [Diff Module](#diff-module).

![Diff-from-log](https://github.com/NicolasGB/jj.nvim/raw/main/assets/diff-log.gif)

### Describe a change

You can describe any change directly from the log buffer:

- `d` - Describe the revision under cursor using your configured editor

### Edit changes

Jumping up and down your log history ?

In your log output press `CR` in a line to directly edit a `mutable` change.
If you are sure what you are doing press `S-CR` (Shift Enter) to edit an `immutable` change.
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

### Abandon changes from the log buffer

You can abandon changes directly from the log buffer, works in visual mode to abandon multiple changes:

- `a` - Abandon the revision under the cursor

### Fetch and push from the log buffer

You can fetch and push directly from the log buffer:

- `f` - Fetch from remote
- `<S-p>` - Push a bookmark through the picker
- `p` - Push bookmark of revision under cursor to remote

### Manage bookmarks from the log buffer

- `b` - Create a new bookmark or move an existing one to the revision under cursor
  - Select from existing bookmarks to move them
  - Or create a new bookmark at that revision

### Squash changes from the log buffer

Enter an interactive squash mode to squash one or more changes into a destination:

- `s` - Enter squash mode targeting the revision under cursor (in normal mode) or selected revisions (in visual mode)
- `<S-s>` - Quick squash the revision under cursor into its parent

Once in squash mode, the interface highlights your selection and the current squash destination:

- Selected changes are highlighted in your configured `selected_hl` color (default: dark magenta)
- The cursor position (potential squash destination) is highlighted in your configured `targeted_hl` color (default: green)
- Move the cursor to preview different squash destinations with live highlighting

From squash mode, choose how to squash:

- `<CR>` - Squash into (`-t`) the revision under cursor
- `<S-CR>` - Squash into (`-t`) ignoring immutability
- `<Esc>` or `<C-c>` - Exit squash mode without making changes

**Visual mode selection:** Select multiple revisions in visual mode before pressing `s` to squash them all at once. The plugin extracts each selected revision and squashes them together.

**Quick squash:** In normal mode, press `<S-s>` to quickly squash the current revision into its parent. This ignores immutability.

![Squash-from-log](https://github.com/NicolasGB/jj.nvim/raw/main/assets/squash.gif)

### Rebase changes from the log buffer

Enter an interactive rebase mode directly from the log buffer to rebase one or more changes:

- `r` - Enter rebase mode targeting the revision under cursor (in normal mode) or selected revisions (in visual mode)

Once in rebase mode, the interface highlights your selection and the current rebase destination:

- Selected changes are highlighted in your configured `selected_hl` color (default: dark magenta)
- The cursor position (potential rebase destination) is highlighted in your configured `targeted_hl` color (default: green)
- Move the cursor to preview different rebase destinations with live highlighting

From rebase mode, choose how to rebase:

- `<CR>` or `o` - Rebase onto (`-o`) the revision under cursor
- `a` - Rebase after (`-A`) the revision under cursor
- `b` - Rebase before (`-B`) the revision under cursor
- `<S-CR>` or `<S-o>` - Rebase onto (`-o`) ignoring immutability
- `<S-a>` - Rebase after (`-A`) ignoring immutability
- `<S-b>` - Rebase before (`-B`) ignoring immutability
- `<Esc>` or `<C-c>` - Exit rebase mode without making changes

**Visual mode selection:** Select multiple revisions in visual mode before pressing `r` to rebase them all at once. The plugin extracts each selected revision and rebases them together.

**Single revision:** In normal mode, place your cursor on a single revision and press `r` to rebase just that change.

![Rebase-from-log](https://github.com/NicolasGB/jj.nvim/raw/main/assets/rebase.gif)

### Open a PR/MR from the log buffer

- `o` - Open a PR/MR for the revision under cursor
- `<S-o>` - Select a remote from all available bookmarks and open a PR/MR

The plugin automatically:

- Extracts the bookmark from the revision
- Detects your git platform (GitHub, GitLab, Gitea, Forgejo, etc.)
- Constructs the appropriate PR/MR URL
- Handles both HTTPS and SSH remote URLs
- Prompts you to select a remote if you have multiple

**This is a jj.nvim exclusive feature** - the ability to seamlessly bridge from your Neovim jj workflow directly to your remote platform's PR/MR interface.

### Open a changed file

Just press enter to open a file from the `status` output in your current window.
![Open-status](https://github.com/NicolasGB/jj.nvim/raw/main/assets/enter-status.gif)

### Restore a changed file

Press `<S-x>` on a file from the `status` output and that's it, it's restored.

![Restore-status](https://github.com/NicolasGB/jj.nvim/raw/main/assets/x-status.gif)

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

Using the latest stable release:

```lua
{
    "nicolasgb/jj.nvim",
    version = "*", -- Use latest stable release
    -- Or from the main branch (uncomment the branch line and comment the version line)
    -- branch = "main",
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
:J push               " Push all changes
:J push main         " Push only main bookmark
:J fetch             " Fetch from remote
:J open_pr           " Open PR for current change's bookmark
:J open_pr --list    " Select bookmark from all and open PR
:J bookmark create/move/delete
:J # This will use your defined default command
:J <your-alias>
:J commit            " Opens your configured editor describes @ and then creates a new change -A immediately
:J commit <any text here> " Automatically describes @ and creates a new change -A immediately
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
    editor = {
        added = { fg = "#3fb950", ctermfg = "Green" },      -- Added files
        modified = { fg = "#56d4dd", ctermfg = "Cyan" },    -- Modified files
        deleted = { fg = "#f85149", ctermfg = "Red" },      -- Deleted files
        renamed = { fg = "#d29922", ctermfg = "Yellow" },   -- Renamed files
    },
    log = {
        selected = { bg = "#3d2c52", ctermbg = "DarkMagenta" },
        targeted = { fg = "#5a9e6f", ctermfg = "Green" },
    }
  },

  -- Configure terminal behavior
  terminal = {
    -- Cursor render delay in milliseconds (default: 10)
    -- If cursor column is being reset to 0 when refreshing commands, try increasing this value
    -- This delay allows the terminal emulator to complete rendering before restoring cursor position
    cursor_render_delay = 10,
  },

  -- Configure diff module
  diff = {
    -- Default backend for viewing diffs
    -- "native" - Built-in split diff using Neovim's diff mode (default)
    -- "diffview" - Use diffview.nvim plugin (requires diffview.nvim)
    -- "codediff" - Use codediff.nvim plugin (requires codediff.nvim)
    -- Or any custom backend name you've registered
    backend = "native",
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

    -- Configure log command behavior
    log = {
      close_on_edit = false,                                     -- Close log buffer after editing a change
    },

    -- Configure bookmark command
    bookmark = {
        prefix = ""
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
        abandon = "a",                      -- Abandon revision under cursor
        bookmark = "b",                     -- Create or move bookmark to revision under cursor
        fetch = "f",                        -- Fetch from remote
        push = "p",                         -- Push bookmark of revision under cursor
        push_all = "<S-p>",                 -- Push all changes to remote
        open_pr = "o",                      -- Open PR/MR for revision under cursor
        open_pr_list = "<S-o>",             -- Open PR/MR by selecting from all bookmarks
        rebase = "r",                       -- Enter rebase mode targeting revision under cursor or selected revisions
        rebase_mode = {
            onto = { "<CR>", "o" },           -- Select revision under cursor as rebase onto destination
            after = { "a", "A" },             -- Rebase after revision under cursor
            before = { "b", "B" },            -- Rebase before revision under cursor
            onto_immutable = { "<S-CR>", "<S-o>" }, -- Select revision  as a rebase onto destination (ignore immutability)
            after_immutable = "<S-a>",              -- Rebase after revision under cursor (ignore immutability)
            before_immutable = "<S-b>",             -- Rebase before revision under cursor (ignore immutability)
            exit_mode = { "<Esc>", "<C-c>" }, -- Exit rebase mode
        },
        squash = "s",                       -- Enter squash mode targeting revision under cursor or selected revisions
        squash_mode = {
            into = "<CR>",                     -- Squash into revision under cursor
            into_immutable = "<S-CR>",         -- Squash into revision under cursor (ignore immutability)
            exit_mode = { "<Esc>", "<C-c>" }, -- Exit squash mode
        },
        quick_squash = "<S-s>",             -- Quick squash revision under cursor into its parent (ignore immutability)
        summary = "<S-k>",                  -- Show summary tooltip for revision under cursor
        summary_tooltip = {
            diff = "<S-d>",                   -- Diff file at this revision
            edit = "<CR>",                    -- Edit revision and open file
            edit_immutable = "<S-CR>",        -- Edit revision (ignore immutability) and open file
        },
      },
      -- Status buffer keymaps (set to nil to disable)
      status = {
        open_file = "<CR>",                 -- Open file under cursor
        restore_file = "<S-x>",             -- Restore file under cursor
      },
      -- Close keymaps (shared across all buffers)
      close = { "q", "<Esc>" },
    },

}}

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
local cmd = require("jj.cmd")
cmd.log({
  summary = false,      -- Show summary of changes (default: false)
  reversed = false,     -- Reverse the log order (default: false)
  no_graph = false,     -- Hide the graph (default: false)
  limit = 20,          -- Limit number of entries (default: 20)
  revisions = "'all()'" -- Revision specifier (default: all reachable)
})

-- Examples:
cmd.log({ limit = 50 })                    -- Show 50 entries
cmd.log({ revisions = "'main::@'" })       -- Show commits between main and current
cmd.log({ summary = true, limit = 100 })   -- Show summary with high limit
cmd.log({ raw = "-r 'main::@' --summary --no-graph" }) -- Pass raw flags directly
```

## Configuration Examples

### New Command Options

The `new` function accepts an options table:

```lua
local cmd = require("jj.cmd")
cmd.new({
  show_log = false,     -- Display log after creating new change (default: false)
  with_input = false,   -- Prompt for parent revision (default: false)
  args = ""             -- Additional arguments to pass to jj new
})

-- Examples:
cmd.new({ show_log = true })                           -- Create new and show log
cmd.new({ show_log = true, with_input = true })        -- Prompt for parent
cmd.new({ args = "--before @" })                       -- Pass custom args
```

### Push Command Options

The `push` function accepts an options table:

```lua
local cmd = require("jj.cmd")
cmd.push({
  bookmark = "main"     -- Push specific bookmark (default: all changes)
})

-- Examples:
cmd.push()                    -- Push all changes
cmd.push({ bookmark = "main" }) -- Push only main bookmark
cmd.push({ bookmark = "feature" }) -- Push only feature bookmark
```

### Bookmark Management Command Options

The `bookmark_create` function creates a new bookmark:

```lua
local cmd = require("jj.cmd")
cmd.bookmark_create()                               -- Prompts for bookmark name, then prompts the revision
cmd.bookmark_create({ prefix = "feature/" })        -- Uses prefix for default bookmark name
```

You can also set a default bookmark prefix in the config:

```lua
require("jj").setup({
  cmd = {
    bookmark = {
      prefix = "feature/"  -- Default prefix when creating bookmarks
    }
  }
})
```

The `bookmark_move` function moves an existing bookmark to a new revision:

```lua
local cmd = require("jj.cmd")
cmd.bookmark_move()  -- Select bookmark, then specify new revset
```

The `bookmark_delete` function deletes a bookmark:

```lua
local cmd = require("jj.cmd")
cmd.bookmark_delete()  -- Select bookmark to delete
```

### Open PR/MR Command Options

The `open_pr` function accepts an options table:

```lua
local cmd = require("jj.cmd")
cmd.open_pr({
  list_bookmarks = false    -- Whether to select from all bookmarks (default: false, uses current revision)
})

-- Examples:
cmd.open_pr()                          -- Open PR for current change's bookmark
cmd.open_pr({ list_bookmarks = true }) -- Select bookmark from all and open PR
```

### Diff Module

The diff module provides a unified API for viewing diffs with pluggable backend support.

The natively supported backends are:

- Native (Diffs the current file in place and uses a floating buffer with your jj diff command when diffing changes)
- [codediff](https://github.com/esmuellert/codediff.nvim)
- [diffview](https://github.com/sindrets/diffview.nvim)

#### Functions

```lua
local diff = require("jj.diff")

-- Diff current buffer against a revision (default: @-)
-- The `layout` is only supported for the native backend
diff.diff_current({ rev = "@-", layout = "vertical" })

-- Show what changed in a single revision
diff.show_revision({ rev = "abc123" })

-- Diff between two revisions
diff.diff_revisions({ left = "main", right = "@" })

-- Convenience functions (LEGACY FUNCTIONS)
diff.open_vdiff()                   -- Vertical split diff against parent
diff.open_vdiff({ rev = "main" })   -- Vertical split against specific revision
diff.open_hdiff()                   -- Horizontal split diff
diff.open_hdiff({ rev = "@-2" })    -- Horizontal split against @-2
```

#### Log Buffer Integration

The diff module integrates seamlessly with the log buffer:

- `<S-d>` - Show diff for the revision under cursor in a floating window

These actions use the configured diff backend, allowing you to leverage your preferred diff viewer directly from the log.

### Custom Diff Backends

The diff module supports pluggable backends. Built-in backends include `native`, `diffview`, and `codediff`. You can register your own backend:

```lua
local diff = require("jj.diff")

diff.register_backend("my-backend", {
  -- Diff current buffer against a revision
  diff_current = function(opts)
    -- opts.rev: revision to diff against (default: "@-")
    -- opts.path: file path (default: current buffer)
    -- opts.layout: "vertical" or "horizontal"
  end,

  -- Show what changed in a single revision
  show_revision = function(opts)
    -- opts.rev: revision to show
    -- opts.path: optional file filter
    -- opts.display: "floating", "tab", or "split"
  end,

  -- Diff between two revisions
  diff_revisions = function(opts)
    -- opts.left: left/base revision
    -- opts.right: right/target revision
    -- opts.path: optional file filter
    -- opts.display: "floating", "tab", or "split"
  end,
})
```

Set your backend as default in the config:

```lua
require("jj").setup({
  diff = {
    backend = "my-backend"
  }
})
```

Or use it per-call:

```lua
diff.diff_current({ backend = "my-backend", rev = "main" })
```

All three functions are optional—missing ones fall back to the `native` implementation.

### Annotations

View file blame and line history using the annotate module. Can be invoked via command or Lua API.

**Via `:J` command:**

```sh
:J annotate         " Show blame/annotations for entire file in vertical split
:J annotate_line    " Show annotation for current line in floating buffer
```

**Via Lua API:**

```lua
local annotate = require("jj.annotate")
annotate.file()    -- Show blame/annotations for entire file in vertical split
annotate.line()    -- Show annotation for current line in a tooltip
```

The file annotation displays a vertical split showing:

- Change ID (colored uniquely per commit)
- Author name
- Timestamp

Press `<CR>` on any annotation line to view the diff for that change.

The line annotation displays a floating tooltip with the current line's annotation and the commit description.

Example keymaps:

```lua
local annotate = require("jj.annotate")
vim.keymap.set("n", "<leader>ja", annotate.file, { desc = "JJ annotate file" })
vim.keymap.set("n", "<leader>jA", annotate.line, { desc = "JJ annotate line" })
```

## Example config

```lua

{
  "nicolasgb/jj.nvim",
  dependencies = {
    "folke/snacks.nvim", -- Optional, only needed if you use pickers

    -- One of these two if you want to use them as your diff backend
    "esmuellert/codediff.nvim",
    "sindrets/diffview.nvim",
  },

  config = function()
    local jj = require("jj")
    jj.setup({
      terminal = {
        cursor_render_delay = 10, -- Adjust if cursor position isn't restoring correctly
      },
      diff = {
          backend = "codediff"
      },
      cmd = {
        describe = {
          editor = {
            type = "buffer",
            keymaps = {
              close = { "q", "<Esc>", "<C-c>" },
            }
          }
        },
        bookmark = {
            prefix = "feat/"
        },
        keymaps = {
          log = {
            checkout = "<CR>",
            describe = "d",
            diff = "<S-d>",
            abandon = "<S-a>",
            fetch = "<S-f>",
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
    local cmd = require("jj.cmd")
    vim.keymap.set("n", "<leader>jd", cmd.describe, { desc = "JJ describe" })
    vim.keymap.set("n", "<leader>jl", cmd.log, { desc = "JJ log" })
    vim.keymap.set("n", "<leader>je", cmd.edit, { desc = "JJ edit" })
    vim.keymap.set("n", "<leader>jn", cmd.new, { desc = "JJ new" })
    vim.keymap.set("n", "<leader>js", cmd.status, { desc = "JJ status" })
    vim.keymap.set("n", "<leader>sj", cmd.squash, { desc = "JJ squash" })
    vim.keymap.set("n", "<leader>ju", cmd.undo, { desc = "JJ undo" })
    vim.keymap.set("n", "<leader>jy", cmd.redo, { desc = "JJ redo" })
    vim.keymap.set("n", "<leader>jr", cmd.rebase, { desc = "JJ rebase" })
    vim.keymap.set("n", "<leader>jbc", cmd.bookmark_create, { desc = "JJ bookmark create" })
    vim.keymap.set("n", "<leader>jbd", cmd.bookmark_delete, { desc = "JJ bookmark delete" })
    vim.keymap.set("n", "<leader>jbm", cmd.bookmark_move, { desc = "JJ bookmark move" })
    vim.keymap.set("n", "<leader>ja", cmd.abandon, { desc = "JJ abandon" })
    vim.keymap.set("n", "<leader>jf", cmd.fetch, { desc = "JJ fetch" })
    vim.keymap.set("n", "<leader>jp", cmd.push, { desc = "JJ push" })
    vim.keymap.set("n", "<leader>jpr", cmd.open_pr, { desc = "JJ open PR from bookmark in current revision or parent" })
    vim.keymap.set("n", "<leader>jpl", function()
        cmd.open_pr { list_bookmarks = true }
    end, { desc = "JJ open PR listing available bookmarks" })


    -- Diff commands
    local diff = require("jj.diff")
    vim.keymap.set("n", "<leader>df", function() diff.open_vdiff() end, { desc = "JJ diff current buffer" })
    vim.keymap.set("n", "<leader>dF", function() diff.open_hsplit() end, { desc = "JJ hdiff current buffer" })

    -- Pickers
    local picker = require("jj.picker")
    vim.keymap.set("n", "<leader>gj", function() picker.status() end, { desc = "JJ Picker status" })
    vim.keymap.set("n", "<leader>jgh", function() picker.file_history() end, { desc = "JJ Picker history" })

    -- Some functions like `log` can take parameters
    vim.keymap.set("n", "<leader>jL", function()
      cmd.log {
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

Once the plugin is more complete I'll write docs for each of the commands.

## FAQ

- Telescope Support? Planned but I don't use it, it's already thought of by design, will implement it at some point or if someone submits a PR I'll accept it gladly.

## License

[MIT](License)
