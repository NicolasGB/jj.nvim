-- Real jj fixtures; only UI prompts and external diff integrations are mocked.
return function(run_test, eq)
	local cmd = require("jj.cmd")
	local log = require("jj.cmd.log")
	local terminal = require("jj.ui.terminal")
	local context = require("jj.core.context")
	local utils = require("jj.utils")
	local diff = require("jj.diff")
	local file = require("jj.file")
	local annotate = require("jj.annotate")
	local function wait_for(fn)
		assert(vim.wait(5000, fn, 10), "timed out waiting for jj operation")
	end
	local function fixture(name, fn)
		run_test("cwd: " .. name, function()
			local base = vim.fn.tempname() .. " project with spaces"
			local outer, inner = base .. "/outer", base .. "/outer/fms-insight"
			local saved_cwd, saved_config = vim.fn.getcwd(), vim.env.JJ_CONFIG
			local saved_select, saved_input, saved_notify = vim.ui.select, vim.ui.input, vim.notify
			vim.fn.mkdir(inner, "p")
			vim.fn.writefile({ "[user]", 'name = "Cwd Test"', 'email = "cwd@example.com"' }, base .. "/config.toml")
			vim.env.JJ_CONFIG = base .. "/config.toml"
			local function jj(cwd, ...)
				local result = vim.system(vim.list_extend({ "jj" }, { ... }), { cwd = cwd, text = true }):wait()
				assert(result.code == 0, result.stderr)
				return vim.trim(result.stdout)
			end
			local function id(cwd)
				return jj(cwd, "log", "--no-graph", "-r", "@", "-T", "commit_id")
			end
			local errors = {}
			local ok, err = xpcall(function()
				jj(outer, "git", "init", "--colocate")
				vim.fn.writefile({ "/fms-insight/" }, outer .. "/.gitignore")
				vim.fn.writefile({ "outer file" }, outer .. "/same file.txt")
				jj(outer, "describe", "-m", "OUTER repository")
				jj(inner, "git", "init", "--colocate")
				vim.fn.writefile({ "inner file" }, inner .. "/same file.txt")
				vim.fn.mkdir(inner .. "/sub", "p")
				jj(inner, "describe", "-m", "INNER repository")
				require("jj").setup({
					terminal = { window = { type = "hsplit" } },
					cmd = { describe = { editor = { type = "buffer" } } },
				})
				vim.notify = function(message, level)
					if level == vim.log.levels.ERROR then
						table.insert(errors, message)
					end
				end
				vim.cmd("tabnew")
				vim.cmd("tcd " .. vim.fn.fnameescape(outer))
				local function open(opts, description)
					cmd.log(opts)
					wait_for(function()
						return terminal.state.buf
							and terminal.state.buf_cmd == "log"
							and table
								.concat(vim.api.nvim_buf_get_lines(terminal.state.buf, 0, -1, false), "\n")
								:find(description, 1, true)
					end)
					vim.api.nvim_win_set_cursor(0, { 1, 0 })
					return terminal.state.buf
				end
				fn({ outer = outer, inner = inner, base = base, jj = jj, id = id, open = open, errors = errors })
			end, debug.traceback)
			vim.ui.select, vim.ui.input, vim.notify = saved_select, saved_input, saved_notify
			terminal.close_tooltip()
			terminal.close_terminal_buffer()
			terminal.close_floating_buffer()
			vim.cmd("silent! tabonly!")
			vim.cmd("silent! only!")
			vim.cmd("enew!")
			vim.cmd("cd " .. vim.fn.fnameescape(saved_cwd))
			vim.env.JJ_CONFIG = saved_config
			vim.fn.delete(base, "rf")
			if not ok then
				error(err)
			end
		end)
	end

	run_test("revision URI round-trips directory and relative path with reserved characters", function()
		local cwd, path = "/tmp/project with % and #/sub", "../same % file.txt"
		local rev, parsed_path, parsed_cwd = utils.parse_jj_uri(utils.jj_uri("abcd", path, cwd))
		eq("abcd", rev)
		eq(path, parsed_path)
		eq(cwd, parsed_cwd)
	end)
	run_test("revision URI parser preserves legacy directory-less paths", function()
		for _, path in ipairs({ "src/same file.txt", "cwd=config/file%.txt" }) do
			local rev, parsed_path, cwd = utils.parse_jj_uri("jj://abcd/" .. path)
			eq("abcd", rev)
			eq(path, parsed_path)
			eq(nil, cwd)
		end
	end)
	fixture("default uses invoking tab directory", function(f)
		local buf = f.open(nil, "OUTER repository")
		eq(f.outer, context.from_buffer(buf).cwd)
		eq(f.outer, vim.fn.getcwd())
	end)
	for _, relative in ipairs({ false, true }) do
		fixture((relative and "relative" or "absolute") .. " nested directory with spaces", function(f)
			local before = f.id(f.outer)
			local buf = f.open(
				{ cwd = relative and "fms-insight" or f.inner, revisions = "@", limit = 4, summary = true },
				"INNER repository"
			)
			eq(f.outer, vim.fn.getcwd())
			eq(f.inner, context.from_buffer(buf).cwd)
			local old = f.id(f.inner)
			log.handle_log_new()
			wait_for(function()
				return f.id(f.inner) ~= old
			end)
			wait_for(function()
				return terminal.state.buf ~= buf and terminal.state.buf_cmd == "log"
			end)
			eq(before, f.id(f.outer), "outer commit must be unchanged")
			local ctx = context.from_buffer(terminal.state.buf)
			eq(f.inner, ctx.cwd)
			eq("@", ctx.log_opts.revisions)
			eq(4, ctx.log_opts.limit)
			eq(true, ctx.log_opts.summary)
			wait_for(function()
				return require("jj.core.parser").get_all_revsets(
					vim.api.nvim_buf_get_lines(terminal.state.buf, 0, -1, false)
				)[1] ~= nil
			end)
			local rendered = vim.api.nvim_buf_get_lines(terminal.state.buf, 0, -1, false)
			eq(1, #require("jj.core.parser").get_all_revsets(rendered))
			eq(nil, table.concat(rendered, "\n"):find("INNER repository", 1, true))
		end)
	end
	fixture("omitted cwd captures window-local directory", function(f)
		vim.cmd("lcd " .. vim.fn.fnameescape(f.inner))
		f.open(nil, "INNER repository")
		eq(f.inner, context.from_buffer().cwd)
	end)
	fixture("fresh default log after inner uses invoking outer directory", function(f)
		f.open({ cwd = f.inner }, "INNER repository")
		f.open(nil, "OUTER repository")
		eq(f.outer, context.from_buffer().cwd)
	end)
	fixture("delayed bookmark prompts stay in original repo after another log opens", function(f)
		f.open({ cwd = "fms-insight", revisions = "@" }, "INNER repository")
		local select_cb, input_cb
		vim.ui.select = function(_, _, cb)
			select_cb = cb
		end
		vim.ui.input = function(_, cb)
			input_cb = cb
		end
		log.handle_log_bookmark()
		assert(select_cb)
		f.open(nil, "OUTER repository")
		vim.cmd("tcd " .. vim.fn.fnameescape(f.base))
		select_cb("[Create new]")
		assert(input_cb)
		input_cb("inner-only")
		wait_for(function()
			return f.jj(f.inner, "bookmark", "list"):find("inner-only", 1, true)
		end)
		wait_for(function()
			return context.from_buffer(terminal.state.buf).cwd == f.inner
		end)
		eq("", f.jj(f.outer, "bookmark", "list"))
		eq("@", context.from_buffer(terminal.state.buf).log_opts.revisions)
	end)
	fixture("description editor save retains repository after directory change", function(f)
		f.open({ cwd = f.inner }, "INNER repository")
		local editor = require("jj.ui.editor")
		local saved = editor.open_editor
		local save, close
		editor.open_editor = function(_, on_save, on_close)
			save, close = on_save, on_close
		end
		local ok, err = pcall(log.handle_log_describe)
		editor.open_editor = saved
		assert(ok, err)
		assert(
			save,
			vim.inspect({ errors = f.errors, line = vim.api.nvim_get_current_line(), cfg = cmd.config.describe })
		)
		vim.cmd("tcd " .. vim.fn.fnameescape(f.base))
		save({ "INNER saved later" })
		eq("INNER saved later", f.jj(f.inner, "log", "--no-graph", "-r", "@", "-T", "description"))
		eq("OUTER repository", f.jj(f.outer, "log", "--no-graph", "-r", "@", "-T", "description"))
		close()
		wait_for(function()
			return terminal.state.buf and context.from_buffer(terminal.state.buf).cwd == f.inner
		end)
	end)
	fixture("summary file open uses inner path despite outer cwd", function(f)
		f.open({ cwd = f.inner }, "INNER repository")
		-- Simulate the file line of the tooltip, with its originating context.
		local buf = vim.api.nvim_create_buf(false, true)
		context.attach(buf, context.from_buffer())
		vim.cmd("new")
		vim.api.nvim_win_set_buf(0, buf)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "A same file.txt" })
		log.handle_summary_edit("@", false)
		wait_for(function()
			return vim.api.nvim_buf_get_name(0) == f.inner .. "/same file.txt"
		end)
		eq("inner file", vim.api.nvim_buf_get_lines(0, 0, 1, false)[1])
		eq(f.inner, context.from_buffer().cwd)
		diff.diff_current({ backend = "native" })
		eq(f.inner, context.from_buffer().cwd)
		vim.cmd("tabnew")
		vim.wait(20)
	end)
	fixture("historical file reload and deferred write use command cwd below workspace root", function(f)
		local before = f.id(f.outer)
		file.open_target({ cwd = f.inner .. "/sub", path = "../same file.txt", rev = "@", split = "tab" })
		local buf = vim.api.nvim_get_current_buf()
		eq("inner file", vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
		vim.cmd("tcd " .. vim.fn.fnameescape(f.outer))
		vim.cmd("edit!")
		eq("inner file", vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "inner historical edit" })
		vim.cmd("write")
		eq(false, vim.bo[buf].modified)
		eq("inner historical edit", f.jj(f.inner, "file", "show", "same file.txt"))
		eq(before, f.id(f.outer))
	end)
	fixture("native diff keeps file and historical side in inner repository", function(f)
		f.jj(f.inner, "new", "-m", "INNER child")
		vim.fn.writefile({ "inner changed" }, f.inner .. "/same file.txt")
		diff.diff_current({ cwd = f.inner, path = "same file.txt", backend = "native" })
		eq("inner file", vim.api.nvim_buf_get_lines(0, 0, 1, false)[1])
		eq(f.inner, context.from_buffer().cwd)
		eq(f.outer, vim.fn.getcwd())
		vim.cmd("tabnew") -- leave cleanup callbacks to drain before fixture teardown
		vim.wait(20)
	end)
	for _, kind in ipairs({ "revision", "revisions", "history", "current" }) do
		fixture("Diffview " .. kind .. " selects inner repository and preserves spaced paths", function(f)
			f.open({ cwd = f.inner }, "INNER repository")
			local saved = package.loaded.diffview
			vim.api.nvim_create_user_command("DiffviewToggleFiles", function() end, {})
			local received
			package.loaded.diffview = {
				open = function(args)
					received = args
				end,
				file_history = function(_, args)
					received = args
				end,
			}
			local ok, err = pcall(
				diff.open,
				kind,
				{ backend = "diffview", cwd = f.inner, rev = "@", left = "@", right = "@-", path = "same file.txt" }
			)
			package.loaded.diffview = saved
			vim.api.nvim_del_user_command("DiffviewToggleFiles")
			assert(ok, err)
			assert(received)
			eq("-C" .. f.inner, received[1])
			assert(received[2]:find(utils.get_commit_id("@", f.inner), 1, true))
			eq(f.inner .. "/same file.txt", received[#received])
			eq(f.outer, vim.fn.getcwd())
		end)
	end
	fixture("tooltip queries and replacement stay in originating repository", function(f)
		f.open({ cwd = f.inner }, "INNER repository")
		-- Headless Neovim has no attached screen; supply cursor screen coordinates.
		local row, col = vim.fn.screenrow, vim.fn.screencol
		vim.fn.screenrow, vim.fn.screencol = function()
			return 1
		end, function()
			return 1
		end
		local ok, err = pcall(log.handle_log_summary)
		vim.fn.screenrow, vim.fn.screencol = row, col
		assert(ok, err)
		terminal.keep_tooltip_open(true)
		wait_for(function()
			local buf = terminal.state.tooltip_buf
			return buf
				and table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"):find("INNER repository", 1, true)
		end)
		eq(f.inner, context.from_buffer(terminal.state.tooltip_buf).cwd)
		eq(f.outer, vim.fn.getcwd())
		local old = terminal.state.tooltip_buf
		terminal.run_tooltip({ "jj", "root" }, { cwd = f.inner })
		terminal.keep_tooltip_open(true)
		wait_for(function()
			return table
				.concat(vim.api.nvim_buf_get_lines(terminal.state.tooltip_buf, 0, -1, false), "\n")
				:find(f.inner, 1, true)
		end)
		eq(false, vim.api.nvim_buf_is_valid(old))
	end)
	fixture("undo and redo from log preserve inner repository and revset", function(f)
		local outer_before, inner_before = f.id(f.outer), f.id(f.inner)
		f.open({ cwd = f.inner, revisions = "@", limit = 2 }, "INNER repository")
		log.handle_log_new()
		wait_for(function()
			return f.id(f.inner) ~= inner_before
		end)
		local created = f.id(f.inner)
		wait_for(function()
			return terminal.state.buf_cmd == "log"
		end)
		cmd.undo()
		wait_for(function()
			return f.id(f.inner) == inner_before
		end)
		wait_for(function()
			return terminal.state.buf_cmd == "log"
		end)
		cmd.redo()
		wait_for(function()
			return f.id(f.inner) == created
		end)
		eq(outer_before, f.id(f.outer))
		eq("@", context.from_buffer(terminal.state.buf).log_opts.revisions)
	end)
	fixture("tag input callback targets original repository", function(f)
		f.open({ cwd = f.inner }, "INNER repository")
		local answer
		vim.ui.input = function(_, cb)
			answer = cb
		end
		log.handle_log_tag_set()
		f.open(nil, "OUTER repository")
		answer("inner-tag")
		wait_for(function()
			return f.jj(f.inner, "tag", "list"):find("inner-tag", 1, true)
		end)
		eq("", f.jj(f.outer, "tag", "list"))
	end)
	fixture("fetch preparatory query and delayed remote selection use inner repository", function(f)
		f.jj(f.inner, "git", "remote", "add", "inner-one", f.base .. "/unused-one")
		f.jj(f.inner, "git", "remote", "add", "inner-two", f.base .. "/unused-two")
		f.open({ cwd = f.inner }, "INNER repository")
		local choose, choices
		vim.ui.select = function(items, _, cb)
			choices, choose = items, cb
		end
		log.handle_log_fetch()
		assert(choose, "must query the inner repo's remotes")
		eq("inner-one", choices[1].name)
		f.open(nil, "OUTER repository")
		local runner = require("jj.core.runner")
		local saved = runner.execute_async
		local root
		runner.execute_async = function(argv, done, _, _, _, _, opts)
			eq("fetch", argv[3])
			-- Verify repository identity using the same execution options, without networking.
			root = vim.trim(vim.system({ "jj", "root" }, { cwd = opts.cwd, text = true }):wait().stdout)
			done("")
		end
		local ok, err = pcall(choose, choices[2])
		runner.execute_async = saved
		assert(ok, err)
		eq(f.inner, root)
	end)
	fixture("status and restore operate on inner file after directory changes", function(f)
		f.jj(f.inner, "new")
		vim.fn.writefile({ "inner modified" }, f.inner .. "/same file.txt")
		cmd.status({ cwd = f.inner })
		wait_for(function()
			return terminal.state.buf_cmd == "status"
				and table
					.concat(vim.api.nvim_buf_get_lines(terminal.state.buf, 0, -1, false), "\n")
					:find("M same file.txt", 1, true)
		end)
		local lines = vim.api.nvim_buf_get_lines(terminal.state.buf, 0, -1, false)
		for i, line in ipairs(lines) do
			if line:find("M same file.txt", 1, true) then
				vim.api.nvim_win_set_cursor(0, { i, 0 })
			end
		end
		vim.cmd("tcd " .. vim.fn.fnameescape(f.base))
		cmd.config.confirm_destructive_actions = false
		require("jj.cmd.status").handle_status_restore()
		assert(
			#f.errors == 0,
			vim.inspect({ errors = f.errors, lines = lines, current = vim.api.nvim_get_current_line() })
		)
		eq(
			"inner file",
			f.jj(f.inner, "file", "show", "same file.txt"),
			vim.inspect({ lines = lines, current = vim.api.nvim_get_current_line() })
		)
		eq("outer file", f.jj(f.outer, "file", "show", "same file.txt"))
	end)
	for _, interactive in ipairs({ false, true }) do
		fixture(
			(interactive and "interactive" or "rendered") .. " floating terminal runs in inner repository",
			function(f)
				local done
				terminal.run_floating({ "jj", "describe", "-m", "INNER terminal" }, nil, {
					cwd = f.inner,
					interactive = interactive,
					on_exit = function(code)
						done = code
					end,
				})
				vim.cmd("tcd " .. vim.fn.fnameescape(f.base))
				wait_for(function()
					return done ~= nil
				end)
				eq(0, done)
				eq("INNER terminal", f.jj(f.inner, "log", "--no-graph", "-r", "@", "-T", "description"))
				eq("OUTER repository", f.jj(f.outer, "log", "--no-graph", "-r", "@", "-T", "description"))
			end
		)
	end
	fixture("interactive completion can reopen a floating log in the selected repository", function(f)
		require("jj").setup({ terminal = { window = { type = "floating" } } })
		terminal.run_floating({ "jj", "describe", "-m", "INNER terminal return" }, nil, {
			cwd = f.inner,
			interactive = true,
			on_exit = function(code)
				eq(0, code)
				cmd.log({ cwd = f.inner, revisions = "@" })
			end,
		})
		wait_for(function()
			local buf = terminal.state.buf
			return buf
				and vim.api.nvim_buf_is_valid(buf)
				and table
					.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
					:find("INNER terminal return", 1, true)
		end)
		eq(f.inner, context.from_buffer(terminal.state.buf).cwd)
		eq(f.outer, vim.fn.getcwd())
	end)
	fixture("native diff from a subdirectory resolves sibling workspace paths", function(f)
		f.jj(f.inner, "new", "-m", "INNER child")
		diff.diff_current({ cwd = f.inner .. "/sub", path = "../same file.txt", backend = "native" })
		eq("inner file", vim.api.nvim_buf_get_lines(0, 0, 1, false)[1])
		eq(f.inner .. "/sub", context.from_buffer().cwd)
		vim.cmd("tabnew")
		vim.wait(20)
	end)
	fixture("CodeDiff receives repository path with spaces as one argument", function(f)
		f.open({ cwd = f.inner }, "INNER repository")
		local saved = package.loaded.codediff
		local args
		package.loaded.codediff = {}
		vim.api.nvim_create_user_command("CodeDiff", function(opts)
			args = opts.fargs
		end, { nargs = "*" })
		local ok, err = pcall(diff.show_revision, { rev = "@", backend = "codediff", cwd = f.inner })
		package.loaded.codediff = saved
		vim.api.nvim_del_user_command("CodeDiff")
		assert(ok, err)
		assert(args)
		eq("--repo", args[#args - 1])
		eq(f.inner, args[#args])
		eq(utils.get_commit_id("@-", f.inner), args[1])
		eq(f.outer, vim.fn.getcwd())
	end)
	fixture("native working-file side retains context for a later Jdiff", function(f)
		f.jj(f.inner, "new", "-m", "INNER child")
		vim.fn.writefile({ "inner changed" }, f.inner .. "/same file.txt")
		diff.diff_current({ cwd = f.inner, path = "same file.txt", backend = "native" })
		local historical_win = vim.api.nvim_get_current_win()
		local working_win
		for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
			if vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)) == f.inner .. "/same file.txt" then
				working_win = win
			end
		end
		assert(working_win)
		vim.api.nvim_win_close(historical_win, true)
		vim.wait(20)
		vim.api.nvim_set_current_win(working_win)
		eq(f.outer, vim.fn.getcwd())
		vim.cmd("Jdiff")
		eq("inner file", vim.api.nvim_buf_get_lines(0, 0, 1, false)[1])
		eq(f.inner, context.from_buffer().cwd)
		vim.cmd("tabnew")
		vim.wait(20)
	end)
	for _, backend in ipairs({ "file", "native" }) do
		fixture(
			backend .. " revision buffers distinguish identical relative paths in different directories",
			function(f)
				vim.fn.writefile({ "inner sub file" }, f.inner .. "/sub/same file.txt")
				local outer_before = f.id(f.outer)
				local function open(cwd)
					if backend == "file" then
						file.open_target({ cwd = cwd, path = "same file.txt", rev = "@", split = "tab" })
					else
						vim.cmd("tabnew")
						diff.diff_current({ cwd = cwd, path = "same file.txt", rev = "@", backend = "native" })
					end
					return vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
				end
				local first, first_win = open(f.inner)
				local second, second_win = open(f.inner .. "/sub")
				local first_name, second_name = vim.api.nvim_buf_get_name(first), vim.api.nvim_buf_get_name(second)
				assert(first_name ~= "" and second_name ~= "", "both historical buffers must be named")
				assert(first_name ~= second_name, "different files must have distinct historical names")
				eq("inner file", vim.api.nvim_buf_get_lines(first, 0, 1, false)[1])
				eq("inner sub file", vim.api.nvim_buf_get_lines(second, 0, 1, false)[1])
				for _, entry in ipairs({ { first, first_win, "inner file" }, { second, second_win, "inner sub file" } }) do
					vim.api.nvim_set_current_win(entry[2])
					vim.cmd("tcd " .. vim.fn.fnameescape(f.outer))
					vim.cmd("edit!")
					eq(entry[3], vim.api.nvim_buf_get_lines(entry[1], 0, 1, false)[1])
				end
				vim.api.nvim_buf_set_lines(second, 0, -1, false, { "sub historical write" })
				vim.cmd("write")
				eq(false, vim.bo[second].modified)
				eq("sub historical write", f.jj(f.inner, "file", "show", "sub/same file.txt"))
				eq("inner file", f.jj(f.inner, "file", "show", "same file.txt"))
				eq(outer_before, f.id(f.outer))
				vim.cmd("tabnew")
				vim.wait(20)
			end
		)
	end
	fixture("historical URI reopens a wiped buffer from outside its repository", function(f)
		vim.fn.writefile({ "inner sub file" }, f.inner .. "/sub/same file.txt")
		file.open_target({ cwd = f.inner .. "/sub", path = "same file.txt", rev = "@", split = "tab" })
		local buf = vim.api.nvim_get_current_buf()
		local name = vim.api.nvim_buf_get_name(buf)
		vim.api.nvim_buf_delete(buf, { force = true })
		vim.cmd("tcd " .. vim.fn.fnameescape(f.outer))
		vim.cmd("edit " .. vim.fn.fnameescape(name))
		eq("inner sub file", vim.api.nvim_buf_get_lines(0, 0, 1, false)[1])
		eq(f.inner .. "/sub", context.from_buffer().cwd)
		vim.api.nvim_buf_set_lines(0, 0, -1, false, { "reopened sub file" })
		vim.cmd("write")
		eq("reopened sub file", f.jj(f.inner, "file", "show", "sub/same file.txt"))
		eq("outer file", f.jj(f.outer, "file", "show", "same file.txt"))
	end)
	fixture("file annotations and their diff action retain historical repository context", function(f)
		vim.fn.writefile({ "inner annotated line" }, f.inner .. "/sub/same file.txt")
		local short_id = f.jj(f.inner, "log", "--no-graph", "-r", "@", "-T", "change_id.short(6)")
		file.open_target({ cwd = f.inner .. "/sub", path = "same file.txt", rev = "@", split = "tab" })
		local source = vim.api.nvim_get_current_buf()
		eq(f.outer, vim.fn.getcwd())
		annotate.file()
		local annotations = vim.api.nvim_get_current_buf()
		assert(annotations ~= source, vim.inspect(f.errors))
		assert(vim.api.nvim_buf_get_lines(annotations, 0, 1, false)[1]:find(short_id, 1, true))
		vim.cmd("tcd " .. vim.fn.fnameescape(f.base))
		local enter
		for _, keymap in ipairs(vim.api.nvim_buf_get_keymap(annotations, "n")) do
			if keymap.lhs == "<CR>" then
				enter = keymap.callback
			end
		end
		assert(enter)
		enter()
		local output = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
		assert(output:find("+inner annotated line", 1, true), vim.inspect(f.errors))
		eq(f.inner .. "/sub", context.from_buffer().cwd)
	end)
	fixture("line annotation queries the historical revision and description in its repository", function(f)
		file.open_target({ cwd = f.inner, path = "same file.txt", rev = "@", split = "tab" })
		local source = vim.api.nvim_get_current_buf()
		vim.b[source].jj_context = nil -- Exercise URI context recovery as well.
		annotate.line()
		local tooltip
		for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
			local buf = vim.api.nvim_win_get_buf(win)
			if buf ~= source and vim.api.nvim_win_get_config(win).relative ~= "" then
				tooltip = buf
			end
		end
		assert(tooltip, vim.inspect(f.errors))
		local text = table.concat(vim.api.nvim_buf_get_lines(tooltip, 0, -1, false), "\n")
		assert(text:find("INNER repository", 1, true), text)
		eq(f.inner, context.from_buffer(tooltip).cwd)
		eq(f.outer, vim.fn.getcwd())
	end)
	fixture("line annotation does not reuse another repository's tooltip", function(f)
		file.open_target({ cwd = f.inner, path = "same file.txt", rev = "@", split = "tab" })
		local source_win = vim.api.nvim_get_current_win()
		annotate.line()
		local inner_tooltip
		for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
			if vim.api.nvim_win_get_config(win).relative ~= "" then
				inner_tooltip = vim.api.nvim_win_get_buf(win)
			end
		end
		assert(inner_tooltip)
		-- Keep the existing tooltip alive while preparing a different source.
		vim.api.nvim_set_current_win(source_win)
		file.open_target({ cwd = f.outer, path = "same file.txt", rev = "@", split = "tab" })
		annotate.line()
		eq(false, vim.api.nvim_buf_is_valid(inner_tooltip))
		local outer_tooltip
		for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
			if vim.api.nvim_win_get_config(win).relative ~= "" then
				outer_tooltip = vim.api.nvim_win_get_buf(win)
			end
		end
		assert(outer_tooltip)
		local text = table.concat(vim.api.nvim_buf_get_lines(outer_tooltip, 0, -1, false), "\n")
		assert(text:find("OUTER repository", 1, true), text)
		eq(f.outer, context.from_buffer(outer_tooltip).cwd)
	end)
	local function remote(f, name, url, commit)
		f.jj(f.inner, "git", "remote", "add", name, url)
		local result = vim.system(
			{ "git", "update-ref", "refs/remotes/" .. name .. "/main", commit },
			{ cwd = f.inner, text = true }
		):wait()
		assert(result.code == 0, result.stderr)
		f.jj(f.inner, "git", "import")
		f.jj(f.inner, "bookmark", "track", "main@" .. name)
	end
	for _, mode in ipairs({ "single", "delayed", "fallback" }) do
		fixture(
			"browse " .. mode .. " resolves historical paths, remotes, and revisions in the inner repository",
			function(f)
				vim.fn.writefile({ "inner browsed line" }, f.inner .. "/sub/same file.txt")
				local commit = f.id(f.inner)
				remote(f, "origin", "https://github.com/example/inner.git", commit)
				if mode == "delayed" then
					remote(f, "mirror", "https://gitlab.com/example/inner.git", commit)
				end
				if mode == "fallback" then
					f.jj(f.inner, "new", "-m", "unpublished child")
				end
				file.open_target({ cwd = f.inner .. "/sub", path = "same file.txt", rev = "@", split = "tab" })
				local buf = vim.api.nvim_get_current_buf()
				vim.b[buf].jj_context = nil
				eq(f.outer, vim.fn.getcwd())
				local choose, choices, url
				vim.ui.select = function(items, _, callback)
					choices, choose = items, callback
				end
				local saved = utils.open_url
				utils.open_url = function(value)
					url = value
				end
				local ok, err = pcall(function()
					require("jj.browse").browse(mode == "fallback" and { args = "@" } or nil)
					if mode == "delayed" then
						assert(choose, vim.inspect(f.errors))
						-- Change both directory and buffer before the selection completes.
						vim.cmd("tabnew")
						vim.cmd("tcd " .. vim.fn.fnameescape(f.base))
						for _, choice in ipairs(choices) do
							if choice.name == "mirror" then
								choose(choice)
							end
						end
					end
					local host = mode == "delayed" and "https://gitlab.com/example/inner/-"
						or "https://github.com/example/inner"
					eq(host .. "/blob/main/sub/same%20file.txt#L1", url, vim.inspect(f.errors))
				end)
				utils.open_url = saved
				assert(ok, err)
			end
		)
	end
	fixture("invalid directories report clear errors without replacing the log", function(f)
		local buf = f.open(nil, "OUTER repository")
		for _, case in ipairs({
			{ f.base .. "/missing", "Directory does not exist" },
			{ f.inner .. "/same file.txt", "Not a directory" },
			{ f.base, "Not a jj repository" },
		}) do
			cmd.log({ cwd = case[1] })
			assert(f.errors[#f.errors]:find(case[2], 1, true), vim.inspect(f.errors))
			eq(buf, terminal.state.buf)
		end
	end)
end
