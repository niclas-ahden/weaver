import Arg
import Base
import Cli
import Opt
import Param
import Parser

## Subcommands that your CLI will parse as a field in your config.
##
## A subcommand is a CLI of its own, built the same way, that runs when its
## name is the first parameter given. It comes after any option fields and
## before any parameter fields in a record builder.
SubCmd :: [].{

	## A subcommand, ready to be given to [optional] or [required].
	SubcommandParserConfig(sub_state) : {
		name : Str,
		parser : Base.ArgParser(sub_state),
		config : Base.SubcommandConfig,
	}

	## Create an empty subcommand.
	##
	## If you only need to register a subcommand based on its name,
	## this provides that. Subcommands that take arguments should be
	## built like normal CLIs and finalized with [finish].
	##
	## ```roc
	## foo_subcommand =
	##     SubCmd.empty({ name: "foobar", description: "Foo and bar subcommand", value: FooBar })
	## ```
	empty : { name : Str, description ?: Str, value : common_state } -> SubcommandParserConfig(common_state)
	empty = |{ name, description, value }| {
		{ options, parameters, subcommands, parser } =
			Cli.from_arg_parser(|args| Ok({ data: value, remaining_args: args }))
				.check_for_help_and_version()
				.into_parts()

		config = {
			description: description ?? "",
			options,
			parameters,
			subcommands: HasSubcommands(subcommands),
		}

		{ name, config, parser }
	}

	## Bundle a CLI builder into a subcommand.
	##
	## Subcommands use the same CLI builder that top-level CLIs do,
	## so they are composed using the same tools. The difference lies in
	## how subcommands are prepared for usage by parents. In addition to
	## providing a `name` and a `description`, you also provide a `mapper`,
	## which is a function that converts the subcommand's data into a common
	## type that all subcommands under a parent command need to share. This
	## is required since the parent command will have a field (added with
	## [optional] or [required]) that must have a unified type.
	##
	## ```roc
	## foo_subcommand =
	##     {
	##         foo: Opt.str({ short: "f" }),
	##         bar: Opt.str({ short: "b" }),
	##     }.Cli
	##         |> SubCmd.finish({ name: "foobar", description: "Foo and bar subcommand", mapper: |data| FooBar(data) })
	## ```
	finish : Cli(state, from_action, to_action), { name : Str, description ?: Str, mapper : state -> common_state } -> SubcommandParserConfig(common_state)
	finish = |builder, { name, description, mapper }| {
		{ options, parameters, subcommands, parser } =
			builder
				.check_for_help_and_version()
				.update_parser(|{ data, remaining_args }| Ok({ data: mapper(data), remaining_args }))
				.into_parts()

		config = {
			description: description ?? "",
			options,
			parameters,
			subcommands: HasSubcommands(subcommands),
		}

		{ name, config, parser }
	}

	## Use previously defined subcommands as data in a parent CLI builder.
	##
	## Once all options have been parsed, we then check the first parameter
	## passed to see if it's one of the provided subcommands. If so, we parse
	## the remaining arguments as that subcommand's data, and otherwise continue
	## parsing the current command.
	##
	## The [optional] function can only be used after all `Opt` fields have been
	## registered (if any) as we don't want to parse options for a subcommand
	## instead of a parent, and cannot be used after any parameters have been
	## registered. This is enforced using the type state pattern, where we encode
	## the state of the program into its types. If you're curious, check the
	## `Cli` type to see how this works using its two action type variables.
	##
	## ```roc
	## foo_subcommand =
	##     Opt.str({ short: "f" })
	##         |> SubCmd.finish({ name: "foo", description: "Foo subcommand", mapper: |f| Foo(f) })
	##
	## bar_subcommand =
	##     Opt.str({ short: "b" })
	##         |> SubCmd.finish({ name: "bar", description: "Bar subcommand", mapper: |b| Bar(b) })
	##
	## expect
	##     SubCmd.optional([foo_subcommand, bar_subcommand])
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("bar"), Utf8("-b"), Utf8("abc")])
	##     == Ok(Ok(Bar("abc")))
	## ```
	optional : List(SubcommandParserConfig(sub_state)) -> Cli(Try(sub_state, [NoSubcommand]), Cli.GetOptionsAction, Cli.GetParamsAction)
	optional = |subcommand_configs| {
		subcommands = Dict.from_list(subcommand_configs.map(|{ name, config, .. }| (name, config)))

		full_parser = |{ args, subcommand_path }|
			get_first_arg_to_check_for_subcommand_call(
				args,
				subcommand_path,
				subcommand_configs,
				|subcommand_found|
					match subcommand_found {
						Err(NotFound) => SuccessfullyParsed({ data: Err(NoSubcommand), remaining_args: args, subcommand_path })
						Ok(subcommand) => {
							sub_parser =
								Base.on_successful_arg_parse(
									subcommand.parser,
									|{ data: sub_data, remaining_args: sub_remaining_args, subcommand_path: sub_subcommand_path }|
										SuccessfullyParsed({ data: Ok(sub_data), remaining_args: sub_remaining_args, subcommand_path: sub_subcommand_path }),
								)

							sub_parser({
								args: args.drop_first(1),
								subcommand_path: subcommand_path.append(subcommand.name),
							})
						}
					},
			)

		Cli.from_full_parser(full_parser).add_subcommands(subcommands)
	}

	## Use previously defined subcommands as data in a parent CLI builder.
	##
	## Once all options have been parsed, we then check the first parameter
	## passed to see if it's one of the provided subcommands. If so, we parse
	## the remaining arguments as that subcommand's data, and otherwise we
	## fail parsing.
	##
	## The [required] function can only be used after all `Opt` fields have been
	## registered (if any) as we don't want to parse options for a subcommand
	## instead of a parent, and cannot be used after any parameters have been
	## registered. This is enforced using the type state pattern, where we encode
	## the state of the program into its types. If you're curious, check the
	## `Cli` type to see how this works using its two action type variables.
	##
	## ```roc
	## expect
	##     SubCmd.required([foo_subcommand, bar_subcommand])
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("bar"), Utf8("-b"), Utf8("abc")])
	##     == Ok(Bar("abc"))
	## ```
	required : List(SubcommandParserConfig(sub_data)) -> Cli(sub_data, Cli.GetOptionsAction, Cli.GetParamsAction)
	required = |subcommand_configs| {
		subcommands = Dict.from_list(subcommand_configs.map(|{ name, config, .. }| (name, config)))

		full_parser = |{ args, subcommand_path }|
			get_first_arg_to_check_for_subcommand_call(
				args,
				subcommand_path,
				subcommand_configs,
				|subcommand_found|
					match subcommand_found {
						Err(NotFound) => IncorrectUsage(NoSubcommandCalled, { subcommand_path: subcommand_path })
						Ok(subcommand) =>
							(subcommand.parser)({
								args: args.drop_first(1),
								subcommand_path: subcommand_path.append(subcommand.name),
							})
					},
			)

		Cli.from_full_parser(full_parser).add_subcommands(subcommands)
	}
}

