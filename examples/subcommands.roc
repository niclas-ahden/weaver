app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.31.0/Ff3fkK1TjYTVxMj9V21FP24ojTJXYk314Fbo1whBZ6Yf.tar.zst",
	weaver: "../package/main.roc",
}

import pf.Stdout
import weaver.Cli
import weaver.Opt
import weaver.Param
import weaver.SubCmd

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
		force: Opt.flag({ short: "f", help: "Force the task to complete." }),
		sc: SubCmd.optional([subcommand_parser1, subcommand_parser2]),
		file: Param.maybe_str({ name: "file", help: "The file to process." }),
		files: Param.str_list({ name: "files", help: "The rest of the files." }),
	}.Cli
		.finish({
			name: "subcommands",
			version: "v0.0.1",
			authors: ["Some One <some.one@mail.com>"],
			description: "This is a basic example of what you can build with Weaver. You get safe parsing, useful error messages, and help pages all for free!",
		})
		|> Cli.assert_valid

subcommand_parser1 =
	{
		d: Opt.maybe_u64({ short: "d", help: "A non-overlapping subcommand flag with s2." }),
		volume: Opt.maybe_u64({ short: "v", long: "volume", help: "How loud to grind the gears." }),
		sc: SubCmd.optional([sub_subcommand_parser1, sub_subcommand_parser2]),
	}.Cli
		|> SubCmd.finish({ name: "s1", description: "A first subcommand.", mapper: |data| S1(data) })

subcommand_parser2 =
	Opt.maybe_u64({ short: "d", help: "This doesn't overlap with s1's -d flag." })
		.map(|d| DFlag(d))
		|> SubCmd.finish({
			name: "s2",
			description: "Another subcommand.",
			mapper: |data| S2(data),
		})

sub_subcommand_parser1 =
	{
		a: Opt.u64({ short: "a", help: "An example short flag for a sub-subcommand." }),
		b: Opt.u64({ short: "b", help: "Another example short flag for a sub-subcommand." }),
	}.Cli
		|> SubCmd.finish({ name: "ss1", description: "A sub-subcommand.", mapper: |data| SS1(data) })

sub_subcommand_parser2 =
	{
		a: Opt.u64({ short: "a", help: "Set the alpha level." }),
		c: Opt.u64({ short: "c", long: "create", help: "Create a doohickey." }),
		data: Param.str({ name: "data", help: "Data to manipulate." }),
	}.Cli
		|> SubCmd.finish({ name: "ss2", description: "Another sub-subcommand.", mapper: |data| SS2(data) })
