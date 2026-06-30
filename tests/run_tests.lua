#!/usr/bin/env -S nvim -l

-- Simple test runner using Neovim's built-in features
-- Run with: nvim -l tests/run_tests.lua

-- Add lua directory to package path
package.path = package.path .. ";lua/?.lua;lua/?/init.lua"

-- Load the parser module
local parser = require("jj.core.parser")

local utils = require("jj.utils")
local jj_args = require("jj.core.args")

local tests_passed = 0
local tests_failed = 0
local failures = {}

local function assert_equals(expected, actual, msg)
	if expected ~= actual then
		error(
			string.format("%s\nExpected: %s\nGot: %s", msg or "Assertion failed", tostring(expected), tostring(actual))
		)
	end
end

local function assert_is_nil(value, msg)
	if value ~= nil then
		error(string.format("%s\nExpected: nil\nGot: %s", msg or "Assertion failed", tostring(value)))
	end
end

local function assert_table_equals(expected, actual, msg)
	if type(expected) ~= "table" or type(actual) ~= "table" then
		error(
			string.format("%s\nExpected table, got: %s and %s", msg or "Assertion failed", type(expected), type(actual))
		)
	end
	if not vim.deep_equal(expected, actual) then
		error(
			string.format(
				"%s\nExpected: %s\nGot: %s",
				msg or "Assertion failed",
				vim.inspect(expected),
				vim.inspect(actual)
			)
		)
	end
end

local function run_test(name, test_fn)
	local status, err = pcall(test_fn)
	if status then
		tests_passed = tests_passed + 1
		print(string.format("✓ %s", name))
	else
		tests_failed = tests_failed + 1
		print(string.format("✗ %s", name))
		table.insert(failures, { name = name, error = err })
	end
end

print("\n=== Running parser tests ===\n")

-- Test cases
run_test("parses simple diamond symbol", function()
	local line = "◆ abc123 my commit message"
	assert_equals("abc123", parser.get_revset(line))
end)

run_test("parses simple circle symbol", function()
	local line = "○ def456 another commit"
	assert_equals("def456", parser.get_revset(line))
end)

run_test("parses simple @ symbol", function()
	local line = "@ def456 another commit"
	assert_equals("def456", parser.get_revset(line))
end)

run_test("parses conflict symbol", function()
	local line = "× ghi789 conflicted commit"
	assert_equals("ghi789", parser.get_revset(line))
end)

run_test("parses with leading whitespace", function()
	local line = "  ◆ jkl012 indented commit"
	assert_equals("jkl012", parser.get_revset(line))
end)

run_test("parses single branch with box drawing", function()
	local line = "│ ○ mno345 commit on branch"
	assert_equals("mno345", parser.get_revset(line))
end)

run_test("parses multiple branches", function()
	local line = "│ │ ◆ pqr678 commit with multiple branches"
	assert_equals("pqr678", parser.get_revset(line))
end)

run_test("parses complex graph with connectors", function()
	local line = "├─○ stu901 commit after merge"
	assert_equals("stu901", parser.get_revset(line))
end)

run_test("parses graph with multiple box chars", function()
	local line = "│ ├─◆ vwx234 complex branch"
	assert_equals("vwx234", parser.get_revset(line))
end)

run_test("parses ASCII @ symbol", function()
	local line = "@ yza567 current working copy"
	assert_equals("yza567", parser.get_revset(line))
end)

run_test("parses ASCII * symbol (git-style)", function()
	local line = "* bcd890 git style commit"
	assert_is_nil(parser.get_revset(line))
end)

run_test("parses ASCII graph with pipe", function()
	local line = "| * efg123 ascii branch"
	assert_is_nil(parser.get_revset(line))
end)

run_test("parses mixed ASCII graph", function()
	local line = "|\\  @ hij456 merge commit"
	assert_equals("hij456", parser.get_revset(line))
end)

run_test("parses @ not at top", function()
	local line = "│ @ klm789 current change in middle"
	assert_equals("klm789", parser.get_revset(line))
end)

run_test("parses @ with multiple branches", function()
	local line = "│ │ @ nop012 working copy on branch"
	assert_equals("nop012", parser.get_revset(line))
end)

