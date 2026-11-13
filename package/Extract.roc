import Arg
import Base
import Parser

## Take the values of one option or parameter out of the parsed arguments,
## and hand back the arguments that are left.
Extract :: [].{

	## Collect the values of a parameter from the start of the arguments.
	extract_param_values : { args : List(Parser.ParsedArg), param : Base.ParameterConfig } -> Try({ values : List(Arg), remaining_args : List(Parser.ParsedArg) }, Base.ArgExtractErr)
	extract_param_values = |{ args, param }| {
		starting_state = {
			action: GetParam,
			values: [],
			remaining_args: [],
		}

		state_after = args.fold_try(
			starting_state,
			|state, arg|
				match state.action {
					GetParam => extract_single_param(state, param, arg)
					StopParsing => Ok({ ..state, remaining_args: state.remaining_args.append(arg) })
				},
		)?

		Ok({ values: state_after.values, remaining_args: state_after.remaining_args })
	}

	## Collect every value of an option, wherever it is in the arguments.
	extract_option_values : { args : List(Parser.ParsedArg), option : Base.OptionConfig } -> Try({ values : List(Parser.ArgValue), remaining_args : List(Parser.ParsedArg) }, Base.ArgExtractErr)
	extract_option_values = |{ args, option }| {
		starting_state = {
			action: FindOption,
			values: [],
			remaining_args: [],
		}

		state_after = args.fold_try(
			starting_state,
			|state, arg|
				match state.action {
					FindOption => find_option_for_extraction(state, arg, option)
					GetValue => get_value_for_extraction(state, arg, option)
				},
		)?

		match state_after.action {
			GetValue => Err(NoValueProvidedForOption(option))
			FindOption => Ok({ values: state_after.values, remaining_args: state_after.remaining_args })
		}
	}
}

ExtractParamValuesState : {
	action : [GetParam, StopParsing],
	values : List(Arg),
	remaining_args : List(Parser.ParsedArg),
}

ExtractOptionValueWalkerState : {
	action : [FindOption, GetValue],
	values : List(Parser.ArgValue),
	remaining_args : List(Parser.ParsedArg),
}

extract_single_param : ExtractParamValuesState, Base.ParameterConfig, Parser.ParsedArg -> Try(ExtractParamValuesState, Base.ArgExtractErr)
extract_single_param = |state, param, arg|
	match arg {
		Short(short) => Err(UnrecognizedShortArg(short))
		ShortGroup(group) => Err(UnrecognizedShortArg(group.names.first() ?? ""))
		Long(long) => Err(UnrecognizedLongArg(long.name))
		Parameter(p) =>
			match param.plurality {
				Optional | One => Ok({ ..state, action: StopParsing, values: state.values.append(p) })
				Many => Ok({ ..state, values: state.values.append(p) })
			}
	}

find_option_for_extraction : ExtractOptionValueWalkerState, Parser.ParsedArg, Base.OptionConfig -> Try(ExtractOptionValueWalkerState, Base.ArgExtractErr)
find_option_for_extraction = |state, arg, option|
	match arg {
		Short(short) =>
			if short == option.short {
				if option.expected_value == NothingExpected {
					Ok({ ..state, values: state.values.append(Err(NoValue)) })
				} else {
					Ok({ ..state, action: GetValue })
				}
			} else {
				Ok({ ..state, remaining_args: state.remaining_args.append(arg) })
			}

		ShortGroup(short_group) => find_options_in_short_group(state, option, short_group)

		Long(long) =>
			if long.name == option.long {
				if option.expected_value == NothingExpected {
					match long.value {
						Ok(_val) => Err(OptionDoesNotExpectValue(option))
						Err(NoValue) => Ok({ ..state, values: state.values.append(Err(NoValue)) })
					}
				} else {
					match long.value {
						Ok(val) => Ok({ ..state, values: state.values.append(Ok(val)) })
						Err(NoValue) => Ok({ ..state, action: GetValue })
					}
				}
			} else {
				Ok({ ..state, remaining_args: state.remaining_args.append(arg) })
			}

		Parameter(_) => Ok({ ..state, remaining_args: state.remaining_args.append(arg) })
	}

find_options_in_short_group : ExtractOptionValueWalkerState, Base.OptionConfig, { names : List(Str), complete : [Partial, Complete] } -> Try(ExtractOptionValueWalkerState, Base.ArgExtractErr)
find_options_in_short_group = |state, option, short_group| {
	starting_state : { action : [FindOption, GetValue], remaining : List(Str), values : List(Parser.ArgValue) }
	starting_state = { action: FindOption, remaining: [], values: [] }

	state_after = short_group.names.fold_try(
		starting_state,
		|sg_state, name|
			match sg_state.action {
				GetValue => Err(CannotUsePartialShortGroupAsValue(option, short_group.names))
				FindOption =>
					if name == option.short {
						if option.expected_value == NothingExpected {
							Ok({ ..sg_state, values: sg_state.values.append(Err(NoValue)) })
						} else {
							Ok({ ..sg_state, action: GetValue })
						}
					} else {
						Ok({ ..sg_state, remaining: sg_state.remaining.append(name) })
					}
			},
	)?

	option_was_found = !state_after.values.is_empty() or state_after.action == GetValue

	rest_of_group =
		if !option_was_found {
			Ok(ShortGroup(short_group))
		} else if state_after.remaining.is_empty() {
			Err(NoValue)
		} else {
			Ok(ShortGroup({ complete: Partial, names: state_after.remaining }))
		}

	Ok({
		action: state_after.action,
		remaining_args: state.remaining_args.append_if_ok(rest_of_group),
		values: state.values.concat(state_after.values),
	})
}

get_value_for_extraction : ExtractOptionValueWalkerState, Parser.ParsedArg, Base.OptionConfig -> Try(ExtractOptionValueWalkerState, Base.ArgExtractErr)
get_value_for_extraction = |state, arg, option| {
	value =
		match arg {
			Short(s) => Arg.from_str("-${s}")
			ShortGroup({ names, complete: Complete }) => Arg.from_str("-${Str.join_with(names, "")}")
			ShortGroup({ names, complete: Partial }) => return Err(CannotUsePartialShortGroupAsValue(option, names))
			# Using [Arg.display] is safe here because `val` must be valid UTF-8 to be `Ok`
			Long({ name, value: Ok(val) }) => Arg.from_str("--${name}=${Arg.display(val)}")
			Long({ name, value: Err(NoValue) }) => Arg.from_str("--${name}")
			Parameter(p) => p
		}

	Ok({ ..state, action: FindOption, values: state.values.append(Ok(value)) })
}
