## The tests of whole CLIs: building, validating, parsing and the messages
## shown to the user. They need Opt, Param and SubCmd together, which the
## package's own modules can't import without a cycle, so they live in an app.
##
## Run them with `roc test tests/cli_test.roc`, which also runs the
## package's `expect` blocks, or with `./tests.roc`.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.31.0/Ff3fkK1TjYTVxMj9V21FP24ojTJXYk314Fbo1whBZ6Yf.tar.zst",
	weaver: "../package/main.roc",
}

import pf.Stdout
import weaver.Arg
import weaver.Cli
import weaver.ErrorFormatter
import weaver.Help
import weaver.Opt
import weaver.Param
import weaver.SubCmd
import weaver.Validate

main! = |_args| {
	Stdout.line!("Run me with `roc test tests/cli_test.roc`.")?
	Ok({})
}

parse : Cli.CliParser(data), List(Str) -> Try(data, Str)
parse = |cli_parser, args| Cli.parse_or_display_message(cli_parser, args.map(|arg| Utf8(arg)))

parse_args : Cli.CliParser(data), List(Str) -> [ShowHelp({ subcommand_path : List(Str) }), ShowVersion, IncorrectUsage(_, { subcommand_path : List(Str) }), SuccessfullyParsed(data)]
parse_args = |{ parser, .. }, args| parser(args.map(Arg.from_str))

# The tests that upstream Weaver kept in CliTest.roc.

basic_cli : Cli.CliParser([Alpha(U64)])
basic_cli =
	Opt.u64({ short: "a", help: "Set the alpha level." })
		.map(|alpha| Alpha(alpha))
		.finish({ name: "basic-cli", version: "v1.0.0", text_style: Plain })
		|> Cli.assert_valid

expect parse(basic_cli, ["-a", "123"]) == Ok(Alpha(123))

expect {
	help_message =
		\\basic-cli v1.0.0
		\\
		\\Usage:
		\\  basic-cli -a NUM [options]
		\\
		\\Options:
		\\  -a NUM         Set the alpha level.
		\\  -h, --help     Show this help page.
		\\  -V, --version  Show the version.

	parse(basic_cli, ["-h"]) == Err(help_message)
}

# The tests that upstream Weaver kept at the end of Cli.roc.

expect
	Opt.count({ short: "v" })
		.map(|v| Verbosity(v))
		.finish({ name: "empty" })
		.is_ok()

expect
	Opt.count({ short: "" })
		.map(|v| Verbosity(v))
		.finish({ name: "example" })
		.is_err()

expect
	{
		verbosity: Opt.count({ short: "v" }),
		points: Param.str({ name: "points" }),
	}.Cli
		.finish({ name: "test" })
		.is_ok()

# The examples in the documentation of Cli.

expect {
	cli_parser =
		{
			alpha: Opt.u64({ short: "a", help: "Set the alpha level" }),
			verbosity: Opt.count({ short: "v", long: "verbose", help: "How loud we should be." }),
			files: Param.str_list({ name: "files", help: "The files to process." }),
		}.Cli
			.finish({
				name: "example",
				version: "v1.0.0",
				authors: ["Some One <some.one@mail.com>"],
				description: "Do some work with some files.",
			})
			|> Cli.assert_valid

	Cli.parse_or_display_message(cli_parser, [Utf8("-a"), Utf8("123"), Utf8("-vvv"), Utf8("file.txt"), Utf8("file-2.txt")])
		== Ok({ alpha: 123, verbosity: 3, files: ["file.txt", "file-2.txt"] })
}

expect {
	cli_parser =
		{
			verbosity: Opt.count({ short: "v", long: "verbose" }),
			file: Param.str({ name: "file" }),
		}.Cli
			.finish({ name: "example" })
			|> Cli.assert_valid

	parse_args(cli_parser, ["file.txt", "-vvv"]) == SuccessfullyParsed({ verbosity: 3, file: "file.txt" })
}

expect {
	cli_parser =
		Cli.weave(Opt.count({ short: "v" }), Param.str({ name: "file" }), |verbosity, file| { verbosity, file })
			.finish({ name: "example" })
			|> Cli.assert_valid

	parse(cli_parser, ["-v", "file.txt"]) == Ok({ verbosity: 1, file: "file.txt" })
}