run_test("parses @ after merge connector", function()
	local line = "├─@ qrs345 working copy after merge"
	assert_equals("qrs345", parser.get_revset(line))
end)

run_test("parses with various box drawing characters", function()
	local line = "╭─╮ ○ tuv678 fancy box"
	assert_equals("tuv678", parser.get_revset(line))
end)

run_test("parses deeply nested branches", function()
	local line = "│ │ │ │ ◆ wxy901 deeply nested"
	assert_equals("wxy901", parser.get_revset(line))
end)

run_test("parses revision with numbers and letters", function()
	local line = "◆ abc123def456 mixed alphanumeric"
	assert_equals("abc123def456", parser.get_revset(line))
end)

run_test("stops at first non-alphanumeric after revision", function()
	local line = "○ xyz789 this is the message"
	assert_equals("xyz789", parser.get_revset(line))
end)

run_test("parses with different line connector styles", function()
	local line = "┼─┤ ◆ zab234 cross connector"
	assert_equals("zab234", parser.get_revset(line))
end)

run_test("parses with curve connectors", function()
	local line = "╰─○ cde567 curve connector"
	assert_equals("cde567", parser.get_revset(line))
end)

run_test("parses with double line vertical ┃", function()
	local line = "┃ ◆ fgh890 double line vertical"
	assert_equals("fgh890", parser.get_revset(line))
end)

run_test("parses with light triple dash vertical ┆", function()
	local line = "┆ ○ ijk123 light triple dash"
	assert_equals("ijk123", parser.get_revset(line))
end)

run_test("parses with heavy triple dash vertical ┇", function()
	local line = "┇ ◆ lmn456 heavy triple dash"
	assert_equals("lmn456", parser.get_revset(line))
end)

run_test("parses with light quadruple dash vertical ┊", function()
	local line = "┊ ○ opq789 light quadruple dash"
	assert_equals("opq789", parser.get_revset(line))
end)

run_test("parses with heavy quadruple dash vertical ┋", function()
	local line = "┋ ◆ rst012 heavy quadruple dash"
	assert_equals("rst012", parser.get_revset(line))
end)

run_test("parses with top-left corner ┌", function()
	local line = "┌─○ uvw345 top left corner"
	assert_equals("uvw345", parser.get_revset(line))
end)

run_test("parses with top-right corner ┐", function()
	local line = "┐ ◆ xyz678 top right corner"
	assert_equals("xyz678", parser.get_revset(line))
end)

run_test("parses with bottom-left corner └", function()
	local line = "└─○ abc901 bottom left corner"
	assert_equals("abc901", parser.get_revset(line))
end)

run_test("parses with bottom-right corner ┘", function()
	local line = "┘ ◆ def234 bottom right corner"
	assert_equals("def234", parser.get_revset(line))
end)

run_test("parses with left tee ├", function()
	local line = "├ ○ ghi567 left tee"
	assert_equals("ghi567", parser.get_revset(line))
end)

run_test("parses with right tee ┤", function()
	local line = "┤ ◆ jkl890 right tee"
	assert_equals("jkl890", parser.get_revset(line))
end)

run_test("parses with top tee ┬", function()
	local line = "┬─○ mno123 top tee"
	assert_equals("mno123", parser.get_revset(line))
end)

run_test("parses with bottom tee ┴", function()
	local line = "┴─◆ pqr456 bottom tee"
	assert_equals("pqr456", parser.get_revset(line))
end)

run_test("parses with cross ┼", function()
	local line = "┼ ○ stu789 cross"
	assert_equals("stu789", parser.get_revset(line))
end)

run_test("parses with mixed special box chars", function()
	local line = "┃ ┆ ┇ ○ vwx012 mixed special"
	assert_equals("vwx012", parser.get_revset(line))
end)

run_test("parses with rounded corners", function()
	local line = "╭─╮ ╰─╯ ◆ yza345 rounded corners"
	assert_equals("yza345", parser.get_revset(line))
end)

run_test("returns nil for lines without revision", function()
	local line = "This is just a description line"
	assert_is_nil(parser.get_revset(line))
end)

