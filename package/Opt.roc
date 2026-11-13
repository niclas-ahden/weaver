import Arg
import Base
import Cli
import Extract
import Parser

## Options that your CLI will parse as fields in your config.
##
## Options are given by name, as `-a 1`, `--alpha 1` or `--alpha=1`,
## and can be given in any order. They must come before any subcommand or
## parameter fields in a record builder.
Opt :: [].{

	## Add a required option that takes a custom type to your CLI builder.
	##
	## You need to provide a kebab-case type name for your help messages as well as a
	## parser for said type. The parser needs to return an `Err(InvalidValue(Str))`
	## on failure, where the `Str` is the reason the parsing failed that will
	## get displayed in the incorrect usage message.
	##
	## Parsing arguments will fail if the option is not given as an argument
	## or a value is not provided to the option.
	##
	## ```roc
	## parse_color : Arg -> Try([Green, Red, Blue], [InvalidNumStr, InvalidValue(Str), InvalidUtf8])
	## parse_color = |color|
	##     match Arg.to_str(color) {
	##         Ok("green") => Ok(Green)
	##         Ok("red") => Ok(Red)
	##         Ok("blue") => Ok(Blue)
	##         _ => Err(InvalidValue("'${Arg.display(color)}' is not a valid color, must be green, red, or blue"))
	##     }
	##
	## expect
	##     Opt.single({ short: "c", parser: parse_color, type: "color" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("-c"), Utf8("green")])
	##     == Ok(Green)
	## ```
	single : Base.DefaultableOptionConfigParams(a) -> Cli(a, Cli.GetOptionsAction, Cli.GetOptionsAction)
	single = |{ parser, type, short, long, help, default }| {
		option = { expected_value: ExpectsValue(type), plurality: One, short: short ?? "", long: long ?? "", help: help ?? "" }
		default_value = default ?? NoDefault

		value_parser = |values|
			match get_maybe_value(values, option)? {
				Err(NoValue) =>
					match default_value {
						Value(value) => Ok(value)
						Generate(generator) => Ok(generator({}))
						NoDefault => Err(MissingOption(option))
					}
				Ok(Err(NoValue)) => Err(NoValueProvidedForOption(option))
				Ok(Ok(val)) => parser(val).map_err(|err| InvalidOptionValue(err, option))
			}

		builder_with_option_parser(option, value_parser)
	}

	## Add an optional option that takes a custom type to your CLI builder.
	##
	## You need to provide a kebab-case type name for your help messages as well as a
	## parser for said type. The parser needs to return an `Err(InvalidValue(Str))`
	## on failure, where the `Str` is the reason the parsing failed that will
	## get displayed in the incorrect usage message.
	##
	## Parsing arguments will fail if more than one instance of the argument
	## is provided, there is no value given for the option call, or the value
	## doesn't parse correctly.
	##
	## ```roc
	## expect
	##     Opt.maybe({ short: "c", type: "color", parser: parse_color })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([])
	##     == Ok(Err(NoValue))
	## ```
	maybe : Base.OptionConfigParams(data) -> Cli(Try(data, [NoValue]), Cli.GetOptionsAction, Cli.GetOptionsAction)
	maybe = |{ parser, type, short, long, help }| {
		option = { expected_value: ExpectsValue(type), plurality: Optional, short: short ?? "", long: long ?? "", help: help ?? "" }

		value_parser = |values|
			match get_maybe_value(values, option)? {
				Err(NoValue) => Ok(Err(NoValue))
				Ok(Err(NoValue)) => Err(NoValueProvidedForOption(option))
				Ok(Ok(val)) =>
					match parser(val) {
						Ok(value) => Ok(Ok(value))
						Err(err) => Err(InvalidOptionValue(err, option))
					}
			}

		builder_with_option_parser(option, value_parser)
	}

	## Add an option that takes a custom type and can be given multiple times
	## to your CLI builder.
	##
	## You need to provide a kebab-case type name for your help messages as well as a
	## parser for said type. The parser needs to return an `Err(InvalidValue(Str))`
	## on failure, where the `Str` is the reason the parsing failed that will
	## get displayed in the incorrect usage message.
	##
	## Parsing arguments will fail if any calls of the option don't provide
	## a value or any of the options don't parse correctly.
	##
	## ```roc
	## expect
	##     Opt.list({ short: "c", long: "color", type: "color", parser: parse_color })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("-c"), Utf8("green"), Utf8("--color=red")])
	##     == Ok([Green, Red])
	## ```
	list : Base.OptionConfigParams(data) -> Cli(List(data), Cli.GetOptionsAction, Cli.GetOptionsAction)
	list = |{ parser, type, short, long, help }| {
		option = { expected_value: ExpectsValue(type), plurality: Many, short: short ?? "", long: long ?? "", help: help ?? "" }

		value_parser = |values|
			values.map_try(
				|value|
					match value {
						Err(NoValue) => Err(NoValueProvidedForOption(option))
						Ok(val) => parser(val).map_err(|err| InvalidOptionValue(err, option))
					},
			)

		builder_with_option_parser(option, value_parser)
	}

	## Add an optional flag to your CLI builder.
	##
	## Parsing arguments will fail if the flag is given more than once
	## or if a value is provided to it, e.g. `--flag=value`.
	##
	## ```roc
	## expect
	##     Opt.flag({ short: "f", long: "force" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("-f")])
	##     == Ok(True)
	## ```
	flag : Base.OptionConfigBaseParams -> Cli(Bool, Cli.GetOptionsAction, Cli.GetOptionsAction)
	flag = |{ short, long, help }| {
		option = { expected_value: NothingExpected, plurality: Optional, short: short ?? "", long: long ?? "", help: help ?? "" }

		value_parser = |values|
			match get_maybe_value(values, option)? {
				Err(NoValue) => Ok(False)
				Ok(Err(NoValue)) => Ok(True)
				Ok(Ok(_val)) => Err(OptionDoesNotExpectValue(option))
			}

		builder_with_option_parser(option, value_parser)
	}

	## Add a flag that can be given multiple times to your CLI builder.
	##
	## Parsing arguments will fail if this flag is ever given a value,
	## e.g. `--flag=value`.
	##
	## ```roc
	## expect
	##     Opt.count({ short: "f", long: "force" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("-f"), Utf8("--force"), Utf8("-fff")])
	##     == Ok(5)
	## ```
	count : Base.OptionConfigBaseParams -> Cli(U64, Cli.GetOptionsAction, Cli.GetOptionsAction)
	count = |{ short, long, help }| {
		option = { expected_value: NothingExpected, plurality: Many, short: short ?? "", long: long ?? "", help: help ?? "" }

		value_parser = |values|
			if values.any(|value| value.is_ok()) {
				Err(OptionDoesNotExpectValue(option))
			} else {
				Ok(values.len())
			}

		builder_with_option_parser(option, value_parser)
	}

	## Add a required option that takes an [Arg] to your CLI builder.
	##
	## Parsing arguments will fail if the option is not given as an argument
	## or a value is not provided to the option.
	##
	## ```roc
	## expect
	##     Opt.arg({ long: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("--answer=abc")])
	##     == Ok(Arg.from_str("abc"))
	## ```
	arg : Base.DefaultableOptionConfigBaseParams(Arg) -> Cli(Arg, Cli.GetOptionsAction, Cli.GetOptionsAction)
	arg = |{ short, long, help, default }|
		Opt.single({ parser: |a| Ok(a), type: Base.str_type_name, short: short ?? "", long: long ?? "", help: help ?? "", default: default ?? NoDefault })

	## Add an optional option that takes an [Arg] to your CLI builder.
	##
	## Parsing arguments will fail if more than one instance of the argument
	## is provided or there is no value given for the option call.
	##
	## ```roc
	## expect
	##     Opt.maybe_arg({ long: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([])
	##     == Ok(Err(NoValue))
	## ```
	maybe_arg : Base.OptionConfigBaseParams -> Cli(Try(Arg, [NoValue]), Cli.GetOptionsAction, Cli.GetOptionsAction)
	maybe_arg = |{ short, long, help }|
		Opt.maybe({ parser: |a| Ok(a), type: Base.str_type_name, short: short ?? "", long: long ?? "", help: help ?? "" })

	## Add an option that takes an [Arg] and can be given multiple times
	## to your CLI builder.
	##
	## Parsing arguments will fail if any calls of the option don't provide
	## a value.
	##
	## ```roc
	## expect
	##     Opt.arg_list({ short: "a", long: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("-a"), Utf8("abc"), Utf8("--answer"), Utf8("def"), Utf8("--answer=ghi")])
	##     == Ok([Arg.from_str("abc"), Arg.from_str("def"), Arg.from_str("ghi")])
	## ```
	arg_list : Base.OptionConfigBaseParams -> Cli(List(Arg), Cli.GetOptionsAction, Cli.GetOptionsAction)
	arg_list = |{ short, long, help }|
		Opt.list({ parser: |a| Ok(a), type: Base.str_type_name, short: short ?? "", long: long ?? "", help: help ?? "" })

	## Add a required option that takes a byte list to your CLI builder.
	##
	## Parsing arguments will fail if the option is not given as an argument
	## or a value is not provided to the option.
	##
	## ```roc
	## expect
	##     Opt.bytes({ long: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("--answer=abc")])
	##     == Ok([97, 98, 99])
	## ```
	bytes : Base.DefaultableOptionConfigBaseParams(List(U8)) -> Cli(List(U8), Cli.GetOptionsAction, Cli.GetOptionsAction)
	bytes = |{ short, long, help, default }|
		Opt.single({ parser: |a| Ok(Arg.to_bytes(a)), type: Base.str_type_name, short: short ?? "", long: long ?? "", help: help ?? "", default: default ?? NoDefault })

	## Add an optional option that takes a byte list to your CLI builder.
	##
	## Parsing arguments will fail if more than one instance of the argument
	## is provided or there is no value given for the option call.
	##
	## ```roc
	## expect
	##     Opt.maybe_bytes({ long: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([])
	##     == Ok(Err(NoValue))
	## ```
	maybe_bytes : Base.OptionConfigBaseParams -> Cli(Try(List(U8), [NoValue]), Cli.GetOptionsAction, Cli.GetOptionsAction)
	maybe_bytes = |{ short, long, help }|
		Opt.maybe({ parser: |a| Ok(Arg.to_bytes(a)), type: Base.str_type_name, short: short ?? "", long: long ?? "", help: help ?? "" })

	## Add an option that takes a byte list and can be given multiple times
	## to your CLI builder.
	##
	## Parsing arguments will fail if any calls of the option don't provide
	## a value.
	##
	## ```roc
	## expect
	##     Opt.bytes_list({ short: "a", long: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("-a"), Utf8("abc"), Utf8("--answer"), Utf8("def"), Utf8("--answer=ghi")])
	##     == Ok([[97, 98, 99], [100, 101, 102], [103, 104, 105]])
	## ```
	bytes_list : Base.OptionConfigBaseParams -> Cli(List(List(U8)), Cli.GetOptionsAction, Cli.GetOptionsAction)
	bytes_list = |{ short, long, help }|
		Opt.list({ parser: |a| Ok(Arg.to_bytes(a)), type: Base.str_type_name, short: short ?? "", long: long ?? "", help: help ?? "" })

	## Add a required option that takes a string to your CLI builder.
	##
	## Parsing arguments will fail if the option is not given as an argument,
	## a value is not provided to the option, or the value is not valid UTF-8.
	##
	## ```roc
	## expect
	##     Opt.str({ long: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("--answer=abc")])
	##     == Ok("abc")
	## ```
	str : Base.DefaultableOptionConfigBaseParams(Str) -> Cli(Str, Cli.GetOptionsAction, Cli.GetOptionsAction)
	str = |{ short, long, help, default }|
		Opt.single({ parser: parse_str, type: Base.str_type_name, short: short ?? "", long: long ?? "", help: help ?? "", default: default ?? NoDefault })

	## Add an optional option that takes a string to your CLI builder.
	##
	## Parsing arguments will fail if more than one instance of the argument
	## is provided, there is no value given for the option call, or the value is not valid UTF-8.
	##
	## ```roc
	## expect
	##     Opt.maybe_str({ long: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([])
	##     == Ok(Err(NoValue))
	## ```
	maybe_str : Base.OptionConfigBaseParams -> Cli(Try(Str, [NoValue]), Cli.GetOptionsAction, Cli.GetOptionsAction)
	maybe_str = |{ short, long, help }|
		Opt.maybe({ parser: parse_str, type: Base.str_type_name, short: short ?? "", long: long ?? "", help: help ?? "" })

	## Add an option that takes a string and can be given multiple times
	## to your CLI builder.
	##
	## Parsing arguments will fail if any calls of the option don't provide
	## a value, or the value is not valid UTF-8.
	##
	## ```roc
	## expect
	##     Opt.str_list({ short: "a", long: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("-a"), Utf8("abc"), Utf8("--answer"), Utf8("def"), Utf8("--answer=ghi")])
	##     == Ok(["abc", "def", "ghi"])
	## ```
	str_list : Base.OptionConfigBaseParams -> Cli(List(Str), Cli.GetOptionsAction, Cli.GetOptionsAction)
	str_list = |{ short, long, help }|
		Opt.list({ parser: parse_str, type: Base.str_type_name, short: short ?? "", long: long ?? "", help: help ?? "" })

	## Add a required option that takes a `Dec` to your CLI builder.
	##
	## Parsing arguments will fail if the option is not given as an argument,
	## a value is not provided to the option, or the value is not a number.
	##
	## ```roc
	## expect
	##     Opt.dec({ long: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("--answer=42.5")])
	##     == Ok(42.5)
	## ```
	dec : Base.DefaultableOptionConfigBaseParams(Dec) -> Cli(Dec, Cli.GetOptionsAction, Cli.GetOptionsAction)
	dec = |{ short, long, help, default }|
		Opt.single({ parser: |a| parse_num(a, Dec.from_str), type: Base.num_type_name, short: short ?? "", long: long ?? "", help: help ?? "", default: default ?? NoDefault })

	## Add an optional option that takes a `Dec` to your CLI builder.
	##
	## Parsing arguments will fail if more than one instance of the argument
	## is provided, there is no value given for the option call, or the value is not a number.
	##
	## ```roc
	## expect
	##     Opt.maybe_dec({ long: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([])
	##     == Ok(Err(NoValue))
	## ```
	maybe_dec : Base.OptionConfigBaseParams -> Cli(Try(Dec, [NoValue]), Cli.GetOptionsAction, Cli.GetOptionsAction)
	maybe_dec = |{ short, long, help }|
		Opt.maybe({ parser: |a| parse_num(a, Dec.from_str), type: Base.num_type_name, short: short ?? "", long: long ?? "", help: help ?? "" })

	## Add an option that takes a `Dec` and can be given multiple times
	## to your CLI builder.
	##
	## Parsing arguments will fail if any calls of the option don't provide
	## a value, or the value is not a number.
	##
	## ```roc
	## expect
	##     Opt.dec_list({ short: "a", long: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("-a"), Utf8("1"), Utf8("--answer=2"), Utf8("--answer"), Utf8("-3.0")])
	##     == Ok([1.0, 2.0, -3.0])
	## ```
	dec_list : Base.OptionConfigBaseParams -> Cli(List(Dec), Cli.GetOptionsAction, Cli.GetOptionsAction)
	dec_list = |{ short, long, help }|
		Opt.list({ parser: |a| parse_num(a, Dec.from_str), type: Base.num_type_name, short: short ?? "", long: long ?? "", help: help ?? "" })

	## Add a required option that takes a `F32` to your CLI builder.
	##
	## Parsing arguments will fail if the option is not given as an argument,
	## a value is not provided to the option, or the value is not a number.
	##
	## ```roc
	## expect
	##     Opt.f32({ long: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("--answer=42.5")])
	##     == Ok(42.5)
	## ```
	f32 : Base.DefaultableOptionConfigBaseParams(F32) -> Cli(F32, Cli.GetOptionsAction, Cli.GetOptionsAction)
	f32 = |{ short, long, help, default }|
		Opt.single({ parser: |a| parse_num(a, F32.from_str), type: Base.num_type_name, short: short ?? "", long: long ?? "", help: help ?? "", default: default ?? NoDefault })

	## Add an optional option that takes a `F32` to your CLI builder.
	##
	## Parsing arguments will fail if more than one instance of the argument
	## is provided, there is no value given for the option call, or the value is not a number.
	##
	## ```roc
	## expect
	##     Opt.maybe_f32({ long: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([])
	##     == Ok(Err(NoValue))
	## ```
	maybe_f32 : Base.OptionConfigBaseParams -> Cli(Try(F32, [NoValue]), Cli.GetOptionsAction, Cli.GetOptionsAction)
	maybe_f32 = |{ short, long, help }|
		Opt.maybe({ parser: |a| parse_num(a, F32.from_str), type: Base.num_type_name, short: short ?? "", long: long ?? "", help: help ?? "" })

	## Add an option that takes a `F32` and can be given multiple times
	## to your CLI builder.
	##
	## Parsing arguments will fail if any calls of the option don't provide
	## a value, or the value is not a number.
	##
	## ```roc
	## expect
	##     Opt.f32_list({ short: "a", long: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("-a"), Utf8("1"), Utf8("--answer=2"), Utf8("--answer"), Utf8("-3.0")])
	##     == Ok([1.0, 2.0, -3.0])
	## ```
	f32_list : Base.OptionConfigBaseParams -> Cli(List(F32), Cli.GetOptionsAction, Cli.GetOptionsAction)
	f32_list = |{ short, long, help }|
		Opt.list({ parser: |a| parse_num(a, F32.from_str), type: Base.num_type_name, short: short ?? "", long: long ?? "", help: help ?? "" })

	## Add a required option that takes a `F64` to your CLI builder.
	##
	## Parsing arguments will fail if the option is not given as an argument,
	## a value is not provided to the option, or the value is not a number.
	##
	## ```roc
	## expect
	##     Opt.f64({ long: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("--answer=42.5")])
	##     == Ok(42.5)
	## ```
	f64 : Base.DefaultableOptionConfigBaseParams(F64) -> Cli(F64, Cli.GetOptionsAction, Cli.GetOptionsAction)
	f64 = |{ short, long, help, default }|
		Opt.single({ parser: |a| parse_num(a, F64.from_str), type: Base.num_type_name, short: short ?? "", long: long ?? "", help: help ?? "", default: default ?? NoDefault })

	## Add an optional option that takes a `F64` to your CLI builder.
	##
	## Parsing arguments will fail if more than one instance of the argument
	## is provided, there is no value given for the option call, or the value is not a number.
	##
	## ```roc
	## expect
	##     Opt.maybe_f64({ long: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([])
	##     == Ok(Err(NoValue))
	## ```
	maybe_f64 : Base.OptionConfigBaseParams -> Cli(Try(F64, [NoValue]), Cli.GetOptionsAction, Cli.GetOptionsAction)
	maybe_f64 = |{ short, long, help }|
		Opt.maybe({ parser: |a| parse_num(a, F64.from_str), type: Base.num_type_name, short: short ?? "", long: long ?? "", help: help ?? "" })

	## Add an option that takes a `F64` and can be given multiple times
	## to your CLI builder.
	##
	## Parsing arguments will fail if any calls of the option don't provide
	## a value, or the value is not a number.
	##
	## ```roc
	## expect
	##     Opt.f64_list({ short: "a", long: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("-a"), Utf8("1"), Utf8("--answer=2"), Utf8("--answer"), Utf8("-3.0")])
	##     == Ok([1.0, 2.0, -3.0])
	## ```
	f64_list : Base.OptionConfigBaseParams -> Cli(List(F64), Cli.GetOptionsAction, Cli.GetOptionsAction)
	f64_list = |{ short, long, help }|
		Opt.list({ parser: |a| parse_num(a, F64.from_str), type: Base.num_type_name, short: short ?? "", long: long ?? "", help: help ?? "" })

	## Add a required option that takes a `U8` to your CLI builder.
	##
	## Parsing arguments will fail if the option is not given as an argument,
	## a value is not provided to the option, or the value is not a number.
	##
	## ```roc
	## expect
	##     Opt.u8({ long: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("--answer=42")])
	##     == Ok(42)
	## ```
	u8 : Base.DefaultableOptionConfigBaseParams(U8) -> Cli(U8, Cli.GetOptionsAction, Cli.GetOptionsAction)
	u8 = |{ short, long, help, default }|
		Opt.single({ parser: |a| parse_num(a, U8.from_str), type: Base.num_type_name, short: short ?? "", long: long ?? "", help: help ?? "", default: default ?? NoDefault })

	## Add an optional option that takes a `U8` to your CLI builder.
	##
	## Parsing arguments will fail if more than one instance of the argument
	## is provided, there is no value given for the option call, or the value is not a number.
	##
	## ```roc
	## expect
	##     Opt.maybe_u8({ long: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([])
	##     == Ok(Err(NoValue))
	## ```
	maybe_u8 : Base.OptionConfigBaseParams -> Cli(Try(U8, [NoValue]), Cli.GetOptionsAction, Cli.GetOptionsAction)
	maybe_u8 = |{ short, long, help }|
		Opt.maybe({ parser: |a| parse_num(a, U8.from_str), type: Base.num_type_name, short: short ?? "", long: long ?? "", help: help ?? "" })

	## Add an option that takes a `U8` and can be given multiple times
	## to your CLI builder.
	##
	## Parsing arguments will fail if any calls of the option don't provide
	## a value, or the value is not a number.
	##
	## ```roc
	## expect
	##     Opt.u8_list({ short: "a", long: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("-a"), Utf8("1"), Utf8("--answer=2"), Utf8("--answer"), Utf8("3")])
	##     == Ok([1, 2, 3])
	## ```
	u8_list : Base.OptionConfigBaseParams -> Cli(List(U8), Cli.GetOptionsAction, Cli.GetOptionsAction)
	u8_list = |{ short, long, help }|
		Opt.list({ parser: |a| parse_num(a, U8.from_str), type: Base.num_type_name, short: short ?? "", long: long ?? "", help: help ?? "" })

	## Add a required option that takes a `U16` to your CLI builder.
	##
	## Parsing arguments will fail if the option is not given as an argument,
	## a value is not provided to the option, or the value is not a number.
	##
	## ```roc
	## expect
	##     Opt.u16({ long: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("--answer=42")])
	##     == Ok(42)
	## ```
	u16 : Base.DefaultableOptionConfigBaseParams(U16) -> Cli(U16, Cli.GetOptionsAction, Cli.GetOptionsAction)
	u16 = |{ short, long, help, default }|
		Opt.single({ parser: |a| parse_num(a, U16.from_str), type: Base.num_type_name, short: short ?? "", long: long ?? "", help: help ?? "", default: default ?? NoDefault })

	## Add an optional option that takes a `U16` to your CLI builder.
	##
	## Parsing arguments will fail if more than one instance of the argument
	## is provided, there is no value given for the option call, or the value is not a number.
	##
	## ```roc
	## expect
	##     Opt.maybe_u16({ long: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([])
	##     == Ok(Err(NoValue))
	## ```
	maybe_u16 : Base.OptionConfigBaseParams -> Cli(Try(U16, [NoValue]), Cli.GetOptionsAction, Cli.GetOptionsAction)
	maybe_u16 = |{ short, long, help }|
		Opt.maybe({ parser: |a| parse_num(a, U16.from_str), type: Base.num_type_name, short: short ?? "", long: long ?? "", help: help ?? "" })

	## Add an option that takes a `U16` and can be given multiple times
	## to your CLI builder.
	##
	## Parsing arguments will fail if any calls of the option don't provide
	## a value, or the value is not a number.
	##
	## ```roc
	## expect
	##     Opt.u16_list({ short: "a", long: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("-a"), Utf8("1"), Utf8("--answer=2"), Utf8("--answer"), Utf8("3")])
	##     == Ok([1, 2, 3])
	## ```
	u16_list : Base.OptionConfigBaseParams -> Cli(List(U16), Cli.GetOptionsAction, Cli.GetOptionsAction)
	u16_list = |{ short, long, help }|
		Opt.list({ parser: |a| parse_num(a, U16.from_str), type: Base.num_type_name, short: short ?? "", long: long ?? "", help: help ?? "" })

	## Add a required option that takes a `U32` to your CLI builder.
	##
	## Parsing arguments will fail if the option is not given as an argument,
	## a value is not provided to the option, or the value is not a number.
	##
	## ```roc
	## expect
	##     Opt.u32({ long: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("--answer=42")])
	##     == Ok(42)
	## ```
	u32 : Base.DefaultableOptionConfigBaseParams(U32) -> Cli(U32, Cli.GetOptionsAction, Cli.GetOptionsAction)
	u32 = |{ short, long, help, default }|
		Opt.single({ parser: |a| parse_num(a, U32.from_str), type: Base.num_type_name, short: short ?? "", long: long ?? "", help: help ?? "", default: default ?? NoDefault })

	## Add an optional option that takes a `U32` to your CLI builder.
	##
	## Parsing arguments will fail if more than one instance of the argument
	## is provided, there is no value given for the option call, or the value is not a number.
	##
	## ```roc
	## expect
	##     Opt.maybe_u32({ long: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([])
	##     == Ok(Err(NoValue))
	## ```
	maybe_u32 : Base.OptionConfigBaseParams -> Cli(Try(U32, [NoValue]), Cli.GetOptionsAction, Cli.GetOptionsAction)
	maybe_u32 = |{ short, long, help }|
		Opt.maybe({ parser: |a| parse_num(a, U32.from_str), type: Base.num_type_name, short: short ?? "", long: long ?? "", help: help ?? "" })

	## Add an option that takes a `U32` and can be given multiple times
	## to your CLI builder.
	##
	## Parsing arguments will fail if any calls of the option don't provide
	## a value, or the value is not a number.
	##
	## ```roc
	## expect
	##     Opt.u32_list({ short: "a", long: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("-a"), Utf8("1"), Utf8("--answer=2"), Utf8("--answer"), Utf8("3")])
	##     == Ok([1, 2, 3])
	## ```
	u32_list : Base.OptionConfigBaseParams -> Cli(List(U32), Cli.GetOptionsAction, Cli.GetOptionsAction)
	u32_list = |{ short, long, help }|
		Opt.list({ parser: |a| parse_num(a, U32.from_str), type: Base.num_type_name, short: short ?? "", long: long ?? "", help: help ?? "" })

	## Add a required option that takes a `U64` to your CLI builder.
	##
	## Parsing arguments will fail if the option is not given as an argument,
	## a value is not provided to the option, or the value is not a number.
	##
	## ```roc
	## expect
	##     Opt.u64({ long: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("--answer=42")])
	##     == Ok(42)
	## ```
	u64 : Base.DefaultableOptionConfigBaseParams(U64) -> Cli(U64, Cli.GetOptionsAction, Cli.GetOptionsAction)
	u64 = |{ short, long, help, default }|
		Opt.single({ parser: |a| parse_num(a, U64.from_str), type: Base.num_type_name, short: short ?? "", long: long ?? "", help: help ?? "", default: default ?? NoDefault })

	## Add an optional option that takes a `U64` to your CLI builder.
	##
	## Parsing arguments will fail if more than one instance of the argument
	## is provided, there is no value given for the option call, or the value is not a number.
	##
	## ```roc
	## expect
	##     Opt.maybe_u64({ long: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([])
	##     == Ok(Err(NoValue))
	## ```
	maybe_u64 : Base.OptionConfigBaseParams -> Cli(Try(U64, [NoValue]), Cli.GetOptionsAction, Cli.GetOptionsAction)
	maybe_u64 = |{ short, long, help }|
		Opt.maybe({ parser: |a| parse_num(a, U64.from_str), type: Base.num_type_name, short: short ?? "", long: long ?? "", help: help ?? "" })

	## Add an option that takes a `U64` and can be given multiple times
	## to your CLI builder.
	##
	## Parsing arguments will fail if any calls of the option don't provide
	## a value, or the value is not a number.
	##
	## ```roc
	## expect
	##     Opt.u64_list({ short: "a", long: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("-a"), Utf8("1"), Utf8("--answer=2"), Utf8("--answer"), Utf8("3")])
	##     == Ok([1, 2, 3])
	## ```
	u64_list : Base.OptionConfigBaseParams -> Cli(List(U64), Cli.GetOptionsAction, Cli.GetOptionsAction)
	u64_list = |{ short, long, help }|
		Opt.list({ parser: |a| parse_num(a, U64.from_str), type: Base.num_type_name, short: short ?? "", long: long ?? "", help: help ?? "" })

	## Add a required option that takes a `U128` to your CLI builder.
	##
	## Parsing arguments will fail if the option is not given as an argument,
	## a value is not provided to the option, or the value is not a number.
	##
	## ```roc
	## expect
	##     Opt.u128({ long: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("--answer=42")])
	##     == Ok(42)
	## ```
	u128 : Base.DefaultableOptionConfigBaseParams(U128) -> Cli(U128, Cli.GetOptionsAction, Cli.GetOptionsAction)
	u128 = |{ short, long, help, default }|
		Opt.single({ parser: |a| parse_num(a, U128.from_str), type: Base.num_type_name, short: short ?? "", long: long ?? "", help: help ?? "", default: default ?? NoDefault })

	## Add an optional option that takes a `U128` to your CLI builder.
	##
	## Parsing arguments will fail if more than one instance of the argument
	## is provided, there is no value given for the option call, or the value is not a number.
	##
	## ```roc
	## expect
	##     Opt.maybe_u128({ long: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([])
	##     == Ok(Err(NoValue))
	## ```
	maybe_u128 : Base.OptionConfigBaseParams -> Cli(Try(U128, [NoValue]), Cli.GetOptionsAction, Cli.GetOptionsAction)
	maybe_u128 = |{ short, long, help }|
		Opt.maybe({ parser: |a| parse_num(a, U128.from_str), type: Base.num_type_name, short: short ?? "", long: long ?? "", help: help ?? "" })

	## Add an option that takes a `U128` and can be given multiple times
	## to your CLI builder.
	##
	## Parsing arguments will fail if any calls of the option don't provide
	## a value, or the value is not a number.
	##
	## ```roc
	## expect
	##     Opt.u128_list({ short: "a", long: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("-a"), Utf8("1"), Utf8("--answer=2"), Utf8("--answer"), Utf8("3")])
	##     == Ok([1, 2, 3])
	## ```
	u128_list : Base.OptionConfigBaseParams -> Cli(List(U128), Cli.GetOptionsAction, Cli.GetOptionsAction)
	u128_list = |{ short, long, help }|
		Opt.list({ parser: |a| parse_num(a, U128.from_str), type: Base.num_type_name, short: short ?? "", long: long ?? "", help: help ?? "" })

	## Add a required option that takes a `I8` to your CLI builder.
	##
	## Parsing arguments will fail if the option is not given as an argument,
	## a value is not provided to the option, or the value is not a number.
	##
	## ```roc
	## expect
	##     Opt.i8({ long: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("--answer=-42")])
	##     == Ok(-42)
	## ```
	i8 : Base.DefaultableOptionConfigBaseParams(I8) -> Cli(I8, Cli.GetOptionsAction, Cli.GetOptionsAction)
	i8 = |{ short, long, help, default }|
		Opt.single({ parser: |a| parse_num(a, I8.from_str), type: Base.num_type_name, short: short ?? "", long: long ?? "", help: help ?? "", default: default ?? NoDefault })

	## Add an optional option that takes a `I8` to your CLI builder.
	##
	## Parsing arguments will fail if more than one instance of the argument
	## is provided, there is no value given for the option call, or the value is not a number.
	##
	## ```roc
	## expect
	##     Opt.maybe_i8({ long: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([])
	##     == Ok(Err(NoValue))
	## ```
	maybe_i8 : Base.OptionConfigBaseParams -> Cli(Try(I8, [NoValue]), Cli.GetOptionsAction, Cli.GetOptionsAction)
	maybe_i8 = |{ short, long, help }|
		Opt.maybe({ parser: |a| parse_num(a, I8.from_str), type: Base.num_type_name, short: short ?? "", long: long ?? "", help: help ?? "" })

	## Add an option that takes a `I8` and can be given multiple times
	## to your CLI builder.
	##
	## Parsing arguments will fail if any calls of the option don't provide
	## a value, or the value is not a number.
	##
	## ```roc
	## expect
	##     Opt.i8_list({ short: "a", long: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("-a"), Utf8("1"), Utf8("--answer=2"), Utf8("--answer"), Utf8("-3")])
	##     == Ok([1, 2, -3])
	## ```
	i8_list : Base.OptionConfigBaseParams -> Cli(List(I8), Cli.GetOptionsAction, Cli.GetOptionsAction)
	i8_list = |{ short, long, help }|
		Opt.list({ parser: |a| parse_num(a, I8.from_str), type: Base.num_type_name, short: short ?? "", long: long ?? "", help: help ?? "" })

	## Add a required option that takes a `I16` to your CLI builder.
	##
	## Parsing arguments will fail if the option is not given as an argument,
	## a value is not provided to the option, or the value is not a number.
	##
	## ```roc
	## expect
	##     Opt.i16({ long: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("--answer=-42")])
	##     == Ok(-42)
	## ```
	i16 : Base.DefaultableOptionConfigBaseParams(I16) -> Cli(I16, Cli.GetOptionsAction, Cli.GetOptionsAction)
	i16 = |{ short, long, help, default }|
		Opt.single({ parser: |a| parse_num(a, I16.from_str), type: Base.num_type_name, short: short ?? "", long: long ?? "", help: help ?? "", default: default ?? NoDefault })

	## Add an optional option that takes a `I16` to your CLI builder.
	##
	## Parsing arguments will fail if more than one instance of the argument
	## is provided, there is no value given for the option call, or the value is not a number.
	##
	## ```roc
	## expect
	##     Opt.maybe_i16({ long: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([])
	##     == Ok(Err(NoValue))
	## ```
	maybe_i16 : Base.OptionConfigBaseParams -> Cli(Try(I16, [NoValue]), Cli.GetOptionsAction, Cli.GetOptionsAction)
	maybe_i16 = |{ short, long, help }|
		Opt.maybe({ parser: |a| parse_num(a, I16.from_str), type: Base.num_type_name, short: short ?? "", long: long ?? "", help: help ?? "" })

	## Add an option that takes a `I16` and can be given multiple times
	## to your CLI builder.
	##
	## Parsing arguments will fail if any calls of the option don't provide
	## a value, or the value is not a number.
	##
	## ```roc
	## expect
	##     Opt.i16_list({ short: "a", long: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("-a"), Utf8("1"), Utf8("--answer=2"), Utf8("--answer"), Utf8("-3")])
	##     == Ok([1, 2, -3])
	## ```
	i16_list : Base.OptionConfigBaseParams -> Cli(List(I16), Cli.GetOptionsAction, Cli.GetOptionsAction)
	i16_list = |{ short, long, help }|
		Opt.list({ parser: |a| parse_num(a, I16.from_str), type: Base.num_type_name, short: short ?? "", long: long ?? "", help: help ?? "" })

	## Add a required option that takes a `I32` to your CLI builder.
	##
	## Parsing arguments will fail if the option is not given as an argument,
	## a value is not provided to the option, or the value is not a number.
	##
	## ```roc
	## expect
	##     Opt.i32({ long: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("--answer=-42")])
	##     == Ok(-42)
	## ```
	i32 : Base.DefaultableOptionConfigBaseParams(I32) -> Cli(I32, Cli.GetOptionsAction, Cli.GetOptionsAction)
	i32 = |{ short, long, help, default }|
		Opt.single({ parser: |a| parse_num(a, I32.from_str), type: Base.num_type_name, short: short ?? "", long: long ?? "", help: help ?? "", default: default ?? NoDefault })

	## Add an optional option that takes a `I32` to your CLI builder.
	##
	## Parsing arguments will fail if more than one instance of the argument
	## is provided, there is no value given for the option call, or the value is not a number.
	##
	## ```roc
	## expect
	##     Opt.maybe_i32({ long: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([])
	##     == Ok(Err(NoValue))
	## ```
	maybe_i32 : Base.OptionConfigBaseParams -> Cli(Try(I32, [NoValue]), Cli.GetOptionsAction, Cli.GetOptionsAction)
	maybe_i32 = |{ short, long, help }|
		Opt.maybe({ parser: |a| parse_num(a, I32.from_str), type: Base.num_type_name, short: short ?? "", long: long ?? "", help: help ?? "" })

	## Add an option that takes a `I32` and can be given multiple times
	## to your CLI builder.
	##
	## Parsing arguments will fail if any calls of the option don't provide
	## a value, or the value is not a number.
	##
	## ```roc
	## expect
	##     Opt.i32_list({ short: "a", long: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("-a"), Utf8("1"), Utf8("--answer=2"), Utf8("--answer"), Utf8("-3")])
	##     == Ok([1, 2, -3])
	## ```
	i32_list : Base.OptionConfigBaseParams -> Cli(List(I32), Cli.GetOptionsAction, Cli.GetOptionsAction)
	i32_list = |{ short, long, help }|
		Opt.list({ parser: |a| parse_num(a, I32.from_str), type: Base.num_type_name, short: short ?? "", long: long ?? "", help: help ?? "" })

	## Add a required option that takes a `I64` to your CLI builder.
	##
	## Parsing arguments will fail if the option is not given as an argument,
	## a value is not provided to the option, or the value is not a number.
	##
	## ```roc
	## expect
	##     Opt.i64({ long: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("--answer=-42")])
	##     == Ok(-42)
	## ```
	i64 : Base.DefaultableOptionConfigBaseParams(I64) -> Cli(I64, Cli.GetOptionsAction, Cli.GetOptionsAction)
	i64 = |{ short, long, help, default }|
		Opt.single({ parser: |a| parse_num(a, I64.from_str), type: Base.num_type_name, short: short ?? "", long: long ?? "", help: help ?? "", default: default ?? NoDefault })

	## Add an optional option that takes a `I64` to your CLI builder.
	##
	## Parsing arguments will fail if more than one instance of the argument
	## is provided, there is no value given for the option call, or the value is not a number.
	##
	## ```roc
	## expect
	##     Opt.maybe_i64({ long: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([])
	##     == Ok(Err(NoValue))
	## ```
	maybe_i64 : Base.OptionConfigBaseParams -> Cli(Try(I64, [NoValue]), Cli.GetOptionsAction, Cli.GetOptionsAction)
	maybe_i64 = |{ short, long, help }|
		Opt.maybe({ parser: |a| parse_num(a, I64.from_str), type: Base.num_type_name, short: short ?? "", long: long ?? "", help: help ?? "" })

	## Add an option that takes a `I64` and can be given multiple times
	## to your CLI builder.
	##
	## Parsing arguments will fail if any calls of the option don't provide
	## a value, or the value is not a number.
	##
	## ```roc
	## expect
	##     Opt.i64_list({ short: "a", long: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("-a"), Utf8("1"), Utf8("--answer=2"), Utf8("--answer"), Utf8("-3")])
	##     == Ok([1, 2, -3])
	## ```
	i64_list : Base.OptionConfigBaseParams -> Cli(List(I64), Cli.GetOptionsAction, Cli.GetOptionsAction)
	i64_list = |{ short, long, help }|
		Opt.list({ parser: |a| parse_num(a, I64.from_str), type: Base.num_type_name, short: short ?? "", long: long ?? "", help: help ?? "" })

	## Add a required option that takes a `I128` to your CLI builder.
	##
	## Parsing arguments will fail if the option is not given as an argument,
	## a value is not provided to the option, or the value is not a number.
	##
	## ```roc
	## expect
	##     Opt.i128({ long: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("--answer=-42")])
	##     == Ok(-42)
	## ```
	i128 : Base.DefaultableOptionConfigBaseParams(I128) -> Cli(I128, Cli.GetOptionsAction, Cli.GetOptionsAction)
	i128 = |{ short, long, help, default }|
		Opt.single({ parser: |a| parse_num(a, I128.from_str), type: Base.num_type_name, short: short ?? "", long: long ?? "", help: help ?? "", default: default ?? NoDefault })

	## Add an optional option that takes a `I128` to your CLI builder.
	##
	## Parsing arguments will fail if more than one instance of the argument
	## is provided, there is no value given for the option call, or the value is not a number.
	##
	## ```roc
	## expect
	##     Opt.maybe_i128({ long: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([])
	##     == Ok(Err(NoValue))
	## ```
	maybe_i128 : Base.OptionConfigBaseParams -> Cli(Try(I128, [NoValue]), Cli.GetOptionsAction, Cli.GetOptionsAction)
	maybe_i128 = |{ short, long, help }|
		Opt.maybe({ parser: |a| parse_num(a, I128.from_str), type: Base.num_type_name, short: short ?? "", long: long ?? "", help: help ?? "" })

	## Add an option that takes a `I128` and can be given multiple times
	## to your CLI builder.
	##
	## Parsing arguments will fail if any calls of the option don't provide
	## a value, or the value is not a number.
	##
	## ```roc
	## expect
	##     Opt.i128_list({ short: "a", long: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("-a"), Utf8("1"), Utf8("--answer=2"), Utf8("--answer"), Utf8("-3")])
	##     == Ok([1, 2, -3])
	## ```
	i128_list : Base.OptionConfigBaseParams -> Cli(List(I128), Cli.GetOptionsAction, Cli.GetOptionsAction)
	i128_list = |{ short, long, help }|
		Opt.list({ parser: |a| parse_num(a, I128.from_str), type: Base.num_type_name, short: short ?? "", long: long ?? "", help: help ?? "" })

}

