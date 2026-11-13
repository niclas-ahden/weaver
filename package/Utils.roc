## Helpers for checking and changing the case of names.
Utils :: [].{

	## Whether a name is kebab-case: lowercase letters and digits joined by
	## single dashes, starting with a letter.
	is_kebab_case : Str -> Bool
	is_kebab_case = |s|
		match Str.to_utf8(s) {
			[] => False
			[single] => is_lower_case(single) or is_digit(single)
			[first, .. as middle, last] => {
				first_is_kebab = is_lower_case(first)
				last_is_kebab = is_lower_case(last) or is_digit(last)
				middle_is_kebab = middle.all(|char| is_lower_case(char) or is_digit(char) or char == dash_ascii_code)
				no_double_dashes =
					middle
						.map2(middle.drop_first(1), |left, right| (left, right))
						.all(|(left, right)| !(left == dash_ascii_code and right == dash_ascii_code))

				first_is_kebab and last_is_kebab and middle_is_kebab and no_double_dashes
			}
		}

	## Uppercase the ASCII letters of a string.
	to_upper_case : Str -> Str
	to_upper_case = |str| {
		bytes = Str.to_utf8(str).map(
			|c|
				if is_lower_case(c) {
					c - ('a' - 'A')
				} else {
					c
				},
		)
		Str.from_utf8(bytes) ?? ""
	}
}

dash_ascii_code : U8
dash_ascii_code = '-'

is_digit : U8 -> Bool
is_digit = |char| char >= '0' and char <= '9'

is_lower_case : U8 -> Bool
is_lower_case = |char| char >= 'a' and char <= 'z'

expect Str.to_utf8("19aB ").map(is_digit) == [True, True, False, False, False]

expect Str.to_utf8("aAzZ-").map(is_lower_case) == [True, False, True, False, False]

expect Utils.is_kebab_case("abc-def")
expect !Utils.is_kebab_case("-abc-def")
expect !Utils.is_kebab_case("abc-def-")
expect !Utils.is_kebab_case("-")
expect !Utils.is_kebab_case("")
expect !Utils.is_kebab_case("abc--def")

expect Utils.to_upper_case("abc") == "ABC"
expect Utils.to_upper_case("ABC") == "ABC"
expect Utils.to_upper_case("aBc00-") == "ABC00-"