run_test("returns nil for empty line", function()
	local line = ""
	assert_is_nil(parser.get_revset(line))
end)

run_test("returns nil for only graph characters", function()
	local line = "│ │ ├─"
	assert_is_nil(parser.get_revset(line))
end)

-- Regression tests for false positives with description lines
run_test("returns nil for description line 'go' (false positive)", function()
	local line = "│ │  go mod tidy"
	assert_is_nil(parser.get_revset(line))
end)

run_test("returns nil for description line 'Improve' (false positive)", function()
	local line = "│ │ │  Improve input validation and UX for repository"
	assert_is_nil(parser.get_revset(line))
end)

run_test("returns nil for description line 'Add' (false positive)", function()
	local line = "│ │ │  Add Makefile and performance docs"
	assert_is_nil(parser.get_revset(line))
end)

run_test("returns nil for description line starting with word (graph only)", function()
	local line = "├───  description text here"
	assert_is_nil(parser.get_revset(line))
end)

run_test("returns nil for line with only graph chars and text", function()
	local line = "│ │ │  commit message without symbol"
	assert_is_nil(parser.get_revset(line))
end)

run_test("still parses correctly when symbol is present", function()
	local line = "│ │ ◆  s some description"
	assert_equals("s", parser.get_revset(line))
end)

run_test("still parses correctly with box chars and symbol", function()
	local line = "├─○ go some description"
	assert_equals("go", parser.get_revset(line))
end)

run_test("still parses correctly with divergent change suffix /0", function()
	local line = "├─○ go/0 some description"
	assert_equals("go/0", parser.get_revset(line))
end)

-- Divergent changes tests
run_test("parses divergent change with /0", function()
	local line = "◆ abc123/0 first divergent copy"
	assert_equals("abc123/0", parser.get_revset(line))
end)

run_test("parses divergent change with /1", function()
	local line = "○  rs/1 lam@lamtrung.com 9 hours ago pr-83-1 6a7 (divergent)"
	assert_equals("rs/1", parser.get_revset(line))
end)

run_test("parses divergent change with /2", function()
	local line = "◆ ghi789/2 third divergent copy"
	assert_equals("ghi789/2", parser.get_revset(line))
end)

run_test("parses divergent change with higher number /10", function()
	local line = "○ jkl012/10 tenth divergent copy"
	assert_equals("jkl012/10", parser.get_revset(line))
end)

run_test("parses divergent change with graph chars", function()
	local line = "│ │ ◆ mno345/0 divergent on branch"
	assert_equals("mno345/0", parser.get_revset(line))
end)

run_test("parses divergent change with @ symbol", function()
	local line = "@ pqr678/1 working copy divergent"
	assert_equals("pqr678/1", parser.get_revset(line))
end)

run_test("parses divergent change with conflict symbol", function()
	local line = "× stu901/0 conflicted divergent"
	assert_equals("stu901/0", parser.get_revset(line))
end)

run_test("parses divergent change with merge connector", function()
	local line = "├─○ vwx234/2 divergent after merge"
	assert_equals("vwx234/2", parser.get_revset(line))
end)

run_test("parses divergent change deeply nested", function()
	local line = "│ │ │ │ ◆ yza567/0 deeply nested divergent"
	assert_equals("yza567/0", parser.get_revset(line))
end)

run_test("parses short revset with divergent suffix", function()
	local line = "○ a/0 single char divergent"
	assert_equals("a/0", parser.get_revset(line))
end)

run_test("parses divergent change at end of line", function()
	local line = "◆ bcd890/1"
	assert_equals("bcd890/1", parser.get_revset(line))
end)

print("\n=== Running parse_conflicted_files tests ===\n")

run_test("parse_conflicted_files: single file", function()
	assert_table_equals(
		{ { rel_path = "src/foo.rs", abs_path = "/repo/src/foo.rs" } },
		parser.parse_conflicted_files("src/foo.rs\0/repo/src/foo.rs\0")
	)
end)

