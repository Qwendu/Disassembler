// run with jai example.jai -plug Disassembler

global : int;

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
		if a > 2
		{
			a += 1;
		}else{
			a -= 1;
		}
	}
	
	return b - a;
} @Disassemble(foo.asm)


baz :: () -> int
{
	return 3;
} @Disassemble

boo :: ()
{
} @Disassemble

main :: ()
{
	res := foo();
}
