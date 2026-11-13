import Base
import Utils

## Render the help page and the usage text of a command or subcommand.
Help :: [].{

	## Render the help text for a command at or under the root config.
	##
	## The second argument should be a list of subcommand names, e.g.
	## `["example", "subcommand-1", "subcommand-2"]`. If the subcommand
	## isn't found, the root command's help page is rendered by default.
	##
	## ```roc
	## example_cli =
	##     Opt.count({ short: "v", help: "How verbose our logs should be." })
	##         .finish({
	##             name: "example",
	##             version: "v0.1.0",
	##             description: "An example CLI.",
	##             text_style: Plain,
	##         })
	##         |> Cli.assert_valid
	##
	## expect
	##     Help.help_text(example_cli.config, ["example"], Plain)
	##     ==
	##         \\example v0.1.0
	##         \\
	##         \\An example CLI.
	##         \\
	##         \\Usage:
	##         \\  example [options]
	##         \\
	##         \\Options:
	##         \\  -v             How verbose our logs should be.
	##         \\  -h, --help     Show this help page.
	##         \\  -V, --version  Show the version.
	## ```
	help_text : Base.CliConfig, List(Str), Base.TextStyle -> Str
	help_text = |base_config, path, text_style| {
		{ config, subcommand_path } = find_subcommand_or_default(base_config, path)

		name = Str.join_with(subcommand_path, " ")

		top_line = Str.join_with([name, config.version].drop_if(Str.is_empty), " ")

		authors_text =
			if config.authors.is_empty() {
				""
			} else {
				Str.concat("\n", Str.join_with(config.authors, " "))
			}

		description_text =
			if config.description.is_empty() {
				""
			} else {
				Str.concat("\n\n", config.description)
			}

		subcommands_text =
			match config.subcommands {
				HasSubcommands(scs) if !scs.is_empty() => commands_help(config.subcommands, text_style)
				_ => ""
			}

		parameters_text =
			if config.parameters.is_empty() {
				""
			} else {
				parameters_help(config.parameters, text_style)
			}

		options_text =
			if config.options.is_empty() {
				""
			} else {
				options_help(config.options, text_style)
			}

		bottom_sections = Str.join_with([subcommands_text, parameters_text, options_text].drop_if(Str.is_empty), "\n\n")

		(style, reset) = heading_style(text_style)

		"${style}${top_line}${reset}${authors_text}${description_text}\n\n${Help.usage_help(config, subcommand_path, text_style)}\n\n${bottom_sections}"
	}

	## Render just the usage text for a command at or under the root config.
	##
	## The second argument should be a list of subcommand names, e.g.
	## `["example", "subcommand-1", "subcommand-2"]`. If the subcommand
	## isn't found, the root command's usage text is rendered by default.
	##
	## ```roc
	## example_cli =
	##     Opt.count({ short: "v", help: "How verbose our logs should be." })
	##         .finish({
	##             name: "example",
	##             version: "v0.1.0",
	##             description: "An example CLI.",
	##             text_style: Plain,
	##         })
	##         |> Cli.assert_valid
	##
	## expect
	##     Help.usage_help(example_cli.config, ["example"], Plain)
	##     ==
	##         \\Usage:
	##         \\  example [options]
	## ```
	usage_help : Base.CliConfig, List(Str), Base.TextStyle -> Str
	usage_help = |base_config, path, text_style| {
		{ config, subcommand_path } = find_subcommand_or_default(base_config, path)

		name = Str.join_with(subcommand_path, " ")

		required_options =
			config.options
				.drop_if(|opt| opt.expected_value == NothingExpected)
				.map(option_simple_name_formatter)

		other_options =
			if required_options.len() == config.options.len() {
				[]
			} else {
				["[options]"]
			}

		params_strings = config.parameters.map(|param| "<${param.name}${ellipsis(param.plurality)}>")

		first_line = Str.join_with(required_options.concat(other_options).concat(params_strings), " ")

		subcommand_usage =
			match config.subcommands {
				HasSubcommands(sc) if !sc.is_empty() => "\n  ${name} <COMMAND>"
				_ => ""
			}

		(style, reset) = heading_style(text_style)

		"${style}Usage:${reset}\n  ${name} ${first_line}${subcommand_usage}"
	}
}

bold_ansi_code : Str
bold_ansi_code = "\u(1b)[1m"

bold_and_underline_ansi_code : Str
bold_and_underline_ansi_code = "\u(1b)[1m\u(1b)[4m"

reset_ansi_code : Str
reset_ansi_code = "\u(1b)[0m"

heading_style : Base.TextStyle -> (Str, Str)
heading_style = |text_style|
	match text_style {
		Color => (bold_and_underline_ansi_code, reset_ansi_code)
		Plain => ("", "")
	}

ellipsis : Base.Plurality -> Str
ellipsis = |plurality|
	match plurality {
		Optional | One => ""
		Many => "..."
	}

