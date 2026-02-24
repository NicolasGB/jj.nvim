# jj.nvim

⚠️ **WORK IN PROGRESS** ⚠️

> **Note:** This project is pre-v1. Breaking changes may occur in the configuration, API, and features until v1.0.0 is released.

`jj.nvim` brings [Jujutsu (jj)](https://github.com/jj-vcs/jj) to your editor. Execute jj commands directly from Neovim with rich UI integration, custom editors for commit messages, interactive diff viewing from the log, live rebasing with preview, status browsing with file restoration, and one-click PR/MR opening. It's jj for Neovim without leaving your workflow.

![Demo](https://github.com/NicolasGB/jj.nvim/raw/main/assets/demo.gif)

## Table of Contents

- [Highlights](#highlights)
- [Installation](#installation)
  - [Requirements](#requirements)
- [Quick Start](#quick-start)
- [Cmdline Usage](#cmdline-usage)
  - [Diff Commands](#diff-commands)
- [Log Buffer](#log-buffer)
  - [Viewing & Navigation](#viewing--navigation)
  - [Creating & Rewriting History](#creating--rewriting-history)
  - [Remote Operations](#remote-operations)
  - [Bookmarks & Tags](#bookmarks--tags)
- [Status Buffer](#status-buffer)
- [Diff](#diff)
  - [Built-in Backends](#built-in-backends)
  - [Custom Backends](#custom-backends)
- [Annotations](#annotations)
- [Browse on Remote](#browse-on-remote)
- [Pickers](#pickers)
- [Configuration](#configuration)
  - [Default Config](#default-config)
  - [Command Options](#command-options)
  - [Full Example](#full-example)
- [FAQ](#faq)
- [Contributing](#contributing)
- [License](#license)

## Highlights

Here's a taste of what jj.nvim can do — all without leaving Neovim:

- **🔀 Live rebase with preview** — Enter rebase mode from the log, move your cursor to preview destinations with live highlighting, then confirm with a keypress. Supports visual selection for multi-revision rebases.

![Rebase-from-log](https://github.com/NicolasGB/jj.nvim/raw/main/assets/rebase.gif)

- **📦 Interactive squash mode** — Select one or more changes, navigate to a destination with live-highlighted preview, and squash. Visual mode and quick-squash supported.

![Squash-from-log](https://github.com/NicolasGB/jj.nvim/raw/main/assets/squash.gif)

- **📝 Diff any change from the log** — Press `<S-d>` on any revision to view its diff. Works with your preferred diff backend (native, [diffview](https://github.com/sindrets/diffview.nvim), [codediff](https://github.com/esmuellert/codediff.nvim)).

![Diff-from-log](https://github.com/NicolasGB/jj.nvim/raw/main/assets/diff-log.gif)

- **📋 Change summary tooltips** — Preview files changed in any revision with `<S-k>`, then jump into the diff or edit the file directly from the tooltip.

![Summary-from-log](https://github.com/NicolasGB/jj.nvim/raw/main/assets/summary.gif)

- **⚡ Edit any change instantly** — Press `<CR>` on any revision in the log to edit it. One keypress to jump anywhere in your history.

![Edit-from-log](https://github.com/NicolasGB/jj.nvim/raw/main/assets/edit-log.gif)

- **🌐 Open PRs from the log** — Detect your git platform, extract the bookmark, and open the PR/MR URL — all from one keypress in the log buffer.

- **🔍 File annotations** — View blame with unique colors per change ID, author, and timestamp. Press `<CR>` on any line to see that change's diff.

- **📂 Status buffer with restore** — Browse changed files, open them with `<CR>`, or restore them with `<S-x>`.

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

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

### Requirements

- [Jujutsu](https://github.com/jj-vcs/jj) installed and available in PATH
- [GitHub CLI (`gh`)](https://cli.github.com/) — Optional, required for `fetch_pr` command

## Quick Start

Minimal setup to get productive immediately:

```lua
require("jj").setup({})

local cmd = require("jj.cmd")
vim.keymap.set("n", "<leader>jl", cmd.log, { desc = "JJ log" })
vim.keymap.set("n", "<leader>jd", cmd.describe, { desc = "JJ describe" })
vim.keymap.set("n", "<leader>js", cmd.status, { desc = "JJ status" })
vim.keymap.set("n", "<leader>jn", cmd.new, { desc = "JJ new" })
```

Open the log with `<leader>jl` and you get access to most features through the log buffer keymaps: edit (`<CR>`), describe (`d`), diff (`<S-d>`), rebase (`r`), squash (`s`), and more.

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
:J fetch_pr          " Fetch a PR from GitHub
:Jbrowse             " Open current file on remote at cursor line
:Jbrowse main        " Open current file on remote at the given revset
:J split             " Split a change interactively
:J bookmark create/move/delete
:J tag set           " Set a tag (prompts for revision and tag name)
:J tag set abc123    " Set a tag on a specific revision
:J tag delete        " Delete a tag via picker
:J tag delete v1.0   " Delete a specific tag
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

## Log Buffer

The log buffer is the central hub of jj.nvim. Open it with `:J log` or `cmd.log()` and you get access to the full power of the plugin through keymaps.

### Viewing & Navigation

#### Change summary

Quickly preview the files changed in any revision without leaving the log:

- `<S-k>` — Show a tooltip with the revision's changed files
- `<S-k>` — Press again to enter the tooltip buffer

From the summary view:

- `<S-d>` — Diff the file under cursor at that revision
- `<CR>` — Edit the revision and open the file
- `<S-CR>` — Edit the revision (ignoring immutability) and open the file

![Summary-from-log](https://github.com/NicolasGB/jj.nvim/raw/main/assets/summary.gif)

#### Diff any change

Press `<S-d>` on any revision to view its diff. You can also visually select multiple changes to diff between the first and last selected.

> [!NOTE]
> Integrates with your preferred diff plugin or uses your native jj diff config. See [Diff](#diff).

![Diff-from-log](https://github.com/NicolasGB/jj.nvim/raw/main/assets/diff-log.gif)

#### Describe a change

- `d` — Describe the revision under cursor using your configured editor

#### Edit changes

Press `<CR>` on a line to directly edit a `mutable` change. Press `<S-CR>` (Shift Enter) to edit an `immutable` change.

![Edit-from-log](https://github.com/NicolasGB/jj.nvim/raw/main/assets/edit-log.gif)

### Creating & Rewriting History

#### Create new changes

- `n` — Create a new change branching off the revision under the cursor
- `<C-n>` — Create a new change after the revision under the cursor
- `<S-n>` — Create a new change after while ignoring immutability constraints

#### Squash changes

Enter an interactive squash mode to squash one or more changes into a destination:

- `s` — Enter squash mode (normal mode: revision under cursor, visual mode: selected revisions)
- `<S-s>` — Quick squash the revision under cursor into its parent

Once in squash mode, the interface highlights your selection and the current squash destination:

- Selected changes are highlighted in your configured `selected_hl` color (default: dark magenta)
- The cursor position (potential squash destination) is highlighted in your configured `targeted_hl` color (default: green)
- Move the cursor to preview different squash destinations with live highlighting

From squash mode:

- `<CR>` — Squash into (`-t`) the revision under cursor
- `<S-CR>` — Squash into (`-t`) ignoring immutability
- `<Esc>` or `<C-c>` — Exit squash mode without making changes

**Visual mode selection:** Select multiple revisions in visual mode before pressing `s` to squash them all at once.

**Quick squash:** In normal mode, press `<S-s>` to quickly squash the current revision into its parent. This ignores immutability.

![Squash-from-log](https://github.com/NicolasGB/jj.nvim/raw/main/assets/squash.gif)

#### Split changes

Split a change into two or more revisions directly from the log buffer or the command line:

- `<C-s>` — Split the revision under cursor from the log buffer

The split command opens an interactive floating terminal where jj guides you through selecting which changes go into the first commit. The remaining changes stay in the second commit.

> [!NOTE]
> If you want to use something like [hunk.nvim](https://github.com/julienvincent/hunk.nvim), simply follow the steps and update your jj's config to use it as a tool and a neovim instance with hunk will be ran inside your current neovim, for a seamless integration
>
> Other tools that ran in the terminal like jj's native should work out of the box too.

**Via `:J` command:**

```sh
:J split              " Split @ interactively
:J split abc123       " Split a specific revision
:J split @ --parallel " Create parallel changes instead of sequential
:J split @ --message "first half" " Set a commit message for the first split
```

**Via Lua API:**

```lua
local cmd = require("jj.cmd")
cmd.split()                                      -- Split @ interactively
cmd.split({ rev = "abc123" })                    -- Split a specific revision
cmd.split({ parallel = true })                   -- Create parallel changes
cmd.split({ message = "first half" })            -- Set message for first split
cmd.split({ filesets = { "src/" } })             -- Only include specific filesets
cmd.split({ ignore_immutable = true })           -- Split an immutable revision
```

The floating terminal size is configurable via the `split.width` and `split.height` options (ratios between `0.1` and `1.0`).

#### Rebase changes

Enter an interactive rebase mode directly from the log buffer:

- `r` — Enter rebase mode (normal mode: revision under cursor, visual mode: selected revisions)

Once in rebase mode, the interface highlights your selection and the current rebase destination:

- Selected changes are highlighted in your configured `selected_hl` color (default: dark magenta)
- The cursor position (potential rebase destination) is highlighted in your configured `targeted_hl` color (default: green)
- Move the cursor to preview different rebase destinations with live highlighting

From rebase mode:

- `<CR>` or `o` — Rebase onto (`-o`) the revision under cursor
- `a` — Rebase after (`-A`) the revision under cursor
- `b` — Rebase before (`-B`) the revision under cursor
- `<S-CR>` or `<S-o>` — Rebase onto (`-o`) ignoring immutability
- `<S-a>` — Rebase after (`-A`) ignoring immutability
- `<S-b>` — Rebase before (`-B`) ignoring immutability
- `<Esc>` or `<C-c>` — Exit rebase mode without making changes

**Visual mode selection:** Select multiple revisions in visual mode before pressing `r` to rebase them all at once.

**Single revision:** In normal mode, place your cursor on a single revision and press `r` to rebase just that change.

![Rebase-from-log](https://github.com/NicolasGB/jj.nvim/raw/main/assets/rebase.gif)

#### Abandon changes

Works in visual mode to abandon multiple changes:

- `a` — Abandon the revision under the cursor

#### Undo / Redo

- `<S-u>` — Undo the last operation
- `<S-r>` — Redo the last undone operation

### Remote Operations

#### Fetch and push

- `f` — Fetch from remote
- `p` — Push bookmark of revision under cursor to remote
- `<S-p>` — Push a bookmark through the picker

#### Open a PR/MR

- `o` — Open a PR/MR for the revision under cursor
- `<S-o>` — Select a remote from all available bookmarks and open a PR/MR

The plugin automatically:

- Extracts the bookmark from the revision
- Detects your git platform (GitHub, GitLab, Gitea, Forgejo, etc.)
- Constructs the appropriate PR/MR URL
- Handles both HTTPS and SSH remote URLs
- Prompts you to select a remote if you have multiple

**This is a jj.nvim exclusive feature** — the ability to seamlessly bridge from your Neovim jj workflow directly to your remote platform's PR/MR interface.

#### Fetch a PR from GitHub

Fetch an open pull request from GitHub and import it into your local repository as a jj change:

**Via `:J` command:**

```sh
:J fetch_pr           " Open a picker to select an open PR to fetch
```

**Via Lua API:**

```lua
local cmd = require("jj.cmd")
cmd.fetch_pr()                   -- Fetch a PR (default limit: 100)
cmd.fetch_pr({ limit = 50 })     -- Fetch with a custom PR list limit
```

The plugin:

- Lists open PRs from GitHub using the `gh` CLI
- Presents a picker to select a PR
- Fetches the PR branch via `git fetch` and imports it with `jj git import`
- Automatically refreshes the log buffer if it's open
- Handles naming conflicts by retrying with incremented suffixes (e.g., `pr-42-1`, `pr-42-2`)

> [!NOTE]
> Requires a colocated repository and the [`gh` CLI](https://cli.github.com/) installed.

### Bookmarks & Tags

#### Manage bookmarks

- `b` — Create a new bookmark or move an existing one to the revision under cursor
  - Select from existing bookmarks to move them
  - Or create a new bookmark at that revision

#### Manage tags

- `<S-t>` — Create a new tag on the revision under cursor

Deleting and pushing tags (for colocated repositories) is also supported and changes are reflected if the log buffer is open. Set up some keybinds and you're good to go, please see [Tag Management](#tag-management) under Command Options.

## Status Buffer

The status buffer shows the current repository status. Open it with `:J status` or `cmd.status()`.

### Open a changed file

Press `<CR>` to open a file from the status output in your current window.

![Open-status](https://github.com/NicolasGB/jj.nvim/raw/main/assets/enter-status.gif)

### Restore a changed file

Press `<S-x>` on a file from the status output to restore it.

![Restore-status](https://github.com/NicolasGB/jj.nvim/raw/main/assets/x-status.gif)

## Diff

The diff module provides a unified API for viewing diffs with pluggable backend support.

### Built-in Backends

- **Native** — Diffs the current file in place and uses a floating buffer with your jj diff command when diffing changes (default)
- **[codediff](https://github.com/esmuellert/codediff.nvim)** — Use codediff.nvim plugin
- **[diffview](https://github.com/sindrets/diffview.nvim)** — Use diffview.nvim plugin

**Functions:**

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

The diff module integrates seamlessly with the log buffer — `<S-d>` shows the diff for the revision under cursor using your configured backend.

### Custom Backends

The diff module supports pluggable backends. You can register your own:

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

All three functions are optional — missing ones fall back to the `native` implementation.

## Annotations

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

## Browse on Remote

Open the current buffer's file in your browser on the hosted remote (GitHub/GitLab/Gitea/Forgejo, etc.) at the current cursor line or a visually selected range.

**Usage:**

```sh
:Jbrowse          " Use @ (best-effort chooses a remote-reachable ref)
:Jbrowse main     " Use an explicit revset (no walkback)
```

**How it works:**

- Takes the current buffer path and makes it repo-relative (must be inside a jj repo)
- Collects git remotes; if there's more than one, prompts you to pick one
- Normalizes the remote URL to an HTTPS base repo URL
- Picks a ref that is expected to exist on the remote:
  - With default `@`: walks back first-parent up to 20 parents to find a commit reachable from that remote's bookmarks; falls back to `trunk()` if needed
  - With an explicit revset (e.g. `main`, `@-2`): uses that revset directly (no walkback)
  - If there's a single unambiguous remote bookmark pointing at the chosen commit, uses that bookmark name; otherwise uses the commit SHA
- Builds a provider-specific URL and adds a line anchor:
  - GitHub-style: `#L<start>` or `#L<start>-L<end>`
  - GitLab-style: `#L<start>` or `#L<start>-<end>`

In Visual mode, select lines and run `:Jbrowse` to open a range.

## Pickers

Pickers are available via [Snacks.nvim](https://github.com/folke/snacks.nvim):

```lua
local picker = require("jj.picker")
picker.status()        -- Displays the current changes diffs
picker.file_history()  -- Displays a buffer's history changes and allows to edit its change (including immutable changes)
```

## Configuration

### Default Config

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
        -- [Added/Modified/Deleted] are handled by nvim's builtin syntax coloring for the type
        -- Although you can override them too.
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
          close = { "<C-c>", "q" },  -- Keys to close editor without saving
        }
      }
    },

    -- Configure log command behavior
    log = {
      close_on_edit = false,                                     -- Close log buffer after editing a change
    },

    -- Configure split command
    split = {
      width = 0.99,                                              -- Width ratio of the floating terminal (0.1 to 1.0)
      height = 0.95,                                             -- Height ratio of the floating terminal (0.1 to 1.0)
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
        split = "<C-s>",                    -- Split the revision under cursor
        tag_create = "<S-t>",               -- Create a tag on the revision under cursor
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
      -- Floating buffer keymaps
      floating = {
        close = "q",
        hide = "<Esc>",
      },
    },

  }}

```

### Command Options

#### Describe Editor Modes

The `describe.editor.type` option lets you choose how you want to write commit descriptions:

- **`"buffer"`** (default) — Opens a full buffer editor similar to Git's commit message editor. Shows file changes with syntax highlighting. Multi-line editing with proper formatting. Close with `q` or `<Esc>`, save with `:w` or `:wq`.
- **`"input"`** — Simple single-line input prompt. Uses `vim.ui.input()` which can be customized by UI plugins like dressing.nvim.

```lua
require("jj").setup({
  cmd = {
    describe = {
      editor = {
        type = "input",                         -- Use simple input mode
        keymaps = {
          close = { "q", "<Esc>", "<C-c>" },    -- Customize close keybindings
        }
      }
    }
  }
})
```

#### Highlight Customization

The `highlights` option allows you to customize the colors used in the describe buffer's file status display. Each highlight accepts standard Neovim highlight attributes (`fg`, `bg`, `ctermfg`, `ctermbg`, `bold`, `italic`, `underline`):

```lua
require("jj").setup({
  highlights = {
    editor = {
      modified = { fg = "#89ddff", bold = true },
      added = { fg = "#c3e88d", ctermfg = "LightGreen" },
    }
  }
})
```

#### Log

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

#### New

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

#### Push

```lua
local cmd = require("jj.cmd")
cmd.push()                          -- Push all changes
cmd.push({ bookmark = "main" })    -- Push only main bookmark
cmd.push({ bookmark = "feature" }) -- Push only feature bookmark
```

#### Bookmarks

```lua
local cmd = require("jj.cmd")
cmd.bookmark_create()                            -- Prompts for bookmark name, then prompts the revision
cmd.bookmark_create({ prefix = "feature/" })     -- Uses prefix for default bookmark name
cmd.bookmark_move()                              -- Select bookmark, then specify new revset
cmd.bookmark_delete()                            -- Select bookmark to delete
```

You can set a default bookmark prefix in the config:

```lua
require("jj").setup({
  cmd = {
    bookmark = {
      prefix = "feature/"  -- Default prefix when creating bookmarks
    }
  }
})
```

#### Tag Management

```lua
local cmd = require("jj.cmd")
cmd.tag_set()              -- Prompts for revision and tag name
cmd.tag_set("abc123")      -- Set a tag on a specific revision (prompts for tag name)
cmd.tag_delete()           -- Select tag to delete from picker
cmd.tag_push()             -- Select tag to push from picker (prompts for remote if multiple)
```

#### Open PR/MR

```lua
local cmd = require("jj.cmd")
cmd.open_pr()                          -- Open PR for current change's bookmark
cmd.open_pr({ list_bookmarks = true }) -- Select bookmark from all and open PR
```

#### Fetch PR

```lua
local cmd = require("jj.cmd")
cmd.fetch_pr()                -- Fetch a PR with default limit
cmd.fetch_pr({ limit = 50 }) -- Fetch with fewer results in the picker
```

### Full Example

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
              close = { "q", "<Esc>", "<C-c>" }, -- Enable <Esc> in the editor
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
        editor = {
          modified = { fg = "#89ddff" },
        }
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
    vim.keymap.set("n", "<leader>jts", cmd.tag_set, { desc = "JJ tag set" })
    vim.keymap.set("n", "<leader>jtd", cmd.tag_delete, { desc = "JJ tag delete" })
    vim.keymap.set("n", "<leader>jtp", cmd.tag_push, { desc = "JJ tag push" })
    vim.keymap.set("n", "<leader>ja", cmd.abandon, { desc = "JJ abandon" })
    vim.keymap.set("n", "<leader>jf", cmd.fetch, { desc = "JJ fetch" })
    vim.keymap.set("n", "<leader>jp", cmd.push, { desc = "JJ push" })
    vim.keymap.set("n", "<leader>jpr", cmd.open_pr, { desc = "JJ open PR from bookmark in current revision or parent" })
    vim.keymap.set("n", "<leader>jpl", function()
        cmd.open_pr { list_bookmarks = true }
    end, { desc = "JJ open PR listing available bookmarks" })
    vim.keymap.set("n", "<leader>jfp", cmd.fetch_pr, { desc = "JJ fetch PR from GitHub" })


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

## FAQ

- Telescope Support? Planned but I don't use it, it's already thought of by design, will implement it at some point or if someone submits a PR I'll accept it gladly.

## Contributing

This is an early-stage project. Contributions are welcome, but please be aware that the API and features are likely to change significantly.

## License

[MIT](License)