run_test("parse_conflicted_files: multiple files", function()
	assert_table_equals({
		{ rel_path = "a.txt", abs_path = "/repo/a.txt" },
		{ rel_path = "b.txt", abs_path = "/repo/b.txt" },
	}, parser.parse_conflicted_files("a.txt\0/repo/a.txt\0b.txt\0/repo/b.txt\0"))
end)

run_test("parse_conflicted_files: paths with tabs and newlines", function()
	assert_table_equals(
		{ { rel_path = "weird\tname\n.txt", abs_path = "/repo/weird\tname\n.txt" } },
		parser.parse_conflicted_files("weird\tname\n.txt\0/repo/weird\tname\n.txt\0")
	)
end)

run_test("parse_conflicted_files: empty output yields empty list", function()
	assert_table_equals({}, parser.parse_conflicted_files(""))
end)

run_test("parse_conflicted_files: nil output yields empty list", function()
	assert_table_equals({}, parser.parse_conflicted_files(nil))
end)

print("\n=== Running scan_conflict_sections tests ===\n")

run_test("scan_conflict_sections: one entry per opening marker", function()
	local lines = {
		"line 1",
		"<<<<<<< Conflict 1 of 2",
		"%%%%%%%",
		">>>>>>>",
		"between",
		"<<<<<<< Conflict 2 of 2",
		">>>>>>>",
	}
	assert_table_equals({
		{
			file = "/abs/a.txt",
			rel_path = "a.txt",
			pos = { 2, 0 },
			text = "a.txt:2",
		},
		{
			file = "/abs/a.txt",
			rel_path = "a.txt",
			pos = { 6, 0 },
			text = "a.txt:6",
		},
	}, parser.scan_conflict_sections("a.txt", "/abs/a.txt", lines))
end)

run_test("scan_conflict_sections: no markers yields empty list", function()
	assert_table_equals({}, parser.scan_conflict_sections("a.txt", "/abs/a.txt", { "no", "markers", "here" }))
end)

run_test("scan_conflict_sections: empty file yields empty list", function()
	assert_table_equals({}, parser.scan_conflict_sections("a.txt", "/abs/a.txt", {}))
end)

print("\n=== Running parse_default_cmd tests ===\n")

run_test("parse_default_cmd: parses config list array output", function()
	local output = 'ui.default-command = ["log", "--no-pager", "--limit", "18"]'
	assert_table_equals({ "log", "--no-pager", "--limit", "18" }, parser.parse_default_cmd(output))
end)

run_test("parse_default_cmd: parses config list single string output", function()
	local output = 'ui.default-command = "log"'
	assert_table_equals({ "log" }, parser.parse_default_cmd(output))
end)

run_test("parse_default_cmd: parses bare array (config get format)", function()
	local output = '["log", "--limit", "10"]'
	assert_table_equals({ "log", "--limit", "10" }, parser.parse_default_cmd(output))
end)

run_test("parse_default_cmd: parses bare string (config get format)", function()
	local output = '"log"'
	assert_table_equals({ "log" }, parser.parse_default_cmd(output))
end)

run_test("parse_default_cmd: parses unquoted string", function()
	local output = "log"
	assert_table_equals({ "log" }, parser.parse_default_cmd(output))
end)

run_test("parse_default_cmd: returns nil for empty string", function()
	assert_is_nil(parser.parse_default_cmd(""))
end)

run_test("parse_default_cmd: returns nil for nil", function()
	assert_is_nil(parser.parse_default_cmd(nil))
end)

print("\n=== Running parse_push_args tests ===\n")

local cmd = require("jj.cmd")

run_test("parse_push_args: parses bookmark and remote", function()
	local opts, err = cmd.parse_push_args({ "my-bookmark", "--remote", "origin" })
	assert_is_nil(err)
	assert_table_equals({ bookmark = "my-bookmark", remote = "origin" }, opts)
end)

run_test("parse_push_args: parses deleted flag", function()
	local opts, err = cmd.parse_push_args({ "--deleted" })
	assert_is_nil(err)
	assert_table_equals({ deleted = true }, opts)
end)

