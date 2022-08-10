vt100.bin vt100.hex vt100.lst &: src/vt100.asm
	asm8080 -lvt100 -ovt100 src/vt100.asm

vt100.sym : vt100.lst
	perl -ne '/([a-z0-9_]*)\s*Label.*([a-f0-9]{4})h\Z/i&&do{print "$2 $1\n";}' VT100.final.lst > vt100.sym

vt100.equ : vt100.lst
	perl -ne '/([a-z0-9_]*)\s*EQU.*([a-f0-9]{4})h\Z/i&&do{print "$2 $1\n";}' VT100.final.lst > vt100.equ

.PHONY : clean

clean :
	rm -f vt100.bin vt100.hex vt100.lst vt100.sym vt100.equ

