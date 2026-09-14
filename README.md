# W65C134S-NoICE
## Using NoICE on the Western Design Center W65C134SX board

NoICE Debugger (https://www.noicedebugger.com) is a remote debugger
analogous to using gdb with a remote stub. 
NoICE supports a variety of 8-bit and 16-bit targets, including the 65C02.

The UI of NoICE runs under Windows. For 65(C)02 and similar targets,
NoICE uses a small target monitor, usually communicating via a serial line.
Full details of the protocol may be found on the NoICE website.

This repository is intended to allow NoICE to be used to debug programs running
on the W65C134SX board.

NoICE itself is not Open Source or Free. However, files posted in this
repository are in the public domain.

## Target Monitor

NoICE ships (or downloads) with source code for standard monitors. This
repository contains monitors modified to support various modes of operation
on W65C134SX hardware.

The classic (since 1993) NoICE monitor has used polled serial ports, and runs
with interrupts disabled. Polled serial is simpler to implement, which makes
the monitor easier to port to new hardware.

But the main advantage of polled serial is that when the monitor hits a breakpoint
(BRK on the 6502) and enters the monitor, "time freezes:" there may be interrupts
pending, and more may be requested while the monitor is active, but you don't
need to worry about program state and variables changing while you ponder.
It also means that you can place breakpoint INSIDE interrupt handlers or other
places where interrupts are disabled.

Alas, the UART (ACI) on the W65C134 cannot be used in polled mode: it has no
status bits for "Rx data available" or "Tx empty." So this monitor has to use
interrupts for serial communication. Upon entry to the monitor, either initially 
or via BRK or other means, the monitor
will mask or disable all interrupts other than the serial port, in hopes of
getting as close to "time freezes" as we can. (See INTERRUPT_NOTES in the
monitor code for details.)

On the plus side, using interrupts means that NoICE can read and write target
memory **WHILE A USER PROGRAM IS RUNNING**, or force the program to stop, as long
as the user program has interrupts enabled.

If you need to port a NoICE monitor to new hardware and can/prefer to use polled
serial, you should start with the classic 6502 monitor MON6502.ASM rather than
the code here. For more information on that, refer to the NoICE help file
[monitor.htm](https://www.noicedebugger.com/help/monitor.htm)

This file may be be assembled and linked with WDC tools WDC02AS and WDCLN.

**CAUTION:** the WDC assembler won't let you put a space within an expression, so
```
   LDA #THING + OTHER  or
   IF THING > OTHER
``` 
will quietly ignore the characters after "THING." Ain't that special?

The W65C134SXB hardware supports eight 32K "banks" of Flash EPROM. NoICE supports
banked memory (see NoICE help file 2bitmmu.htm), but this monitor DOES NOT
support NoICE memory banking:
- The monitor resides in the top page of Flash. If you change banks, the
  monitor will disappear
- NoICE sets breakpoints by writing BRK instructions. Thus, user code must be
  in RAM, which isn't affected by banking on the W65C134SXB anyway.

This monitor is normally configured to be burned into and run from the top 4K of Flash
(addresses 0xF00 to 0xFFFF), hiding the WDC ROM monitor and taking control of
the interrupt vectors. In order to allow user programs to service interrupts, 
most of the hardware vectors JMP through a set of "re-vectors" at the top of RAM, from 0x7FD0-0x7FFF.

The monitor may be configured to be loaded into and run from RAM. However, you will still need to
burn a set of interrupt vectors at FFD0-FFFF to "re-vector" interrupts through RAM.
The monitor source and build files give more information, and BurnMonitor has burn the
re-vectoring code.

## Installing, Bypassing, and Removing the Monitor
The W65C134SXB ships with a simple monitor in ROM that takes control after reset.
If you install a SST39SF010A Flash chip in the board, you can burn a magic "WDC" at 0x8000
that will cause the ROM monitor to run a program from Flash. That program can "hide"
the ROM monitor, allowing it to take over the interrupt vectors.
This is the normal mode or operation for NoICE.

### Installing the pre-built Monitor
- The file **BurnMonitor.s19** contains a Flash burner (BurnMonitor.asm) merged with a copy of
the NoICE monitor (moved to 2000)
- Use the WDC monitor to load **BurnMonitor.s19**
- Use the WDC monitor to "G 1000" to burn the monitor and stub
- If the burn succeeds, LED XCS0 will flash. If the erase or burn fails, LEDs XCS0 and XCS3 should flash alternately.
- Reset or power-cycle the board, and it should run the NoICE monitor. XCS0 will flash, and you will get a short message on the serial port.
- After doing this once, you can use NoICE instead of the WDC monitor

### Bypassing the NoICE Monitor
With the NoICE monitor installed as above, a reset will start the WDC monitor. It will see the "WDC"
and address 0x8000, and jump to 0x8004, starting the NoICE monitor.

However, if you hold the NMI pin (Port 4 bit 0, available on J3, pin 3) low during reset or 
powerup, the code at 0x8000 will jump back into the WDC monitor. So you can still use the 
WDC monitor until the next reset. You might do this to run BurnMonitor again, to load an 
updated version of the NoICE monitor; or just to remember how crude the WDC monitor is
compared to NoICE.

### Bypassing the NoICE Monitor
Should you decide that you don't want to use the NoICE monitor, you will need to remove the "WDC"
at 0x8000. To do this

- While holding the NMI pin low,  reset or power up the board.
- This should show the WDC monitor startup message on the serial port
- Use the WDC monitor to load **BurnMonitor.s19**
- Use the WDC monitor to "G 1006" to erase the Flash sector at 0x8000
- If the burn succeeds, LED XCS0 will flash. If the erase or burn fails, LEDs XCS0 and XCS3 
should flash alternately
- Reset or power-cycle the board, and it should run the WDC monitor.

## Files

### Mon6502_W65C134S.asm and .bat
Mon6502_W65C134S.asm is the source code for the NoICE monitor for the W65C134SXB board.

In most cases, you can use the pre-built BurnMonitor.s19 and will not need to modify or assemble 
Mon6502_W65C134S.asm. However, we encourage you to read the source code to become familiar 
with how it operates, and with some of the quirks of operation on the W65C134SX.

If you do need to assemble the monitor, run Mon6502_W65C134S.bat. In addition to
generating a normal S-record file, it uses srec_cat to generate a version of S-record file
with addresses changed to load at 0x2000 for use with BurnMonitor.

### BurnMonitor.asm, .bat, and .s19
BurnMonitor.asm is a special-purpose Flash burner with just enough capability to install
or remove the NoICE monitor from Flash. 
See [Installing, Bypassing, and Removing the Monitor](#Installing,-Bypassing,-and-Removing-the-Monitor)
for details.

You may find parts of BurnMonitor.asm useful for other Flash-burning needs.

### NoICE02.noi
When NoICE02.exe runs, it looks in its own directory for a file named **NoICE02.noi**. If the files exists,
NoICE PLAYS the commands in the file.

This version of NoICE02.noi contains STATETEXT for all 24 interrupt vectors on the W65C134S, as
well as symbols for all of the W65C134S I/O registers. Feel free to add, modify, or remove commands
from this file, and place it in the appropriate directory.

When the NoICE monitor initializes, it sets default handlers in all 24 of the interrupt "re-vectors"
in RAM. Code that uses a given interrupt is expected to initialize the appropriate re-vector.
If an interrupt occurs for which you have **NOT** set the re-vector, the default handler will
report the offending interrupt to NoICE on the PC. The STATETEXT commands in NoICE02.noi
provide text to be shown for these reports.

The I/O register definitions are used by the NoICE disassembler, and you may use them when
entering address expressions. If you don't like the WDC names, simply change NoICE02.noi.

## Support Utilities

### wdc_noi.py
NoICE is most conveniently used as a source-level debugger. However, doing that
requires appropriate debug information about the code being debugged. NoICE
supports elf/dwarf debug files, but these are not generated by WDC tools
that I have seen.

The WDC tools do support some symbol options, including the WDC/Zardoz format.
wdc_noi.py extracts symbol definitions and line-number information from WDC/Zardoz SYM files. 

To use this
- Assemble your code using **WDC02AS** with flags **-g** to get debug information, **-s**
to get symbol information, and **-l** to get an assembly listing file
- Link your code using **WDCLN** with flags **-g** to get debug information, **-sz**
to get a debug file, **-t** to get a map, and **-HM19** to get an S-record file
- Run **wdc_noi.py** specifying the SYM debug file

Thus, for myprog.asm you might have
```
   WDC02AS -g -s -l myprog.asm
   WDCLN -g -sz -t -hM19 myprog.obj
   wcd_noi myprog.sym
```
This will generate myprog.noi. Run NoICE02, then PLAY myprog.noi. This will define all your program's
symbols and line number information, then load myprog.s19 and be ready for debugging.

**MOST** assemblers let you specify a start address or symbol on your END directive, and place
this address in the S9 record of the output file. WDC's tools don't seem to do this. To work
around this, wdc_noi.py allows an optional **-S** or **--start** switch to let you define
a start address for use in debugging.

Presuming that your program has a label on its first instruction, simply specify this label after
the -S switch. If you don't have a label on your first instruction, you may specify a hex address.

### wdcsym_noi.py
This was my initial attempt, trying to avoid parsing Zardoz files by scraping debug information
from a text file generated by WDCSYM. For myprog.asm you might have
```
   WDC02AS -g -s -l myprog.asm
   WDCLN -g -sz -t -hM19 myprog.obj
   WDCSYM -a -l -s myprog.sym>myprog.txt
   wcdsym_noi myprog.txt
```
This worked, but WDCSYM truncates symbol names at ten characters, which I found unacceptable.
So Zardoz it is.


