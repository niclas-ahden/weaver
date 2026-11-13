app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.31.0/Ff3fkK1TjYTVxMj9V21FP24ojTJXYk314Fbo1whBZ6Yf.tar.zst",
	weaver: "../package/main.roc",
}

import pf.Stdout
import weaver.Cli
import weaver.Opt
import weaver.Param

main! = |args| {
	data =
		match Cli.parse_or_display_message(cli_parser, args) {
			Ok(parsed) => parsed
			Err(message) => {
				Stdout.line!(message)?
				return Err(Exit(1))
			}
		}

	Stdout.line!("Successfully parsed! Here's what I got:")?
	Stdout.line!("")?
	Stdout.line!(Str.inspect(data))?

	Ok({})
}

cli_parser =
	{
		alpha: Opt.u64({
			short: "a",
			long: "alpha",
			help: "Set the alpha level. [default: 123]",
			default: Value(123),
		}),
		beta: Opt.dec({
			short: "b",
			long: "beta",
			help: "Set the beta level. [default: PI]",
			default: Generate(|{}| Dec.pi),
		}),
		file: Param.maybe_str({
			name: "file",
			help: "The file to process. [default: NONE]",
		}).map(|f| f ?? "NONE"),
	}.Cli
		.finish({
			name: "default-values",
			version: "v0.0.1",
		})
		|> Cli.assert_valid
