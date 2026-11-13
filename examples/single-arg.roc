app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.31.0/Ff3fkK1TjYTVxMj9V21FP24ojTJXYk314Fbo1whBZ6Yf.tar.zst",
	weaver: "../package/main.roc",
}

import pf.Stdout
import weaver.Cli
import weaver.Opt

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
	Opt.u64({ short: "a", long: "alpha", help: "Set the alpha level." })
		.map(|alpha| Alpha(alpha))
		.finish({
			name: "single-arg",
			version: "v0.0.1",
		})
		|> Cli.assert_valid
