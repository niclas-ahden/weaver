import Arg
import Base
import Cli
import Extract

## Parameters that your CLI will parse as fields in your config.
##
## Parameters are the arguments that are not options, taken in the order
## they are given. They must come after any option or subcommand fields in a
## record builder, and a parameter list can't be followed by anything.
Param :: [].{

	## Add a required parameter of a custom type to your CLI builder.
	##
	## You need to provide a kebab-case type name for your help messages as well as a
	## parser for said type. The parser needs to return an `Err(InvalidValue(Str))`
	## on failure, where the `Str` is the reason the parsing failed that will
	## get displayed in the incorrect usage message.
	##
	## Parsing arguments will fail if the parameter fails to parse or
	## is not provided.
	##
	## Parameters must be provided last after any option or subcommand fields,
	## as they are parsed last of the three extracted values, and parameter
	## list fields cannot be followed by any other fields. This is enforced
	## using the type state pattern, where we encode the state of the program
	## into its types. If you're curious, check the `Cli` type to see how this
	## works using its two action type variables.
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
	##     Param.single({ name: "answer", type: "color", parser: parse_color })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("blue")])
	##     == Ok(Blue)
	## ```
	single : Base.DefaultableParameterConfigParams(data) -> Cli(data, { ..from_action }, Cli.GetParamsAction)
	single = |{ parser, type, name, help, default }| {
		param = { name, type, help: help ?? "", plurality: One }
		default_value = default ?? NoDefault

		value_parser = |values|
			match values.first() {
				Err(ListWasEmpty) =>
					match default_value {
						Value(value) => Ok(value)
						Generate(generator) => Ok(generator({}))
						NoDefault => Err(MissingParam(param))
					}
				Ok(single_value) => parser(single_value).map_err(|err| InvalidParamValue(err, param))
			}

		builder_with_parameter_parser(param, value_parser)
	}

	## Add an optional parameter of a custom type to your CLI builder.
	##
	## You need to provide a kebab-case type name for your help messages as well as a
	## parser for said type. The parser needs to return an `Err(InvalidValue(Str))`
	## on failure, where the `Str` is the reason the parsing failed that will
	## get displayed in the incorrect usage message.
	##
	## Parsing arguments will fail if the parameter fails to parse.
	##
	## Parameters must be provided last after any option or subcommand fields,
	## as they are parsed last of the three extracted values, and parameter
	## list fields cannot be followed by any other fields. This is enforced
	## using the type state pattern, where we encode the state of the program
	## into its types. If you're curious, check the `Cli` type to see how this
	## works using its two action type variables.
	##
	## ```roc
	## expect
	##     Param.maybe({ name: "answer", type: "color", parser: parse_color })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([])
	##     == Ok(Err(NoValue))
	## ```
	maybe : Base.ParameterConfigParams(data) -> Cli(Try(data, [NoValue]), { ..from_action }, Cli.GetParamsAction)
	maybe = |{ parser, type, name, help }| {
		param = { name, type, help: help ?? "", plurality: Optional }

		value_parser = |values|
			match values.first() {
				Err(ListWasEmpty) => Ok(Err(NoValue))
				Ok(single_value) =>
					match parser(single_value) {
						Ok(value) => Ok(Ok(value))
						Err(err) => Err(InvalidParamValue(err, param))
					}
			}

		builder_with_parameter_parser(param, value_parser)
	}

	## Add a parameter of a custom type that can be provided
	## multiple times to your CLI builder.
	##
	## You need to provide a kebab-case type name for your help messages as well as a
	## parser for said type. The parser needs to return an `Err(InvalidValue(Str))`
	## on failure, where the `Str` is the reason the parsing failed that will
	## get displayed in the incorrect usage message.
	##
	## Parsing arguments will fail if any of the values fail to parse.
	##
	## Parameters must be provided last after any option or subcommand fields,
	## as they are parsed last of the three extracted values, and parameter
	## list fields cannot be followed by any other fields. This is enforced
	## using the type state pattern, where we encode the state of the program
	## into its types. If you're curious, check the `Cli` type to see how this
	## works using its two action type variables.
	##
	## ```roc
	## expect
	##     Param.list({ name: "answer", type: "color", parser: parse_color })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("blue"), Utf8("red"), Utf8("green")])
	##     == Ok([Blue, Red, Green])
	## ```
	list : Base.ParameterConfigParams(data) -> Cli(List(data), { ..from_action }, Cli.StopCollectingAction)
	list = |{ parser, type, name, help }| {
		param = { name, type, help: help ?? "", plurality: Many }

		value_parser = |values| values.map_try(parser).map_err(|err| InvalidParamValue(err, param))

		builder_with_parameter_parser(param, value_parser)
	}

	## Add a required [Arg] parameter to your CLI builder.
	##
	## Parsing arguments will fail if the parameter is not provided.
	##
	## ```roc
	## expect
	##     Param.arg({ name: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("abc")])
	##     == Ok(Arg.from_str("abc"))
	## ```
	arg : Base.DefaultableParameterConfigBaseParams(Arg) -> Cli(Arg, { ..from_action }, Cli.GetParamsAction)
	arg = |{ name, help, default }|
		Param.single({ parser: |a| Ok(a), type: Base.str_type_name, name, help: help ?? "", default: default ?? NoDefault })

	## Add an optional [Arg] parameter to your CLI builder.
	##
	## Parsing arguments cannot fail because of this parameter.
	##
	## ```roc
	## expect
	##     Param.maybe_arg({ name: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([])
	##     == Ok(Err(NoValue))
	## ```
	maybe_arg : Base.ParameterConfigBaseParams -> Cli(Try(Arg, [NoValue]), { ..from_action }, Cli.GetParamsAction)
	maybe_arg = |{ name, help }|
		Param.maybe({ parser: |a| Ok(a), type: Base.str_type_name, name, help: help ?? "" })

	## Add an [Arg] parameter that can be provided multiple times
	## to your CLI builder.
	##
	## Parsing arguments cannot fail because of this parameter.
	##
	## ```roc
	## expect
	##     Param.arg_list({ name: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("abc"), Utf8("def"), Utf8("ghi")])
	##     == Ok([Arg.from_str("abc"), Arg.from_str("def"), Arg.from_str("ghi")])
	## ```
	arg_list : Base.ParameterConfigBaseParams -> Cli(List(Arg), { ..from_action }, Cli.StopCollectingAction)
	arg_list = |{ name, help }|
		Param.list({ parser: |a| Ok(a), type: Base.str_type_name, name, help: help ?? "" })

	## Add a required byte list parameter to your CLI builder.
	##
	## Parsing arguments will fail if the parameter is not provided.
	##
	## ```roc
	## expect
	##     Param.bytes({ name: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("abc")])
	##     == Ok([97, 98, 99])
	## ```
	bytes : Base.DefaultableParameterConfigBaseParams(List(U8)) -> Cli(List(U8), { ..from_action }, Cli.GetParamsAction)
	bytes = |{ name, help, default }|
		Param.single({ parser: |a| Ok(Arg.to_bytes(a)), type: Base.str_type_name, name, help: help ?? "", default: default ?? NoDefault })

	## Add an optional byte list parameter to your CLI builder.
	##
	## Parsing arguments cannot fail because of this parameter.
	##
	## ```roc
	## expect
	##     Param.maybe_bytes({ name: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([])
	##     == Ok(Err(NoValue))
	## ```
	maybe_bytes : Base.ParameterConfigBaseParams -> Cli(Try(List(U8), [NoValue]), { ..from_action }, Cli.GetParamsAction)
	maybe_bytes = |{ name, help }|
		Param.maybe({ parser: |a| Ok(Arg.to_bytes(a)), type: Base.str_type_name, name, help: help ?? "" })

	## Add a byte list parameter that can be provided multiple times
	## to your CLI builder.
	##
	## Parsing arguments cannot fail because of this parameter.
	##
	## ```roc
	## expect
	##     Param.bytes_list({ name: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("abc"), Utf8("def"), Utf8("ghi")])
	##     == Ok([[97, 98, 99], [100, 101, 102], [103, 104, 105]])
	## ```
	bytes_list : Base.ParameterConfigBaseParams -> Cli(List(List(U8)), { ..from_action }, Cli.StopCollectingAction)
	bytes_list = |{ name, help }|
		Param.list({ parser: |a| Ok(Arg.to_bytes(a)), type: Base.str_type_name, name, help: help ?? "" })

	## Add a required string parameter to your CLI builder.
	##
	## Parsing arguments will fail if the parameter is not provided
	## or the value is not valid UTF-8.
	##
	## ```roc
	## expect
	##     Param.str({ name: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("abc")])
	##     == Ok("abc")
	## ```
	str : Base.DefaultableParameterConfigBaseParams(Str) -> Cli(Str, { ..from_action }, Cli.GetParamsAction)
	str = |{ name, help, default }|
		Param.single({ parser: parse_str, type: Base.str_type_name, name, help: help ?? "", default: default ?? NoDefault })

	## Add an optional string parameter to your CLI builder.
	##
	## Parsing arguments will fail if the value is not valid UTF-8.
	##
	## ```roc
	## expect
	##     Param.maybe_str({ name: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([])
	##     == Ok(Err(NoValue))
	## ```
	maybe_str : Base.ParameterConfigBaseParams -> Cli(Try(Str, [NoValue]), { ..from_action }, Cli.GetParamsAction)
	maybe_str = |{ name, help }|
		Param.maybe({ parser: parse_str, type: Base.str_type_name, name, help: help ?? "" })

	## Add a string parameter that can be provided multiple times
	## to your CLI builder.
	##
	## Parsing arguments will fail if any of the parameters are
	## not not valid UTF-8.
	##
	## ```roc
	## expect
	##     Param.str_list({ name: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("abc"), Utf8("def"), Utf8("ghi")])
	##     == Ok(["abc", "def", "ghi"])
	## ```
	str_list : Base.ParameterConfigBaseParams -> Cli(List(Str), { ..from_action }, Cli.StopCollectingAction)
	str_list = |{ name, help }|
		Param.list({ parser: parse_str, type: Base.str_type_name, name, help: help ?? "" })

	## Add a required `Dec` parameter to your CLI builder.
	##
	## Parsing arguments will fail if the parameter is not provided
	## or the value is not a valid number.
	##
	## ```roc
	## expect
	##     Param.dec({ name: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("42.5")])
	##     == Ok(42.5)
	## ```
	dec : Base.DefaultableParameterConfigBaseParams(Dec) -> Cli(Dec, { ..from_action }, Cli.GetParamsAction)
	dec = |{ name, help, default }|
		Param.single({ parser: |a| parse_num(a, Dec.from_str), type: Base.num_type_name, name, help: help ?? "", default: default ?? NoDefault })

	## Add an optional `Dec` parameter to your CLI builder.
	##
	## Parsing arguments will fail if the value is not a valid number.
	##
	## ```roc
	## expect
	##     Param.maybe_dec({ name: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([])
	##     == Ok(Err(NoValue))
	## ```
	maybe_dec : Base.ParameterConfigBaseParams -> Cli(Try(Dec, [NoValue]), { ..from_action }, Cli.GetParamsAction)
	maybe_dec = |{ name, help }|
		Param.maybe({ parser: |a| parse_num(a, Dec.from_str), type: Base.num_type_name, name, help: help ?? "" })

	## Add a `Dec` parameter that can be provided multiple times
	## to your CLI builder.
	##
	## Parsing arguments will fail if any of the parameters are
	## not not a valid number.
	##
	## ```roc
	## expect
	##     Param.dec_list({ name: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("56.0"), Utf8("8.8"), Utf8("99.9")])
	##     == Ok([56.0, 8.8, 99.9])
	## ```
	dec_list : Base.ParameterConfigBaseParams -> Cli(List(Dec), { ..from_action }, Cli.StopCollectingAction)
	dec_list = |{ name, help }|
		Param.list({ parser: |a| parse_num(a, Dec.from_str), type: Base.num_type_name, name, help: help ?? "" })

	## Add a required `F32` parameter to your CLI builder.
	##
	## Parsing arguments will fail if the parameter is not provided
	## or the value is not a valid number.
	##
	## ```roc
	## expect
	##     Param.f32({ name: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("42.5")])
	##     == Ok(42.5)
	## ```
	f32 : Base.DefaultableParameterConfigBaseParams(F32) -> Cli(F32, { ..from_action }, Cli.GetParamsAction)
	f32 = |{ name, help, default }|
		Param.single({ parser: |a| parse_num(a, F32.from_str), type: Base.num_type_name, name, help: help ?? "", default: default ?? NoDefault })

	## Add an optional `F32` parameter to your CLI builder.
	##
	## Parsing arguments will fail if the value is not a valid number.
	##
	## ```roc
	## expect
	##     Param.maybe_f32({ name: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([])
	##     == Ok(Err(NoValue))
	## ```
	maybe_f32 : Base.ParameterConfigBaseParams -> Cli(Try(F32, [NoValue]), { ..from_action }, Cli.GetParamsAction)
	maybe_f32 = |{ name, help }|
		Param.maybe({ parser: |a| parse_num(a, F32.from_str), type: Base.num_type_name, name, help: help ?? "" })

	## Add a `F32` parameter that can be provided multiple times
	## to your CLI builder.
	##
	## Parsing arguments will fail if any of the parameters are
	## not not a valid number.
	##
	## ```roc
	## expect
	##     Param.f32_list({ name: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("56.0"), Utf8("8.8"), Utf8("99.9")])
	##     == Ok([56.0, 8.8, 99.9])
	## ```
	f32_list : Base.ParameterConfigBaseParams -> Cli(List(F32), { ..from_action }, Cli.StopCollectingAction)
	f32_list = |{ name, help }|
		Param.list({ parser: |a| parse_num(a, F32.from_str), type: Base.num_type_name, name, help: help ?? "" })

	## Add a required `F64` parameter to your CLI builder.
	##
	## Parsing arguments will fail if the parameter is not provided
	## or the value is not a valid number.
	##
	## ```roc
	## expect
	##     Param.f64({ name: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("42.5")])
	##     == Ok(42.5)
	## ```
	f64 : Base.DefaultableParameterConfigBaseParams(F64) -> Cli(F64, { ..from_action }, Cli.GetParamsAction)
	f64 = |{ name, help, default }|
		Param.single({ parser: |a| parse_num(a, F64.from_str), type: Base.num_type_name, name, help: help ?? "", default: default ?? NoDefault })

	## Add an optional `F64` parameter to your CLI builder.
	##
	## Parsing arguments will fail if the value is not a valid number.
	##
	## ```roc
	## expect
	##     Param.maybe_f64({ name: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([])
	##     == Ok(Err(NoValue))
	## ```
	maybe_f64 : Base.ParameterConfigBaseParams -> Cli(Try(F64, [NoValue]), { ..from_action }, Cli.GetParamsAction)
	maybe_f64 = |{ name, help }|
		Param.maybe({ parser: |a| parse_num(a, F64.from_str), type: Base.num_type_name, name, help: help ?? "" })

	## Add a `F64` parameter that can be provided multiple times
	## to your CLI builder.
	##
	## Parsing arguments will fail if any of the parameters are
	## not not a valid number.
	##
	## ```roc
	## expect
	##     Param.f64_list({ name: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("56.0"), Utf8("8.8"), Utf8("99.9")])
	##     == Ok([56.0, 8.8, 99.9])
	## ```
	f64_list : Base.ParameterConfigBaseParams -> Cli(List(F64), { ..from_action }, Cli.StopCollectingAction)
	f64_list = |{ name, help }|
		Param.list({ parser: |a| parse_num(a, F64.from_str), type: Base.num_type_name, name, help: help ?? "" })

	## Add a required `U8` parameter to your CLI builder.
	##
	## Parsing arguments will fail if the parameter is not provided
	## or the value is not a valid number.
	##
	## ```roc
	## expect
	##     Param.u8({ name: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("42")])
	##     == Ok(42)
	## ```
	u8 : Base.DefaultableParameterConfigBaseParams(U8) -> Cli(U8, { ..from_action }, Cli.GetParamsAction)
	u8 = |{ name, help, default }|
		Param.single({ parser: |a| parse_num(a, U8.from_str), type: Base.num_type_name, name, help: help ?? "", default: default ?? NoDefault })

	## Add an optional `U8` parameter to your CLI builder.
	##
	## Parsing arguments will fail if the value is not a valid number.
	##
	## ```roc
	## expect
	##     Param.maybe_u8({ name: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([])
	##     == Ok(Err(NoValue))
	## ```
	maybe_u8 : Base.ParameterConfigBaseParams -> Cli(Try(U8, [NoValue]), { ..from_action }, Cli.GetParamsAction)
	maybe_u8 = |{ name, help }|
		Param.maybe({ parser: |a| parse_num(a, U8.from_str), type: Base.num_type_name, name, help: help ?? "" })

	## Add a `U8` parameter that can be provided multiple times
	## to your CLI builder.
	##
	## Parsing arguments will fail if any of the parameters are
	## not not a valid number.
	##
	## ```roc
	## expect
	##     Param.u8_list({ name: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("12"), Utf8("34"), Utf8("56")])
	##     == Ok([12, 34, 56])
	## ```
	u8_list : Base.ParameterConfigBaseParams -> Cli(List(U8), { ..from_action }, Cli.StopCollectingAction)
	u8_list = |{ name, help }|
		Param.list({ parser: |a| parse_num(a, U8.from_str), type: Base.num_type_name, name, help: help ?? "" })

	## Add a required `U16` parameter to your CLI builder.
	##
	## Parsing arguments will fail if the parameter is not provided
	## or the value is not a valid number.
	##
	## ```roc
	## expect
	##     Param.u16({ name: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("42")])
	##     == Ok(42)
	## ```
	u16 : Base.DefaultableParameterConfigBaseParams(U16) -> Cli(U16, { ..from_action }, Cli.GetParamsAction)
	u16 = |{ name, help, default }|
		Param.single({ parser: |a| parse_num(a, U16.from_str), type: Base.num_type_name, name, help: help ?? "", default: default ?? NoDefault })

	## Add an optional `U16` parameter to your CLI builder.
	##
	## Parsing arguments will fail if the value is not a valid number.
	##
	## ```roc
	## expect
	##     Param.maybe_u16({ name: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([])
	##     == Ok(Err(NoValue))
	## ```
	maybe_u16 : Base.ParameterConfigBaseParams -> Cli(Try(U16, [NoValue]), { ..from_action }, Cli.GetParamsAction)
	maybe_u16 = |{ name, help }|
		Param.maybe({ parser: |a| parse_num(a, U16.from_str), type: Base.num_type_name, name, help: help ?? "" })

	## Add a `U16` parameter that can be provided multiple times
	## to your CLI builder.
	##
	## Parsing arguments will fail if any of the parameters are
	## not not a valid number.
	##
	## ```roc
	## expect
	##     Param.u16_list({ name: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("12"), Utf8("34"), Utf8("56")])
	##     == Ok([12, 34, 56])
	## ```
	u16_list : Base.ParameterConfigBaseParams -> Cli(List(U16), { ..from_action }, Cli.StopCollectingAction)
	u16_list = |{ name, help }|
		Param.list({ parser: |a| parse_num(a, U16.from_str), type: Base.num_type_name, name, help: help ?? "" })

	## Add a required `U32` parameter to your CLI builder.
	##
	## Parsing arguments will fail if the parameter is not provided
	## or the value is not a valid number.
	##
	## ```roc
	## expect
	##     Param.u32({ name: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("42")])
	##     == Ok(42)
	## ```
	u32 : Base.DefaultableParameterConfigBaseParams(U32) -> Cli(U32, { ..from_action }, Cli.GetParamsAction)
	u32 = |{ name, help, default }|
		Param.single({ parser: |a| parse_num(a, U32.from_str), type: Base.num_type_name, name, help: help ?? "", default: default ?? NoDefault })

	## Add an optional `U32` parameter to your CLI builder.
	##
	## Parsing arguments will fail if the value is not a valid number.
	##
	## ```roc
	## expect
	##     Param.maybe_u32({ name: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([])
	##     == Ok(Err(NoValue))
	## ```
	maybe_u32 : Base.ParameterConfigBaseParams -> Cli(Try(U32, [NoValue]), { ..from_action }, Cli.GetParamsAction)
	maybe_u32 = |{ name, help }|
		Param.maybe({ parser: |a| parse_num(a, U32.from_str), type: Base.num_type_name, name, help: help ?? "" })

	## Add a `U32` parameter that can be provided multiple times
	## to your CLI builder.
	##
	## Parsing arguments will fail if any of the parameters are
	## not not a valid number.
	##
	## ```roc
	## expect
	##     Param.u32_list({ name: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("12"), Utf8("34"), Utf8("56")])
	##     == Ok([12, 34, 56])
	## ```
	u32_list : Base.ParameterConfigBaseParams -> Cli(List(U32), { ..from_action }, Cli.StopCollectingAction)
	u32_list = |{ name, help }|
		Param.list({ parser: |a| parse_num(a, U32.from_str), type: Base.num_type_name, name, help: help ?? "" })

	## Add a required `U64` parameter to your CLI builder.
	##
	## Parsing arguments will fail if the parameter is not provided
	## or the value is not a valid number.
	##
	## ```roc
	## expect
	##     Param.u64({ name: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("42")])
	##     == Ok(42)
	## ```
	u64 : Base.DefaultableParameterConfigBaseParams(U64) -> Cli(U64, { ..from_action }, Cli.GetParamsAction)
	u64 = |{ name, help, default }|
		Param.single({ parser: |a| parse_num(a, U64.from_str), type: Base.num_type_name, name, help: help ?? "", default: default ?? NoDefault })

	## Add an optional `U64` parameter to your CLI builder.
	##
	## Parsing arguments will fail if the value is not a valid number.
	##
	## ```roc
	## expect
	##     Param.maybe_u64({ name: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([])
	##     == Ok(Err(NoValue))
	## ```
	maybe_u64 : Base.ParameterConfigBaseParams -> Cli(Try(U64, [NoValue]), { ..from_action }, Cli.GetParamsAction)
	maybe_u64 = |{ name, help }|
		Param.maybe({ parser: |a| parse_num(a, U64.from_str), type: Base.num_type_name, name, help: help ?? "" })

	## Add a `U64` parameter that can be provided multiple times
	## to your CLI builder.
	##
	## Parsing arguments will fail if any of the parameters are
	## not not a valid number.
	##
	## ```roc
	## expect
	##     Param.u64_list({ name: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("12"), Utf8("34"), Utf8("56")])
	##     == Ok([12, 34, 56])
	## ```
	u64_list : Base.ParameterConfigBaseParams -> Cli(List(U64), { ..from_action }, Cli.StopCollectingAction)
	u64_list = |{ name, help }|
		Param.list({ parser: |a| parse_num(a, U64.from_str), type: Base.num_type_name, name, help: help ?? "" })

	## Add a required `U128` parameter to your CLI builder.
	##
	## Parsing arguments will fail if the parameter is not provided
	## or the value is not a valid number.
	##
	## ```roc
	## expect
	##     Param.u128({ name: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("42")])
	##     == Ok(42)
	## ```
	u128 : Base.DefaultableParameterConfigBaseParams(U128) -> Cli(U128, { ..from_action }, Cli.GetParamsAction)
	u128 = |{ name, help, default }|
		Param.single({ parser: |a| parse_num(a, U128.from_str), type: Base.num_type_name, name, help: help ?? "", default: default ?? NoDefault })

	## Add an optional `U128` parameter to your CLI builder.
	##
	## Parsing arguments will fail if the value is not a valid number.
	##
	## ```roc
	## expect
	##     Param.maybe_u128({ name: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([])
	##     == Ok(Err(NoValue))
	## ```
	maybe_u128 : Base.ParameterConfigBaseParams -> Cli(Try(U128, [NoValue]), { ..from_action }, Cli.GetParamsAction)
	maybe_u128 = |{ name, help }|
		Param.maybe({ parser: |a| parse_num(a, U128.from_str), type: Base.num_type_name, name, help: help ?? "" })

	## Add a `U128` parameter that can be provided multiple times
	## to your CLI builder.
	##
	## Parsing arguments will fail if any of the parameters are
	## not not a valid number.
	##
	## ```roc
	## expect
	##     Param.u128_list({ name: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("12"), Utf8("34"), Utf8("56")])
	##     == Ok([12, 34, 56])
	## ```
	u128_list : Base.ParameterConfigBaseParams -> Cli(List(U128), { ..from_action }, Cli.StopCollectingAction)
	u128_list = |{ name, help }|
		Param.list({ parser: |a| parse_num(a, U128.from_str), type: Base.num_type_name, name, help: help ?? "" })

	## Add a required `I8` parameter to your CLI builder.
	##
	## Parsing arguments will fail if the parameter is not provided
	## or the value is not a valid number.
	##
	## ```roc
	## expect
	##     Param.i8({ name: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("--"), Utf8("-42")])
	##     == Ok(-42)
	## ```
	i8 : Base.DefaultableParameterConfigBaseParams(I8) -> Cli(I8, { ..from_action }, Cli.GetParamsAction)
	i8 = |{ name, help, default }|
		Param.single({ parser: |a| parse_num(a, I8.from_str), type: Base.num_type_name, name, help: help ?? "", default: default ?? NoDefault })

	## Add an optional `I8` parameter to your CLI builder.
	##
	## Parsing arguments will fail if the value is not a valid number.
	##
	## ```roc
	## expect
	##     Param.maybe_i8({ name: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([])
	##     == Ok(Err(NoValue))
	## ```
	maybe_i8 : Base.ParameterConfigBaseParams -> Cli(Try(I8, [NoValue]), { ..from_action }, Cli.GetParamsAction)
	maybe_i8 = |{ name, help }|
		Param.maybe({ parser: |a| parse_num(a, I8.from_str), type: Base.num_type_name, name, help: help ?? "" })

	## Add a `I8` parameter that can be provided multiple times
	## to your CLI builder.
	##
	## Parsing arguments will fail if any of the parameters are
	## not not a valid number.
	##
	## ```roc
	## expect
	##     Param.i8_list({ name: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("--"), Utf8("1"), Utf8("-2"), Utf8("3")])
	##     == Ok([1, -2, 3])
	## ```
	i8_list : Base.ParameterConfigBaseParams -> Cli(List(I8), { ..from_action }, Cli.StopCollectingAction)
	i8_list = |{ name, help }|
		Param.list({ parser: |a| parse_num(a, I8.from_str), type: Base.num_type_name, name, help: help ?? "" })

	## Add a required `I16` parameter to your CLI builder.
	##
	## Parsing arguments will fail if the parameter is not provided
	## or the value is not a valid number.
	##
	## ```roc
	## expect
	##     Param.i16({ name: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("--"), Utf8("-42")])
	##     == Ok(-42)
	## ```
	i16 : Base.DefaultableParameterConfigBaseParams(I16) -> Cli(I16, { ..from_action }, Cli.GetParamsAction)
	i16 = |{ name, help, default }|
		Param.single({ parser: |a| parse_num(a, I16.from_str), type: Base.num_type_name, name, help: help ?? "", default: default ?? NoDefault })

	## Add an optional `I16` parameter to your CLI builder.
	##
	## Parsing arguments will fail if the value is not a valid number.
	##
	## ```roc
	## expect
	##     Param.maybe_i16({ name: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([])
	##     == Ok(Err(NoValue))
	## ```
	maybe_i16 : Base.ParameterConfigBaseParams -> Cli(Try(I16, [NoValue]), { ..from_action }, Cli.GetParamsAction)
	maybe_i16 = |{ name, help }|
		Param.maybe({ parser: |a| parse_num(a, I16.from_str), type: Base.num_type_name, name, help: help ?? "" })

	## Add a `I16` parameter that can be provided multiple times
	## to your CLI builder.
	##
	## Parsing arguments will fail if any of the parameters are
	## not not a valid number.
	##
	## ```roc
	## expect
	##     Param.i16_list({ name: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("--"), Utf8("1"), Utf8("-2"), Utf8("3")])
	##     == Ok([1, -2, 3])
	## ```
	i16_list : Base.ParameterConfigBaseParams -> Cli(List(I16), { ..from_action }, Cli.StopCollectingAction)
	i16_list = |{ name, help }|
		Param.list({ parser: |a| parse_num(a, I16.from_str), type: Base.num_type_name, name, help: help ?? "" })

	## Add a required `I32` parameter to your CLI builder.
	##
	## Parsing arguments will fail if the parameter is not provided
	## or the value is not a valid number.
	##
	## ```roc
	## expect
	##     Param.i32({ name: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("--"), Utf8("-42")])
	##     == Ok(-42)
	## ```
	i32 : Base.DefaultableParameterConfigBaseParams(I32) -> Cli(I32, { ..from_action }, Cli.GetParamsAction)
	i32 = |{ name, help, default }|
		Param.single({ parser: |a| parse_num(a, I32.from_str), type: Base.num_type_name, name, help: help ?? "", default: default ?? NoDefault })

	## Add an optional `I32` parameter to your CLI builder.
	##
	## Parsing arguments will fail if the value is not a valid number.
	##
	## ```roc
	## expect
	##     Param.maybe_i32({ name: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([])
	##     == Ok(Err(NoValue))
	## ```
	maybe_i32 : Base.ParameterConfigBaseParams -> Cli(Try(I32, [NoValue]), { ..from_action }, Cli.GetParamsAction)
	maybe_i32 = |{ name, help }|
		Param.maybe({ parser: |a| parse_num(a, I32.from_str), type: Base.num_type_name, name, help: help ?? "" })

	## Add a `I32` parameter that can be provided multiple times
	## to your CLI builder.
	##
	## Parsing arguments will fail if any of the parameters are
	## not not a valid number.
	##
	## ```roc
	## expect
	##     Param.i32_list({ name: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("--"), Utf8("1"), Utf8("-2"), Utf8("3")])
	##     == Ok([1, -2, 3])
	## ```
	i32_list : Base.ParameterConfigBaseParams -> Cli(List(I32), { ..from_action }, Cli.StopCollectingAction)
	i32_list = |{ name, help }|
		Param.list({ parser: |a| parse_num(a, I32.from_str), type: Base.num_type_name, name, help: help ?? "" })

	## Add a required `I64` parameter to your CLI builder.
	##
	## Parsing arguments will fail if the parameter is not provided
	## or the value is not a valid number.
	##
	## ```roc
	## expect
	##     Param.i64({ name: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("--"), Utf8("-42")])
	##     == Ok(-42)
	## ```
	i64 : Base.DefaultableParameterConfigBaseParams(I64) -> Cli(I64, { ..from_action }, Cli.GetParamsAction)
	i64 = |{ name, help, default }|
		Param.single({ parser: |a| parse_num(a, I64.from_str), type: Base.num_type_name, name, help: help ?? "", default: default ?? NoDefault })

	## Add an optional `I64` parameter to your CLI builder.
	##
	## Parsing arguments will fail if the value is not a valid number.
	##
	## ```roc
	## expect
	##     Param.maybe_i64({ name: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([])
	##     == Ok(Err(NoValue))
	## ```
	maybe_i64 : Base.ParameterConfigBaseParams -> Cli(Try(I64, [NoValue]), { ..from_action }, Cli.GetParamsAction)
	maybe_i64 = |{ name, help }|
		Param.maybe({ parser: |a| parse_num(a, I64.from_str), type: Base.num_type_name, name, help: help ?? "" })

	## Add a `I64` parameter that can be provided multiple times
	## to your CLI builder.
	##
	## Parsing arguments will fail if any of the parameters are
	## not not a valid number.
	##
	## ```roc
	## expect
	##     Param.i64_list({ name: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("--"), Utf8("1"), Utf8("-2"), Utf8("3")])
	##     == Ok([1, -2, 3])
	## ```
	i64_list : Base.ParameterConfigBaseParams -> Cli(List(I64), { ..from_action }, Cli.StopCollectingAction)
	i64_list = |{ name, help }|
		Param.list({ parser: |a| parse_num(a, I64.from_str), type: Base.num_type_name, name, help: help ?? "" })

	## Add a required `I128` parameter to your CLI builder.
	##
	## Parsing arguments will fail if the parameter is not provided
	## or the value is not a valid number.
	##
	## ```roc
	## expect
	##     Param.i128({ name: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("--"), Utf8("-42")])
	##     == Ok(-42)
	## ```
	i128 : Base.DefaultableParameterConfigBaseParams(I128) -> Cli(I128, { ..from_action }, Cli.GetParamsAction)
	i128 = |{ name, help, default }|
		Param.single({ parser: |a| parse_num(a, I128.from_str), type: Base.num_type_name, name, help: help ?? "", default: default ?? NoDefault })

	## Add an optional `I128` parameter to your CLI builder.
	##
	## Parsing arguments will fail if the value is not a valid number.
	##
	## ```roc
	## expect
	##     Param.maybe_i128({ name: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([])
	##     == Ok(Err(NoValue))
	## ```
	maybe_i128 : Base.ParameterConfigBaseParams -> Cli(Try(I128, [NoValue]), { ..from_action }, Cli.GetParamsAction)
	maybe_i128 = |{ name, help }|
		Param.maybe({ parser: |a| parse_num(a, I128.from_str), type: Base.num_type_name, name, help: help ?? "" })

	## Add a `I128` parameter that can be provided multiple times
	## to your CLI builder.
	##
	## Parsing arguments will fail if any of the parameters are
	## not not a valid number.
	##
	## ```roc
	## expect
	##     Param.i128_list({ name: "answer" })
	##         .finish({ name: "example" })
	##         |> Cli.assert_valid
	##         |> Cli.parse_or_display_message([Utf8("--"), Utf8("1"), Utf8("-2"), Utf8("3")])
	##     == Ok([1, -2, 3])
	## ```
	i128_list : Base.ParameterConfigBaseParams -> Cli(List(I128), { ..from_action }, Cli.StopCollectingAction)
	i128_list = |{ name, help }|
		Param.list({ parser: |a| parse_num(a, I128.from_str), type: Base.num_type_name, name, help: help ?? "" })

}

