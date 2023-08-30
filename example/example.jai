// run with jai example.jai -plug Disassembler


foo :: () -> int
{
	a := 3;
	b := 4;
	if a > 3
	{
		a += b * 2;
	}
	
	return b - a;
} @Disassemble(foo.asm)

bar :: () -> int
{
	a := 3;
	b := 4;
	while true
	{
		if a > 3
		{
			a += b * 2;
		}
	}
	
	return b - a;
} @Disassemble(foo.asm)


baz :: () -> int
{
	return 3;
} @Disassemble

main :: ()
{
	res := foo();
}
