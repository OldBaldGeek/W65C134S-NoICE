#!/usr/bin/python
#
# wdc_noi.py: extract debug information from WDC/Zardoz SYM files for use by NoICE
#
# The WDC/Zardoz SYM file format is documented in chapter 6 of
# "WDCTools Debugger" pdf dated September 13, 2013
# There are additional equates and enums in wdc\Tools\include\OBJ816.H
#
# Written by John Hartman
#
VERSION = '2.0'

# I like upper-case for hex characters, and lower-case for 0x.
# So my f-strings don't use :#x or :#X. If you don't like it, use the source, Luke
import os
import sys
import string
import argparse

# The chapter 6 description uses C_xxx for the class of symbol records.
# wdc\Tools\include\OBJ816.H has (among other things) definitions:
#   enum { C_NULL, C_AUTO, C_EXT, C_STAT, C_REG, C_EXTDEF, C_ARG,
#          C_STRTAG, C_MOS, C_EOS, C_UNTAG, C_MOU, C_ENTAG, C_MOE,
#          C_TPDEF, C_USTATIC, C_REGPARM, C_FIELD, C_UEXT, C_STATLAB,
#          C_EXTLAB, C_BLOCK, C_EBLOCK, C_FUNC, C_EFUNC, C_FILE, C_LINE,
#          C_FRAME };
# Most of these are used to allow debugging of C code.
# So for, we only handle assembly and global symbols
C_EXT = 2
C_FILE = 25

# Contents of the SYM file
g_data = 0
g_string_table_offset = 0

# "Auxiliary Record Table Format" in chapter 6 says that the low four bits of
# each longword indicates a base type as defined in the T_xxx enum.
# But the enum has 19 values...
# For now, we'll mask off 5 bits.
#
# %U and %S follow NoICE's current radix, so the user can select decimal or
# hex display. %X always display in hex.
g_aux_type_as_noice_type = [
    '%X08',     # 0 T_NULL
    '%X08',     # 1 T_VOID
    '%X08',     # 2 T_SCHAR
    '%X08',     # 3 T_CHAR
    '%S16',     # 4 T_SHORT
    '%S16',     # 5 T_INT16
    '%S32',     # 6 T_INT32
    '%S32',     # 7 T_LONG
    '%float',   # 8 T_FLOAT
    '%double',  # 9 T_DOUBLE
    '%X08',     # 10 T_STRUCT
    '%X08',     # 11 T_UNION
    '%X08',     # 12 T_ENUM
    '%X08',     # 13 T_LDOUBLE
    '%U08',     # 14 T_UCHAR
    '%U16',     # 15 T_USHORT
    '%U16',     # 16 T_UINT16
    '%U32',     # 17 T_UINT32
    '%U32'      # 18 T_ULONG
]

#==============================================================================
# Cursor to read from a WDC/Zardoz SYM file
class SymCursor:
    def __init__(self, a_offset):
        self.cursor = a_offset

    def set_cursor(self, a_offset):
        self.cursor = a_offset

    def get_cursor(self):
        return self.cursor

    def byte(self):
        global g_data
        retval = g_data[self.cursor]
        self.cursor += 1
        return retval

    def word(self):
        global g_data
        retval = g_data[self.cursor] + (g_data[self.cursor+1]<<8)
        self.cursor += 2
        return retval

    def longword(self):
        global g_data
        retval = (g_data[self.cursor] + (g_data[self.cursor+1]<<8) +
                 (g_data[self.cursor+2]<<16) + (g_data[self.cursor+3]<<24))
        self.cursor += 4
        return retval

#=============================================================================
# Return the string at specified offset
def string_at(a_offset):
    global g_data
    global g_string_table_offset
    offset = g_string_table_offset + a_offset
    # We assume no string longer than 200 bytes
    clean_bytes, _, _ = g_data[offset:offset+200].partition(b'\x00')
    retval = clean_bytes.decode('ascii')
    return retval

#==============================================================================
# Read the Header from a WDC/Zardoz SYM file
class Header:
    def __init__(self, a_cursor):
        self.valid = False
        self.signature = a_cursor.word()
        if self.signature == 0x2345:
            self.valid = True
            self.version = a_cursor.word()
            self.num_sections = a_cursor.word()
            self.symrec_offset = a_cursor.longword()
            self.num_symrec = a_cursor.word()
            self.aux_offset = a_cursor.longword()
            self.num_aux = a_cursor.word()
            self.stringtable_offset = a_cursor.longword()
            self.stringtable_size = a_cursor.longword()
            self.sourcefile_offset = a_cursor.longword()
            self.num_sourcefiles = a_cursor.word()
            self.num_modules = a_cursor.word()