builder_with_option_parser : Base.OptionConfig, (List(Parser.ArgValue) -> Try(data, Base.ArgExtractErr)) -> Cli(data, from_action, to_action)
builder_with_option_parser = |option, value_parser| {
	arg_parser = |args| {
		{ values, remaining_args } = Extract.extract_option_values({ args, option })?
		data = value_parser(values)?

		Ok({ data, remaining_args })
	}

	Cli.from_arg_parser(arg_parser).add_option(option)
}

get_maybe_value : List(Parser.ArgValue), Base.OptionConfig -> Try(Try(Parser.ArgValue, [NoValue]), Base.ArgExtractErr)
get_maybe_value = |values, option|
	match values {
		[] => Ok(Err(NoValue))
		[single_value] => Ok(Ok(single_value))
		_ => Err(OptionCanOnlyBeSetOnce(option))
	}

parse_str : Arg -> Try(Str, Base.InvalidValue)
parse_str = |arg| Ok(Arg.to_str(arg)?)

parse_num : Arg, (Str -> Try(num, [BadNumStr])) -> Try(num, Base.InvalidValue)
parse_num = |arg, from_str| {
	str = Arg.to_str(arg)?

	match from_str(str) {
		Ok(num) => Ok(num)
		Err(BadNumStr) => Err(InvalidNumStr)
	}
}