run_test("parse_push_args: allows remote before bookmark", function()
	local opts, err = cmd.parse_push_args({ "--remote", "origin", "my-bookmark" })
	assert_is_nil(err)
	assert_table_equals({ bookmark = "my-bookmark", remote = "origin" }, opts)
end)

run_test("parse_push_args: errors on missing remote value", function()
	local opts, err = cmd.parse_push_args({ "--remote" })
	assert_is_nil(opts)
	assert_equals("Missing remote name after --remote", err)
end)

run_test("parse_push_args: errors when remote value is another option", function()
	local opts, err = cmd.parse_push_args({ "--remote", "--deleted" })
	assert_is_nil(opts)
	assert_equals("Missing remote name after --remote", err)
end)

run_test("parse_push_args: errors on duplicate remotes", function()
	local opts, err = cmd.parse_push_args({ "--remote", "origin", "--remote", "upstream" })
	assert_is_nil(opts)
	assert_equals("Remote already set. Cannot specify multiple remotes.", err)
end)

run_test("parse_push_args: errors on multiple bookmarks", function()
	local opts, err = cmd.parse_push_args({ "bookmark-1", "bookmark-2" })
	assert_is_nil(opts)
	assert_equals("Only one bookmark can be provided", err)
end)

run_test("parse_push_args: errors on unknown option", function()
	local opts, err = cmd.parse_push_args({ "--foo" })
	assert_is_nil(opts)
	assert_equals("Unknown option: --foo", err)
end)

run_test("parse_push_args: errors on deleted with bookmark", function()
	local opts, err = cmd.parse_push_args({ "--deleted", "my-bookmark" })
	assert_is_nil(opts)
	assert_equals("Cannot specify both --deleted and a bookmark", err)
end)

print("\n=== Running build_log_cmd tests ===\n")

local log = require("jj.cmd.log")

run_test("build_log_cmd: raw_flags with --no-pager does not duplicate it", function()
	local cmd = log.build_log_cmd({ raw_flags = "--no-pager --limit 18" })
	-- Should contain exactly one --no-pager
	local _, count = cmd:gsub("%-%-no%-pager", "")
	assert_equals(1, count, "Expected exactly one --no-pager")
	assert_equals("jj log --no-pager --limit 18", cmd)
end)

run_test("build_log_cmd: raw_flags without --no-pager works normally", function()
	local cmd = log.build_log_cmd({ raw_flags = "--limit 18" })
	assert_equals("jj log --no-pager --limit 18", cmd)
end)

run_test("build_log_cmd: raw_flags that is only --no-pager", function()
	local cmd = log.build_log_cmd({ raw_flags = "--no-pager" })
	assert_equals("jj log --no-pager", cmd)
end)

run_test("build_log_cmd: structured opts with limit", function()
	local cmd = log.build_log_cmd({ limit = 10 })
	assert_equals(true, cmd:find("--limit 10") ~= nil, "Expected --limit 10 in command")
	assert_equals(true, cmd:find("--no%-pager") ~= nil, "Expected --no-pager in command")
end)

run_test("build_log_cmd: structured opts with revisions", function()
	local cmd = log.build_log_cmd({ revisions = "main" })
	assert_equals(true, cmd:find("--revisions main") ~= nil, "Expected --revisions main in command")
end)

run_test("build_log_cmd: default opts produces valid command", function()
	local cmd = log.build_log_cmd({})
	assert_equals(true, cmd:find("^jj log %-%-no%-pager") ~= nil, "Expected command to start with jj log --no-pager")
end)

print("\n=== Running resolve arg parsing tests ===\n")

local cmd = require("jj.cmd")

run_test("parse_resolve_args: defaults to @", function()
	local opts, err = cmd.parse_resolve_args({})
	assert_is_nil(err)
	assert_table_equals({ rev = "@" }, opts)
end)

run_test("parse_resolve_args: parses revision, tool, external and filesets", function()
	local opts, err = cmd.parse_resolve_args({
		"-r",
		"abc123",
		"--tool",
		"mergiraf",
		"--external",
		"src/",
		"README.md",
	})
	assert_is_nil(err)
	assert_table_equals({
		rev = "abc123",
		external = true,
		args = { "--tool", "mergiraf" },
		filesets = { "src/", "README.md" },
	}, opts)
end)

