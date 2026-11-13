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
		alpha: Opt.u64({ short: "a", help: "Set the alpha level." }),
		force: Opt.flag({ short: "f", help: "Force the task to complete." }),
		file: Param.maybe_str({ name: "file", help: "The file to process." }),
		files: Param.str_list({ name: "files", help: "The rest of the files." }),
	}.Cli
		.finish({
			name: "basic",
			version: "v0.0.1",
			authors: ["Some One <some.one@mail.com>"],
			description: "This is a basic example of what you can build with Weaver. You get safe parsing, useful error messages, and help pages all for free!",
		})
		|> Cli.assert_valid