# Tests

parse : Cli.CliParser(data), List(Str) -> Try(data, Str)
parse = |cli_parser, args| Cli.parse_or_display_message(cli_parser, args.map(|arg| Utf8(arg)))

finish : Cli(data, from_action, to_action) -> Cli.CliParser(data)
finish = |builder| builder.finish({ name: "example", text_style: Plain }) |> Cli.assert_valid

parse_color : Arg -> Try([Green, Red, Blue], Base.InvalidValue)
parse_color = |color|
	match Arg.to_str(color) {
		Ok("green") => Ok(Green)
		Ok("red") => Ok(Red)
		Ok("blue") => Ok(Blue)
		_ => Err(InvalidValue("'${Arg.display(color)}' is not a valid color, must be green, red, or blue"))
	}

expect parse(finish(Opt.single({ short: "c", parser: parse_color, type: "color" })), ["-c", "green"]) == Ok(Green)
expect parse(finish(Opt.single({ short: "c", parser: parse_color, type: "color", default: Value(Blue) })), []) == Ok(Blue)
expect parse(finish(Opt.single({ short: "c", parser: parse_color, type: "color", default: Generate(|_| Red) })), []) == Ok(Red)
expect
	parse(finish(Opt.single({ short: "c", parser: parse_color, type: "color" })), ["-c", "pink"])
		== Err("Error: The value provided to -c was not a valid color: 'pink' is not a valid color, must be green, red, or blue\n\nUsage:\n  example -c COLOR [options]")