run_test("parse_resolve_args: errors on unknown long option", function()
	local opts, err = cmd.parse_resolve_args({ "--summary", "src/" })
	assert_is_nil(opts)
	assert_equals("Unknown option: --summary", err)
end)

run_test("parse_resolve_args: errors on duplicate --tool", function()
	local opts, err = cmd.parse_resolve_args({ "--tool", "meld", "--tool", "mergiraf" })
	assert_is_nil(opts)
	assert_equals("Tool already set. Cannot specify multiple tools.", err)
end)

run_test("parse_resolve_args: errors on duplicate revision", function()
	local opts, err = cmd.parse_resolve_args({ "-r", "a", "--revision", "b" })
	assert_is_nil(opts)
	assert_equals("Revision already set. Cannot specify multiple revisions.", err)
end)

run_test("parse_resolve_args: errors on missing --tool value", function()
	local opts, err = cmd.parse_resolve_args({ "--tool" })
	assert_is_nil(opts)
	assert_equals("Missing value for --tool", err)
end)

run_test("parse_resolve_args: errors on missing -r/--revision value", function()
	local opts, err = cmd.parse_resolve_args({ "-r" })
	assert_is_nil(opts)
	assert_equals("Missing value for --revision/-r", err)
end)

local resolve = require("jj.cmd.resolve")

run_test("resolve: passes jj-quoted argv for external execution", function()
	local runner = require("jj.core.runner")
	local original_execute_argv_async = runner.execute_argv_async
	local original_notify = utils.notify
	local original_ensure_jj = utils.ensure_jj

	local captured_cmd = nil
	runner.execute_argv_async = function(cmd)
		captured_cmd = cmd
	end
	utils.notify = function() end
	utils.ensure_jj = function()
		return true
	end

	local ok, err = pcall(function()
		resolve.resolve({
			rev = "abc 123",
			args = { "--tool", "my tool" },
			filesets = { "dir with spaces/", "glob:*" },
			external = true,
		})
		assert_table_equals({
			"jj",
			"resolve",
			"--revision",
			"abc 123",
			"--tool",
			"my tool",
			jj_args.fileset("dir with spaces/"),
			jj_args.fileset("glob:*"),
		}, captured_cmd)
	end)

	runner.execute_argv_async = original_execute_argv_async
	utils.notify = original_notify
	utils.ensure_jj = original_ensure_jj
	if not ok then
		error(err)
	end
end)

run_test("resolve: passes jj-quoted filesets for floating execution", function()
	local terminal = require("jj.ui.terminal")
	local original_run_floating = terminal.run_floating
	local original_notify = utils.notify
	local original_ensure_jj = utils.ensure_jj

	local captured_cmd = nil
	terminal.run_floating = function(cmd)
		captured_cmd = cmd
	end
	utils.notify = function() end
	utils.ensure_jj = function()
		return true
	end

	local ok, err = pcall(function()
		resolve.resolve({
			rev = "abc 123",
			args = { "--tool", "my tool" },
			filesets = { "dir with spaces/", "glob:*" },
		})
		assert_table_equals({
			"jj",
			"resolve",
			"--revision",
			"abc 123",
			"--tool",
			"my tool",
			jj_args.fileset("dir with spaces/"),
			jj_args.fileset("glob:*"),
		}, captured_cmd)
	end)

	terminal.run_floating = original_run_floating
	utils.notify = original_notify
	utils.ensure_jj = original_ensure_jj
	if not ok then
		error(err)
	end
end)

print("\n=== Running utils helper tests ===\n")

run_test("is_change_conflicted: returns true when jj reports conflict", function()
	local runner = require("jj.core.runner")
	local original_execute_command = runner.execute_command

	runner.execute_command = function(cmd, error_prefix, input, silent)
		assert_equals("jj log --no-graph -r 'abc123' -T 'conflict' --quiet", cmd)
		assert_equals("Error checking if revset has conflicts", error_prefix)
		assert_is_nil(input)
		assert_equals(true, silent)
		return "true\n", true
	end

	local ok, err = pcall(function()
		assert_equals(true, utils.is_change_conflicted("abc123"))
	end)
	runner.execute_command = original_execute_command
	if not ok then
		error(err)
	end
end)

