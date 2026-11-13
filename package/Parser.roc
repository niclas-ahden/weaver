import Arg

## Split command-line arguments into short flags, short flag groups, long
## flags and parameters, before any of them are matched to a CLI's config.
Parser :: [].{

	## The value given to a long flag with `=`, as in `--name=value`.
	ArgValue : Try(Arg, [NoValue])

	## A command-line argument, sorted by its shape.
	ParsedArg : [
		Short(Str),
		ShortGroup({ names : List(Str), complete : [Complete, Partial] }),
		Long({ name : Str, value : ArgValue }),
		Parameter(Arg),
	]

	## Sort command-line arguments by their shape.
	##
	## Everything after a `--` argument is a parameter, whatever it looks like.
	## The list should not start with the program's name, so pass in what
	## basic-cli's `main!` receives as is.
	parse_args : List(Arg) -> List(ParsedArg)
	parse_args = |args| {
		var $parsed_args = []
		var $pass_through = False
		for arg in args {
			if $pass_through {
				$parsed_args = $parsed_args.append(Parameter(arg))
			} else {
				parsed_arg = parse_arg(arg)
				match parsed_arg {
					Parameter(a) if a == double_dash_arg => {
						$pass_through = True
					}
					_ => {
						$parsed_args = $parsed_args.append(parsed_arg)
					}
				}
			}
		}
		$parsed_args
	}
}

single_dash_arg : Arg
single_dash_arg = Arg.from_str("-")

double_dash_arg : Arg
double_dash_arg = Arg.from_str("--")

parse_arg : Arg -> Parser.ParsedArg
parse_arg = |arg| {
	str_arg =
		match Arg.to_str(arg) {
			Ok(str) => str
			Err(InvalidUtf8) => return Parameter(arg)
		}

	match str_arg.split_first("-") {
		Ok({ before: "", after }) =>
			if after == "" {
				Parameter(single_dash_arg)
			} else {
				match after.split_first("-") {
					Ok({ before: "", after: rest }) =>
						if rest == "" or rest.starts_with("-") {
							Parameter(arg)
						} else {
							parse_long_arg(rest)
						}
					_ => construct_set_of_options(after)
				}
			}
		_ => Parameter(arg)
	}
}

parse_long_arg : Str -> Parser.ParsedArg
parse_long_arg = |arg|
	match arg.split_first("=") {
		Ok({ before: option, after: value }) => Long({ name: option, value: Ok(Arg.from_str(value)) })
		Err(_) => Long({ name: arg, value: Err(NoValue) })
	}

construct_set_of_options : Str -> Parser.ParsedArg
construct_set_of_options = |combined| {
	options = combined.to_utf8().keep_oks(|c| Str.from_utf8([c]))

	match options {
		[alone] => Short(alone)
		other => ShortGroup({ names: other, complete: Complete })
	}
}

expect parse_arg(Arg.from_str("-")) == Parameter(Arg.from_str("-"))

expect parse_arg(Arg.from_str("-a")) == Short("a")

expect parse_arg(Arg.from_str("-abc")) == ShortGroup({ names: ["a", "b", "c"], complete: Complete })

expect parse_arg(Arg.from_str("--abc")) == Long({ name: "abc", value: Err(NoValue) })

expect parse_arg(Arg.from_str("--abc=xyz")) == Long({ name: "abc", value: Ok(Arg.from_str("xyz")) })

expect parse_arg(Arg.from_str("123")) == Parameter(Arg.from_str("123"))

expect parse_arg(Arg.from_str("---abc")) == Parameter(Arg.from_str("---abc"))

expect parse_arg(Arg.from_raw_arg(UnixBytes([45, 0xff]))) == Parameter(Arg.from_raw_arg(UnixBytes([45, 0xff])))

expect {
	parsed = Parser.parse_args(["-a", "123", "--passed", "-bcd", "xyz", "--", "--subject=world"].map(Arg.from_str))

	parsed
		== [
			Short("a"),
			Parameter(Arg.from_str("123")),
			Long({ name: "passed", value: Err(NoValue) }),
			ShortGroup({ names: ["b", "c", "d"], complete: Complete }),
			Parameter(Arg.from_str("xyz")),
			Parameter(Arg.from_str("--subject=world")),
		]
}