expect
	parse(finish(Opt.single({ short: "c", parser: parse_color, type: "color" })), [])
		== Err("Error: Required option -c is missing.\n\nUsage:\n  example -c COLOR [options]")
expect
	parse(finish(Opt.single({ short: "c", parser: parse_color, type: "color" })), ["-c"])
		== Err("Error: Option -c expects a color.\n\nUsage:\n  example -c COLOR [options]")
expect
	parse(finish(Opt.single({ short: "c", parser: parse_color, type: "color" })), ["-c", "red", "-c", "blue"])
		== Err("Error: Option -c can only be set once.\n\nUsage:\n  example -c COLOR [options]")

expect parse(finish(Opt.maybe({ short: "c", type: "color", parser: parse_color })), []) == Ok(Err(NoValue))
expect parse(finish(Opt.maybe({ short: "c", type: "color", parser: parse_color })), ["-c", "red"]) == Ok(Ok(Red))
expect parse(finish(Opt.maybe({ short: "c", type: "color", parser: parse_color })), ["-cred"]).is_err()

expect parse(finish(Opt.list({ short: "c", long: "color", type: "color", parser: parse_color })), ["-c", "green", "--color=red"]) == Ok([Green, Red])
expect parse(finish(Opt.list({ short: "c", long: "color", type: "color", parser: parse_color })), []) == Ok([])

