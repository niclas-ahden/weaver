## Must not compile: an option field after a parameter field. `roc check`
## reports a type mismatch, which ./tests.roc expects.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.31.0/Ff3fkK1TjYTVxMj9V21FP24ojTJXYk314Fbo1whBZ6Yf.tar.zst",
	weaver: "../../package/main.roc",
}

import pf.Stdout
import weaver.Cli
import weaver.Opt
import weaver.Param

main! = |args| {
	data = Cli.parse_or_display_message(cli_parser, args) ?? { file: "", force: False }
	Stdout.line!(Str.inspect(data))
}

cli_parser =
	{
		file: Param.str({ name: "file" }),
		force: Opt.flag({ short: "f" }),
	}.Cli
		.finish({ name: "example" })
		|> Cli.assert_valid