## Walks the subcommand tree from the root CLI config and either
## returns the subcommand's config as if it were the root command if a
## subcommand is found, or just the root command's config otherwise.
find_subcommand_or_default : Base.CliConfig, List(Str) -> { config : Base.CliConfig, subcommand_path : List(Str) }
find_subcommand_or_default = |config, subcommand_path| {
	base_command = {
		description: config.description,
		options: config.options,
		parameters: config.parameters,
		subcommands: config.subcommands,
	}

	match find_subcommand(base_command, subcommand_path.drop_first(1)) {
		Err(KeyNotFound) => { config, subcommand_path }
		Ok(c) => {
			config: {
				name: config.name,
				version: config.version,
				authors: config.authors,
				description: c.description,
				options: c.options,
				parameters: c.parameters,
				subcommands: c.subcommands,
			},
			subcommand_path,
		}
	}
}

## Searches a command's config for subcommands recursively.
find_subcommand : Base.SubcommandConfig, List(Str) -> Try(Base.SubcommandConfig, [KeyNotFound])
find_subcommand = |command, path|
	match path {
		[] => Ok(command)
		[first, .. as rest] =>
			match command.subcommands {
				NoSubcommands => Err(KeyNotFound)
				HasSubcommands(scs) => {
					sc = scs.get(first)?
					find_subcommand(sc, rest)
				}
			}
	}

commands_help : Base.SubcommandsConfig, Base.TextStyle -> Str
commands_help = |subcommands, text_style| {
	commands =
		match subcommands {
			NoSubcommands => []
			HasSubcommands(sc) => sc.to_list()
		}

	aligned_commands = align_two_columns(commands.map(|(name, sub_config)| (name, sub_config.description)), text_style)

	(style, reset) = heading_style(text_style)

	"${style}Commands:${reset}\n${Str.join_with(aligned_commands, "\n")}"
}

parameters_help : List(Base.ParameterConfig), Base.TextStyle -> Str
parameters_help = |params, text_style| {
	formatted_params = align_two_columns(params.map(|param| ("<${param.name}${ellipsis(param.plurality)}>", param.help)), text_style)

	(style, reset) = heading_style(text_style)

	"${style}Arguments:${reset}\n${Str.join_with(formatted_params, "\n")}"
}

short_and_long_names : Base.OptionConfig -> List(Str)
short_and_long_names = |{ short, long, .. }| {
	short_name = if (short != "") "-${short}" else ""
	long_name = if (long != "") "--${long}" else ""

	[short_name, long_name].drop_if(Str.is_empty)
}

value_type_name : Base.OptionConfig -> Str
value_type_name = |option|
	match option.expected_value {
		NothingExpected => ""
		ExpectsValue(name) => " ${Utils.to_upper_case(name)}"
	}

option_name_formatter : Base.OptionConfig -> Str
option_name_formatter = |option| {
	type_name = value_type_name(option)

	Str.join_with(short_and_long_names(option).map(|name| Str.concat(name, type_name)), ", ")
}

option_simple_name_formatter : Base.OptionConfig -> Str
option_simple_name_formatter = |option|
	Str.concat(Str.join_with(short_and_long_names(option), "/"), value_type_name(option))

options_help : List(Base.OptionConfig), Base.TextStyle -> Str
options_help = |options, text_style| {
	formatted_options = align_two_columns(options.map(|option| (option_name_formatter(option), option.help)), text_style)

	(style, reset) = heading_style(text_style)

	"${style}Options:${reset}\n${Str.join_with(formatted_options, "\n")}"
}

indent_multiline_string_by : Str, U64 -> Str
indent_multiline_string_by = |string, indent_amount| {
	indentation = Str.repeat(" ", indent_amount)

	lines = string.split_on("\n").map_with_index(
		|line, index|
			if index == 0 {
				line
			} else {
				Str.concat(indentation, line)
			},
	)

	Str.join_with(lines, "\n")
}

align_two_columns : List((Str, Str)), Base.TextStyle -> List(Str)
align_two_columns = |columns, text_style| {
	max_first_column_len = columns.map(|(first, _second)| first.count_utf8_bytes()).max() ?? 0

	(style, reset) =
		match text_style {
			Color => (bold_ansi_code, reset_ansi_code)
			Plain => ("", "")
		}

	columns.map(
		|(first, second)| {
			buffer = Str.repeat(" ", max_first_column_len - first.count_utf8_bytes())
			second_shifted = indent_multiline_string_by(second, max_first_column_len + 4)

			"  ${style}${first}${buffer}${reset}  ${second_shifted}"
		},
	)
}

expect indent_multiline_string_by("a\nb\nc", 2) == "a\n  b\n  c"

expect align_two_columns([("-a", "Alpha."), ("--beta", "Beta.")], Plain) == ["  -a      Alpha.", "  --beta  Beta."]
