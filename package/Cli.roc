import Arg
import Base
import ErrorFormatter
import Help
import Parser
import Validate

## Weave together a CLI parser using the record builder syntax!
##
## This module is the entry point for creating CLIs using Weaver.
## To get started, write a record whose fields are `Opt`s, `Param`s, or
## `SubCmd`s and end it with `.Cli`. Weaver will automatically register
## them in its config as well as build a parser with the inferred types of
## the fields you set.
##
## ```roc
## {
##     alpha: Opt.u64({ short: "a", help: "Set the alpha level" }),
##     verbosity: Opt.count({ short: "v", long: "verbose", help: "How loud we should be." }),
##     files: Param.str_list({ name: "files", help: "The files to process." }),
## }.Cli
##     .finish({
##         name: "example",
##         version: "v1.0.0",
##         authors: ["Some One <some.one@mail.com>"],
##         description: "Do some work with some files.",
##     })
##     |> Cli.assert_valid
## ```
##
## A record builder needs two or more fields. A single field is given a
## name with [map] instead:
##
## ```roc
## Opt.u64({ short: "a", help: "Set the alpha level" }).map(|alpha| { alpha: alpha })
## ```
##
## You can also add create subcommands in the same way:
##
## ```roc
## foo_subcommand =
##     Opt.u64({ short: "a", help: "Set the alpha level" })
##         |> SubCmd.finish({
##             name: "foo",
##             description: "Foo some stuff.",
##             mapper: |data| Foo(data),
##         })
##
## bar_subcommand =
##     # We allow two subcommands of the same parent to have overlapping
##     # fields since only one can ever be parsed at a time.
##     Opt.u64({ short: "a", help: "Set the alpha level" })
##         |> SubCmd.finish({
##             name: "bar",
##             description: "Bar some stuff.",
##             mapper: |data| Bar(data),
##         })
##
## {
##     verbosity: Opt.count({ short: "v", long: "verbose" }),
##     sc: SubCmd.optional([foo_subcommand, bar_subcommand]),
## }.Cli
## ```
##
## And those subcommands can have their own subcommands! But anyway...
##
## Once you have a command with all of its fields configured, you can
## turn it into a parser using the [finish] function, followed by
## the [assert_valid] function that asserts that the CLI is well configured.
##
## From there, you can take in command line arguments and use your
## data if it parses correctly:
##
## ```roc
## cli_parser =
##     {
##         alpha: Opt.u64({ short: "a", help: "Set the alpha level" }),
##         verbosity: Opt.count({ short: "v", long: "verbose", help: "How loud we should be." }),
##         files: Param.str_list({ name: "files", help: "The files to process." }),
##     }.Cli
##         .finish({
##             name: "example",
##             version: "v1.0.0",
##             authors: ["Some One <some.one@mail.com>"],
##             description: "Do some work with some files.",
##         })
##         |> Cli.assert_valid
##
## expect
##     cli_parser.parse_or_display_message([Utf8("-a"), Utf8("123"), Utf8("-vvv"), Utf8("file.txt"), Utf8("file-2.txt")])
##     == Ok({ alpha: 123, verbosity: 3, files: ["file.txt", "file-2.txt"] })
## ```
##
## You're ready to start parsing arguments using Weaver!
##
## If you want to see more examples, check the [examples](https://github.com/niclas-ahden/weaver/tree/main/examples)
## folder in the [repository](https://github.com/niclas-ahden/weaver).
##
## _note: `Opt`s must be set before an optional `SubCmd` field is given,_
## _and the `SubCmd` field needs to be set before `Param`s are set._
## _`Param` lists also cannot be followed by anything else including_
## _themselves. These requirements ensure we parse arguments in the_
## _right order. Luckily, all of this is ensured at the type level._
##
## A `Cli(data, from_action, to_action)` is a CLI builder: the options,
## parameters and subcommands registered so far and a parser for their
## data. The two action types are what keeps the fields in that order.
Cli(data, _from_action, _to_action) :: {
	parser : Base.ArgParser(data),
	options : List(Base.OptionConfig),
	parameters : List(Base.ParameterConfig),
	subcommands : Dict(Str, Base.SubcommandConfig),
}.{

	## The action of a builder that may be followed by options.
	GetOptionsAction : { get_options : {} }

	## The action of a builder that may be followed by parameters only.
	GetParamsAction : { get_params : {} }

	## The action of a builder that may not be followed by anything.
	StopCollectingAction : []

	## A parser that interprets command line arguments and returns well-formed data.
	CliParser(state) : {
		config : Base.CliConfig,
		parser : List(Arg) -> Base.ArgParserResult(state),
		text_style : Base.TextStyle,
	}

	## Combine two CLI builders into one that parses the fields of the first,
	## then the fields of the second.
	##
	## The record builder syntax `{ a: x, b: y }.Cli` calls this function, so
	## you rarely call it yourself.
	##
	## ```roc
	## expect {
	##     { parser, .. } =
	##         {
	##             verbosity: Opt.count({ short: "v", long: "verbose" }),
	##             file: Param.str({ name: "file" }),
	##         }.Cli
	##             .finish({ name: "example" })
	##             |> Cli.assert_valid
	##
	##     parser([Arg.from_str("file.txt"), Arg.from_str("-vvv")])
	##     == SuccessfullyParsed({ verbosity: 3, file: "file.txt" })
	## }
	## ```
	map2 : Cli(a, action1, action2), Cli(b, action2, action3), (a, b -> c) -> Cli(c, action1, action3)
	map2 = |left, right, combiner| {
		left_parser = left.parser
		right_parser = right.parser
		combined_parser = |input|
			match left_parser(input) {
				ShowVersion => ShowVersion
				ShowHelp(sp) => ShowHelp(sp)
				IncorrectUsage(arg_extract_err, sp) => IncorrectUsage(arg_extract_err, sp)
				SuccessfullyParsed({ data, remaining_args, subcommand_path }) =>
					match right_parser({ args: remaining_args, subcommand_path }) {
						ShowVersion => ShowVersion
						ShowHelp(sp) => ShowHelp(sp)
						IncorrectUsage(arg_extract_err, sp) => IncorrectUsage(arg_extract_err, sp)
						SuccessfullyParsed({ data: data2, remaining_args: rest_of_args, subcommand_path: next_sp }) =>
							SuccessfullyParsed({ data: combiner(data, data2), remaining_args: rest_of_args, subcommand_path: next_sp })
					}
			}

		Cli.{
			parser: combined_parser,
			options: left.options.concat(right.options),
			parameters: left.parameters.concat(right.parameters),
			subcommands: left.subcommands.insert_all(right.subcommands),
		}
	}

	## The same as [map2]. Upstream Weaver's `{ Cli.weave <- ... }` record
	## builder used this name.
	weave : Cli(a, action1, action2), Cli(b, action2, action3), (a, b -> c) -> Cli(c, action1, action3)
	weave = |left, right, combiner| Cli.map2(left, right, combiner)

	## Map over the parsed value of a Weaver field.
	##
	## Useful for naming bare fields, or handling default values.
	##
	## ```roc
	## expect {
	##     { parser, .. } =
	##         {
	##             verbosity: Opt.count({ short: "v", long: "verbose" }).map(|v| Verbosity(v)),
	##             file: Param.maybe_str({ name: "file" }).map(|f| f ?? "NO_FILE"),
	##         }.Cli
	##             .finish({ name: "example" })
	##             |> Cli.assert_valid
	##
	##     parser([Arg.from_str("-vvv")])
	##     == SuccessfullyParsed({ verbosity: Verbosity(3), file: "NO_FILE" })
	## }
	## ```
	map : Cli(a, from_action, to_action), (a -> b) -> Cli(b, from_action, to_action)
	map = |builder, mapper| {
		parser = builder.parser
		combined_parser = |input|
			Base.map_successfully_parsed(
				parser(input),
				|{ data, remaining_args, subcommand_path }| { data: mapper(data), remaining_args, subcommand_path },
			)

		Cli.{
			parser: combined_parser,
			options: builder.options,
			parameters: builder.parameters,
			subcommands: builder.subcommands,
		}
	}

	## Bundle a CLI builder into a parser, ensuring that its configuration is valid.
	##
	## Though the majority of the validation we'd need to do for type safety is
	## rendered unnecessary by the design of this library, there are some things
	## that the type system isn't able to prevent. Here are the checks we currently
	## perform after building your CLI parser:
	##
	## - All commands and subcommands must have kebab-case names.
	## - All options must have either:
	##   - A short flag which is a single character.
	##   - A long flag which is more than one character and kebab-case.
	##   - Both a short and a long flag with the above requirements.
	## - All parameters must be have kebab-case names.
	## - All custom option/parameter types are have kebab-case names.
	## - No options can overlap, even between different subcommands, so long
	##   as the options between the subcommands are ambiguous.
	##   - For example, a CLI with a `-t` option at the root level and also
	##     a `-t` option in the subcommand `sub` would fail validation since
	##     we wouldn't know who should get the `-t` option.
	##   - However, a CLI with two subcommands that each have a `-t` option
	##     would not fail validation since only one subcommand can be called
	##     at once.
	##
	## If you would like to avoid these validations, you can use [finish_without_validating]
	## instead, but you may receive some suprising results when parsing because
	## our parsing logic assumes the above validations have been made.
	##
	## ```roc
	## expect
	##     {
	##         verbosity: Opt.count({ short: "v", long: "verbose" }),
	##         file: Param.str({ name: "file" }),
	##     }.Cli
	##         .finish({ name: "example" })
	##         .is_ok()
	##
	## expect
	##     {
	##         verbosity: Opt.count({ short: "" }),
	##         file: Param.str({ name: "" }),
	##     }.Cli
	##         .finish({ name: "example" })
	##         .is_err()
	## ```
	finish : Cli(data, from_action, to_action), Base.CliConfigParams -> Try(CliParser(data), Validate.CliValidationErr)
	finish = |builder, params| {
		cli_parser = Cli.finish_without_validating(builder, params)
		Validate.validate_cli(cli_parser.config)?

		Ok(cli_parser)
	}

	## Bundle a CLI builder into a parser without validating its configuration.
	##
	## We recommend using the [finish] function to validate your parser as our
	## library's logic assumes said validation has taken place. However, this method
	## could be useful if you know better than our validations about the correctness
	## of your CLI.
	##
	## ```roc
	## expect {
	##     { parser, .. } =
	##         {
	##             verbosity: Opt.count({ short: "v", long: "verbose" }),
	##             file: Param.maybe_str({ name: "file" }),
	##         }.Cli
	##             .finish_without_validating({ name: "example" })
	##
	##     parser([Arg.from_str("-v"), Arg.from_str("-v")])
	##     == SuccessfullyParsed({ verbosity: 2, file: Err(NoValue) })
	## }
	## ```
	finish_without_validating : Cli(data, from_action, to_action), Base.CliConfigParams -> CliParser(data)
	finish_without_validating = |builder, { name, authors, version, description, text_style }| {
		{ options, parameters, subcommands, parser } =
			builder
				.check_for_help_and_version()
				.update_parser(
					|data| {
						ensure_all_args_were_parsed(data.remaining_args)?
						Ok(data)
					},
				)
				.into_parts()

		config = {
			name,
			authors: authors ?? [],
			version: version ?? "",
			description: description ?? "",
			options,
			parameters,
			subcommands: HasSubcommands(subcommands),
		}

		{
			config,
			text_style: text_style ?? Color,
			parser: |args|
				Base.map_successfully_parsed(
					parser({ args: Parser.parse_args(args), subcommand_path: [name] }),
					|{ data, .. }| data,
				),
		}
	}

	## Assert that a CLI is properly configured, crashing your program if not.
	##
	## Given that there are some aspects of a CLI that we cannot ensure are
	## correct at compile time, the easiest way to ensure that your CLI is properly
	## configured is to validate it and crash immediately on failure, following the
	## Fail Fast principle.
	##
	## You can avoid making this assertion by handling the error yourself or
	## by finish your CLI with the [finish_without_validating] function, but
	## the validations we perform (detailed in [finish]'s docs) are important
	## for correct parsing.
	##
	## ```roc
	## Opt.u64({ short: "a" })
	##     .finish({ name: "example" })
	##     |> Cli.assert_valid
	## ```
	assert_valid : Try(CliParser(data), Validate.CliValidationErr) -> CliParser(data)
	assert_valid = |result|
		match result {
			Ok(cli) => cli
			Err(err) => {
				message = ErrorFormatter.format_cli_validation_err(err)
				crash message
			}
		}

	## Parse arguments using a CLI parser or show a useful message on failure.
	##
	## The arguments are what basic-cli's `main!` receives, without the
	## program's name, so an app passes its arguments straight in.
	##
	## We have the following priorities in returning messages to the user:
	## 1) If the `-h/--help` flag is passed, the help page for the command/subcommand
	##    called will be displayed no matter if your arguments were correctly parsed.
	## 2) If the `-V/--version` flag is passed, the version for the app will
	##    be displayed no matter if your arguments were correctly parsed.
	## 3) If the provided arguments were parsed and neither of the above two
	##    built-in flags were passed, we return to you your data.
	## 4) If the provided arguments were not correct, we return a short message
	##    with which argument was not provided correctly, followed by the
	##    usage section of the relevant command/subcommand's help text.
	##
	## ```roc
	## example_cli =
	##     {
	##         verbosity: Opt.count({ short: "v", help: "How verbose our logs should be." }),
	##         alpha: Opt.maybe_u64({ short: "a", long: "alpha", help: "Set the alpha level." }),
	##     }.Cli
	##         .finish({
	##             name: "example",
	##             version: "v0.1.0",
	##             description: "An example CLI.",
	##             text_style: Plain,
	##         })
	##         |> Cli.assert_valid
	##
	## expect
	##     Cli.parse_or_display_message(example_cli, [Utf8("-h")])
	##     == Err(
	##         \\example v0.1.0
	##         \\
	##         \\An example CLI.
	##         \\
	##         \\Usage:
	##         \\  example -a/--alpha NUM [options]
	##         \\
	##         \\Options:
	##         \\  -v                   How verbose our logs should be.
	##         \\  -a NUM, --alpha NUM  Set the alpha level.
	##         \\  -h, --help           Show this help page.
	##         \\  -V, --version        Show the version.
	##     )
	##
	## expect
	##     Cli.parse_or_display_message(example_cli, [Utf8("-V")])
	##     == Err("v0.1.0")
	##
	## expect
	##     Cli.parse_or_display_message(example_cli, [Utf8("-v")])
	##     == Ok({ verbosity: 1, alpha: Err(NoValue) })
	##
	## expect
	##     Cli.parse_or_display_message(example_cli, [Utf8("-x")])
	##     == Err(
	##         \\Error: The argument -x was not recognized.
	##         \\
	##         \\Usage:
	##         \\  example -a/--alpha NUM [options]
	##     )
	## ```
	parse_or_display_message : CliParser(data), List([Utf8(Str), UnixBytes(List(U8)), WindowsU16s(List(U16))]) -> Try(data, Str)
	parse_or_display_message = |cli_parser, external_args| {
		args = external_args.map(Arg.from_raw_arg)
		parser = cli_parser.parser

		match parser(args) {
			SuccessfullyParsed(data) => Ok(data)
			ShowHelp({ subcommand_path }) => Err(Help.help_text(cli_parser.config, subcommand_path, cli_parser.text_style))
			ShowVersion => Err(cli_parser.config.version)
			IncorrectUsage(err, { subcommand_path }) => {
				usage_str = Help.usage_help(cli_parser.config, subcommand_path, cli_parser.text_style)
				Err("Error: ${ErrorFormatter.format_arg_extract_err(err)}\n\n${usage_str}")
			}
		}
	}

	## Make a builder out of a parser of the parsed arguments, with no
	## options, parameters or subcommands registered yet.
	from_arg_parser : (List(Parser.ParsedArg) -> Try({ data : data, remaining_args : List(Parser.ParsedArg) }, Base.ArgExtractErr)) -> Cli(data, from_action, to_action)
	from_arg_parser = |parser| {
		new_parser = |{ args, subcommand_path }|
			match parser(args) {
				Ok({ data, remaining_args }) => SuccessfullyParsed({ data, remaining_args, subcommand_path })
				Err(err) => IncorrectUsage(err, { subcommand_path: subcommand_path })
			}

		Cli.{
			parser: new_parser,
			options: [],
			parameters: [],
			subcommands: Dict.empty(),
		}
	}

	## Make a builder out of an [Base.ArgParser], with no options,
	## parameters or subcommands registered yet.
	from_full_parser : Base.ArgParser(data) -> Cli(data, from_action, to_action)
	from_full_parser = |parser|
		Cli.{
			parser,
			options: [],
			parameters: [],
			subcommands: Dict.empty(),
		}

	## Register an option in a builder's config.
	add_option : Cli(state, from_action, to_action), Base.OptionConfig -> Cli(state, from_action, to_action)
	add_option = |builder, new_option|
		Cli.{
			parser: builder.parser,
			options: builder.options.append(new_option),
			parameters: builder.parameters,
			subcommands: builder.subcommands,
		}

	## Register a parameter in a builder's config.
	add_parameter : Cli(state, from_action, to_action), Base.ParameterConfig -> Cli(state, from_action, to_action)
	add_parameter = |builder, new_parameter|
		Cli.{
			parser: builder.parser,
			options: builder.options,
			parameters: builder.parameters.append(new_parameter),
			subcommands: builder.subcommands,
		}

	## Register subcommands in a builder's config.
	add_subcommands : Cli(state, from_action, to_action), Dict(Str, Base.SubcommandConfig) -> Cli(state, from_action, to_action)
	add_subcommands = |builder, new_subcommands|
		Cli.{
			parser: builder.parser,
			options: builder.options,
			parameters: builder.parameters,
			subcommands: builder.subcommands.insert_all(new_subcommands),
		}

	## Change a builder's data and remaining arguments after it has parsed.
	update_parser : Cli(state, from_action, to_action), ({ data : state, remaining_args : List(Parser.ParsedArg) } -> Try({ data : next_state, remaining_args : List(Parser.ParsedArg) }, Base.ArgExtractErr)) -> Cli(next_state, from_action, to_action)
	update_parser = |builder, updater| {
		new_parser =
			Base.on_successful_arg_parse(
				builder.parser,
				|{ data, remaining_args, subcommand_path }|
					match updater({ data, remaining_args }) {
						Err(err) => IncorrectUsage(err, { subcommand_path: subcommand_path })
						Ok({ data: updated_data, remaining_args: rest_of_args }) =>
							SuccessfullyParsed({ data: updated_data, remaining_args: rest_of_args, subcommand_path })
					},
			)

		set_parser(builder, new_parser)
	}

	## Run another parsing step after a builder has parsed.
	bind_parser : Cli(state, from_action, to_action), (Base.ArgParserState(state) -> Base.ArgParserResult(Base.ArgParserState(next_state))) -> Cli(next_state, from_action, to_action)
	bind_parser = |builder, updater| {
		new_parser : Base.ArgParser(next_state)
		new_parser = Base.on_successful_arg_parse(builder.parser, |state| updater(state))

		set_parser(builder, new_parser)
	}

	## Take a builder apart into its parser and the config it registered.
	into_parts :
		Cli(state, from_action, to_action) -> {
			parser : Base.ArgParser(state),
			options : List(Base.OptionConfig),
			parameters : List(Base.ParameterConfig),
			subcommands : Dict(Str, Base.SubcommandConfig),
		}
	into_parts = |builder| {
		parser: builder.parser,
		options: builder.options,
		parameters: builder.parameters,
		subcommands: builder.subcommands,
	}

	## Register the `-h/--help` and `-V/--version` flags, and show the help
	## page or the version when one of them is given.
	check_for_help_and_version : Cli(state, from_action, to_action) -> Cli(state, from_action, to_action)
	check_for_help_and_version = |builder| {
		parser = builder.parser
		new_parser = |{ args, subcommand_path }|
			match parser({ args, subcommand_path }) {
				ShowHelp(sp) => ShowHelp(sp)
				ShowVersion => ShowVersion
				other =>
					if flag_was_passed(Base.help_option, args) {
						ShowHelp({ subcommand_path: subcommand_path })
					} else if flag_was_passed(Base.version_option, args) {
						ShowVersion
					} else {
						other
					}
			}

		Cli.{
			options: builder.options.concat([Base.help_option, Base.version_option]),
			parameters: builder.parameters,
			subcommands: builder.subcommands,
			parser: new_parser,
		}
	}
}

