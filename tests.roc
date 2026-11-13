#!/usr/bin/env roc
## All tests: the package's `expect` blocks, the CLI tests in
## tests/cli_test.roc, the CLIs that must not compile, and the examples run
## with a few sets of arguments each, their output compared with what they
## should print.
##
## The examples are built with --opt=speed, as the release gate runs them.
## Run everything with:
##
##     nix develop -c ./tests.roc
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.31.0/Ff3fkK1TjYTVxMj9V21FP24ojTJXYk314Fbo1whBZ6Yf.tar.zst",
}

import pf.Cmd
import pf.Env
import pf.Path
import pf.Stdout

main! = |_args| {
	Stdout.line!("== unit tests")?
	call!("roc", ["test", "package/main.roc"])?

	Stdout.line!("== CLI tests")?
	call!("roc", ["test", "tests/cli_test.roc"])?

	Stdout.line!("== CLIs that must not compile")?
	for file in ["tests/compile-errors/option-after-param.roc", "tests/compile-errors/param-after-param-list.roc"] {
		output = Cmd.new(file_arg("roc")).args([file_arg("check"), file_arg(file)]).run!()?
		printed = Str.from_utf8_lossy(output.stdout_bytes.concat(output.stderr_bytes))
		if output.status != Exited(0) and printed.contains("type mismatch") and printed.contains("1 error and 0 warnings") {
			Stdout.line!("ok: ${file} does not compile")?
		} else {
			Stdout.line!("FAIL: ${file} must fail `roc check` with exactly one type mismatch, but printed:\n${printed}")?
			return Err(Exit(1))
		}
	}

	Stdout.line!("== examples")?
	bin_dir = Env.create_temp_dir_with_prefix!("weaver-examples-")?
	result = run_examples!(bin_dir)
	_ = Path.delete_all!(bin_dir)
	result
}

run_examples! = |bin_dir| {
	for example in ["basic", "default-values", "single-arg", "subcommands"] {
		call!("roc", ["build", "--opt=speed", "--no-cache", "examples/${example}.roc", "--output=${Path.display(bin_dir.join(example))}"])?
	}

	var $failures = 0
	for case in cases {
		# A Windows build may have been given an .exe suffix.
		exe = bin_dir.join("${case.example}.exe")
		program = Path.display(if (Path.is_file!(exe) ?? False) exe else bin_dir.join(case.example))
		output = Cmd.new(file_arg(program)).args(case.args.map(file_arg)).run!()?
		stdout = Str.from_utf8_lossy(output.stdout_bytes)
		status_ok =
			match output.status {
				Exited(code) => code == case.exit_code
				Signaled(_) => False
			}
		command = Str.join_with([case.example].concat(case.args), " ")
		if status_ok and stdout == case.stdout {
			Stdout.line!("ok: ${command}")?
		} else {
			$failures = $failures + 1
			Stdout.line!("FAIL: ${command}\n-- expected exit ${I32.to_str(case.exit_code)} and:\n${case.stdout}-- got ${Str.inspect(output.status)} and:\n${stdout}--")?
		}
	}

	if $failures == 0 {
		Ok({})
	} else {
		Stdout.line!("${U64.to_str($failures)} example run(s) failed")?
		Err(Exit(1))
	}
}

## A string as an argument for a command.
file_arg = |str| Utf8(str)

## Run a command with inherited stdio, failing the script on a nonzero exit.
call! = |program, arguments| {
	Cmd.call!(file_arg(program), arguments.map(file_arg)) ? |_| Exit(1)
	Ok({})
}

bold = "\u(1b)[1m"

heading = "\u(1b)[1m\u(1b)[4m"

reset = "\u(1b)[0m"

parsed = "Successfully parsed! Here's what I got:\n\n"

basic_usage = "${heading}Usage:${reset}\n  basic -a NUM [options] <file> <files...>\n"

