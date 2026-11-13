## An OS-aware representation of a command-line argument.
##
## Though we tend to think of args as Unicode strings, most operating systems
## represent command-line arguments as lists of bytes that aren't necessarily
## UTF-8 encoded. Windows doesn't even use bytes, but U16s.
##
## An [Arg] holds an argument in the shape a platform hands it over,
## `[Utf8(Str), UnixBytes(List(U8)), WindowsU16s(List(U16))]`, which is
## what basic-cli's `main!` receives. Weaver takes a list of those directly,
## so most of the time you never see this type. For quick-and-dirty code you
## can use [display] to convert one to a [Str] in a lossy way.
##
## Two args are equal when they hold the same text, whichever of the three
## shapes holds it. Args that are not valid Unicode are only equal to the
## identical bytes or code units.
Arg :: [Utf8(Str), UnixBytes(List(U8)), WindowsU16s(List(U16))].{

	## Wrap a raw, OS-aware argument into an [Arg].
	from_raw_arg : [Utf8(Str), UnixBytes(List(U8)), WindowsU16s(List(U16))] -> Arg
	from_raw_arg = |raw|
		match raw {
			Utf8(str) => Utf8(str)
			UnixBytes(bytes) => UnixBytes(bytes)
			WindowsU16s(u16s) => WindowsU16s(u16s)
		}

	## Unwrap an [Arg] into the raw, OS-aware value it was made from.
	##
	## This is a good way to pass [Arg]s to Roc packages.
	to_raw_arg : Arg -> [Utf8(Str), UnixBytes(List(U8)), WindowsU16s(List(U16))]
	to_raw_arg = |arg|
		match arg {
			Utf8(str) => Utf8(str)
			UnixBytes(bytes) => UnixBytes(bytes)
			WindowsU16s(u16s) => WindowsU16s(u16s)
		}

	## Wrap a UTF-8 [Str] into an [Arg].
	from_str : Str -> Arg
	from_str = |str| Utf8(str)

	## Attempt to decode an [Arg] to a UTF-8 [Str].
	to_str : Arg -> Try(Str, [InvalidUtf8])
	to_str = |arg|
		match arg {
			Utf8(str) => Ok(str)
			UnixBytes(bytes) =>
				match Str.from_utf8(bytes) {
					Ok(str) => Ok(str)
					Err(_) => Err(InvalidUtf8)
				}
			WindowsU16s(u16s) =>
				match Str.from_utf16_le(u16s_to_le_bytes(u16s)) {
					Ok(str) => Ok(str)
					Err(_) => Err(InvalidUtf8)
				}
		}

	## Convert an [Arg] to a list of bytes.
	##
	## Windows code units are split into two bytes each, the high byte first.
	to_bytes : Arg -> List(U8)
	to_bytes = |arg|
		match arg {
			Utf8(str) => Str.to_utf8(str)
			UnixBytes(bytes) => bytes
			WindowsU16s(u16s) => {
				var $bytes = List.with_capacity(2 * u16s.len())
				for codepoint in u16s {
					$bytes = $bytes.append(U16.to_u8_wrap(codepoint.shr_zf_wrap(8))).append(U16.to_u8_wrap(codepoint))
				}
				$bytes
			}
		}

	## Convert an [Arg] to a [Str] for display purposes.
	##
	## This replaces invalid codepoints with the Unicode replacement character "\u(FFFD)".
	display : Arg -> Str
	display = |arg|
		match arg {
			Utf8(str) => str
			UnixBytes(bytes) => Str.from_utf8_lossy(bytes)
			WindowsU16s(u16s) => Str.from_utf16_le_lossy(u16s_to_le_bytes(u16s))
		}

	## Compare two args by their text, whichever shape holds it.
	is_eq : Arg, Arg -> Bool
	is_eq = |left, right|
		match (Arg.to_str(left), Arg.to_str(right)) {
			(Ok(left_str), Ok(right_str)) => left_str == right_str
			_ =>
				match (left, right) {
					(UnixBytes(left_bytes), UnixBytes(right_bytes)) => left_bytes == right_bytes
					(WindowsU16s(left_u16s), WindowsU16s(right_u16s)) => left_u16s == right_u16s
					_ => False
				}
		}

	## Show an [Arg] as the string it displays as.
	to_inspect : Arg -> Str
	to_inspect = |arg| Str.inspect(Arg.display(arg))
}

u16s_to_le_bytes : List(U16) -> List(U8)
u16s_to_le_bytes = |u16s| {
	var $bytes = List.with_capacity(2 * u16s.len())
	for codepoint in u16s {
		$bytes = $bytes.append(U16.to_u8_wrap(codepoint)).append(U16.to_u8_wrap(codepoint.shr_zf_wrap(8)))
	}
	$bytes
}

expect Arg.from_str("abc").to_str() == Ok("abc")
expect Arg.from_raw_arg(UnixBytes([97, 98, 99])).to_str() == Ok("abc")
expect Arg.from_raw_arg(WindowsU16s([97, 98, 99])).to_str() == Ok("abc")
expect Arg.from_raw_arg(UnixBytes([0xff])).to_str() == Err(InvalidUtf8)
expect Arg.from_raw_arg(WindowsU16s([0xd800])).to_str() == Err(InvalidUtf8)

expect Arg.from_raw_arg(UnixBytes([97, 98, 99])) == Arg.from_str("abc")
expect Arg.from_raw_arg(WindowsU16s([97, 98, 99])) == Arg.from_str("abc")
expect Arg.from_raw_arg(UnixBytes([0xff])) == Arg.from_raw_arg(UnixBytes([0xff]))
expect Arg.from_raw_arg(UnixBytes([0xff])) != Arg.from_raw_arg(UnixBytes([0xfe]))
expect Arg.from_str("abc") != Arg.from_str("abd")

expect Arg.from_raw_arg(UnixBytes([97, 0xff])).display() == "a\u(FFFD)"
expect Arg.from_raw_arg(WindowsU16s([0x00e9])).display() == "\u(e9)"

expect Arg.from_str("ab").to_bytes() == [97, 98]
expect Arg.from_raw_arg(WindowsU16s([0x0102])).to_bytes() == [1, 2]

expect Arg.from_raw_arg(UnixBytes([1, 2])).to_raw_arg() == UnixBytes([1, 2])

expect Str.inspect(Arg.from_str("abc")) == "\"abc\""