#==============================================================================
# Read a Symbol record from a WDC/Zardoz SYM file
class SymbolRecord:
    def __init__(self, a_cursor):
        self.index = a_cursor.longword()
        self.value = a_cursor.longword()
        self.symclass = a_cursor.byte()
        self.flags = a_cursor.byte()
        self.aux_index = a_cursor.word()

#=============================================================================
#
def main():
    parser = argparse.ArgumentParser(description =
       (f'wdc_noi version {VERSION}. Parse a WDC/Zardoz -sz SYM file '
        f'to extract debug information for use by NoICE.')
    )
    parser.add_argument('-s', '--start', help='specify start address or symbol')
    parser.add_argument('infile', help='the SYM file from WDCLN -g -sz')

    ns = parser.parse_args()
    infile, extension = os.path.splitext(ns.infile)

    global g_data
    global g_string_table_offset
    global g_aux_type_as_noice_type
    with open(ns.infile,"rb") as symfile:
        g_data = symfile.read()

        # Read the file header
        cur = SymCursor(0)
        header = Header(cur)
        if not header.valid:
            print(f'Not a Zardoz SYM file. Signature is 0x{header.signature:X}')
            return

        g_string_table_offset = header.stringtable_offset

        with open(infile + '.noi',"w") as outfile:
            # Delete obsolete debug info (based on file or timestamp change)
            outfile.write('LASTFILELOADED\n')

            # Get Source File Names, accessed by index in other sections
            files = {}
            current_file = 0
            filecur = SymCursor(header.sourcefile_offset)
            print(f'Source File records: {header.num_sourcefiles}')
            for ix in range(0, header.num_sourcefiles):
                file_index = filecur.longword()
                line_count = filecur.word()
                files[ix] = string_at(file_index)
                outfile.write(f'FILE {string_at(file_index)}\n')

            # Process Aux records (which may be used by module and global symbols)
            # For now, we just cope with primitives, as in assembly code.
            # See the comment above g_aux_type_as_noice_type for details.
            data_types = {}
            auxcur = SymCursor(header.aux_offset)
            print(f'Aux records: {header.num_aux}')
            for ix in range(0, header.num_aux):
                auxval = auxcur.longword()
                print(f'  Aux {ix} 0x{auxval:X}')
                data_types[ix] = g_aux_type_as_noice_type[ auxval & 0x1F ]

            # Process modules
            for ix in range(0,header.num_modules):
                name_index = cur.longword()
                num_sections = cur.word()
                print((f'Module {ix} {string_at(name_index)} has '
                       f'{num_sections} sections'))

                # Sections within the module
                # "Section Information" in the PDF is poorly written.
                # There is a "size" longword for each section. After the section
                # data there is ONE word with the number of line records
                # in the module.
                for iy in range(0,num_sections):
                    section_number  = cur.word()
                    section_address = cur.longword()
                    section_size    = cur.longword()
                    print((f'  Section {section_number} at 0x{section_address:X} '
                           f'size 0x{section_size:X}'))

                # Line records in the module
                num_lines = cur.word()
                print(f'  Line records: {num_lines}')
                for iy in range(0,num_lines):
                    line_address = cur.longword()
                    source_line  = cur.word()
                    line_bytes   = cur.word()
                    file_index   = cur.byte()
                    longa_longi  = cur.byte()
                    if file_index != current_file:
                        current_file = file_index
                        outfile.write(f'FILE {files[current_file]}\n')

                    outfile.write(f'LINE {source_line} 0x{line_address:X}\n')

                # Symbol records in the module
                # (We currently don't use these)
                num_syms = cur.word()
                print(f'  Module Symbols records: {num_syms}')
                for iy in range(0,num_syms):
                    sym = SymbolRecord(cur)

            # Process Global symbols
            cur.set_cursor(header.symrec_offset)
            print(f'Global Symbols records: {header.num_symrec}')
            for ix in range(0, header.num_symrec):
                sym = SymbolRecord(cur)
                if sym.symclass == C_EXT:
                    outfile.write((f'DEF {string_at(sym.index)} 0x{sym.value:X} '
                                   f'{data_types[sym.aux_index]}\n'))

            # Done reading SYM file.
            if current_file != '':
                outfile.write('ENDFILE\n')

            # Ask NoICE to load the program data
            outfile.write(f'LOAD "{infile}.s19"\n')

            # WDC tools don't include a start address in the S9 record, so
            # we allow it to be set from a command line parameter
            if ns.start:
                outfile.write(f'REG PC {ns.start}\n')

            # set source mode and show our glorious results
            outfile.write('MODE 2\n')
            outfile.write('SOURCE PC\n')

if __name__ == "__main__":
    main()
