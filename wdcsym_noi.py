#!/usr/bin/python
#
# wdcsym_noi.py: Parse WDCSYM -ALS txt files
# to extract debug information for use by NoICE
#
# Written by John Hartman
#
# Version 1.0
#
import os
import sys
import string
import argparse
import re

#=============================================================================
#
def main():
    parser = argparse.ArgumentParser(description =
        'Parse WDCSYM -ALS text file to extract debug information for use by NoICE.'
    )
    parser.add_argument('-s', '--start', help='specify start address or symbol')
    parser.add_argument('infile', help='the output txt file from WDCSYM -ALS')

    ns = parser.parse_args()
    infile, extension = os.path.splitext(ns.infile)

    with open(infile + '.noi',"w") as outfile:
        # Delete obsolete debug info (based on file or timestamp change)
        outfile.write('LASTFILELOADED\n')

        section = ''
        # source files, indexed by file number
        files = {}
        current_file = ''
        aux_types = {}

        with open(ns.infile,"r") as symfile:
            # 4 aux entries
            #      0: 00000000 -                    EQU and labels
            #      1: 0000000F -  unsigned short    DS 2, RMB 2, WORD
            #      2: 0000000E -  unsigned char     DS 1, RMB 1
            #      3: 00000012 -  unsigned long     DS 4, RMB 4
            re_aux_entries = re.compile(r'^(\d+) aux entries')
            re_one_aux_entry = re.compile(r'^\s+(\d+): ([0-9A-Za-z]+) -\s+(.+)')

            # Read once to get Aux entries for use by symbols in pass two.
            # We can use these to specify datatypes of defined symbols based
            # on their aux values. This might be useful for C code, where you
            # would usually want to display a two-byte value as a decimal integer,
            # less useful in assembly where a hex display is equally likely.
            for line in symfile:
                match = re_aux_entries.match(line)
                if match:
                    section = 'aux entries'
                    print('Aux entries: ' + match.group(1))

                if section == 'aux entries':
                    match = re_one_aux_entry.match(line)
                    if match:
                        noice_type = ''
                        if match.group(3) == 'unsigned long':
                            noice_type = '%X32'
                        elif match.group(3) == 'unsigned short':
                            noice_type = '%X16'

                        print('  Aux entry ' + match.group(1) +
                                      ' ' + match.group(2) +
                                      ' "' + match.group(3) + '"' +
                                      ' as ' + noice_type)

                        aux_types[match.group(1)] = noice_type

            # Read again to get everything that may use Aux entries
            symfile.seek(0)

            # 14 file entries
            #    0: nlines=410 <IMON.ASM>
            #    1: nlines=410 <COPYRITE.ASM>
            re_files = re.compile(r"^(\d+) file entries")
            re_one_file = re.compile(r'\s(\d+)\: nlines=(.+) \<(.+)\>')

            # module 0: IMON.OBJ
            #    snum = 0 start=40 size=71
            #    snum = 1 start=8000 size=32491
            #    snum = 3 start=FEF3 size=269
            #    nlinrecs = 1854
            #        file 5 line 4 @ 8000 ps=30 len=4
            #        file 5 line 5 @ 8004 ps=30 len=2
            re_module = re.compile(r'^module (\d+)\: (.+)')
            re_one_line = re.compile(r'^\s+file (\d+) line (\d+) \@ ([0-9A-Za-z]+) ps=(\d+) len=(\d+)')

            # 451 global sym recs
            #    LOWNIB     val=0000000F class=    ext flg=0 aux=0
            #    HINIB      val=000000F0 class=    ext flg=0 aux=0
            re_symbols = re.compile(r'^(\d+) global sym recs')
            re_one_symbol = re.compile(r'^\s+(\S+)\s+val=([0-9A-Za-z]+)\sclass=\s+(\S+) flg=(\d+) aux=(\d+)')

            for line in symfile:
                match = re_files.match(line)
                if match:
                    section = 'files'
                    print('Files: ' + match.group(1))

                if section == 'files':
                    match = re_one_file.match(line)
                    if match:
                        files[match.group(1)] = match.group(3)
                        outfile.write('FILE ' + match.group(3) + '\n')

                match = re_module.match(line)
                if match:
                    section = 'modules'
                    print('Modules: ' + match.group(2))

                if section == 'modules':
                    match = re_one_line.match(line)
                    if match:
                        if match.group(1) != current_file:
                            current_file = match.group(1)
                            outfile.write('FILE ' + files[current_file] + '\n')

                        outfile.write('LINE ' + match.group(2) + 
                                      ' 0x' + match.group(3) + '\n')

                match = re_symbols.match(line)
                if match:
                    section = 'symbols'
                    print('Symbols: ' + match.group(1))

                if section == 'symbols':
                    match = re_one_symbol.match(line)
                    if match:
                        outfile.write('DEF ' + match.group(1) + 
                                      ' 0x'  + match.group(2) +
                                      ' '    + aux_types[match.group(5)] + '\n')

            if current_file != '':
                outfile.write('endfile\n')

            # Load the program data
            outfile.write('load "' + infile + '.s19"\n')

            # WDC tools don't include a start address in the S9 record, so
            # set it from a command line parameter
            if ns.start:
                outfile.write('reg pc ' + ns.start + '\n')
            # set source mode and show our glorious results
            outfile.write('mode 2\n')
            outfile.write('s pc\n')

if __name__ == "__main__":
    main()
