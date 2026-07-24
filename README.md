<h1 align="center">
  <img src="assets/jj-nvim-logo-nord.png" alt="jj.nvim logo" width="200">
  <br>
  jj.nvim
</h1>

⚠️ **WORK IN PROGRESS** ⚠️

> **Note:** This project is pre-v1. Breaking changes may occur in the configuration, API, and features until v1.0.0 is released.

`jj.nvim` brings [Jujutsu (jj)](https://github.com/jj-vcs/jj) to your editor. Execute jj commands directly from Neovim with rich UI integration, custom editors for commit messages, interactive diff viewing from the log, live rebasing with preview, status browsing with file restoration, and one-click PR/MR opening. It's jj for Neovim without leaving your workflow.

![Demo](https://github.com/NicolasGB/jj.nvim/raw/main/assets/demo.gif)

## Table of Contents

- [Current Features](#current-features)
- [Enhanced Integrations](#enhanced-integrations)
  - [View change summary from the log buffer](view-change-summary-from-the-log-buffer)
  - [Diff any change](#diff-any-change)
  - [Diff revision history](#diff-revision-history)
  - [Change the log revset from the log buffer](#change-the-log-revset-from-the-log-buffer)
  - [Describe a change](#describe-a-change)
  - [Edit changes](#edit-changes)
  - [Create new changes from the log buffer](#create-new-changes-from-the-log-buffer)
  - [Undo/Redo from the log buffer](#undoredo-from-the-log-buffer)
  - [Abandon changes from the log buffer](#abandon-changes-from-the-log-buffer)
  - [Fetch and push from the log buffer](#fetch-and-push-from-the-log-buffer)
  - [Manage bookmarks from the log buffer](#manage-bookmarks-from-the-log-buffer)
  - [Manage tags from the log buffer](#manage-tags-from-the-log-buffer)
  - [Squash changes from the log buffer](#squash-changes-from-the-log-buffer)
  - [Split changes from the log buffer](#split-changes-from-the-log-buffer)
  - [Resolve conflicts from the log buffer](#resolve-conflicts-from-the-log-buffer)
  - [Rebase changes from the log buffer](#rebase-changes-from-the-log-buffer)
  - [Duplicate changes from the log buffer](#duplicate-changes-from-the-log-buffer)
  - [Open a PR/MR from the log buffer](#open-a-prmr-from-the-log-buffer)
  - [Browse current file on remote](#browse-current-file-on-remote)
  - [Open a changed file](#open-a-changed-file)
  - [Restore a changed file](#restore-a-changed-file)
- [Installation](#installation)
- [Cmdline Usage](#cmdline-usage)
  - [Diff Commands](#diff-commands)
- [Default Config](#default-config)
- [Configuration Examples](#configuration-examples)
  - [Editor Options](#editor-options)
  - [New Command Options](#new-command-options)
  - [Resolve Command Options](#resolve-command-options)
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
- [Support](#support)

## Current Features

- Basic jj command execution through `:J` command
- Terminal-based output display for jj commands
- Support jj subcommands including your aliases through the cmdline.
- First class citizens with ui integration
  - `describe` / `desc` - Set change descriptions with a Git-style commit message editor
  - `status` / `st` - Show repository status
  - `log` - Display log history with configurable options and change the displayed revset from the log buffer
  - `diff` - Show changes with optional filtering by current file
  - `new` - Create a new change with optional parent selection
  - `edit` - Edit a change
  - `squash` - Squash the current diff to its parent or interactive squash mode from the log buffer
  - `split` - Split a change interactively in a floating terminal
  - `resolve` - Resolve conflicts interactively in a floating terminal or via external strategy
  - `rebase` - Rebase changes to a destination
  - `duplicate` - Duplicate one or more changes to a destination revision
  - `bookmark create/delete/track/forget` - Create, delete, track, and forget (untrack) bookmarks
  - `tag set/delete/push` - Create, delete, and push tags (push requires colocated repos)
  - `undo` - Undo the last operation
  - `redo` - Redo the last undone operation
  - `open_pr` - Open a PR/MR on your remote (GitHub, GitLab, Gitea, Forgejo, etc.)
  - `browse` - Open the current file on your remote at the current line (or selected range)
  - `annotate` / `annotate_line` - View file blame and line history with change ID, author, and timestamp
  - `commit` - Describe the current change and create a new one after
  - `diff_history` - Open a history-aware diff between two revisions when supported by your diff backend
  - Diff commands
  - `:Jdiff [revision]` - Vertical split diff against a jj revision
  - `:Jhdiff [revision]` - Horizontal split diff
- Picker for [Snacks.nvim](https://github.com/folke/snacks.nvim)
  - `picker.status()` displays the current changed files with live diff preview (or falls back to `vim.ui.select()`)
  - `picker.file_history()` displays the current buffer's revision history and lets you edit the selected change (or falls back to `vim.ui.select()`)
  - `picker.conflict()` lists conflicted revisions, previews their changes, and launches conflict resolution (with Snacks, or `vim.ui.select()` as a fallback)
  - `picker.conflict_sections()` lists each individual conflict section in the current revision and navigates to it in the current window, a split or a tab (with Snacks, or `vim.ui.select()` as a fallback)

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

You can diff any change in your log history by pressing `<S-d>` on its line or on a summary file change. This opens the configured diff backend for the revision under the cursor.

> [!NOTE]
> Integrates with your preferred diff plugin or uses your native jj diff config. See [Diff Module](#diff-module).

![Diff-from-log](https://github.com/NicolasGB/jj.nvim/raw/main/assets/diff-log.gif)

### Diff revision history

You can now open a history-aware diff between two revisions:

- In the log buffer, visually select multiple revisions and press `<S-h>`
- `jj.nvim` uses the first and last selected revisions as the range boundaries
- `diffview` opens `DiffviewFileHistory` for that range
- `codediff` opens `CodeDiff history` for that range
- The `native` backend currently shows a warning because history mode is not supported there yet

This is useful when you want to inspect the evolution of a stack or compare a revision range with commit history preserved instead of showing a single plain diff.

### Change the log revset from the log buffer

You can change which revset the log buffer is displaying without closing and reopening it:

- `<C-r>` - Prompt for a new revset and reload the log buffer with it

This is useful for quickly narrowing the log to something like `main::@`, `mutable()`, or any other revset while staying in the same log view.

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
- `B` - Delete a bookmark at the revision under cursor
  - If multiple bookmarks are present, select from the list or delete all of them

### Manage tags from the log buffer

- `<S-t>` - Create a new tag on the revision under cursor

Deleting and pushing tags (for colocated repositories) is also supported and changes are reflected if the log buffer is open. Set up some keybinds and you're good to go, please see [here](#tag-management-command-options).

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

### Split changes from the log buffer

Split a change into two or more revisions directly from the log buffer or the command line:

- `<C-s>` - Split the revision under cursor from the log buffer

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

### Resolve conflicts from the log buffer

Resolve conflicts for the revision under the cursor directly from the log buffer:

- `gr` - Resolve conflicts for the selected revision

How it integrates with the log buffer:

- Uses `jj resolve --revision <revset>` for the revision under cursor
- If `cmd.resolve_strategies` has more than one strategy, `vim.ui.select` prompts you to choose one
- If a strategy is selected, its `args` and `external` options are passed to `cmd.resolve(...)`
- On success, the log buffer is automatically reloaded so conflict state is refreshed
- When using floating terminals, cancelled/failed resolve attempts restore the log view

> [!NOTE]
> See the [Example config](#example-config) below for a complete `resolve_strategies` setup.

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

### Duplicate changes from the log buffer

Enter an interactive duplicate mode directly from the log buffer to duplicate one or more changes:

- `<C-y>` - Enter duplicate mode targeting the revision under cursor (in normal mode) or selected revisions (in visual mode)

Once in duplicate mode, the interface highlights your selection and the current duplicate destination:

- Selected changes are highlighted in your configured `selected_hl` color (default: dark magenta)
- The cursor position (target destination) is highlighted in your configured `targeted_hl` color (default: green)
- Move the cursor to preview different duplicate destinations with live highlighting

From duplicate mode, choose how to duplicate:

- `<CR>` or `o` - Duplicate onto (`-o`) the revision under cursor
- `a` - Duplicate after (`-A`) the revision under cursor
- `b` - Duplicate before (`-B`) the revision under cursor
- `<S-CR>` or `<S-o>` - Duplicate onto (`-o`) ignoring immutability
- `<S-a>` - Duplicate after (`-A`) ignoring immutability
- `<S-b>` - Duplicate before (`-B`) ignoring immutability
- `<Esc>` or `<C-c>` - Exit duplicate mode without making changes

**Visual mode selection:** Select multiple revisions in visual mode before pressing `<C-y>` to duplicate them all at once. The plugin extracts each selected revision and duplicates them together.

**Single revision:** In normal mode, place your cursor on a single revision and press `<C-y>` to duplicate just that change.

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

### Browse current file on remote

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

### Open or restore changed files

The `status` buffer supports these default keybindings:

- `<CR>` — Open the file under the cursor in the current window.
- `<S-x>` — Restore the file under the cursor.
- Visual mode + `<S-x>` — Restore every changed file in the selected status lines at once.

Restoring multiple files runs one `jj restore` command, refreshes the status buffer when it succeeds, and reports every restored path. Renamed files are handled correctly: both the old and new paths are restored.

![Open-status](https://github.com/NicolasGB/jj.nvim/raw/main/assets/enter-status.gif)

![Restore-status](https://github.com/NicolasGB/jj.nvim/raw/main/assets/x-status.gif)

### Status picker (Snacks.nvim)

When using the [Snacks.nvim](https://github.com/folke/snacks.nvim) picker integration, `picker.status()` opens a fuzzy-findable list of changed files with a live diff preview. Available keybindings:

- `<Enter>` - Open the selected file
- `<C-d>` - Open the selected file and run `Jdiff`

If Snacks is not enabled, `picker.status()` falls back to `vim.ui.select()`, where selecting an entry simply opens the chosen file.

### File history picker (Snacks.nvim)

`picker.file_history()` shows the current buffer's revision history.

When Snacks is enabled, you get a fuzzy picker with a diff preview for each revision. Selecting an entry edits that revision with `jj edit <rev> --ignore-immutable` and refreshes changed buffers.

If Snacks is not enabled, `picker.file_history()` falls back to `vim.ui.select()` with the same revision list. Selecting an entry performs the same edit action and buffer refresh, but without the Snacks preview UI.

### Conflict picker (Snacks.nvim)

`picker.conflict()` opens a picker for `jj log -r 'conflicts()'`, so you can resolve conflicted revisions without first navigating to them in the log buffer.

When Snacks is enabled, it uses the Snacks picker UI. Otherwise, it falls back to a plain `vim.ui.select()` picker with the same conflicted revision list.

Available actions in the Snacks picker:

- `<Enter>` - Resolve the selected conflicted revision
- `<C-e>` - Run `jj edit` on the selected conflicted revision and refresh changed buffers

What it shows:

- The conflicted revision/change id
- The author
- The first line of the description
- A live `jj show --stat --git` preview for the selected conflict

What happens on confirm:

- `<Enter>` resolves the selected conflicted revision
- If `cmd.resolve_strategies` contains multiple entries, `jj.nvim` prompts you to choose one
- The selected strategy's `args` and `external` options are forwarded to `cmd.resolve(...)`
- If no strategies are configured, it falls back to the default interactive `jj resolve`

The fallback `vim.ui.select()` version supports selecting a conflicted revision to resolve, but does not provide the extra Snacks-only `<C-e>` edit action.

This makes it easy to keep a dedicated “show me all conflicts” picker bound to a keymap, especially when using the Snacks picker UI.

### Conflict sections picker (Snacks.nvim)

`picker.conflict_sections()` lists the individual conflict sections in the current revision (`@`) so you can jump straight to a conflict and resolve it in your own editor (e.g. Neovim) instead of launching an external merge tool.

It uses the `conflicted_files()` template to find the conflicted files, then scans each file for conflict opening markers (lines starting with `<<<<<<<`) to produce one entry per conflict section, since the template does not report line numbers.

When Snacks is enabled, it uses a standard file picker, so the usual bindings apply:

- `<Enter>` - Open the conflict in the current window
- `<C-s>` - Open the conflict in a horizontal split
- `<C-v>` - Open the conflict in a vertical split
- `<C-t>` - Open the conflict in a new tab

If Snacks is not enabled, it falls back to a plain `vim.ui.select()` picker that opens the selected conflict in the current window.

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
:J push --remote origin " Push all changes to a specific remote
:J push main --remote origin " Push only main bookmark to a specific remote
:J push --deleted --remote origin " Push deleted bookmarks to a specific remote
:J fetch             " Fetch from remote
:J open_pr           " Open PR for current change's bookmark
:J open_pr --list    " Select bookmark from all and open PR
:Jbrowse             " Open current file on remote at cursor line
:Jbrowse main        " Open current file on remote at the given revset
:J split             " Split a change interactively
:J resolve           " Resolve conflicts for @
:J resolve -r abc123 --tool mergiraf --external src/ " Resolve rev/filesets with an external tool
:J resolve                                " Resolve conflicts for @
:J resolve -r abc123                      " Resolve a specific revision
:J resolve --revision abc123 src/         " Resolve only matching filesets
:J resolve --tool mergiraf --external     " Resolve using an external tool
:J resolve --tool meld --ext src/         " --ext alias + fileset filtering
:J diff_history " Prompt for a `left..right` range and open a history-aware diff
:J diff_history main..@ " Open a history-aware diff between main and the working copy
:J bookmark create/move/delete/track/forget
:J tag set " Set a tag (prompts for revision and tag name)
:J tag set abc123 " Set a tag on a specific revision
:J tag delete " Delete a tag via picker
:J tag delete v1.0 " Delete a specific tag
:J # This will use your defined default command
:J <your-alias>
:J commit " Opens your configured editor describes @ and then creates a new change -A immediately
:J commit <any text here> " Automatically describes @ and creates a new change -A immediately

```

### Diff Commands

The plugin also provides `:Jdiff`, `:Jvdiff`, and `:Jhdiff` commands for diffing against specific revisions:

```sh
:Jdiff              " Vertical diff against @- (parent)
:Jdiff @--          " Vertical diff against specific revision
:Jvdiff main        " Vertical diff against main bookmark
:Jhdiff trunk()     " Horizontal diff against trunk
```

### File Commands

Fugitive-inspired commands for viewing and editing files at specific jj revisions:

```sh
:Jread                   " Read current file at @ into current buffer (undoable)
:Jread main:src/init.lua " Read a file at a revision into the current buffer
:Jedit                   " Open current file at @ in the current window
:Jedit @--:%             " Open current file as it was at @--
:Jtabedit main:README.md " Open a file at a revision in a new tab
:Jsplit main:README.md   " Open a file at a revision in a horizontal split
:Jvsplit trunk():lua/jj/file.lua " Open a file at a revision in a vertical split
```

Target format is `<rev>:<path>`:

- `<rev>` is any valid jj revset (`@`, `main`, `@--`, `trunk()`, etc.)
- `<path>` can be `%` (current buffer file), repo-relative, or absolute
- If no argument is passed, defaults to `@:%`

The open commands (`:Jedit`, `:Jtabedit`, `:Jsplit`, `:Jvsplit`) create a `jj://<change_id>/<path>`
buffer. The revision expression is resolved to a stable change ID so the buffer name is unaffected
by bookmark movement. Mutable revisions are editable — `:w` writes the buffer back into the
revision via `jj diffedit`. Immutable revisions show an error on write.

## Default Config

```lua
{
  -- Setup snacks as a picker
  picker = {
    -- Here you can pass the options as you would for snacks.
    -- It will be used when using the picker
    snacks = {}
  },

  -- Configure editor behavior for describe/commit buffers
  editor = {
    -- When true, automatically enter insert mode only if the description is empty.
    -- If a description already exists, stay in normal mode.
    auto_insert = false,

    -- Configure the describe/commit editor buffer window
    window = {
      type = "hsplit",           -- Type of window (hsplit/vsplit/floating/tab)
      split_size = 0.5,          -- Size % of split (height for hsplit, width for vsplit)
      floating_width = 0.99,     -- Width % for floating window (0.1 to 1.0)
      floating_height = 0.95,    -- Height % for floating window (0.1 to 1.0)
    },
  },

  -- Customize syntax highlighting colors for the describe buffer
  -- Note: added, modified, deleted use Neovim's built-in highlight groups (Added, Changed, Removed)
  -- Only renamed has a custom default since Neovim doesn't have a built-in group for it
  highlights = {
    editor = {
        -- added = { fg = "#3fb950", ctermfg = "Green" },   -- Optional: override Added highlight
        -- modified = { fg = "#56d4dd", ctermfg = "Cyan" }, -- Optional: override Changed highlight
        -- deleted = { fg = "#f85149", ctermfg = "Red" },   -- Optional: override Removed highlight
        renamed = { fg = "#d29922", ctermfg = "Yellow" },   -- Renamed files (custom default)
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

    -- Configure terminal window
    window = {
       type = "hsplit",           -- Type of window the terminal is displayed in (hsplit/vsplit/floating/tab)
       split_size = 0.5,          -- Size % of the split window, either height (hsplit) or width (vsplit) (between 0.1 and 1.0)
       floating_width = 0.99,     -- Width % of the floating window (between 0.1 and 1.0)
       floating_height = 0.95,    -- Height % of the floating window (between 0.1 and 1.0)
    },
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

    -- Optional resolve strategy picker shared across cmd integrations
    resolve_strategies = {
      {
        name = "Meld",
        args = { "--tool", "meld" },
        external = true,
      },
      {
        name = "Mergiraf",
        args = { "--tool", "mergiraf" },
        external = true,
      },
    },

    -- Configure bookmark command
    bookmark = {
        prefix = ""
    },

    -- Configure keymaps for command buffers
    keymaps = {
      -- Log buffer keymaps (set to nil to disable)
      log = {
        edit = "<CR>",                      -- Edit revision under cursor
        edit_immutable = "<S-CR>",          -- Edit revision (ignore immutability)
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
        bookmark_del = "B",                 -- Delete bookmark of revision under cursor
        fetch = "f",                        -- Fetch from remote
        push = "p",                         -- Push bookmark of revision under cursor
        push_all = "<S-p>",                 -- Push all changes to remote
        open_pr = "o",                      -- Open PR/MR for revision under cursor
        open_pr_list = "<S-o>",             -- Open PR/MR by selecting from all bookmarks
        rebase = "r",                       -- Enter rebase mode targeting revision under cursor or selected revisions
        rebase_mode = {
            onto = { "<CR>", "o" },           -- Select revision under cursor as rebase onto destination
            after = "a",                      -- Rebase after revision under cursor
            before = "b",                     -- Rebase before revision under cursor
            onto_immutable = { "<S-CR>", "<S-o>" }, -- Select revision  as a rebase onto destination (ignore immutability)
            after_immutable = "<S-a>",              -- Rebase after revision under cursor (ignore immutability)
            before_immutable = "<S-b>",             -- Rebase before revision under cursor (ignore immutability)
            exit_mode = { "<Esc>", "<C-c>" }, -- Exit rebase mode
        },
        duplicate = "<C-y>",                -- Enter duplicate mode targeting revision under cursor or selected revisions
        duplicate_mode = {
            onto = { "<CR>", "o" },           -- Select revision under cursor as duplicate onto destination
            after = "a",                      -- Duplicate after revision under cursor
            before = "b",                     -- Duplicate before revision under cursor
            onto_immutable = { "<S-CR>", "<S-o>" }, -- Duplicate onto revision under cursor (ignore immutability)
            after_immutable = "<S-a>",              -- Duplicate after revision under cursor (ignore immutability)
            before_immutable = "<S-b>",             -- Duplicate before revision under cursor (ignore immutability)
            exit_mode = { "<Esc>", "<C-c>" }, -- Exit duplicate mode
        },
        squash = "s",                       -- Enter squash mode targeting revision under cursor or selected revisions
        squash_mode = {
            into = "<CR>",                     -- Squash into revision under cursor
            into_immutable = "<S-CR>",         -- Squash into revision under cursor (ignore immutability)
            exit_mode = { "<Esc>", "<C-c>" }, -- Exit squash mode
        },
        quick_squash = "<S-s>",             -- Quick squash revision under cursor into its parent (ignore immutability)
        split = "<C-s>",                    -- Split the revision under cursor
        resolve = "gr",                     -- Resolve conflicts for revision under cursor
        history = "<S-h>",                  -- Show a history-aware diff for the selected revision range
        change_revset = "<C-r>",            -- Change the revset(s) being viewed in the log buffer
        tag_set = "<S-t>",                  -- Create a tag on the revision under cursor
        summary = "<S-k>",                  -- Show summary tooltip for revision under cursor
        select_next_revision = "gj",        -- Move cursor to the next revision in the log
        select_prev_revision = "gk",        -- Move cursor to the previous revision in the log
        summary_tooltip = {
            diff = "<S-d>",                   -- Diff file at this revision
            edit = "<CR>",                    -- Edit revision and open file
            edit_immutable = "<S-CR>",        -- Edit revision (ignore immutability) and open file
            edit_file = "o",                  -- Open the file under cursor in a new tab like `:Jtabedit` would
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
        close = "q",                          -- Close floating buffer
        hide = "<Esc>",                       -- Hide floating buffer
      },
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

### Editor Options

The top-level `editor` config controls behavior for the describe/commit editor buffers.

#### `editor.auto_insert`

When `auto_insert = true`, `jj.nvim` automatically enters Insert mode when opening a describe or commit buffer **only if the description is empty**.

If the change already has a description, the buffer stays in Normal mode so you can review or edit the existing message without being dropped straight into Insert mode.

Default:

```lua
require("jj").setup({
  editor = {
    auto_insert = false,
  }
})
```

Enable smart auto-insert:

```lua
require("jj").setup({
  editor = {
    auto_insert = true,
  }
})
```

#### `editor.window`

Control where the describe/commit editor buffer opens:

- `type`: `"hsplit" | "vsplit" | "floating" | "tab"`
- `split_size`: split ratio for `hsplit`/`vsplit` (default `0.5`)
- `floating_width`: width ratio for floating windows (default `0.99`)
- `floating_height`: height ratio for floating windows (default `0.95`)

Example:

```lua
require("jj").setup({
  editor = {
    window = {
      type = "floating",
      floating_width = 0.9,
      floating_height = 0.8,
    },
  },
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
  summary = false,                     -- Show summary of changes (default: false)
  reversed = false,                    -- Reverse the log order (default: false)
  no_graph = false,                    -- Hide the graph (default: false)
  limit = 50,                          -- Optional limit; omitted by default
  revisions = "main::@",               -- Optional revset
  raw_flags = { "-r", "main::@" }      -- Optional raw argv flags for `jj log`
})

-- Examples:
cmd.log({ limit = 50 })
cmd.log({ revisions = "main::@" })
cmd.log({ summary = true, limit = 100 })
cmd.log({ raw_flags = { "-r", "main::@", "--summary", "--no-graph" } })
```

> [!IMPORTANT]
> Breaking change: `cmd.log` now expects `raw_flags` as a `string[]` argv list.
> The old `raw = "..."` string format is no longer supported.

## Configuration Examples

### New Command Options

The `new` function accepts an options table:

```lua
local cmd = require("jj.cmd")
cmd.new({
  show_log = false,                  -- Display log after creating new change (default: false)
  with_input = false,                -- Prompt for parent revision (default: false)
  args = { "--before", "@" }         -- Additional argv arguments passed to `jj new`
})

-- Examples:
cmd.new({ show_log = true })
cmd.new({ show_log = true, with_input = true })
cmd.new({ args = { "--before", "@" } })
```

> [!IMPORTANT]
> Breaking change: `cmd.new` now expects `args` as a `string[]` argv list.
> The old `args = "--before @"` string format is no longer supported.

### Resolve Command Options

The `resolve` function accepts an options table:

```lua
local cmd = require("jj.cmd")
cmd.resolve({
  rev = "@",                    -- Revision to resolve (default: "@")
  filesets = { "src/" },        -- Optional filesets to limit what gets resolved
  args = { "--tool", "meld" }, -- Extra args passed to `jj resolve`
  external = true,               -- Run as an external command instead of in an nvim floating terminal
})

-- Examples:
cmd.resolve()                                                -- Resolve @ in floating terminal
cmd.resolve({ rev = "abc123" })                            -- Resolve a specific revision
cmd.resolve({ rev = "abc123", filesets = { "lua/" } })    -- Resolve only selected filesets
cmd.resolve({ external = true, args = { "--tool", "kdiff3" } }) -- Use an external merge tool
```

When called from the log buffer via `gr`, `jj.nvim` can optionally prompt for a strategy using `cmd.resolve_strategies`.

> [!NOTE]
> See [Example config](#example-config) for a full `cmd.resolve_strategies` example.

CLI flags for `:J resolve`:

- `-r <rev>` or `--revision <rev>`: target revision (default: `@`)
- `--tool <name>`: pass merge tool to `jj resolve`
- `--external` or `--ext`: run outside the floating terminal
- trailing positional args are treated as filesets
- unknown long options are rejected to avoid ambiguity with filesets

### Push Command Options

The `push` function accepts an options table:

```lua
local cmd = require("jj.cmd")
cmd.push({
  bookmark = "main",    -- Push specific bookmark (default: all changes)
  remote = "origin",    -- Optional target remote
  -- deleted = true,     -- Push deleted bookmarks instead of a bookmark
})

-- Examples:
cmd.push()                               -- Push all changes
cmd.push({ bookmark = "main" })         -- Push only main bookmark
cmd.push({ bookmark = "feature" })      -- Push only feature bookmark
cmd.push({ remote = "origin" })         -- Push all changes to a specific remote
cmd.push({ bookmark = "main", remote = "origin" }) -- Push only main to a specific remote
cmd.push({ deleted = true, remote = "origin" })     -- Push deleted bookmarks to a specific remote
```

The `:J push` command also supports these forms:

```sh
:J push --remote origin
:J push main --remote origin
:J push --deleted --remote origin
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

The `bookmark_track` function tracks an untracked bookmark:

```lua
local cmd = require("jj.cmd")
cmd.bookmark_track()  -- Select bookmark to track
```

The `bookmark_forget` function forgets a bookmark (untracks it locally):

```lua
local cmd = require("jj.cmd")
cmd.bookmark_forget()  -- Select bookmark to forget/untrack
```

### Tag Management Command Options

The `tag_set` function creates a tag on a revision:

```lua
local cmd = require("jj.cmd")
cmd.tag_set()              -- Prompts for revision and tag name
cmd.tag_set("abc123")      -- Set a tag on a specific revision (prompts for tag name)
```

The `tag_delete` function deletes a tag via picker:

```lua
local cmd = require("jj.cmd")
cmd.tag_delete()           -- Select tag to delete from picker
```

The `tag_push` function pushes a tag to a remote (colocated repositories only):

```lua
local cmd = require("jj.cmd")
cmd.tag_push()             -- Select tag to push from picker (prompts for remote if multiple)
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

-- Open a history-aware diff between two revisions
-- Supported by the `diffview` and `codediff` backends
-- The `native` backend currently warns instead
diff.diff_history_revisions({ left = "main", right = "@" })

-- Convenience functions (LEGACY FUNCTIONS)
diff.open_vdiff()                   -- Vertical split diff against parent
diff.open_vdiff({ rev = "main" })   -- Vertical split against specific revision
diff.open_hdiff()                   -- Horizontal split diff
diff.open_hdiff({ rev = "@-2" })    -- Horizontal split against @-2
```

#### Log Buffer Integration

The diff module integrates seamlessly with the log buffer:

- `<S-d>` - Show diff for the revision under cursor in a floating window
- `<S-h>` - In visual mode, open a history-aware diff for the first and last selected revisions

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

  -- Open a history-aware diff between two revisions
  diff_history_revisions = function(opts)
    -- opts.left: left/base revision
    -- opts.right: right/target revision
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

All four backend functions are optional—missing ones fall back to the `native` implementation.

### File Module

The file module provides file-at-revision workflows similar to Fugitive's `Gread`/`Gedit`.

```lua
local file = require("jj.file")

-- Read a file from a revision into the current buffer (undoable)
file.read_target({ rev = "main", path = "lua/jj/init.lua" })
file.read_target({ rev = "@--", path = "%" }) -- current file at @--

-- Open buffers at a given revision
file.open_target({ rev = "main", path = "README.md" })                -- current window (default)
file.open_target({ rev = "@", path = "%", split = "horizontal" })    -- split
file.open_target({ rev = "trunk()", path = "%", split = "vertical" }) -- vsplit
file.open_target({ rev = "@--", path = "%", split = "tab" })          -- new tab
```

`split` accepts: `"current"` (default), `"tab"`, `"horizontal"`, or `"vertical"`.

Annotate also works from `jj://` virtual buffers and resolves the revision and path automatically.

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
              close = { "q", "<Esc>", "<C-c>" }, -- Enable <Esc> in the editor
            }
          }
        },
        bookmark = {
            prefix = "feat/"
        },
        resolve_strategies = {
          {
            name = "Meld",
            args = { "--tool", "meld" },
            external = true,
          },
          {
            name = "Mergiraf",
            args = { "--tool", "mergiraf" },
            external = true,
          },
        },
        keymaps = {
          log = {
            edit = "<CR>",
            describe = "d",
            diff = "<S-d>",
            abandon = "<S-a>",
            fetch = "<S-f>",
            resolve = "gr",  -- Resolve conflicts for revision under cursor
          },
          status = {
            open_file = "<CR>",
            restore_file = "<S-x>",
          },
          close = { "q", "<Esc>" },
        },
      },
      highlights = {
        editor = {
          -- Customize colors if desired
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


    -- Diff commands
    local diff = require("jj.diff")
    vim.keymap.set("n", "<leader>df", function() diff.open_vdiff() end, { desc = "JJ diff current buffer" })
    vim.keymap.set("n", "<leader>dF", function() diff.open_hdiff() end, { desc = "JJ hdiff current buffer" })

    -- Pickers
    local picker = require("jj.picker")
    vim.keymap.set("n", "<leader>gj", function() picker.status() end, { desc = "JJ Picker status" })
    vim.keymap.set("n", "<leader>jgh", function() picker.file_history() end, { desc = "JJ Picker history" })
    vim.keymap.set("n", "<leader>jgc", function() picker.conflict() end, { desc = "JJ Picker conflicts" })
    vim.keymap.set("n", "<leader>jgs", function() picker.conflict_sections() end, { desc = "JJ Picker conflict sections" })

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

## Support

If `jj.nvim` improves your workflow, consider supporting its development.

Your support helps me spend more time improving the plugin, fixing bugs, and adding new features.

<a href="https://buymeacoffee.com/nicolasgb" target="_blank">
  <img src="https://img.buymeacoffee.com/button-api/?text=Buy+me+a+coffee&emoji=☕&slug=nicolasgb&button_colour=FFDD00&font_colour=000000&font_family=Poppins&outline_colour=000000&coffee_colour=ffffff" alt="Buy Me A Coffee" height="50">
</a>

If you can't contribute financially, starring the repository and sharing it with other Jujutsu users is just as appreciated.