expect {
	cli_parser =
		{
			verbosity: Opt.count({ short: "v", long: "verbose" }).map(|v| Verbosity(v)),
			file: Param.maybe_str({ name: "file" }).map(|f| f ?? "NO_FILE"),
		}.Cli
			.finish({ name: "example" })
			|> Cli.assert_valid

	parse_args(cli_parser, ["-vvv"]) == SuccessfullyParsed({ verbosity: Verbosity(3), file: "NO_FILE" })
}

expect {
	cli_parser =
		Opt.u64({ short: "a", help: "Set the alpha level" })
			.map(|alpha| { alpha: alpha })
			.finish({ name: "example" })
			|> Cli.assert_valid

	parse(cli_parser, ["-a", "1"]) == Ok({ alpha: 1 })
}

expect
	{
		verbosity: Opt.count({ short: "v", long: "verbose" }),
		file: Param.str({ name: "file" }),
	}.Cli
		.finish({ name: "example" })
		.is_ok()

expect
	{
		verbosity: Opt.count({ short: "" }),
		file: Param.str({ name: "" }),
	}.Cli
		.finish({ name: "example" })
		.is_err()

expect {
	cli_parser =
		{
			verbosity: Opt.count({ short: "v", long: "verbose" }),
			file: Param.maybe_str({ name: "file" }),
		}.Cli
			.finish_without_validating({ name: "example" })

	parse_args(cli_parser, ["-v", "-v"]) == SuccessfullyParsed({ verbosity: 2, file: Err(NoValue) })
}

example_cli : Cli.CliParser({ verbosity : U64, alpha : Try(U64, [NoValue]) })
example_cli =
	{
		verbosity: Opt.count({ short: "v", help: "How verbose our logs should be." }),
		alpha: Opt.maybe_u64({ short: "a", long: "alpha", help: "Set the alpha level." }),
	}.Cli
		.finish({
			name: "example",
			version: "v0.1.0",
			description: "An example CLI.",
			text_style: Plain,
		})
		|> Cli.assert_valid

expect
	parse(example_cli, ["-h"])
		== Err(
			\\example v0.1.0
			\\
			\\An example CLI.
			\\
			\\Usage:
			\\  example -a/--alpha NUM [options]
			\\
			\\Options:
			\\  -v                   How verbose our logs should be.
			\\  -a NUM, --alpha NUM  Set the alpha level.
			\\  -h, --help           Show this help page.
			\\  -V, --version        Show the version.
		)

expect parse(example_cli, ["-V"]) == Err("v0.1.0")

expect parse(example_cli, ["-v"]) == Ok({ verbosity: 1, alpha: Err(NoValue) })

expect parse(example_cli, ["-v", "--alpha=5"]) == Ok({ verbosity: 1, alpha: Ok(5) })

expect
	parse(example_cli, ["-x"])
		== Err(
			\\Error: The argument -x was not recognized.
			\\
			\\Usage:
			\\  example -a/--alpha NUM [options]
		)

expect
	parse(example_cli, ["extra"])
		== Err(
			\\Error: The parameter "extra" was not expected.
			\\
			\\Usage:
			\\  example -a/--alpha NUM [options]
		)

# Help is shown even when the rest of the arguments are wrong.
expect parse(example_cli, ["-x", "--help"]).map_err(|message| message.starts_with("example v0.1.0")) == Err(True)

# Arguments from the operating system come in any of the three shapes.
expect Cli.parse_or_display_message(example_cli, [UnixBytes([45, 118]), WindowsU16s([45, 97]), Utf8("2")]) == Ok({ verbosity: 1, alpha: Ok(2) })

# The examples in the documentation of Help.

help_cli : Cli.CliParser(U64)
help_cli =
	Opt.count({ short: "v", help: "How verbose our logs should be." })
		.finish({
			name: "example",
			version: "v0.1.0",
			description: "An example CLI.",
			text_style: Plain,
		})
		|> Cli.assert_valid

expect
	Help.help_text(help_cli.config, ["example"], Plain)
		==
		\\example v0.1.0
		\\
		\\An example CLI.
		\\
		\\Usage:
		\\  example [options]
		\\
		\\Options:
		\\  -v             How verbose our logs should be.
		\\  -h, --help     Show this help page.
		\\  -V, --version  Show the version.