expect parse(finish(Opt.flag({ short: "f", long: "force" })), ["-f"]) == Ok(True)
expect parse(finish(Opt.flag({ short: "f", long: "force" })), []) == Ok(False)
expect
	parse(finish(Opt.flag({ short: "f", long: "force" })), ["--force=yes"])
		== Err("Error: Option -f/--force does not expect a value.\n\nUsage:\n  example [options]")

expect parse(finish(Opt.count({ short: "f", long: "force" })), ["-f", "--force", "-fff"]) == Ok(5)
expect parse(finish(Opt.count({ short: "f", long: "force" })), []) == Ok(0)

# Flags in the same short group are all found.
expect parse(finish({ v: Opt.flag({ short: "v" }), f: Opt.flag({ short: "f" }) }.Cli), ["-vf"]) == Ok({ v: True, f: True })
expect parse(finish({ a: Opt.u64({ short: "a" }), f: Opt.flag({ short: "f" }) }.Cli), ["-fa", "1"]) == Ok({ a: 1, f: True })
expect parse(finish({ a: Opt.u64({ short: "a" }), f: Opt.flag({ short: "f" }) }.Cli), ["-fa1"]).is_err()

expect parse(finish(Opt.arg({ long: "answer" })), ["--answer=abc"]) == Ok(Arg.from_str("abc"))
expect parse(finish(Opt.maybe_arg({ long: "answer" })), []) == Ok(Err(NoValue))
expect
	parse(finish(Opt.arg_list({ short: "a", long: "answer" })), ["-a", "abc", "--answer", "def", "--answer=ghi"])
		== Ok([Arg.from_str("abc"), Arg.from_str("def"), Arg.from_str("ghi")])

