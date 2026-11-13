## Must not compile: a parameter field after a parameter list field.
## `roc check` reports a type mismatch, which ./tests.roc expects.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.31.0/Ff3fkK1TjYTVxMj9V21FP24ojTJXYk314Fbo1whBZ6Yf.tar.zst",
	weaver: "../../package/main.roc",
}

import pf.Stdout
import weaver.Cli
import weaver.Param

main! = |args| {
	data = Cli.parse_or_display_message(cli_parser, args) ?? { files: [], last: "" }
	Stdout.line!(Str.inspect(data))
}

cli_parser =
	{
		files: Param.str_list({ name: "files" }),
		last: Param.str({ name: "last" }),
	}.Cli
		.finish({ name: "example" })
		|> Cli.assert_valid