builder_with_parameter_parser : Base.ParameterConfig, (List(Arg) -> Try(data, Base.ArgExtractErr)) -> Cli(data, from_action, to_action)
builder_with_parameter_parser = |param, value_parser| {
	arg_parser = |args| {
		{ values, remaining_args } = Extract.extract_param_values({ args, param })?
		data = value_parser(values)?

		Ok({ data, remaining_args })
	}

	Cli.from_arg_parser(arg_parser).add_parameter(param)
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

expect parse(finish(Param.single({ name: "answer", type: "color", parser: parse_color })), ["blue"]) == Ok(Blue)
expect parse(finish(Param.single({ name: "answer", type: "color", parser: parse_color, default: Value(Red) })), []) == Ok(Red)
expect
	parse(finish(Param.single({ name: "answer", type: "color", parser: parse_color })), [])
		== Err("Error: The 'answer' parameter did not receive a value.\n\nUsage:\n  example [options] <answer>")
expect
	parse(finish(Param.single({ name: "answer", type: "color", parser: parse_color })), ["pink"])
		== Err("Error: The value provided to the 'answer' parameter was not a valid color: 'pink' is not a valid color, must be green, red, or blue.\n\nUsage:\n  example [options] <answer>")
expect
	parse(finish(Param.single({ name: "answer", type: "color", parser: parse_color })), ["red", "blue"])
		== Err("Error: The parameter \"blue\" was not expected.\n\nUsage:\n  example [options] <answer>")

expect parse(finish(Param.maybe({ name: "answer", type: "color", parser: parse_color })), []) == Ok(Err(NoValue))
expect parse(finish(Param.maybe({ name: "answer", type: "color", parser: parse_color })), ["green"]) == Ok(Ok(Green))

expect parse(finish(Param.list({ name: "answer", type: "color", parser: parse_color })), ["blue", "red", "green"]) == Ok([Blue, Red, Green])
expect parse(finish(Param.list({ name: "answer", type: "color", parser: parse_color })), []) == Ok([])

expect parse(finish(Param.arg({ name: "answer" })), ["abc"]) == Ok(Arg.from_str("abc"))
expect parse(finish(Param.maybe_arg({ name: "answer" })), []) == Ok(Err(NoValue))
expect parse(finish(Param.arg_list({ name: "answer" })), ["abc", "def", "ghi"]) == Ok([Arg.from_str("abc"), Arg.from_str("def"), Arg.from_str("ghi")])

expect parse(finish(Param.bytes({ name: "answer" })), ["abc"]) == Ok([97, 98, 99])
expect parse(finish(Param.maybe_bytes({ name: "answer" })), []) == Ok(Err(NoValue))
expect parse(finish(Param.bytes_list({ name: "answer" })), ["abc", "def", "ghi"]) == Ok([[97, 98, 99], [100, 101, 102], [103, 104, 105]])

expect parse(finish(Param.str({ name: "answer" })), ["abc"]) == Ok("abc")
expect parse(finish(Param.str({ name: "answer", default: Generate(|_| "xyz") })), []) == Ok("xyz")
expect parse(finish(Param.maybe_str({ name: "answer" })), []) == Ok(Err(NoValue))
expect parse(finish(Param.str_list({ name: "answer" })), ["abc", "def", "ghi"]) == Ok(["abc", "def", "ghi"])
expect
	Cli.parse_or_display_message(finish(Param.str({ name: "answer" })), [UnixBytes([0xff])])
		== Err("Error: The value provided to the 'answer' parameter was not valid UTF-8.\n\nUsage:\n  example [options] <answer>")

expect parse(finish(Param.dec({ name: "answer" })), ["42.5"]) == Ok(42.5)
expect parse(finish(Param.maybe_dec({ name: "answer" })), []) == Ok(Err(NoValue))
expect parse(finish(Param.dec_list({ name: "answer" })), ["56.0", "8.8", "99.9"]) == Ok([56.0, 8.8, 99.9])
expect parse(finish(Param.f32({ name: "answer" })), ["42.5"]) == Ok(42.5)
expect parse(finish(Param.f64({ name: "answer" })), ["42.5"]) == Ok(42.5)
expect parse(finish(Param.u8({ name: "answer" })), ["42"]) == Ok(42)
expect parse(finish(Param.u16({ name: "answer" })), ["42"]) == Ok(42)
expect parse(finish(Param.u32({ name: "answer" })), ["42"]) == Ok(42)
expect parse(finish(Param.u64({ name: "answer" })), ["42"]) == Ok(42)
expect parse(finish(Param.maybe_u64({ name: "answer" })), []) == Ok(Err(NoValue))
expect parse(finish(Param.u64_list({ name: "answer" })), ["12", "34", "56"]) == Ok([12, 34, 56])
expect parse(finish(Param.u128({ name: "answer" })), ["42"]) == Ok(42)
expect parse(finish(Param.i8({ name: "answer" })), ["--", "-42"]) == Ok(-42)
expect parse(finish(Param.i16({ name: "answer" })), ["--", "-42"]) == Ok(-42)
expect parse(finish(Param.i32({ name: "answer" })), ["--", "-42"]) == Ok(-42)
expect parse(finish(Param.i64({ name: "answer" })), ["--", "-42"]) == Ok(-42)
expect parse(finish(Param.i64_list({ name: "answer" })), ["--", "1", "-2", "3"]) == Ok([1, -2, 3])
expect parse(finish(Param.i128({ name: "answer" })), ["--", "-42"]) == Ok(-42)
expect
	parse(finish(Param.u64({ name: "answer" })), ["x"])
		== Err("Error: The value provided to the 'answer' parameter was not a valid number.\n\nUsage:\n  example [options] <answer>")

# Parameters are parsed in order, and a list takes the rest.
expect
	parse(finish({ first: Param.str({ name: "first" }), second: Param.maybe_u64({ name: "second" }), rest: Param.str_list({ name: "rest" }) }.Cli), ["a", "2", "c", "d"])
		== Ok({ first: "a", second: Ok(2), rest: ["c", "d"] })