expect parse(finish(Opt.bytes({ long: "answer" })), ["--answer=abc"]) == Ok([97, 98, 99])
expect parse(finish(Opt.maybe_bytes({ long: "answer" })), []) == Ok(Err(NoValue))
expect parse(finish(Opt.bytes_list({ short: "a", long: "answer" })), ["-a", "abc", "--answer", "def", "--answer=ghi"]) == Ok([[97, 98, 99], [100, 101, 102], [103, 104, 105]])

expect parse(finish(Opt.str({ long: "answer" })), ["--answer=abc"]) == Ok("abc")
expect parse(finish(Opt.str({ long: "answer", default: Value("xyz") })), []) == Ok("xyz")
expect parse(finish(Opt.maybe_str({ long: "answer" })), []) == Ok(Err(NoValue))
expect parse(finish(Opt.str_list({ short: "a", long: "answer" })), ["-a", "abc", "--answer", "def", "--answer=ghi"]) == Ok(["abc", "def", "ghi"])
expect {
	cli_parser = finish(Opt.str({ long: "answer" }))
	Cli.parse_or_display_message(cli_parser, [UnixBytes([45, 45, 97, 110, 115, 119, 101, 114]), UnixBytes([0xff])])
		== Err("Error: The value provided to --answer was not valid UTF-8.\n\nUsage:\n  example --answer STR [options]")
}