set_parser : Cli(state, from_action, to_action), Base.ArgParser(next_state) -> Cli(next_state, from_action, to_action)
set_parser = |builder, parser|
	Cli.{
		options: builder.options,
		parameters: builder.parameters,
		subcommands: builder.subcommands,
		parser,
	}

flag_was_passed : Base.OptionConfig, List(Parser.ParsedArg) -> Bool
flag_was_passed = |option, args|
	args.any(
		|arg|
			match arg {
				Short(short) => short == option.short
				ShortGroup(sg) => sg.names.any(|n| n == option.short)
				Long(long) => long.name == option.long
				Parameter(_p) => False
			},
	)

## Fail the parsing process if any arguments are left over after parsing.
ensure_all_args_were_parsed : List(Parser.ParsedArg) -> Try({}, Base.ArgExtractErr)
ensure_all_args_were_parsed = |remaining_args|
	match remaining_args {
		[] => Ok({})
		[first, ..] =>
			match first {
				Parameter(param) => Err(ExtraParamProvided(param))
				Long(long) => Err(UnrecognizedLongArg(long.name))
				Short(short) => Err(UnrecognizedShortArg(short))
				ShortGroup(sg) => Err(UnrecognizedShortArg(sg.names.first() ?? ""))
			}
	}

expect {
	{ parser, .. } =
		Cli.from_arg_parser(|args| Ok({ data: Str.inspect(args), remaining_args: [] }))
			.map(|s| Inspected(s))
			.into_parts()

	out = parser({ args: [Parameter(Arg.from_str("123"))], subcommand_path: [] })

	out
		== SuccessfullyParsed({
			data: Inspected("[Parameter(\"123\")]"),
			remaining_args: [],
			subcommand_path: [],
		})
}

expect !flag_was_passed(Base.help_option, [Parameter(Arg.from_str("-h"))])

expect flag_was_passed(Base.help_option, [Short("h")])

expect flag_was_passed(Base.help_option, [ShortGroup({ names: ["v", "h"], complete: Complete })])

expect flag_was_passed(Base.help_option, [Long({ name: "help", value: Err(NoValue) })])

expect flag_was_passed(Base.help_option, [Long({ name: "help", value: Ok(Arg.from_str("123")) })])
