import Utils
import Base

## Check the parts of a CLI's configuration that the type system can't.
Validate :: [].{

	## A name and the subcommand it was found at.
	NameAtSubcommand : { name : Str, subcommand_path : List(Str) }

	## An option and the subcommand it was found at.
	OptionAtSubcommand : { option : Base.OptionConfig, subcommand_path : List(Str) }

	## A parameter and the subcommand it was found at.
	ParamAtSubcommand : { param : Base.ParameterConfig, subcommand_path : List(Str) }

	## The types of errors that might be found in a misconfigured CLI.
	CliValidationErr : [
		OverlappingParameterNames({ first : Str, second : Str, subcommand_path : List(Str) }),
		OverlappingOptionNames({ left : OptionAtSubcommand, right : OptionAtSubcommand }),
		InvalidShortFlagName(NameAtSubcommand),
		InvalidLongFlagName(NameAtSubcommand),
		InvalidCommandName(NameAtSubcommand),
		InvalidParameterName(NameAtSubcommand),
		OptionMustHaveShortOrLongName({ subcommand_path : List(Str) }),
		InvalidOptionValueType(OptionAtSubcommand),
		InvalidParameterValueType(ParamAtSubcommand),
		OverrodeSpecialHelpFlag(OptionAtSubcommand),
		OverrodeSpecialVersionFlag(OptionAtSubcommand),
	]

	## Ensure that a CLI's configuration is valid.
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
	## - No options can overlap, even between different subcommands, so long
	##   as the options between the subcommands are ambiguous.
	##   - For example, a CLI with a `-t` option at the root level and also
	##     a `-t` option in the subcommand `sub` would fail validation since
	##     we wouldn't know who should get the `-t` option.
	##   - However, a CLI with two subcommands that each have a `-t` option
	##     would not fail validation since only one subcommand can be called
	##     at once.
	validate_cli : Base.CliConfig -> Try({}, CliValidationErr)
	validate_cli = |{ name, options, parameters, subcommands, .. }|
		validate_command({
			name,
			options,
			parent_options: [],
			parameters,
			subcommands,
			subcommand_path: [name],
		})
}

ValidateCommandParams : {
	name : Str,
	options : List(Base.OptionConfig),
	parent_options : List(Validate.OptionAtSubcommand),
	parameters : List(Base.ParameterConfig),
	subcommands : Base.SubcommandsConfig,
	subcommand_path : List(Str),
}

validate_command : ValidateCommandParams -> Try({}, Validate.CliValidationErr)
validate_command = |{ name, options, parent_options, parameters, subcommands, subcommand_path }| {
	ensure_command_is_well_named({ name, subcommand_path })?

	for option in options {
		ensure_option_is_well_named({ option, subcommand_path })?
		ensure_option_value_type_is_well_named({ option, subcommand_path })?
	}

	for param in parameters {
		ensure_param_is_well_named({ name: param.name, subcommand_path })?
		ensure_param_value_type_is_well_named({ param, subcommand_path })?
	}

	check_if_there_are_overlapping_parameters(parameters, subcommand_path)?

	options_here = options.map(|option| { option, subcommand_path }).concat(parent_options)

	match subcommands {
		HasSubcommands(subcommand_configs) if !subcommand_configs.is_empty() => {
			for (subcommand_name, subcommand) in subcommand_configs.to_list() {
				validate_command({
					name: subcommand_name,
					options: subcommand.options,
					parent_options: options_here,
					parameters: subcommand.parameters,
					subcommands: subcommand.subcommands,
					subcommand_path: subcommand_path.append(subcommand_name),
				})?
			}
			Ok({})
		}

		_ => check_if_there_are_overlapping_options(options_here)
	}
}

ensure_command_is_well_named : Validate.NameAtSubcommand -> Try({}, Validate.CliValidationErr)
ensure_command_is_well_named = |{ name, subcommand_path }|
	if Utils.is_kebab_case(name) {
		Ok({})
	} else {
		Err(InvalidCommandName({ name, subcommand_path }))
	}

ensure_param_is_well_named : Validate.NameAtSubcommand -> Try({}, Validate.CliValidationErr)
ensure_param_is_well_named = |{ name, subcommand_path }|
	if Utils.is_kebab_case(name) {
		Ok({})
	} else {
		Err(InvalidParameterName({ name, subcommand_path }))
	}