run_test("is_change_conflicted: returns false when jj reports no conflict", function()
	local runner = require("jj.core.runner")
	local original_execute_command = runner.execute_command

	runner.execute_command = function()
		return "false\n", true
	end

	local ok, err = pcall(function()
		assert_equals(false, utils.is_change_conflicted("abc123"))
	end)
	runner.execute_command = original_execute_command
	if not ok then
		error(err)
	end
end)

run_test("is_change_conflicted: returns false when jj command fails", function()
	local runner = require("jj.core.runner")
	local original_execute_command = runner.execute_command

	runner.execute_command = function()
		return nil, false
	end

	local ok, err = pcall(function()
		assert_equals(false, utils.is_change_conflicted("abc123"))
	end)
	runner.execute_command = original_execute_command
	if not ok then
		error(err)
	end
end)

print("\n=== Running utils.parse_bookmark_names tests ===\n")

run_test("parse_bookmark_names: parses simple bookmark", function()
	local input = "main::true"
	assert_table_equals({ { name = "main", is_deleted = false } }, utils.parse_bookmark_names(input))
end)

run_test("parse_bookmark_names: parses multiple bookmarks", function()
	local input = "main::true feature-1::true feature-2::false"
	assert_table_equals({
		{ name = "main", is_deleted = false },
		{ name = "feature-1", is_deleted = false },
		{ name = "feature-2", is_deleted = true },
	}, utils.parse_bookmark_names(input))
end)

run_test("parse_bookmark_names: strips asterisks", function()
	local input = "main*::true feature-1*::true"
	assert_table_equals(
		{ { name = "main", is_deleted = false }, { name = "feature-1", is_deleted = false } },
		utils.parse_bookmark_names(input)
	)
end)

run_test("parse_bookmark_names: strips remote suffixes", function()
	local input = "main@origin::true feature-1@remote::false"
	assert_table_equals(
		{ { name = "main", is_deleted = false }, { name = "feature-1", is_deleted = true } },
		utils.parse_bookmark_names(input)
	)
end)

run_test("parse_bookmark_names: deduplicates bookmarks", function()
	local input = "main::true main@origin::true main*::true"
	assert_table_equals({ { name = "main", is_deleted = false } }, utils.parse_bookmark_names(input))
end)

run_test("parse_bookmark_names: handles mixed input", function()
	local input = "main*::true feature-1::true feature-1@origin::true feature-2*::false"
	assert_table_equals({
		{ name = "main", is_deleted = false },
		{ name = "feature-1", is_deleted = false },
		{ name = "feature-2", is_deleted = true },
	}, utils.parse_bookmark_names(input))
end)

run_test("parse_bookmark_names: handles empty input", function()
	assert_table_equals({}, utils.parse_bookmark_names(""))
end)

run_test("parse_bookmark_names: handles whitespace only", function()
	assert_table_equals({}, utils.parse_bookmark_names("   "))
end)

print("\n=== Running file encoding tests ===\n")

local jj_file = require("jj.file")

--- Hex-dump a string so assertion failures on binary data are readable.
local function hex(s)
	return (s:gsub(".", function(c)
		return string.format("%02x ", string.byte(c))
	end))
end

run_test("decode: utf-16le with BOM and dos endings", function()
	-- "a\r\nü\r\n" in utf-16le with BOM
	local raw = "\255\254a\0\r\0\n\0\252\0\r\0\n\0"
	local lines, had_eol, enc = jj_file._decode(raw)
	assert_table_equals({ "a", "\195\188" }, lines) -- "ü" in utf-8
	assert_equals(true, had_eol)
	assert_equals("utf-16le", enc.fenc)
	assert_equals(true, enc.bomb)
	assert_equals("dos", enc.ff)
	for _, line in ipairs(lines) do
		assert_is_nil(line:find("%z"), "line contains a NUL byte")
		assert_is_nil(line:find("\1"), "line contains a SOH byte")
	end
end)

