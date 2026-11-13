import Arg
import Base
import Validate

## Render errors we encounter in a human-readable format so that
## they are readable for developers and users on failure.
ErrorFormatter :: [].{

	## Render [Base.ArgExtractErr] errors as readable messages.
	##
	## Used in [Cli.parse_or_display_message].
	format_arg_extract_err : Base.ArgExtractErr -> Str
	format_arg_extract_err = |err|
		match err {
			NoSubcommandCalled => "A subcommand must be called."

			MissingOption(option) => "Required option ${option_display_name(option)} is missing."

			OptionCanOnlyBeSetOnce(option) => "Option ${option_display_name(option)} can only be set once."

			NoValueProvidedForOption(option) => "Option ${option_display_name(option)} expects a ${option_type_name(option)}."

			OptionDoesNotExpectValue(option) => "Option ${option_display_name(option)} does not expect a value."

			CannotUsePartialShortGroupAsValue(option, partial_group) => {
				rendered_group = "-${Str.join_with(partial_group, "")}"
				"The short option group ${rendered_group} was partially consumed and cannot be used as a value for ${option_display_name(option)}."
			}

			InvalidOptionValue(value_err, option) =>
				match value_err {
					InvalidNumStr => "The value provided to ${option_display_name(option)} was not a valid number."
					InvalidValue(reason) => "The value provided to ${option_display_name(option)} was not a valid ${option_type_name(option)}: ${reason}"
					InvalidUtf8 => "The value provided to ${option_display_name(option)} was not valid UTF-8."
				}

			InvalidParamValue(value_err, param) =>
				match value_err {
					InvalidNumStr => "The value provided to the '${param.name}' parameter was not a valid number."
					InvalidValue(reason) => "The value provided to the '${param.name}' parameter was not a valid ${full_type_name(param.type)}: ${reason}."
					InvalidUtf8 => "The value provided to the '${param.name}' parameter was not valid UTF-8."
				}

			MissingParam(parameter) => "The '${parameter.name}' parameter did not receive a value."

			UnrecognizedShortArg(short) => "The argument -${short} was not recognized."

			UnrecognizedLongArg(long) => "The argument --${long} was not recognized."

			ExtraParamProvided(param) => "The parameter \"${Arg.display(param)}\" was not expected."
		}

	## Render [Validate.CliValidationErr] errors as readable messages.
	##
	## Displayed as the crash message when [Cli.assert_valid] fails.
	format_cli_validation_err : Validate.CliValidationErr -> Str
	format_cli_validation_err = |err|
		match err {
			OverlappingOptionNames({ left: option1, right: option2 }) =>
				"The ${option_at_subcommand_name(option1)} overlaps with the ${option_at_subcommand_name(option2)}."

			OverlappingParameterNames({ first, second, subcommand_path }) =>
				"The ${param_at_subcommand_name({ name: first, subcommand_path })} overlaps with the ${param_at_subcommand_name({ name: second, subcommand_path })}."

			InvalidShortFlagName({ name, subcommand_path }) =>
				"The ${value_at_subcommand_name({ name: "option '-${name}'", subcommand_path })} is not a single character."

			InvalidLongFlagName({ name, subcommand_path }) =>
				"The ${value_at_subcommand_name({ name: "option '--${name}'", subcommand_path })} is not kebab-case and at least two characters."

			InvalidCommandName({ name, subcommand_path }) =>
				"The ${value_at_subcommand_name({ name: "command '${name}'", subcommand_path })} is not kebab-case."

			InvalidParameterName({ name, subcommand_path }) =>
				"The ${value_at_subcommand_name({ name: "parameter '${name}'", subcommand_path })} is not kebab-case."

			OptionMustHaveShortOrLongName({ subcommand_path }) =>
				"An ${value_at_subcommand_name({ name: "option", subcommand_path })} has neither a short or long name."

			InvalidOptionValueType({ option, subcommand_path }) => {
				value_type =
					match option.expected_value {
						ExpectsValue(type_name) => type_name
						NothingExpected => ""
					}

				"The ${option_at_subcommand_name({ option, subcommand_path })} has value type '${value_type}', which is not kebab-case."
			}

			InvalidParameterValueType({ param, subcommand_path }) =>
				"The ${value_at_subcommand_name({ name: "parameter '${param.name}'", subcommand_path })} has value type '${param.type}', which is not kebab-case."

			OverrodeSpecialHelpFlag({ option, subcommand_path }) =>
				"The ${option_at_subcommand_name({ option, subcommand_path })} tried to overwrite the built-in -h/--help flag."

			OverrodeSpecialVersionFlag({ option, subcommand_path }) =>
				"The ${option_at_subcommand_name({ option, subcommand_path })} tried to overwrite the built-in -V/--version flag."
		}
}

option_display_name : Base.OptionConfig -> Str
option_display_name = |option|
	match (option.short, option.long) {
		("", "") => ""
		(short, "") => "-${short}"
		("", long) => "--${long}"
		(short, long) => "-${short}/--${long}"
	}

option_type_name : Base.OptionConfig -> Str
option_type_name = |option|
	match option.expected_value {
		ExpectsValue(type_name) => full_type_name(type_name)
		NothingExpected => ""
	}

full_type_name : Str -> Str
full_type_name = |type_name|
	if type_name == Base.str_type_name {
		"string"
	} else if type_name == Base.num_type_name {
		"number"
	} else {
		type_name
	}

value_at_subcommand_name : Validate.NameAtSubcommand -> Str
value_at_subcommand_name = |{ name, subcommand_path }| {
	subcommand_path_suffix =
		if subcommand_path.len() <= 1 {
			""
		} else {
			" for command '${Str.join_with(subcommand_path, " ")}'"
		}

	"${name}${subcommand_path_suffix}"
}

option_at_subcommand_name : Validate.OptionAtSubcommand -> Str
option_at_subcommand_name = |{ option, subcommand_path }|
	value_at_subcommand_name({ name: "option '${option_display_name(option)}'", subcommand_path })

param_at_subcommand_name : Validate.NameAtSubcommand -> Str
param_at_subcommand_name = |{ name, subcommand_path }|
	value_at_subcommand_name({ name: "parameter '${name}'", subcommand_path })