ensure_option_is_well_named : Validate.OptionAtSubcommand -> Try({}, Validate.CliValidationErr)
ensure_option_is_well_named = |{ option, subcommand_path }|
	match (option.short, option.long) {
		("", "") => Err(OptionMustHaveShortOrLongName({ subcommand_path: subcommand_path }))
		(short, "") => ensure_short_flag_is_well_named({ name: short, subcommand_path })
		("", long) => ensure_long_flag_is_well_named({ name: long, subcommand_path })
		(short, long) => {
			ensure_short_flag_is_well_named({ name: short, subcommand_path })?
			ensure_long_flag_is_well_named({ name: long, subcommand_path })
		}
	}

ensure_option_value_type_is_well_named : Validate.OptionAtSubcommand -> Try({}, Validate.CliValidationErr)
ensure_option_value_type_is_well_named = |{ option, subcommand_path }|
	match option.expected_value {
		ExpectsValue(type_name) =>
			if Utils.is_kebab_case(type_name) {
				Ok({})
			} else {
				Err(InvalidOptionValueType({ option, subcommand_path }))
			}

		NothingExpected => Ok({})
	}

ensure_param_value_type_is_well_named : Validate.ParamAtSubcommand -> Try({}, Validate.CliValidationErr)
ensure_param_value_type_is_well_named = |{ param, subcommand_path }|
	if Utils.is_kebab_case(param.type) {
		Ok({})
	} else {
		Err(InvalidParameterValueType({ param, subcommand_path }))
	}

ensure_short_flag_is_well_named : Validate.NameAtSubcommand -> Try({}, Validate.CliValidationErr)
ensure_short_flag_is_well_named = |{ name, subcommand_path }|
	if name.count_utf8_bytes() != 1 {
		Err(InvalidShortFlagName({ name, subcommand_path }))
	} else {
		Ok({})
	}

ensure_long_flag_is_well_named : Validate.NameAtSubcommand -> Try({}, Validate.CliValidationErr)
ensure_long_flag_is_well_named = |{ name, subcommand_path }|
	if name.count_utf8_bytes() > 1 and Utils.is_kebab_case(name) {
		Ok({})
	} else {
		Err(InvalidLongFlagName({ name, subcommand_path }))
	}

ensure_option_names_do_not_overlap : Validate.OptionAtSubcommand, Validate.OptionAtSubcommand -> Try({}, Validate.CliValidationErr)
ensure_option_names_do_not_overlap = |left, right| {
	same_command = left.subcommand_path == right.subcommand_path
	either_name_matches =
		(left.option.short != "" and left.option.short == right.option.short)
			or (left.option.long != "" and left.option.long == right.option.long)

	matches_help =
		left.option.short == Base.help_option.short or left.option.long == Base.help_option.long
	matches_version =
		left.option.short == Base.version_option.short or left.option.long == Base.version_option.long

	if either_name_matches {
		if matches_help {
			if same_command {
				Err(OverrodeSpecialHelpFlag(left))
			} else {
				Ok({})
			}
		} else if matches_version {
			if same_command {
				Err(OverrodeSpecialVersionFlag(left))
			} else {
				Ok({})
			}
		} else {
			Err(OverlappingOptionNames({ left, right }))
		}
	} else {
		Ok({})
	}
}

check_if_there_are_overlapping_options : List(Validate.OptionAtSubcommand) -> Try({}, Validate.CliValidationErr)
check_if_there_are_overlapping_options = |options| {
	var $rest = options
	while !$rest.is_empty() {
		left = $rest.first() ?? return Ok({})
		$rest = $rest.drop_first(1)
		for right in $rest {
			ensure_option_names_do_not_overlap(left, right)?
		}
	}
	Ok({})
}

check_if_there_are_overlapping_parameters : List(Base.ParameterConfig), List(Str) -> Try({}, Validate.CliValidationErr)
check_if_there_are_overlapping_parameters = |parameters, subcommand_path| {
	var $rest = parameters
	while !$rest.is_empty() {
		first = $rest.first() ?? return Ok({})
		$rest = $rest.drop_first(1)
		for second in $rest {
			if first.name == second.name {
				return Err(OverlappingParameterNames({ first: first.name, second: second.name, subcommand_path }))
			}
		}
	}
	Ok({})
}
