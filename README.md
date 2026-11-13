Weaver
======

An ergonomic command-line argument parser for the Roc language.

This library aims to provide a convenient interface for parsing CLI arguments
into structured data, in the style of Rust's [clap](https://github.com/clap-rs/clap).
Without code generation at compile time, the closest we can get in Roc is the use of the
record builder syntax, `{ a: x, b: y }.Cli`.
This allows us to build our config and parser at the same time, in a type-safe way!

This is a port of [smores56/weaver](https://github.com/smores56/weaver) to the
current Roc compiler. See [Changes from upstream Weaver](#changes-from-upstream-weaver)
for what is different.

Read the documentation at <https://niclas-ahden.github.io/weaver/>.

## Status

This library is ready to parse your args today, but I'm always looking for more testing
from the community! Feel free to open a GitHub issue if there's a feature you're missing
from another CLI parsing library that you think would fit well in Weaver's nest.

## Example

```roc
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.31.0/Ff3fkK1TjYTVxMj9V21FP24ojTJXYk314Fbo1whBZ6Yf.tar.zst",
	weaver: "https://github.com/niclas-ahden/weaver/releases/download/0.7.1/EyDiT4HEfS5wS5VpyaSJyC4XZHuBM9Bc8g9d1csgQ2pt.tar.zst",
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
```

And here's us calling the above example from the command line:

```console
$ roc examples/basic.roc file1.txt file2.txt -f -a 123
Successfully parsed! Here's what I got:

{ alpha: 123, file: Ok("file1.txt"), files: ["file2.txt"], force: True }

$ roc examples/basic.roc --help
basic v0.0.1
Some One <some.one@mail.com>

This is a basic example of what you can build with Weaver. You get safe parsing, useful error messages, and help pages all for free!

Usage:
  basic -a NUM [options] <file> <files...>

Arguments:
  <file>      The file to process.
  <files...>  The rest of the files.

Options:
  -a NUM         Set the alpha level.
  -f             Force the task to complete.
  -h, --help     Show this help page.
  -V, --version  Show the version.

$ roc examples/basic.roc
Error: Required option -a is missing.

Usage:
  basic -a NUM [options] <file> <files...>
```

There are also some examples in the [examples](./examples) directory that are more
feature-complete, with more to come as this library matures.

## Changes from upstream Weaver

The API is upstream Weaver's, with the changes the current Roc language and
basic-cli call for:

- A CLI is built with the record builder `{ a: x, b: y }.Cli` instead of
  `{ Cli.weave <- a: x, b: y }`. The builder type is now `Cli(data, from_action, to_action)`,
  which calls `Cli.map2` for each field. `Cli.weave` is still there, as another name for `Cli.map2`.
  A record builder needs at least two fields, so name a single field with `.map(|alpha| { alpha: alpha })`.
- The `Builder` module is gone. Its type is now the `Cli` type, and its functions
  (`from_arg_parser`, `add_option`, `update_parser`, `check_for_help_and_version` and so on)
  are members of `Cli`, since a record builder must name a type that has `map2`.
  `Builder.GetOptionsAction` and the other action types are `Cli.GetOptionsAction` and so on,
  and `Cli.CliParser` is the type of a finished parser.
- `Cli.parse_or_display_message(parser, args)` takes the arguments as basic-cli's `main!`
  receives them, `List([Utf8(Str), UnixBytes(List(U8)), WindowsU16s(List(U16))])`, without the
  program's name. There is no third argument to convert them.
- An `Arg` holds one of those three shapes. Two args are equal when they hold the same text.
  The `Arg` module is now exposed, so a custom parser can use it.
- `Result` is `Try`, so a missing optional value is `Err(NoValue)` in a `Try(a, [NoValue])`.
- Tags are no longer functions, so a subcommand's mapper is written `mapper: |data| Foo(data)`.
- Number parsers use the builtin `U64.from_str` and friends, and `Generate` defaults take `|{}| ...`.

Behaviour that changed:

- Options can no longer share a name with the options of a command above them, or with
  `-h/--help` and `-V/--version`. Upstream Weaver documented this check but had it switched off
  until the compiler could handle it.
- Flags that share a short group, as in `-vf`, are all found. Upstream Weaver lost the rest of the
  group once it found the first option in it.
- A CLI finished without a `version` has no `-V/--version`, so one of its own options may be
  called `--version`. A CLI with a version keeps the flag, and so do subcommands.
- The usage line names only the options that have to be given. Upstream Weaver listed every
  option that takes a value there, optional and list options included.

## Tests

`./tests.roc` runs everything: the package's `expect` blocks, the CLI tests in
`tests/cli_test.roc`, two CLIs that must fail to compile because their fields are out of
order, and each example with several sets of arguments, comparing what they print.

```console
$ nix develop -c ./tests.roc
```

## Roadmap

These are some ideas for future development:

- [ ] Optionally set `{ group ?: Str }` per option so they are visually grouped in the help page
- [ ] Completion generation for popular shells (e.g. Bash, Zsh, Fish, etc.)
- [X] Add terminal escape sequences to generated messages for prettier help/usage text formatting (currently working, but could be nicer/more configurable)
- [ ] add convenient CLI platform wrappers (e.g. parse, or print help and exit) for use with module params
- [X] Clean up default parameter code if we can elide different fields on the same record type in different places (not currently allowed)
- [ ] Add more testing (always)