expect
	Help.usage_help(help_cli.config, ["example"], Plain)
		==
		\\Usage:
		\\  example [options]

expect
	Help.usage_help(help_cli.config, ["example"], Color)
		== "\u(1b)[1m\u(1b)[4mUsage:\u(1b)[0m\n  example [options]"

expect {
	authors_cli =
		Opt.flag({ short: "f", help: "Force it." })
			.finish({ name: "example", authors: ["Some One <some.one@mail.com>"], text_style: Plain })
			|> Cli.assert_valid

	Help.help_text(authors_cli.config, ["example"], Plain)
		==
		\\example
		\\Some One <some.one@mail.com>
		\\
		\\Usage:
		\\  example [options]
		\\
		\\Options:
		\\  -f             Force it.
		\\  -h, --help     Show this help page.
		\\  -V, --version  Show the version.
}

# Help text that runs over several lines stays in its column.
expect {
	multiline_cli =
		Opt.flag({ short: "f", help: "Force it.\nEven when it is a bad idea." })
			.finish({ name: "example", text_style: Plain })
			|> Cli.assert_valid

	Help.help_text(multiline_cli.config, ["example"], Plain).contains("  -f             Force it.\n                 Even when it is a bad idea.\n")
}

# The messages of a CLI that fails validation.

validation_message : Try(Cli.CliParser(_data), Validate.CliValidationErr) -> Str
validation_message = |result|
	match result {
		Ok(_) => "valid"
		Err(err) => ErrorFormatter.format_cli_validation_err(err)
	}

expect validation_message(Opt.flag({ short: "f" }).finish({ name: "Example" })) == "The command 'Example' is not kebab-case."

expect validation_message(Opt.flag({ short: "ff" }).finish({ name: "example" })) == "The option '-ff' is not a single character."

expect validation_message(Opt.flag({ long: "f" }).finish({ name: "example" })) == "The option '--f' is not kebab-case and at least two characters."

expect validation_message(Opt.flag({}).finish({ name: "example" })) == "An option has neither a short or long name."

expect validation_message(Param.str({ name: "File" }).finish({ name: "example" })) == "The parameter 'File' is not kebab-case."

expect
	validation_message(Opt.single({ short: "c", type: "Color", parser: |arg| Ok(arg) }).finish({ name: "example" }))
		== "The option '-c' has value type 'Color', which is not kebab-case."

expect
	validation_message({ first: Param.str({ name: "file" }), second: Param.str({ name: "file" }) }.Cli.finish({ name: "example" }))
		== "The parameter 'file' overlaps with the parameter 'file'."

expect
	validation_message({ first: Opt.flag({ short: "f" }), second: Opt.flag({ short: "f", long: "force" }) }.Cli.finish({ name: "example" }))
		== "The option '-f' overlaps with the option '-f/--force'."

expect validation_message(Opt.flag({ short: "h" }).finish({ name: "example" })) == "The option '-h' tried to overwrite the built-in -h/--help flag."

expect validation_message(Opt.flag({ long: "version" }).finish({ name: "example" })) == "The option '--version' tried to overwrite the built-in -V/--version flag."

expect {
	sub =
		Opt.flag({ short: "f" })
			|> SubCmd.finish({ name: "Sub", mapper: |force| Sub(force) })

	validation_message(SubCmd.optional([sub]).finish({ name: "example" })) == "The command 'Sub' for command 'example Sub' is not kebab-case."
}

expect {
	sub =
		Opt.flag({ short: "f", long: "force" })
			|> SubCmd.finish({ name: "sub", mapper: |force| Sub(force) })

	validation_message({ force: Opt.flag({ short: "f" }), sc: SubCmd.optional([sub]) }.Cli.finish({ name: "example" }))
		== "The option '-f/--force' for command 'example sub' overlaps with the option '-f'."
}

# Two subcommands may share option names, since only one of them runs.
expect {
	first =
		Opt.flag({ short: "f" })
			|> SubCmd.finish({ name: "first", mapper: |force| First(force) })
	second =
		Opt.flag({ short: "f" })
			|> SubCmd.finish({ name: "second", mapper: |force| Second(force) })

	validation_message(SubCmd.optional([first, second]).finish({ name: "example" })) == "valid"
}
