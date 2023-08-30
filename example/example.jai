// run with jai example.jai -plug Disassembler


foo :: () -> int
{
	a := 3;
	b := 4;
	a += b * 2;
	
	return b - a;
} @Disassemble


main :: ()
{
	res := foo();
}