expect parse(finish(Opt.dec({ long: "answer" })), ["--answer=42.5"]) == Ok(42.5)
expect parse(finish(Opt.maybe_dec({ long: "answer" })), []) == Ok(Err(NoValue))
expect parse(finish(Opt.dec_list({ short: "a", long: "answer" })), ["-a", "1", "--answer=2", "--answer", "-3.0"]) == Ok([1.0, 2.0, -3.0])
expect parse(finish(Opt.f32({ long: "answer" })), ["--answer=42.5"]) == Ok(42.5)
expect parse(finish(Opt.f64({ long: "answer" })), ["--answer=42.5"]) == Ok(42.5)
expect parse(finish(Opt.f64_list({ short: "a", long: "answer" })), ["-a", "1", "--answer=2", "--answer", "-3.0"]) == Ok([1.0, 2.0, -3.0])
expect parse(finish(Opt.u8({ long: "answer" })), ["--answer=42"]) == Ok(42)
expect parse(finish(Opt.u8({ long: "answer" })), ["--answer=256"]).is_err()
expect parse(finish(Opt.u16({ long: "answer" })), ["--answer=42"]) == Ok(42)
expect parse(finish(Opt.u32({ long: "answer" })), ["--answer=42"]) == Ok(42)
expect parse(finish(Opt.u64({ long: "answer" })), ["--answer=42"]) == Ok(42)
expect parse(finish(Opt.u64({ long: "answer", default: Value(7) })), []) == Ok(7)
expect parse(finish(Opt.maybe_u64({ long: "answer" })), []) == Ok(Err(NoValue))
expect parse(finish(Opt.u64_list({ short: "a", long: "answer" })), ["-a", "1", "--answer=2", "--answer", "3"]) == Ok([1, 2, 3])
expect parse(finish(Opt.u128({ long: "answer" })), ["--answer=42"]) == Ok(42)
expect parse(finish(Opt.i8({ long: "answer" })), ["--answer=-42"]) == Ok(-42)
expect parse(finish(Opt.i16({ long: "answer" })), ["--answer=-42"]) == Ok(-42)
expect parse(finish(Opt.i32({ long: "answer" })), ["--answer=-42"]) == Ok(-42)
expect parse(finish(Opt.i64({ long: "answer" })), ["--answer=-42"]) == Ok(-42)
expect parse(finish(Opt.i64_list({ short: "a", long: "answer" })), ["-a", "1", "--answer=2", "--answer", "-3"]) == Ok([1, 2, -3])
expect parse(finish(Opt.i128({ long: "answer" })), ["--answer=-42"]) == Ok(-42)
expect
	parse(finish(Opt.u64({ short: "a", long: "answer" })), ["-a", "x"])
		== Err("Error: The value provided to -a/--answer was not a valid number.\n\nUsage:\n  example -a/--answer NUM [options]")