run_test("decode: honors explicit enc for BOM-less utf-16le", function()
	local lines = jj_file._decode("h\0i\0", { fenc = "utf-16le", bomb = false, ff = "unix" })
	assert_table_equals({ "hi" }, lines)
end)

run_test("decode: roundtrip reproduces the bytes exactly", function()
	local fixtures = {
		["utf-16le bom"] = "\255\254h\0i\0\n\0\252\0",
		["utf-16be bom"] = "\254\255\0h\0i\0\n\0\252",
		["utf-16le bom + dos"] = "\255\254a\0\r\0\n\0b\0\r\0\n\0",
		["utf-8 bom"] = "\239\187\191hello\nworld\n",
		["plain dos"] = "a\r\nb\r\n",
		["mac"] = "a\rb\r",
		["no trailing newline"] = "a\nb",
		["empty file"] = "",
	}
	for name, raw in pairs(fixtures) do
		local lines, had_eol, enc = jj_file._decode(raw)
		if lines == nil then
			error(string.format("%s: decode failed: %s", name, tostring(had_eol)))
		end
		local encoded, err = jj_file._encode(lines, had_eol, enc)
		if encoded == nil then
			error(string.format("%s: encode failed: %s", name, tostring(err)))
		end
		assert_equals(hex(raw), hex(encoded), name)
	end
end)

print("\n=== Running get_file_content tests ===\n")

run_test("get_file_content: reads existing file content", function()
	local runner = require("jj.core.runner")
	local original = runner.execute_argv_raw
	runner.execute_argv_raw = function(cmd)
		assert_table_equals({ "jj", "file", "show", "-r", "abc123", jj_args.fileset("src/file.py") }, cmd)
		return "a\nb\n", true, ""
	end
	local ok_test, err = pcall(function()
		local lines, had_eol, ok, _, absent = jj_file.get_file_content("abc123", "src/file.py")
		assert_table_equals({ "a", "b" }, lines)
		assert_equals(true, had_eol)
		assert_equals(true, ok)
		assert_equals(false, absent)
	end)
	runner.execute_argv_raw = original
	if not ok_test then
		error(err)
	end
end)

run_test("get_file_content: absent path in revision reports absent (not a read error)", function()
	local runner = require("jj.core.runner")
	local original = runner.execute_argv_raw
	runner.execute_argv_raw = function(cmd)
		assert_table_equals({ "jj", "file", "show", "-r", "abc123", jj_args.fileset("src/new_file.py") }, cmd)
		return nil, false, "Error: No such path: src/new_file.py\n"
	end
	local ok_test, err = pcall(function()
		local lines, had_eol, ok, _, absent = jj_file.get_file_content("abc123", "src/new_file.py")
		assert_table_equals({}, lines)
		assert_equals(false, had_eol)
		assert_equals(false, ok)
		assert_equals(true, absent)
	end)
	runner.execute_argv_raw = original
	if not ok_test then
		error(err)
	end
end)

run_test("get_file_content: genuine read error returns failure without absent", function()
	local runner = require("jj.core.runner")
	local original = runner.execute_argv_raw
	runner.execute_argv_raw = function(cmd)
		assert_table_equals({ "jj", "file", "show", "-r", "nope", jj_args.fileset("src/file.py") }, cmd)
		return nil, false, "Error: Revision `nope` doesn't exist\n"
	end
	local ok_test, err = pcall(function()
		local _, _, ok, _, absent = jj_file.get_file_content("nope", "src/file.py")
		assert_equals(false, ok)
		assert_equals(false, absent)
	end)
	runner.execute_argv_raw = original
	if not ok_test then
		error(err)
	end
end)

-- Print summary
print(string.format("\n=== Test Summary ==="))
print(string.format("Passed: %d", tests_passed))
print(string.format("Failed: %d", tests_failed))

if tests_failed > 0 then
	print("\n=== Failures ===")
	for _, failure in ipairs(failures) do
		print(string.format("\n%s:", failure.name))
		print(string.format("  %s", failure.error))
	end
	os.exit(1)
else
	print("\n✓ All tests passed!")
	os.exit(0)
end