## Check the first parameter passed to see if a subcommand was called.
get_first_arg_to_check_for_subcommand_call :
	List(Parser.ParsedArg), List(Str), List(SubCmd.SubcommandParserConfig(sub_state)), (Try(SubCmd.SubcommandParserConfig(sub_state), [NotFound]) -> Base.ArgParserResult(Base.ArgParserState(state))) -> Base.ArgParserResult(Base.ArgParserState(state))
get_first_arg_to_check_for_subcommand_call = |remaining_args, subcommand_path, subcommand_parsers, callback|
	match remaining_args.first() {
		Err(ListWasEmpty) => callback(Err(NotFound))
		Ok(first_arg) =>
			match first_arg {
				Short(short) => IncorrectUsage(UnrecognizedShortArg(short), { subcommand_path: subcommand_path })
				Long(long) => IncorrectUsage(UnrecognizedLongArg(long.name), { subcommand_path: subcommand_path })
				ShortGroup(sg) => IncorrectUsage(UnrecognizedShortArg(sg.names.first() ?? ""), { subcommand_path: subcommand_path })
				Parameter(p) =>
					match Arg.to_str(p) {
						Ok(param_str) => callback(subcommand_parsers.find_first(|sc| sc.name == param_str))
						Err(InvalidUtf8) => callback(Err(NotFound))
					}
			}
	}

# Tests

parse : Cli.CliParser(data), List(Str) -> Try(data, Str)
parse = |cli_parser, args| Cli.parse_or_display_message(cli_parser, args.map(|arg| Utf8(arg)))

foo_subcommand : SubCmd.SubcommandParserConfig([Foo(Str), Bar(Str)])
foo_subcommand =
	Opt.str({ short: "f", help: "The foo." })
		|> SubCmd.finish({ name: "foo", description: "Foo subcommand", mapper: |f| Foo(f) })

bar_subcommand : SubCmd.SubcommandParserConfig([Foo(Str), Bar(Str)])
bar_subcommand =
	Opt.str({ short: "b", help: "The bar." })
		|> SubCmd.finish({ name: "bar", description: "Bar subcommand", mapper: |b| Bar(b) })

optional_cli : Cli.CliParser({ verbosity : U64, sc : Try([Foo(Str), Bar(Str)], [NoSubcommand]), file : Try(Str, [NoValue]) })
optional_cli =
	{
		verbosity: Opt.count({ short: "v" }),
		sc: SubCmd.optional([foo_subcommand, bar_subcommand]),
		file: Param.maybe_str({ name: "file" }),
	}.Cli
		.finish({ name: "example", text_style: Plain })
		|> Cli.assert_valid

