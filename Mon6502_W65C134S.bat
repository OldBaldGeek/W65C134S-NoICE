rem -g debug; -S pass local symbols; -l listing
WDC02AS -l Mon6502_W65C134S.asm
WDCLN -sz -t -HM19 Mon6502_W65C134S

REM Generate a version offset to load at 0x2000 for the Flash burner
REM This gives an annoying "warning: no header record," since the WDC linker
REM doesn't generate one.
REM It also generates S0 and S5 records, which the WDC ROM monitor does not
REM handle correctly (it ends up executing any hex digits in the A-F range)
REM
REM So to make this file loadable by the WDC monitor you must edit the output
REM file to remove the S0 record at the start, and S5 and S9 records at the end
srec_cat Mon6502_W65C134S.s19 -offset -0xD000 -Output mon_at_2000.s19
