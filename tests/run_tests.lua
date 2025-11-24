#!/usr/bin/env -S nvim -l

-- Simple test runner using Neovim's built-in features
-- Run with: nvim -l tests/run_tests.lua

-- Add lua directory to package path
package.path = package.path .. ";lua/?.lua;lua/?/init.lua"

-- Load the parser module
local parser = require("jj.core.parser")

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
	assert_equals("abc123", parser.get_rev_from_log_line(line))
end)

run_test("parses simple circle symbol", function()
	local line = "○ def456 another commit"
	assert_equals("def456", parser.get_rev_from_log_line(line))
end)

run_test("parses simple @ symbol", function()
	local line = "@ def456 another commit"
	assert_equals("def456", parser.get_rev_from_log_line(line))
end)

run_test("parses conflict symbol", function()
	local line = "× ghi789 conflicted commit"
	assert_equals("ghi789", parser.get_rev_from_log_line(line))
end)

run_test("parses with leading whitespace", function()
	local line = "  ◆ jkl012 indented commit"
	assert_equals("jkl012", parser.get_rev_from_log_line(line))
end)

run_test("parses single branch with box drawing", function()
	local line = "│ ○ mno345 commit on branch"
	assert_equals("mno345", parser.get_rev_from_log_line(line))
end)

run_test("parses multiple branches", function()
	local line = "│ │ ◆ pqr678 commit with multiple branches"
	assert_equals("pqr678", parser.get_rev_from_log_line(line))
end)

run_test("parses complex graph with connectors", function()
	local line = "├─○ stu901 commit after merge"
	assert_equals("stu901", parser.get_rev_from_log_line(line))
end)

run_test("parses graph with multiple box chars", function()
	local line = "│ ├─◆ vwx234 complex branch"
	assert_equals("vwx234", parser.get_rev_from_log_line(line))
end)

run_test("parses ASCII @ symbol", function()
	local line = "@ yza567 current working copy"
	assert_equals("yza567", parser.get_rev_from_log_line(line))
end)

run_test("parses ASCII * symbol (git-style)", function()
	local line = "* bcd890 git style commit"
	assert_equals("bcd890", parser.get_rev_from_log_line(line))
end)

run_test("parses ASCII graph with pipe", function()
	local line = "| * efg123 ascii branch"
	assert_equals("efg123", parser.get_rev_from_log_line(line))
end)

run_test("parses mixed ASCII graph", function()
	local line = "|\\  @ hij456 merge commit"
	assert_equals("hij456", parser.get_rev_from_log_line(line))
end)

run_test("parses @ not at top", function()
	local line = "│ @ klm789 current change in middle"
	assert_equals("klm789", parser.get_rev_from_log_line(line))
end)

run_test("parses @ with multiple branches", function()
	local line = "│ │ @ nop012 working copy on branch"
	assert_equals("nop012", parser.get_rev_from_log_line(line))
end)

run_test("parses @ after merge connector", function()
	local line = "├─@ qrs345 working copy after merge"
	assert_equals("qrs345", parser.get_rev_from_log_line(line))
end)

run_test("parses with various box drawing characters", function()
	local line = "╭─╮ ○ tuv678 fancy box"
	assert_equals("tuv678", parser.get_rev_from_log_line(line))
end)

run_test("parses deeply nested branches", function()
	local line = "│ │ │ │ ◆ wxy901 deeply nested"
	assert_equals("wxy901", parser.get_rev_from_log_line(line))
end)

run_test("parses revision with numbers and letters", function()
	local line = "◆ abc123def456 mixed alphanumeric"
	assert_equals("abc123def456", parser.get_rev_from_log_line(line))
end)

run_test("stops at first non-alphanumeric after revision", function()
	local line = "○ xyz789 this is the message"
	assert_equals("xyz789", parser.get_rev_from_log_line(line))
end)

run_test("parses with different line connector styles", function()
	local line = "┼─┤ ◆ zab234 cross connector"
	assert_equals("zab234", parser.get_rev_from_log_line(line))
end)

run_test("parses with curve connectors", function()
	local line = "╰─○ cde567 curve connector"
	assert_equals("cde567", parser.get_rev_from_log_line(line))
end)

run_test("parses with double line vertical ┃", function()
	local line = "┃ ◆ fgh890 double line vertical"
	assert_equals("fgh890", parser.get_rev_from_log_line(line))
end)

run_test("parses with light triple dash vertical ┆", function()
	local line = "┆ ○ ijk123 light triple dash"
	assert_equals("ijk123", parser.get_rev_from_log_line(line))
end)

run_test("parses with heavy triple dash vertical ┇", function()
	local line = "┇ ◆ lmn456 heavy triple dash"
	assert_equals("lmn456", parser.get_rev_from_log_line(line))
end)

run_test("parses with light quadruple dash vertical ┊", function()
	local line = "┊ ○ opq789 light quadruple dash"
	assert_equals("opq789", parser.get_rev_from_log_line(line))
end)

run_test("parses with heavy quadruple dash vertical ┋", function()
	local line = "┋ ◆ rst012 heavy quadruple dash"
	assert_equals("rst012", parser.get_rev_from_log_line(line))
end)

run_test("parses with top-left corner ┌", function()
	local line = "┌─○ uvw345 top left corner"
	assert_equals("uvw345", parser.get_rev_from_log_line(line))
end)

run_test("parses with top-right corner ┐", function()
	local line = "┐ ◆ xyz678 top right corner"
	assert_equals("xyz678", parser.get_rev_from_log_line(line))
end)

run_test("parses with bottom-left corner └", function()
	local line = "└─○ abc901 bottom left corner"
	assert_equals("abc901", parser.get_rev_from_log_line(line))
end)

run_test("parses with bottom-right corner ┘", function()
	local line = "┘ ◆ def234 bottom right corner"
	assert_equals("def234", parser.get_rev_from_log_line(line))
end)

run_test("parses with left tee ├", function()
	local line = "├ ○ ghi567 left tee"
	assert_equals("ghi567", parser.get_rev_from_log_line(line))
end)

run_test("parses with right tee ┤", function()
	local line = "┤ ◆ jkl890 right tee"
	assert_equals("jkl890", parser.get_rev_from_log_line(line))
end)

run_test("parses with top tee ┬", function()
	local line = "┬─○ mno123 top tee"
	assert_equals("mno123", parser.get_rev_from_log_line(line))
end)

run_test("parses with bottom tee ┴", function()
	local line = "┴─◆ pqr456 bottom tee"
	assert_equals("pqr456", parser.get_rev_from_log_line(line))
end)

run_test("parses with cross ┼", function()
	local line = "┼ ○ stu789 cross"
	assert_equals("stu789", parser.get_rev_from_log_line(line))
end)

run_test("parses with mixed special box chars", function()
	local line = "┃ ┆ ┇ ○ vwx012 mixed special"
	assert_equals("vwx012", parser.get_rev_from_log_line(line))
end)

run_test("parses with rounded corners", function()
	local line = "╭─╮ ╰─╯ ◆ yza345 rounded corners"
	assert_equals("yza345", parser.get_rev_from_log_line(line))
end)

run_test("returns nil for lines without revision", function()
	local line = "This is just a description line"
	assert_is_nil(parser.get_rev_from_log_line(line))
end)

run_test("returns nil for empty line", function()
	local line = ""
	assert_is_nil(parser.get_rev_from_log_line(line))
end)

run_test("returns nil for only graph characters", function()
	local line = "│ │ ├─"
	assert_is_nil(parser.get_rev_from_log_line(line))
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
