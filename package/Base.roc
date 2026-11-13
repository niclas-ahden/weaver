import Arg
import Parser

## The types shared by the rest of Weaver: the config that options,
## parameters and subcommands record about themselves, the errors parsing can
## end in, and the parsers that a CLI is built out of.
Base :: [].{

	## The result of attempting to parse args into config data.
	ArgParserResult(a) : [
		ShowHelp({ subcommand_path : List(Str) }),
		ShowVersion,
		IncorrectUsage(ArgExtractErr, { subcommand_path : List(Str) }),
		SuccessfullyParsed(a),
	]

	## The parameters that an [ArgParser] takes to extract data
	## from args.
	ArgParserParams : { args : List(Parser.ParsedArg), subcommand_path : List(Str) }

	## The intermediate state that an [ArgParser] passes between
	## different parsing steps.
	ArgParserState(a) : { data : a, remaining_args : List(Parser.ParsedArg), subcommand_path : List(Str) }

	## A function that takes command line arguments and a subcommand,
	## and attempts to extract configuration data from said arguments.
	ArgParser(a) : ArgParserParams -> ArgParserResult(ArgParserState(a))

	## Errors that can occur while extracting values from command line arguments.
	ArgExtractErr : [
		NoSubcommandCalled,
		MissingOption(OptionConfig),
		OptionCanOnlyBeSetOnce(OptionConfig),
		NoValueProvidedForOption(OptionConfig),
		OptionDoesNotExpectValue(OptionConfig),
		CannotUsePartialShortGroupAsValue(OptionConfig, List(Str)),
		InvalidOptionValue(InvalidValue, OptionConfig),
		InvalidParamValue(InvalidValue, ParameterConfig),
		MissingParam(ParameterConfig),
		UnrecognizedShortArg(Str),
		UnrecognizedLongArg(Str),
		ExtraParamProvided(Arg),
	]

	## Whether help text should have fancy styling.
	TextStyle : [Color, Plain]

	## The type of value that an option expects to parse.
	ExpectedValue : [ExpectsValue(Str), NothingExpected]

	## How many values an option/parameter can take.
	Plurality : [Optional, One, Many]

	## The two built-in flags that we parse automatically.
	SpecialFlags : { help : Bool, version : Bool }

	## Why a value could not be parsed.
	InvalidValue : [InvalidNumStr, InvalidValue(Str), InvalidUtf8]

	## The value an option or parameter takes when it is not given:
	## none, a fixed value, or one generated when it is needed.
	DefaultValue(a) : [NoDefault, Value(a), Generate({} -> a)]

	## A parser that extracts an argument value from a string.
	ValueParser(a) : Arg -> Try(a, InvalidValue)

	## The settings for an option that takes no value or has no default.
	OptionConfigBaseParams : {
		short ?: Str,
		long ?: Str,
		help ?: Str,
	}

	## The settings for an option that can have a default value.
	DefaultableOptionConfigBaseParams(a) : {
		short ?: Str,
		long ?: Str,
		help ?: Str,
		default ?: DefaultValue(a),
	}

	## The settings for an option of a custom type.
	OptionConfigParams(a) : {
		short ?: Str,
		long ?: Str,
		help ?: Str,
		type : Str,
		parser : ValueParser(a),
	}

	## The settings for an option of a custom type that can have a default value.
	DefaultableOptionConfigParams(a) : {
		short ?: Str,
		long ?: Str,
		help ?: Str,
		type : Str,
		parser : ValueParser(a),
		default ?: DefaultValue(a),
	}

	## Metadata for options in our CLI building system.
	OptionConfig : {
		expected_value : ExpectedValue,
		plurality : Plurality,
		short : Str,
		long : Str,
		help : Str,
	}

	## The settings for a parameter that has no default.
	ParameterConfigBaseParams : {
		name : Str,
		help ?: Str,
	}

	## The settings for a parameter that can have a default value.
	DefaultableParameterConfigBaseParams(a) : {
		name : Str,
		help ?: Str,
		default ?: DefaultValue(a),
	}

	## The settings for a parameter of a custom type.
	ParameterConfigParams(a) : {
		name : Str,
		help ?: Str,
		type : Str,
		parser : ValueParser(a),
	}

	## The settings for a parameter of a custom type that can have a default value.
	DefaultableParameterConfigParams(a) : {
		name : Str,
		help ?: Str,
		type : Str,
		parser : ValueParser(a),
		default ?: DefaultValue(a),
	}

	## Metadata for parameters in our CLI building system.
	ParameterConfig : {
		name : Str,
		help : Str,
		type : Str,
		plurality : Plurality,
	}

	## The settings for bundling a CLI.
	CliConfigParams : {
		name : Str,
		authors ?: List(Str),
		version ?: Str,
		description ?: Str,
		text_style ?: TextStyle,
	}

	## Metadata for a root-level CLI.
	CliConfig : {
		name : Str,
		authors : List(Str),
		version : Str,
		description : Str,
		subcommands : SubcommandsConfig,
		options : List(OptionConfig),
		parameters : List(ParameterConfig),
	}

	## The settings for bundling a subcommand.
	SubcommandConfigParams : {
		name : Str,
		description ?: Str,
	}

	## Metadata for a set of subcommands under a parent command.
	##
	## Since subcommands can have their own sub-subcommands,
	## this type needs to be an enum with an empty variant
	## to avoid infinite recursion.
	SubcommandsConfig := [
		NoSubcommands,
		HasSubcommands(Dict(Str, SubcommandConfig)),
	]

	## Metadata for a subcommand.
	SubcommandConfig : {
		description : Str,
		subcommands : SubcommandsConfig,
		options : List(OptionConfig),
		parameters : List(ParameterConfig),
	}

	## A bind operation for [ArgParserState].
	##
	## If an [ArgParser] successfully parses some data, then said data
	## is provided to a callback and the resulting [ArgParserResult] is
	## passed along in the newly bound [ArgParser].
	on_successful_arg_parse : ArgParser(a), (ArgParserState(a) -> ArgParserResult(ArgParserState(b))) -> ArgParser(b)
	on_successful_arg_parse = |parser, mapper|
		|input|
			match parser(input) {
				ShowVersion => ShowVersion
				ShowHelp(sp) => ShowHelp(sp)
				IncorrectUsage(arg_extract_err, sp) => IncorrectUsage(arg_extract_err, sp)
				SuccessfullyParsed({ data, remaining_args, subcommand_path }) => mapper({ data, remaining_args, subcommand_path })
			}

	## Maps successfully parsed data that was parsed by an [ArgParser]
	## by a user-defined operation.
	map_successfully_parsed : ArgParserResult(a), (a -> b) -> ArgParserResult(b)
	map_successfully_parsed = |result, mapper|
		match result {
			ShowVersion => ShowVersion
			ShowHelp(sp) => ShowHelp(sp)
			IncorrectUsage(arg_extract_err, sp) => IncorrectUsage(arg_extract_err, sp)
			SuccessfullyParsed(parsed) => SuccessfullyParsed(mapper(parsed))
		}

	## The type name of string options and parameters in help text.
	str_type_name : Str
	str_type_name = "str"

	## The type name of number options and parameters in help text.
	num_type_name : Str
	num_type_name = "num"

	## Metadata for the `-h/--help` option that we parse automatically.
	help_option : OptionConfig
	help_option = {
		short: "h",
		long: "help",
		help: "Show this help page.",
		expected_value: NothingExpected,
		plurality: Optional,
	}

	## Metadata for the `-V/--version` option that we parse automatically.
	version_option : OptionConfig
	version_option = {
		short: "V",
		long: "version",
		help: "Show the version.",
		expected_value: NothingExpected,
		plurality: Optional,
	}
}