required_cli : Cli.CliParser([Foo(Str), Bar(Str)])
required_cli =
	SubCmd.required([foo_subcommand, bar_subcommand])
		.finish({ name: "example", version: "v1.2.3", text_style: Plain })
		|> Cli.assert_valid

expect parse(optional_cli, ["bar", "-b", "abc"]) == Ok({ verbosity: 0, sc: Ok(Bar("abc")), file: Err(NoValue) })
expect parse(optional_cli, ["-vv", "foo", "-f", "abc"]) == Ok({ verbosity: 2, sc: Ok(Foo("abc")), file: Err(NoValue) })
expect parse(optional_cli, ["file.txt"]) == Ok({ verbosity: 0, sc: Err(NoSubcommand), file: Ok("file.txt") })
expect parse(optional_cli, []) == Ok({ verbosity: 0, sc: Err(NoSubcommand), file: Err(NoValue) })
expect
	parse(optional_cli, ["foo"])
		== Err("Error: Required option -f is missing.\n\nUsage:\n  example foo -f STR [options]")
expect
	parse(optional_cli, ["-x"])
		== Err("Error: The argument -x was not recognized.\n\nUsage:\n  example [options] <file>\n  example <COMMAND>")

expect
	parse(optional_cli, ["--help"])
		== Err(
			\\example
			\\
			\\Usage:
			\\  example [options] <file>
			\\  example <COMMAND>
			\\
			\\Commands:
			\\  foo  Foo subcommand
			\\  bar  Bar subcommand
			\\
			\\Arguments:
			\\  <file>  ${""}
			\\
			\\Options:
			\\  -v             ${""}
			\\  -h, --help     Show this help page.
			\\  -V, --version  Show the version.
		)

expect
	parse(optional_cli, ["foo", "-h"])
		== Err(
			\\example foo
			\\
			\\Foo subcommand
			\\
			\\Usage:
			\\  example foo -f STR [options]
			\\
			\\Options:
			\\  -f STR         The foo.
			\\  -h, --help     Show this help page.
			\\  -V, --version  Show the version.
		)

expect parse(required_cli, ["bar", "-b", "abc"]) == Ok(Bar("abc"))
expect parse(required_cli, ["foo", "-f", "abc"]) == Ok(Foo("abc"))
expect
	parse(required_cli, [])
		== Err("Error: A subcommand must be called.\n\nUsage:\n  example [options]\n  example <COMMAND>")
expect
	parse(required_cli, ["baz"])
		== Err("Error: A subcommand must be called.\n\nUsage:\n  example [options]\n  example <COMMAND>")
expect parse(required_cli, ["-V"]) == Err("v1.2.3")
expect parse(required_cli, ["bar", "-V"]) == Err("v1.2.3")

expect {
	empty_cli =
		SubCmd.required([SubCmd.empty({ name: "first", value: First }), SubCmd.empty({ name: "second", description: "The second.", value: Second })])
			.finish({ name: "example", text_style: Plain })
			|> Cli.assert_valid

	parse(empty_cli, ["second"]) == Ok(Second) and parse(empty_cli, ["first", "extra"]) == Err("Error: The parameter \"extra\" was not expected.\n\nUsage:\n  example first [options]")
}

# Subcommands of subcommands, and options with the same name in different
# subcommands.
expect {
	inner =
		{ x: Opt.u64({ short: "x" }), b: Opt.u64({ short: "b" }) }.Cli
			|> SubCmd.finish({ name: "inner", mapper: |data| Inner(data) })

	outer =
		{ a: Opt.maybe_u64({ short: "a" }), sc: SubCmd.optional([inner]) }.Cli
			|> SubCmd.finish({ name: "outer", mapper: |data| Outer(data) })

	other =
		Opt.maybe_u64({ short: "a" })
			|> SubCmd.finish({ name: "other", mapper: |data| Other(data) })

	cli_parser =
		SubCmd.optional([outer, other])
			.finish({ name: "example", text_style: Plain })
			|> Cli.assert_valid

	parse(cli_parser, ["outer", "-a", "3", "inner", "-x", "1", "-b", "2"]) == Ok(Ok(Outer({ a: Ok(3), sc: Ok(Inner({ x: 1, b: 2 })) })))
}

# An option of a subcommand may not share a name with an option of a command
# above it.
expect {
	sub =
		Opt.flag({ short: "f" })
			|> SubCmd.finish({ name: "sub", mapper: |data| Sub(data) })

	{ force: Opt.flag({ short: "f" }), sc: SubCmd.optional([sub]) }.Cli
		.finish({ name: "example" })
		.is_err()
}