cases : List({ example : Str, args : List(Str), exit_code : I32, stdout : Str })
cases = [
	{
		example: "basic",
		args: ["file1.txt", "file2.txt", "-f", "-a", "123"],
		exit_code: 0,
		stdout: "${parsed}{ alpha: 123, file: Ok(\"file1.txt\"), files: [\"file2.txt\"], force: True }\n",
	},
	{
		example: "basic",
		args: ["--help"],
		exit_code: 1,
		stdout: Str.join_with(
			[
				"${heading}basic v0.0.1${reset}",
				"Some One <some.one@mail.com>",
				"",
				"This is a basic example of what you can build with Weaver. You get safe parsing, useful error messages, and help pages all for free!",
				"",
				"${heading}Usage:${reset}",
				"  basic -a NUM [options] <file> <files...>",
				"",
				"${heading}Arguments:${reset}",
				"  ${bold}<file>    ${reset}  The file to process.",
				"  ${bold}<files...>${reset}  The rest of the files.",
				"",
				"${heading}Options:${reset}",
				"  ${bold}-a NUM       ${reset}  Set the alpha level.",
				"  ${bold}-f           ${reset}  Force the task to complete.",
				"  ${bold}-h, --help   ${reset}  Show this help page.",
				"  ${bold}-V, --version${reset}  Show the version.",
				"",
			],
			"\n",
		),
	},
	{
		example: "basic",
		args: [],
		exit_code: 1,
		stdout: "Error: Required option -a is missing.\n\n${basic_usage}",
	},
	{
		example: "basic",
		args: ["-a", "x"],
		exit_code: 1,
		stdout: "Error: The value provided to -a was not a valid number.\n\n${basic_usage}",
	},
	{
		example: "basic",
		args: ["-a", "1", "-x"],
		exit_code: 1,
		stdout: "Error: The argument -x was not recognized.\n\n${basic_usage}",
	},
	{
		example: "basic",
		args: ["-V"],
		exit_code: 1,
		stdout: "v0.0.1\n",
	},
	{
		example: "basic",
		args: ["-a", "1", "--", "-f", "--g"],
		exit_code: 0,
		stdout: "${parsed}{ alpha: 1, file: Ok(\"-f\"), files: [\"--g\"], force: False }\n",
	},
	{
		example: "default-values",
		args: [],
		exit_code: 0,
		stdout: "${parsed}{ alpha: 123, beta: 3.141592653589793238, file: \"NONE\" }\n",
	},
	{
		example: "default-values",
		args: ["-a", "5", "--beta=2.5", "f.txt"],
		exit_code: 0,
		stdout: "${parsed}{ alpha: 5, beta: 2.5, file: \"f.txt\" }\n",
	},
	{
		example: "single-arg",
		args: ["--alpha", "7"],
		exit_code: 0,
		stdout: "${parsed}Alpha(7)\n",
	},
	{
		example: "single-arg",
		args: [],
		exit_code: 1,
		stdout: "Error: Required option -a/--alpha is missing.\n\n${heading}Usage:${reset}\n  single-arg -a/--alpha NUM [options]\n",
	},
	{
		example: "subcommands",
		args: [],
		exit_code: 0,
		stdout: "${parsed}{ file: Err(NoValue), files: [], force: False, sc: Err(NoSubcommand) }\n",
	},
	{
		example: "subcommands",
		args: ["-f", "s1", "-d", "3", "ss2", "-a", "1", "-c", "2", "data"],
		exit_code: 0,
		stdout: "${parsed}{ file: Err(NoValue), files: [], force: True, sc: Ok(S1({ d: Ok(3), sc: Ok(SS2({ a: 1, c: 2, data: \"data\" })), volume: Err(NoValue) })) }\n",
	},
	{
		example: "subcommands",
		args: ["s2", "-d", "4"],
		exit_code: 0,
		stdout: "${parsed}{ file: Err(NoValue), files: [], force: False, sc: Ok(S2(DFlag(Ok(4)))) }\n",
	},
	{
		example: "subcommands",
		args: ["a.txt", "b.txt", "c.txt"],
		exit_code: 0,
		stdout: "${parsed}{ file: Ok(\"a.txt\"), files: [\"b.txt\", \"c.txt\"], force: False, sc: Err(NoSubcommand) }\n",
	},
	{
		example: "subcommands",
		args: ["s1", "ss1", "-a", "1"],
		exit_code: 1,
		stdout: "Error: Required option -b is missing.\n\n${heading}Usage:${reset}\n  subcommands s1 ss1 -a NUM -b NUM [options]\n",
	},
	{
		example: "subcommands",
		args: ["s1", "--help"],
		exit_code: 1,
		stdout: Str.join_with(
			[
				"${heading}subcommands s1 v0.0.1${reset}",
				"Some One <some.one@mail.com>",
				"",
				"A first subcommand.",
				"",
				"${heading}Usage:${reset}",
				"  subcommands s1 -d NUM -v/--volume NUM [options]",
				"  subcommands s1 <COMMAND>",
				"",
				"${heading}Commands:${reset}",
				"  ${bold}ss1${reset}  A sub-subcommand.",
				"  ${bold}ss2${reset}  Another sub-subcommand.",
				"",
				"${heading}Options:${reset}",
				"  ${bold}-d NUM              ${reset}  A non-overlapping subcommand flag with s2.",
				"  ${bold}-v NUM, --volume NUM${reset}  How loud to grind the gears.",
				"  ${bold}-h, --help          ${reset}  Show this help page.",
				"  ${bold}-V, --version       ${reset}  Show the version.",
				"",
			],
			"\n",
		),
	},
	{
		example: "subcommands",
		args: ["--help"],
		exit_code: 1,
		stdout: Str.join_with(
			[
				"${heading}subcommands v0.0.1${reset}",
				"Some One <some.one@mail.com>",
				"",
				"This is a basic example of what you can build with Weaver. You get safe parsing, useful error messages, and help pages all for free!",
				"",
				"${heading}Usage:${reset}",
				"  subcommands [options] <file> <files...>",
				"  subcommands <COMMAND>",
				"",
				"${heading}Commands:${reset}",
				"  ${bold}s1${reset}  A first subcommand.",
				"  ${bold}s2${reset}  Another subcommand.",
				"",
				"${heading}Arguments:${reset}",
				"  ${bold}<file>    ${reset}  The file to process.",
				"  ${bold}<files...>${reset}  The rest of the files.",
				"",
				"${heading}Options:${reset}",
				"  ${bold}-f           ${reset}  Force the task to complete.",
				"  ${bold}-h, --help   ${reset}  Show this help page.",
				"  ${bold}-V, --version${reset}  Show the version.",
				"",
			],
			"\n",
		),
	},
]
