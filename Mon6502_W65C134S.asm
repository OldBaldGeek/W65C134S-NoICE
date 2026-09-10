        TTL 'NoICE monitor for the W65C134SXB board'
        CHIP    65C02
        PW      132
        PL      0       ;Ain't gonna print it - skip the headers

; NOTE: this has been modified to run in RAM at 7000 rather than
; in Flash in order to make debugging easier.
; The file Mon6502_W65C134S - saved Flash version.asm as the last Flash version
; before we split.

; NoICE02 Debug monitor for use with the WDC W65C134SXB board
;
; Copyright (c) 2026 by John Hartman
;
; Modification History:
; 8-Sep-2026 JLH rewrite to interrupt-driven serial to support the W65C134SXB
;
; The classic (since 1993) NoICE monitor has used polled serial ports, and run
; with interrupts disabled. Polled serial is simpler to implement, which makes
; the monitor easier to implement or port to new hardware.
;
; But the main advantage of polling is that when the monitor hits a breakpoint
; (BRK on the 6502) and enters the monitor, "time freezes." There may be interrupts
; pending, and more may be requested while the monitor is active, but you don't
; need to worry about program state and variables changing while you ponder.
; It also means that you can place breakpoint INSIDE interrupt handlers or other
; places where interrupts are disabled.
;
; But the UART (ACI) on the W65C134 cannot be used in polled mode: it has no
; status bits for "Rx data available" or "Tx empty." So this monitor uses
; interrupts. Upon entry to the monitor, either initially or via BRK, the monitor
; will mask or disable all interrupts other than the serial port, in hopes of
; getting as close to "time freezes" as we can. (See INTERRUPT_NOTES in the
; code below for details.) Experience will show whether this is close enough.
;
; On the plus side, using interrupts means that NoICE can read and write target
; memory WHILE A USER PROGRAM IS RUNNING, or force the program to stop, as long
; as the user program has interrupts enabled.
;
; If you need to port a NoICE monitor to new hardware and can/prefer to use polled
; serial, you should start with the classic 6502 monitor MON6502.ASM
; For more information, refer to the NoICE help file monitor.htm
;
; This file may be be assembled and linked with WDC tools WDC02AS and WDCLN
; CAUTION: this assembler won't let you put a space within an expression:
;   LDA #THING + OTHER  or
;   IF THING > OTHER
; will quietly ignore the characters after "THING"
;
; The W65C134SXB hardware supports 8 32K "banks" of Flash EPROM. NoICE supports
; banked memory (see NoICE help file 2bitmmu.htm), but this monitor DOES NOT
; support NoICE memory banking:
; - The monitor resides in the top page of Flash. If you change banks, the
;   monitor will disappear
; - NoICE sets breakpoints by writing BRK instructions. Thus, user code must be
;   in RAM, which isn't affected by banking on the W65C134SXB anyway.
;
;============================================================================
; HARDWARE PLATFORM CUSTOMIZATIONS
;
; This monitor uses NO Page 0 RAM
; (unlike the WDC ROM monitor which eats a quarter of that precious resource)
; Instead, we use a block of RAM at the top of the SXB's 32K
;
RAM_START       EQU     $7E00       ;Start of monitor ram
USER_VECT       EQU     $7FD0       ;Start of user interrupt (re)vectors

; To place the monitor in Flash EPROM, set RUN_FROM_RAM to 0
; To place the monitor in RAM, set RUN_FROM_RAM to 1
; See further explanations below
RUN_FROM_RAM    EQU     0

  IFFALSE RUN_FROM_RAM
    ; Configure the monitor to run from Flash EPROM (normal case)
    ; We typically burn the assembled code and interrupt vectors into Flash,
    ; $F000-FFFF.
    ;
    ; This area isn't accessible until BCR and port 3 are configured to hide the
    ; ROM monitor. That is done by a small program burned into Flash at $8000.
    ; This progam:
    ; - may be burned into Flash using NoICE_burner.
    ; - starts with "WDC" so the ROM monitor will run it
    ; - checks the state of Port 4 bit 0 (aka NMI). If this pin is low, jump
    ;   back into the ROM monitor. This allows you to re-program Flash, or
    ;   do other operations using the ROM monitor
    ; - If Port 4 bit 0 is high, then "hide" the ROM monitor and jump to
    ;   the NoICE monitor at MON_START
MON_START       EQU     $F000   ;Monitor code starts here
HARD_VECT       EQU     $FFD0   ;Start of hardware vectors

  ELSE
    ; Configure the monitor to run from RAM, usually for evaluation or testing.
    ; To use NoICE this way, you must burn a "re-vector" program and set of
    ; interrupt vectors into Flash from $F000-FFFF. The re-vector jumps each of
    ; the 24 W65C134S interrupt vectors through vectors at the top of RAM.
    ; The re-vector program may be burned into Flash using NoICE_burner, and
    ; only needs to be done once unless you burn something else at $F000-FFFF.
    ;
    ; With the re-vector in place, use the WDC ROM monitor to load the
    ; NoICE monitor into RAM and execute it, typically with "G7000"
MON_START       EQU     $7000   ;Monitor code starts here

  ENDC

; STACK RAM (PAGE 1)
; Monitor use is at most 8 bytes of stack
; This stack is shared with user programs.
INITSTACK       EQU     $01FF   ;TOP OF STACK RAM

;=================================================================================
; CHIP AND BOARD HARDWARE
;=================================================================================

PD3     EQU     $0003   ;Port 3 data
_PD3_IDLE_LED EQU $01   ; Monitor idle LED
_PD3_ERR_LED  EQU $02   ; Monitor error LED (unexpected interrupt in monitor)
PCS3    EQU     $0007   ;Port 3 control

IFR2    EQU     $0008   ;Interrupt Flag Register 2
IER2    EQU     $0009   ;Interrupt Enable Register 2

TCR1    EQU     $000A   ;Timer Control Register 1
TCR2    EQU     $000B   ;Timer Control Register 2

BCR     EQU     $001B   ;Bus control register
PD4     EQU     $001C   ;Port 4 data
PD5     EQU     $001D   ;Port 5 data
PDD4    EQU     $001E   ;Port 4 data direction
PDD5    EQU     $001F   ;Port 5 data direction
PD6     EQU     $0020   ;Port 6 data
_PD6_TXD   EQU    $02   ;  TX output pin
PDD6    EQU     $0021   ;Port 6 data direction

UART_CTL    EQU $0022   ;ACI status and control
_UART_TXE   EQU   $01   ; Tx enable
_UART_TXSRE EQU   $02   ; Tx interrupt on shift register empty
UART_DATA   EQU $0023   ;ACI data reg

TALL    EQU     $0024   ;Timer A latch low
TALH    EQU     $0025   ;Timer A latch high

TMLL    EQU     $0028   ;Timer M latch low
TMLH    EQU     $0029   ;Timer M latch high
TMCL    EQU     $002A   ;Timer M counter low
TMCH    EQU     $002B   ;Timer M counter high

IFR1    EQU     $002C   ;Interrupt Flag Register 1
IER1    EQU     $002D   ;Interrupt Enable Register 1

;============================================================================
; RAM definitions
        UDATA
        ORG     RAM_START
;
; Target registers: order must match that used by NoICE02 on the PC
TASK_REGS:
REG_STATE       RMB     1
REG_PAGE        RMB     1
REG_SP          RMB     2
REG_Y           RMB     1
REG_X           RMB     1
REG_A           RMB     1
REG_CC          RMB     1
REG_PC          RMB     2
TASK_REG_END:
TASK_REGS_SIZE  EQU    TASK_REG_END-TASK_REGS
;
MON_FLAGS       RMB     1       ;Monitor state flags
_MF_IN_MONITOR    EQU   $01     ;0 if user program is running, 1 if monitor
_MF_BLOCK_NMI     EQU   $02     ;ignore NMI if set (basically debounce)
SKIP_REG_REPORT RMB     1       ;omit register dump when entering monitor
IDLE_TMR        RMB     2       ;Timer for monito idle LED flash
SAVE_IER1       RMB     1       ;save IER1 while monitor is active
SAVE_IER2       RMB     1       ;save IER2 while monitor is active
SAVE_BCR        RMB     1       ;save BCR while monitor is active
;
; In order that we need no page zero RAM, we do memory access via an
; instruction built into RAM. Build instruction and RTS here
CODEBUF         RMB     4       ;ROOM FOR "LDA xxxx, RTS" or "STA xxxx, RTS"
;
; Communications buffer. Must be at least as long as TASK_REG_SZ and TSTG_SIZE
; Larger values may improve speed of NoICE memory commands.
; However, this monitor does memory read and write with interrupts disabled, so
; a shorter buffer minimizes disruption by memory access on a running program.
; Sized to accept a 3-byte paged address plus the content of a 16-byte S-record
BUF_INDEX       RMB     1
CHECKSUM        RMB     1
COMBUF_SIZE     EQU     3+16    ;DATA SIZE FOR COMM BUFFER
COMBUF          RMB     2+COMBUF_SIZE+1  ;FN, LEN, DATA, CHECKSUM
                RMB     64      ;extra space for ASCII messages
;
RAM_END:                        ;address of top+1 OF monitor RAM
        IF RAM_END>USER_VECT
            ERROR_MONITOR_RAM_OVERLAPS_USER_VECTORS
        ENDIF
        ENDS

;===========================================================================
        CODE
        ORG     MON_START
;
; Poweron reset on the W65C134 enters the ROM monitor, which does some
; initialization before checking the Flash for "WDC" and eventually jumping here.
; We re-initialize everything to prevent surprises from different ROM versions.
;
; Power on reset
RESET:
;
; Set CPU mode to safe state
        SEI                     ;INTERRUPTS OFF
        CLD                     ;USE BINARY MODE
        LDX     #<INITSTACK
        TXS

; In order to enable NMI (Port 4 bit 0) as a "stop" button we also have to enable
; IRQ1B and IRQ2B. So if you want to use Port 4 bits 1 and 2 as simple I/O, be
; sure to leave IRQ1B and IRQ2B disabled in IER2.
;
; Bus Control register
;  7  1 External Flash $F000-$FFFF (replace ROM monitor and interrupt vectors)
;  6  1 Port 4 0-2 are NMI,IRQ1,IRQ2 (vs port pins)
;  5  0 Port 5 4-7 are port pins (vs edge interrupt)
;  4  0 Port 5 0-3 are port pins (vs edge interrupt)
;  3  0 Normal mode (vs test)
;  2  0 SIB disabled
;  1  0 Port 4 4-7 are port pins (vs edge interrupt)
;  0  1 Enable memory bus (vs Port 0,1,2)
        LDA     #%11000001
        STA     BCR
        STA     SAVE_BCR

; Port 3
;  7  1 P37_CS7B_Flash  8000-FFFF Flash (internal ROM disabled in BCR)
;  6  1 P36_CS6B_SRAM   0100-7FFF external RAM
;  5  0 P35_AMS         A16 bank switch (1=top bank for monitor)
;  4  0 P34_FA15        A15 bank switch (1=top bank for monitor)
;  3  0 P33_XCS3B       LED indicator (1=off)
;  2  0 P32_XCS2B       LED indicator (1=off)
;  1  0 P31_XCS1B       LED indicator (1=off)
;  0  0 P30_XCS0B       LED indicator (1=off)
        LDA     #%11110000      ;Flash bank3, LEDs ON as an indication of reset
        STA     PD3
        LDA     #%11000000
        STA     PCS3

; Port 6
;  7  0 CHOUT (input, not used by monitor)
;  6  0 CHIN
;  5  0 SDAT
;  4  0 SCLK
;  3  0
;  2  1 Serial DTR (output)
;  1  1 Serial Tx  (output to hold idle line when UART TX disabled)
;  0  0 Serial Rx  (input)
        LDA     #%00000010      ;DTR=0(active), Tx=1(idle)
        STA     PD6
        LDA     #%00000110
        STA     PDD6

; Timer for ACI UART baud rate
;  7  1 Clear Timer A interrupt
;  6  0 Timer A interrupt disabled
;  5  0 Timer A used for ACI baud rate (P6.1 is TxD)
;  4  0 Timer A counts PHI2 pulses
;  3  1 Timer A clock enabled for ACI
;  2  1 Start FCLK
;  1  1 PHI2 source is FCLK
;  0  0 Do not start Watchdog timer
        LDA     #%10001110
        STA     TCR1

; Baud rate is 1/16 of Timer A rate
; At 3.6864 MHZ, 230400 divided by timer init-1
;  9600 baud 24
; 19200 baud 12
; 38400 baud 6
; 57600 baud 4
        LDA     #<(24-1)        ;19,200 baud
        STA     TALL
        LDA     #>(24-1)
        STA     TALH

; ACI Serial
; ACSR (UART_CTL)
;   7  1 write 1 to reset any Rx error (parity, framing, overrun)
;   6  0 software flag, not used by hardware
;   5  1 enable RX, RxInt and RxD on port 6
;   4  0
;   3  0 disable parity
;   2  1 8-bit data
;   1  0 TxInt on data register empty. If 1, also interrupt on shift register empty
;   0  0 disable TX, TxInt and TxD on port 6
        LDA     #%10100400
        STA     UART_CTL

; Interrupt Enable and Flags 1
;   7  0 NE53 neg edge
;   6  0 NE52 neg edge
;   5  0 PE51 pos edge
;   4  0 PE50 pos edge
;   3  0 NE47_DSR neg edge
;   2  0 NE46 neg edge
;   1  0 PE45 pos edge
;   0  0 PE44 pos edge
        LDA     #%00000000      ;disable interrupts
        STA     IER1
        STA     SAVE_IER1
        LDA     #%11111111      ;clear any existing interrupts
        STA     IFR1

; Interrupt Enable and Flags 2
;   7  0 IRQ2B
;   6  0 IRQ1B
;   5  0 Timer 2 Edge
;   4  0 Timer 1 Edge
;   3  0 NE57 neg Edge
;   2  0 PE56 pos edge
;   1  0 PE55 pos edge
;   0  0 PE54 pos edge
        LDA     #%00000000      ;disable interrupts
        STA     IER2
        STA     SAVE_IER2
        LDA     #%11111111      ;clear any existing interrupts
        STA     IFR2

; Other registers as from hardware reset per Table 3-2
        STZ     TCR2
        STZ     PD4
        STZ     PDD4
        STZ     PD5
        STZ     PDD5

  IFFALSE RUN_FROM_RAM
; Running with interrupt vectors in Flash.
; Initialize user vectors in RAM with default unhandled-interrupt handlers
; If user code doesn't set the RAM vector, and the interrupt occurs, the
; monitor will report the interrupt to NoICE.
        LDX     #0
IR_1:   LDA     VEC_INIT,X
        STA     USER_VECT,X
        INX
        CPX     #VEC_SIZE
        BCC     IR_1
  ENDC

; Initialize user registers
        LDX     #<INITSTACK
        STX     REG_SP          ;INIT USER'S STACK POINTER
        LDX     #>INITSTACK
        STX     REG_SP+1
        STZ     REG_PC
        STZ     REG_PC+1
        STZ     REG_A
        STZ     REG_X
        STZ     REG_Y
        STZ     REG_CC
        STZ     REG_STATE       ;STATE IS 0 = RESET

; Initialize memory paging variables and hardware (if any)
        STZ     REG_PAGE        ;NO PAGING

; Flag that we are in the monitor
        LDA     #_MF_IN_MONITOR+_MF_BLOCK_NMI
        STA     MON_FLAGS
        STZ     SKIP_REG_REPORT

; Send an ASCII startup message:
; - visible on a terminal during initial rungout of the monitor
; - shown by NoICE in its TTY window during normal debugging
        LDX     #0
IR_9:   LDA     RESET_MSG,X
        STA     COMBUF,X
        BEQ     IR_10
        INX
        BRA     IR_9
;
IR_10:  JSR     SEND_WAIT
        JMP     RETURN_REGS

RESET_MSG: BYTE "NoICE monitor for W65C134S", 0

;===========================================================================
; Enter here if you have used JSR for breakpoint:  PC is stacked.
; Stacked PC points at JSR+1
;;BRKE: PHP                     ;SAVE CC'S AS IF AFTER A BRK INSTRUCTION
;;      PHA                     ;SAVE ACCUM FROM DIRECT ENTRY
;;      SEC
;
;===========================================================================
; Common handler for default interrupt handlers, or JMP from FN_STOP_TARGET
; Enter with A=interrupt code = processor state to report to host
; A, PSP, and PC are stacked.
; If BRK, stacked PC points at BRK+2 else at PC
INT_ENTRY:
;
; Set CPU mode to safe state
        STA     REG_STATE       ;SAVE MACHINE STATE
        LDA     #_MF_IN_MONITOR
        TSB     MON_FLAGS
        BEQ     IE_10           ;enter the monitor from user code (normal case)
;
; Interrupt or BRK while in the monitor. We have a problem:
; The stacked registers are MONITOR registers, and we don't want to replace
; the saved user registers.
; But what can we do to let the user know?
; For now, we change REG_STATE, return the existing registers.
;
; Fully enter monitor, block NMI
        LDA     #_MF_IN_MONITOR+_MF_BLOCK_NMI
        STA     MON_FLAGS
;
; Clean the stack
        LDX     REG_SP
        TXS
;
; Turn on the error LED
        LDA     #_PD3_ERR_LED
        TRB     PD3
;
; Try to send an ASCII message indicating the problem.
;
; It isn't clear that this will work: since we haven't SERVICED the offending
; interrupt, it is likely to recur as soon as SEND_WAIT enables interrupts
; to send the message. We disable device interrupts (again) and try to avoid
; stack overflow
        STZ     IER1
        STZ     IER2
        LDA     #%00000100      ;disable SIB
        TRB     BCR
;
; TODO: will NoICE display this in the Output tab, since it thinks the target
; isn't running?
; It might be nice to show REG_STATE of the offender in the text.
; However, it IS in updated registers
        LDX     #0
IE_1:   LDA     IE_ERROR,X
        STA     COMBUF,X
        BEQ     IE_2
        INX
        BRA     IE_1
;
IE_2:   JSR     SEND_WAIT
        JMP     RETURN_REGS     ;Go report existing registers
IE_ERROR: BYTE  "ERROR: unexpected interrupt while monitor is active", $D, $A, 0

; Fully enter monitor, block NMI
IE_10:  LDA     #_MF_IN_MONITOR+_MF_BLOCK_NMI
        STA     MON_FLAGS

; Save registers in reg block for return to master
        PLA                     ;GET ACCUMULATOR
        STA     REG_A
        PLA                     ;GET CONDITION CODES
        STA     REG_CC
        PLA                     ;GET LSB OF PC OF BREAKPOINT
        STA     REG_PC
        PLA                     ;GET MSB OF PC OF BREAKPOINT
        STA     REG_PC+1
;
; If this is a breakpoint (state = 1), then back up PC to point at BRK or JSR
        LDA     REG_STATE       ;SAVED STATUS FOR TESTING
        CMP     #1
        BNE     IE_20           ;BR IF NOT BREAKPOINT: PC IS OK
        SEC
        LDA     REG_PC          ;BACK UP PC TO POINT AT BRK (or SBC #3 if JSR)
        SBC     #2
        STA     REG_PC
        LDA     REG_PC+1
        SBC     #0
        STA     REG_PC+1
IE_20:  STX     REG_X
        STY     REG_Y
        TSX
        STX     REG_SP          ;SAVE USER'S STACK POINTER (LSB)
        LDA     #1              ;STACK PAGE ALWAYS 1
        STA     REG_SP+1

;;;     LDA     PAGEIMAGE       ;GET CURRENT USER PAGE
        LDA     #0              ;... OR ZERO IF UNPAGED TARGET
        STA     REG_PAGE        ;SAVE USER'S PAGE
;
; INTERRUPT_NOTES:
; Processor interrupts are currently disabled.
; We need to allow serial interrupts, but nothing else
; Save IER and BCR values, and disable them; restore in RUN_TARGET.
;
; Clearing bits in the IER prevents interrupts from happening, but changes to the
; port bits will still set bits in the IFR. When the IER is restored, any pending
; interrupts will happen immediately (or as soon as the processor I bit is clear)
;
; Interrupt Enable 1
;   7  0 NE53 neg edge
;   6  0 NE52 neg edge
;   5  0 PE51 pos edge
;   4  0 PE50 pos edge
;   3  0 NE47_DSR neg edge
;   2  0 NE46 neg edge
;   1  0 PE45 pos edge
;   0  0 PE44 pos edge
        LDA     IER1
        STA     SAVE_IER1
        STZ     IER1
;
; Interrupt Enable 2
;   7  0 IRQ2B
;   6  0 IRQ1B
;   5  0 Timer 2 Edge
;   4  0 Timer 1 Edge
;   3  0 NE57 neg Edge
;   2  0 PE56 pos edge
;   1  0 PE55 pos edge
;   0  0 PE54 pos edge
        LDA     IER2
        STA     SAVE_IER2
        STZ     IER2

; Bus Control register
; TODO: this is ugly. There seems to be no way to block SIB interrupts
; without disabling the SIB. This may mean you can't use NoICE and the SIB
;
;  7  1 External Flash $F000-$FFFF (replace ROM monitor and interrupt vectors)
;  6  0 Port 4 0-2 are port pins (vs NMI,IRQ1,IRQ2)
;  5  0 Port 5 4-7 are port pins (vs edge interrupt)
;  4  0 Port 5 0-3 are port pins (vs edge interrupt)
;  3  0 Normal mode (vs test)
;  2  0 SIB disabled
;  1  0 Port 4 4-7 are port pins (vs edge interrupt)
;  0  1 Enable memory bus (vs Port 0,1,2)
        LDA     BCR
        STA     SAVE_BCR
        LDA     #%00000100      ;disable SIB
        TRB     BCR

; Entry hack for stop-target message: send status, DO NOT dump registers
        LDA     SKIP_REG_REPORT
        BEQ     RETURN_REGS
        STZ     COMBUF+2        ;status 0 = "happy"
        LDA     #1
        STA     COMBUF+1        ;set length
        JSR     SEND            ;Initiate transmission
        BRA     ENTER_IDLE

; Return registers to master and enter monitor loop
RETURN_REGS:
        LDA     #_MF_IN_MONITOR+_MF_BLOCK_NMI
        STA     MON_FLAGS

        LDA     #FN_RUN_TARGET
        STA     COMBUF
        JSR     COPY_REGS       ;Copy registers to COMBUF
        JSR     SEND            ;Initiate transmission

; Loop here, toggling a heartbeat LED.
; 3.6864 MHz crystal gives 271.267 nsec instruction cycle.
; 65536 17-cycle loops is 302 msec
ENTER_IDLE:
        STZ     SKIP_REG_REPORT
        LDA     #_PD3_IDLE_LED  ;Turn on "in monitor" LED
        TRB     PD3
IDLE:   STZ     IDLE_TMR
        STZ     IDLE_TMR+1
ID_10:  LDX     REG_SP          ;4 Reset to user stack
        TXS                     ;2
        CLI                     ;2
        DEC     IDLE_TMR        ;6
        BNE     ID_10           ;3 = 17 cycles per loop
        DEC     IDLE_TMR+1
        BNE     ID_10
;
; The WDC ROM monitor initializes the watchdog strobe low.
; If we see the strobe high here, we assume that user code has started the
; watchdog, and renew the watchdog here; else we leave it alone.
; If you don't use the watchdog, you could remove this code.
        LDA     #%00000001
        TRB     TCR1            ;test watchdog strobe, set low
        BEQ     ID_20           ;already low: assume watchdog not running
        TSB     TCR1            ;watchdog strobe high, starting the timer
;
ID_20:  LDA     #_PD3_IDLE_LED  ;Toggle the LED
        TSB     PD3
        BEQ     IDLE
        TRB     PD3
        BRA     IDLE

;===========================================================================
; Copy user registers into COMBUF for send to target
COPY_REGS:
        LDX     #0
        LDY     #TASK_REGS_SIZE ;NUMBER OF BYTES
        STY     COMBUF+1        ;SAVE RETURN DATA LENGTH

; Copy the registers
GRLP:   LDA     TASK_REGS,X     ;GET BYTE TO A
        STA     COMBUF+2,X      ;STORE TO RETURN BUFFER
        INX
        DEY
        BNE     GRLP
        RTS

;===========================================================================
; Response string for GET TARGET STATUS request
; Reply describes target:
TSTG:   FCB     7               ;0: PROCESSOR TYPE = 65(C)02
        FCB     COMBUF_SIZE     ;1: SIZE OF COMMUNICATIONS BUFFER
        FCB     %11100000       ;2: has CALL, talk while running, RESET
        FDB     0,0             ;3-6: LOW AND HIGH LIMIT OF MAPPED MEM (NONE)
        FCB     B1-B0           ;7 BREAKPOINT INSTR LENGTH
;
; Define either the BRK or JSR BRKE instruction for use as breakpoint
; so we do it by hand.
B0:     FCB    $00              ;8 BREKAPOINT INSTRUCTION
B1:     FCB    "W65C134S monitor V1.0",0    ;9-? DESCRIPTION, ZERO
        FCB     0               ;page (if used) of CALL breakpoint
        FDB     B0              ;address of CALL breakpoint in native order
TSTG_SIZE       EQU     *-TSTG  ;size of string
;
;======================================================================
; HARDWARE PLATFORM INDEPENDENT EQUATES AND CODE
;
; Communications function codes.
FN_GET_STATUS   EQU     $FF     ;reply with device info
FN_READ_MEM     EQU     $FE     ;reply with data
FN_WRITE_MEM    EQU     $FD     ;reply with status (+/-)
FN_READ_REGS    EQU     $FC     ;reply with registers
FN_WRITE_REGS   EQU     $FB     ;reply with status
FN_RUN_TARGET   EQU     $FA     ;reply (delayed) with registers
FN_SET_BYTES    EQU     $F9     ;reply with data (truncate if error)
FN_IN           EQU     $F8     ;input from port
FN_OUT          EQU     $F7     ;output to port
FN_RESET_TARGET EQU     $F6     ;reset target hardware
;FN_STEP        EQU     $F5     ;step one instruction (needs hardware support)
FN_STOP_TARGET  EQU     $F4     ;stop program execution
;
FN_MIN          EQU     $F0     ;MINIMUM RECOGNIZED FUNCTION CODE
FN_ERROR        EQU     $F0     ;error reply to unknown op-code
;
; 6502 OP-CODE EQUATES
B               EQU     $10     ;BREAK BIT IN CONDITION CODES
LDA_OP          EQU     $AD     ;LDA AAA
STA_OP          EQU     $8D     ;STA AAA
CMP_OP          EQU     $CD     ;CMP AAA
LDAY_OP         EQU     $B9     ;LDA AAA,Y
STAY_OP         EQU     $99     ;STA AAA,Y
CMPY_OP         EQU     $D9     ;CMP AAA,Y
CMPX_OP         EQU     $DD     ;CMP AAA,X
RTS_OP          EQU     $60     ;RTS

;===========================================================================
; Reset for new message, return from interrupt
START_OVER:
        STZ     BUF_INDEX       ;index
        STZ     COMBUF+1        ;default data length for easy tests
        STZ     CHECKSUM        ;computed as each byte is received
;
; Set TxD port pin high, disable transmit, enable receive
        LDA     #_PD6_TXD       ;Set TxD high (idle)
        TSB     PD6
        LDA     #$A4            ;Clear RxError, enable Rx, disable Tx
        STA     UART_CTL
;
        PLY
        PLX
        PLA
        RTI

;===========================================================================
; ACI Receive interrupt
IRQ_AR: PHA
        PHX
        PHY
        LDA     UART_DATA       ;incoming byte
        LDX     BUF_INDEX
        BNE     RX_10
        CMP     #FN_MIN
        BCC     START_OVER      ;invalid initial byte. start over
        ;TODO: could branch for ASCII commands such as:
        ;  CR to show version;
        ;  S  to receive S-records, use S9 to jump to loaded program
        ; etc.

RX_10:  CPX     #1
        BNE     RX_20
        CMP     #COMBUF_SIZE+1
        BCS     START_OVER      ;too long for our buffer. start over

RX_20:  STA     COMBUF,X        ;save byte
        CLC
        ADC     CHECKSUM
        STA     CHECKSUM        ;accumulate into checksum
        INX
        STX     BUF_INDEX
;
; Total length is data-count plus 3 (including checksum)
        DEX
        DEX
        DEX
        CPX     COMBUF+1
        BEQ     RX_90
;
; Continue
RX_EXIT: PLY
        PLX
        PLA
        RTI
;
; Validate and process the message.
RX_90:  LDA     CHECKSUM
        BNE     START_OVER      ;checksum error
;
; We leave interrupts disabled while we act. That may give better
; atomic results on memory ranges including I/O, but also delays other interrupts.
        LDA     COMBUF+0        ;GET THE FUNCTION CODE
        CMP     #FN_GET_STATUS
        BEQ     TARGET_STATUS
        CMP     #FN_READ_MEM
        BEQ     JREAD_MEM
        CMP     #FN_WRITE_MEM
        BEQ     JWRITE_MEM
        CMP     #FN_SET_BYTES
        BEQ     JSET_BYTES
        CMP     #FN_IN
        BEQ     JIN_PORT
        CMP     #FN_OUT
        BEQ     JOUT_PORT
        CMP     #FN_RESET_TARGET
        BEQ     JRESET_TARGET
        CMP     #FN_STOP_TARGET
        BEQ     JSTOP_TARGET
;
; Remaining commands can't be done if the target is running
        LDX     MON_FLAGS
        BEQ     SEND_ERROR

        CMP     #FN_READ_REGS
        BEQ     JREAD_REGS
        CMP     #FN_WRITE_REGS
        BEQ     JWRITE_REGS
        CMP     #FN_RUN_TARGET
        BEQ     JRUN_TARGET
;
; Error: function unknown, or not allowed on running target.  Complain
SEND_ERROR:
        LDA     #FN_ERROR
        STA     COMBUF          ;SET FUNCTION AS "ERROR"
        LDA     #1
        JMP     SEND_STATUS_AND_RTI ;VALUE IS "ERROR"
;
; long jumps to handlers
JREAD_MEM:      JMP     READ_MEM
JWRITE_MEM:     JMP     WRITE_MEM
JREAD_REGS:     JMP     READ_REGS
JWRITE_REGS:    JMP     WRITE_REGS
JRUN_TARGET:    JMP     RUN_TARGET
JSET_BYTES:     JMP     SET_BYTES
JIN_PORT:       JMP     IN_PORT
JOUT_PORT:      JMP     OUT_PORT
JRESET_TARGET:  JMP     RESET_TARGET
JSTOP_TARGET:   JMP     STOP_TARGET

;===========================================================================
;
; Return target status string
;
TARGET_STATUS:
        LDX     #0              ;DATA FOR REPLY
        LDY     #TSTG_SIZE      ;LENGTH OF REPLY
        STY     COMBUF+1        ;SET SIZE IN REPLY BUFFER
TS10:   LDA     TSTG,X          ;MOVE REPLY DATA TO BUFFER
        STA     COMBUF+2,X
        INX
        DEY
        BNE     TS10
;
; Return the data, then exit interrupt
        JMP     SEND_AND_RTI

;===========================================================================
;
; Read Memory: FN, len, page, Alo, Ahi, Nbytes
;
; Uses 2 bytes of stack
;
READ_MEM:
;
; Prepare return buffer: FN (unchanged), LEN, DATA
        LDX     COMBUF+5        ;number of bytes to get
        STX     COMBUF+1        ;return length = requested data
        BEQ     RM_90           ;jif no bytes to get
;
        LDY     COMBUF+3        ;Address
        LDA     COMBUF+4
        BNE     RM_50           ;not page 0: use normal memory access
        CPY     #$40
        BCS     RM_50           ;region doesn't include a port: use normal access
;
; I/O register range, possibly including IER1, IER2, BCR which we change when
; we enter the monitor via breakpoint, NMI, or STOP
; Y has low address
        STX     CODEBUF         ;byte count
        LDX     #0              ;initial offset
RM_10:  LDA     SAVE_IER1
        CPY     #IER1
        BEQ     RM_20
        LDA     SAVE_IER2
        CPY     #IER2
        BEQ     RM_20
        LDA     SAVE_BCR
        CPY     #BCR
        BEQ     RM_20
        LDA     0,Y             ;fetch normal register
RM_20:  STA     COMBUF+2,X
        INX
        INY
        DEC     CODEBUF
        BNE     RM_10
        BRA     RM_90
;
; Normal memory or I/O
; Store address into LDA instruction in RAM
RM_50:  STY     CODEBUF+1
        STA     CODEBUF+2
;
; Build "LDA  AAAA,Y" in RAM
        LDA     #LDAY_OP
        STA     CODEBUF+0
;
; Set return after LDA
        LDA     #RTS_OP
        STA     CODEBUF+3
;
; Set page (if used)
;;      LDA     COMBUF+2
;
; Read the requested bytes from local memory
; TODO: This loop takes 27 cycles per byte
; Moving the entire loop into RAM would save a JSR and RTS on each byte,
; reducing the loop time to 15 cycles.
; Interrupts are disabled here, so you might consider this worthwhile.
; The WRITE_MEM code is similar, but more complex
        LDY     #0              ;initial offset
RM_60:  JSR     CODEBUF         ;get byte aaaa,y to a
        STA     COMBUF+2,Y      ;store to return buffer
        INY
        DEX
        BNE     RM_60
;
; Return the data, then exit interrupt
RM_90:  JMP     SEND_AND_RTI

;===========================================================================
;
; Write Memory:  FN, len, page, Alo, Ahi, (len-3 bytes of Data)
;
; Uses 2 bytes of stack
;
WRITE_MEM:
;
; Prepare return buffer: FN (unchanged), LEN, DATA
        LDX     COMBUF+1        ;received message size,
        DEX                     ;less page, addrlo, addrhi
        DEX
        DEX
        BEQ     WM_90           ;jif no bytes to write
;
        LDY     COMBUF+3        ;Address
        LDA     COMBUF+4
        BNE     WM_50           ;not page 0: normal memory write
        CPY     #$40
        BCS     WM_50           ;region doesn't include a port: normal write
;
; I/O register range including IER1, IER2, BCR
; Y has low address
        STX     CODEBUF         ;byte count
        LDX     #0              ;initial offset
WM_10:  LDA     COMBUF+5,X      ;get byte to write
        CPY     #IER1
        BNE     WM_11
        STA     SAVE_IER1       ;set saved IER1
        BRA     WM_40
;
WM_11:  CPY     #IER2
        BNE     WM_12
        STA     SAVE_IER2       ;set saved IER2
        BRA     WM_40
;
WM_12:  CPY     #BCR
        BNE     WM_13
        STA     SAVE_BCR        ;set saved BCR
        BRA     WM_40
;
WM_13:  STA     0,Y             ;write normal register
WM_40:  INX
        INY
        DEC     CODEBUF
        BNE     WM_10
        BRA     WM_90           ;don't try to read back I/O
;
; Normal memory or I/O
; Store address into instruction in RAM
WM_50   STY     CODEBUF+1
        STA     CODEBUF+2
;
; Build "STA  AAAA,Y" in RAM
        LDA     #STAY_OP
        STA     CODEBUF+0
;
; Set return after STA
        LDA     #RTS_OP
        STA     CODEBUF+3
;
; Set page
;;      LDA     COMBUF+2
;
; Write the specified bytes to local memory
        LDY     #0              ;initial offset
WM_60:  LDA     COMBUF+5,Y      ;get byte to write
        JSR     CODEBUF         ;store the byte at aaaa,y
        INY
        DEX
        BNE     WM_60
;
; X is now 0; Y has byte count, so we flip our register usage
; Build "CMP  AAAA,X" in RAM
        LDA     #CMPX_OP
        STA     CODEBUF+0
;
; Compare to see if the write worked
WM_70:  LDA     COMBUF+5,X      ;get byte just written
        JSR     CODEBUF         ;compare the byte at aaaa,x
        BNE     WM_80           ;br if write failed
        INX
        DEY
        BNE     WM_70
;
; All writes succeeded:  return status = 0
WM_90:  LDA     #0              ;return status = 0
        BRA     WM_99
;
; Write failed:  return status = 1
WM_80:  LDA     #1
;
; Return status, then exit interrupt
WM_99:  JMP     SEND_STATUS_AND_RTI

;===========================================================================
;
; Read registers:  FN, len=0
;
; Not allowed on running target
;
; Uses 2 bytes of stack
;
READ_REGS:
        JSR     COPY_REGS
;
; Return the data, then exit interrupt
        JMP     SEND_AND_RTI

;===========================================================================
;
; Write registers:  FN, len, (register image)
;
; Not allowed on running target
;
WRITE_REGS:
        LDX     #0                      ;POINTER TO DATA
        LDY     COMBUF+1                ;NUMBER OF BYTES
        BEQ     WRR80                   ;JIF NO REGISTERS
;
; Copy the registers
WRRLP:  LDA     COMBUF+2,X              ;GET BYTE TO A
        STA     TASK_REGS,X             ;STORE TO REGISTER RAM
        INX
        DEY
        BNE     WRRLP
;
; The stack has 6 bytes of return to monitor idle loop.
; We just keep going. The idle loop will reload the stack pointer.
;
; Return status, then exit interrupt
WRR80:  LDA     #0
        JMP     SEND_STATUS_AND_RTI

;===========================================================================
;
; Run Target:  FN, len
;
; Not allowed on running target
;
RUN_TARGET:
;
; Stack has the return address, status, A, X, Y from the final receive interrupt.
; All don't-care, since it is just the monitor's idle loop
;
; Restore user's page
;;;     LDA     REG_PAGE        ;USER'S PAGE
;
; Reset stack, flushing Rx Int registers
        LDX     REG_SP          ;USER STACK
        TXS
        LDA     REG_PC+1        ;SAVE MS USER PC FOR RTI
        PHA
        LDA     REG_PC          ;SAVE LS USER PC FOR RTI
        PHA
        LDA     REG_CC          ;SAVE USER CONDITION CODES FOR RTI
        PHA
;
; Since we haven't sent a reply, prepare for next receive message
        STZ     BUF_INDEX       ;index
        STZ     COMBUF+1        ;default data length for easy tests
        STZ     CHECKSUM        ;computed as each byte is received
;
; Turn off monitor status and error LEDs
        LDA     #_PD3_IDLE_LED+_PD3_ERR_LED
        TSB     PD3
;
; Restore target interrupt enables
        LDA     SAVE_IER1
        STA     IER1
        LDA     SAVE_IER2
        STA     IER2
        LDA     SAVE_BCR
        STA     BCR
;
; Restore registers and return to user
        LDX     REG_X
        LDY     REG_Y
        LDA     REG_A
        STZ     MON_FLAGS
        RTI

;===========================================================================
;
; Set target byte(s):  FN, len { (page, alow, ahigh, data), (...)... }
;
; Return has FN, len, (data from memory locations)
;
; If error in insert (memory not writable), abort to return short data
;
; This function is used primarily to set and clear breakpoints.
; We assume you won't set a breakpoint on an I/O register, so no special processing.
;
; Uses 2 bytes of stack
;
SET_BYTES:
        LDY     COMBUF+1        ;LENGTH = 4*NBYTES
        BEQ     SB90            ;JIF NO BYTES
;
; Loop on inserting bytes
        LDX     #0              ;INDEX INTO INPUT BUFFER
        LDY     #0              ;INDEX INTO OUTPUT BUFFER
SB10:
;
; Build "LDA  AAAA" in RAM
        LDA     #LDA_OP
        STA     CODEBUF+0
;
; Set page
;;      LDA     COMBUF+2,X
;
; Set address
        LDA     COMBUF+3,X
        STA     CODEBUF+1
        LDA     COMBUF+4,X
        STA     CODEBUF+2
;
; Set return after LDA
        LDA     #RTS_OP
        STA     CODEBUF+3
;
; Read current data at byte location
        JSR     CODEBUF         ;GET BYTE AT AAAA
        STA     COMBUF+2,Y      ;SAVE IN RETURN BUFFER
;
; Insert new data at byte location
;
; Build "STA  AAAA" in RAM
        LDA     #STA_OP
        STA     CODEBUF+0
        LDA     COMBUF+5,X      ;BYTE TO WRITE
        JSR     CODEBUF
;
; Verify write
        LDA     #CMP_OP
        STA     CODEBUF+0
        LDA     COMBUF+5,X
        JSR     CODEBUF
        BNE     SB90            ;BR IF INSERT FAILED: ABORT AT Y BYTES
;
; Loop for next byte
        INY                     ;COUNT ONE INSERTED BYTE
        INX                     ;STEP TO NEXT BYTE SPECIFIER
        INX
        INX
        INX
        CPX     COMBUF+1
        BNE     SB10            ;LOOP FOR ALL BYTES
;
; Return buffer with data from byte locations
SB90:   STY     COMBUF+1        ;SET COUNT OF RETURN BYTES
;
; Return the data, then exit interrupt
        JMP     SEND_AND_RTI

;===========================================================================
;
; Input from port:  FN, len, PortAddressLow, PortAddressHigh
;
; While the 6502 has no input or output instructions, we retain these
; to allow write-without-verify
;
; Uses 2 bytes of stack
;
IN_PORT:
        LDY     COMBUF+2        ;Address
        LDA     COMBUF+3
        BNE     IP_50           ;not page 0: use normal memory access
        CPY     #$40
        BCS     IP_50           ;region doesn't include a port: use normal access
;
; I/O register range, possibly including IER1, IER2, BCR which we change when
; we enter the monitor via breakpoint, NMI, or STOP
; Y has the address
        LDA     SAVE_IER1
        CPY     #IER1
        BEQ     IP_20
        LDA     SAVE_IER2
        CPY     #IER2
        BEQ     IP_20
        LDA     SAVE_BCR
        CPY     #BCR
        BEQ     IP_20
        LDA     0,Y             ;fetch normal register
;
; Return byte read as "status", then exit interrupt
IP_20:  JMP     SEND_STATUS_AND_RTI

; Normal memory or I/O
; Store address into LDA instruction in RAM
IP_50:  STY     CODEBUF+1
        STA     CODEBUF+2
;
; Build "LDA  AAAA" in RAM
        LDA     #LDA_OP
        STA     CODEBUF+0
;
; Set return after LDA
        LDA     #RTS_OP
        STA     CODEBUF+3
;
; Read the requested byte from local memory
        JSR     CODEBUF         ;get byte to A
;
; Return byte read as "status", then exit interrupt
        JMP     SEND_STATUS_AND_RTI

;===========================================================================
;
; Output to port:  FN, len, PortAddressLo, PAhi (=0), data
;
; While the 6502 has no input or output instructions, we retain this
; to allow write-without-verify of I/O devices.
;
; Uses 2 bytes of stack
;
OUT_PORT:
        LDY     COMBUF+2        ;Address
        LDA     COMBUF+3
        BNE     OP_50           ;not page 0: normal memory write
        CPY     #$40
        BCS     OP_50           ;region doesn't include a port: normal write
;
; I/O register range including IER1, IER2, BCR
; Y has low address
        LDA     COMBUF+4        ;get byte to write
        CPY     #IER1
        BNE     OP_11
        STA     SAVE_IER1       ;set saved IER1
        BRA     OP_90
;
OP_11:  CPY     #IER2
        BNE     OP_12
        STA     SAVE_IER2       ;set saved IER2
        BRA     OP_90
;
OP_12:  CPY     #BCR
        BNE     OP_13
        STA     SAVE_BCR        ;set saved BCR
        BRA     OP_90
;
OP_13:  STA     0,Y             ;write normal register
        BRA     OP_90
;
; Normal memory or I/O
; Store address into instruction in RAM
OP_50:  STY     CODEBUF+1
        STA     CODEBUF+2
;
; Build "STA  AAAA" in RAM
        LDA     #STA_OP
        STA     CODEBUF+0
;
; Set return after STA
        LDA     #RTS_OP
        STA     CODEBUF+3
;
; Write value to port
        LDA     COMBUF+4
        JSR     CODEBUF         ;store byte from A
;
; Do not read port to verify (some I/O devices don't like it)
; Return status of OK, then exit interrupt
OP_90:  LDA     #0
        JMP     SEND_STATUS_AND_RTI

;===========================================================================
;
; Reset target (which may be running user program or in the monitor)
;
RESET_TARGET:
;
; We start (or restart) the watchdog timer, assumING that it won't fire until
; we have sent our status reply.
;
; I see nothing in the datasheet or online that says what Timer M counts.
; Experiments on the W65C134SX indicate that it runs off the 32.768 kHz crystal.
; The datasheet says TMLL and TMLH are not initialized.
; A 10 msec timeout should be plenty of time for our 4-byte status message to
; go out, but not long enough for much else to happen.
; So we set the counter to 328
        LDA     #<328           ;prep watchdog timer for 10 msec
        LDX     #>328
        STA     TMLL
        STX     TMLH
        STA     TMCL
        STX     TMCH            ;this should set the counter
        LDA     #$01
        TRB     TCR1            ;watchdog strobe low
        NOP
        TSB     TCR1            ;watchdog strobe high, (re-)starting the timer
        LDA     #0
        JMP     SEND_STATUS_AND_RTI

;===========================================================================
;
; Stop user program and enter monitor (like a forced BRK)
;
STOP_TARGET:
        LDA     MON_FLAGS
        BNE     ST_90           ;Not running. Do nothing, await next message

; We are called from a UART receive interrupt, and the monitor is not active.
; So the stack has Y,X,A,PSP,PC.
        PLY                     ;Ready for INT_ENTRY, save stack for SEND_WAIT
        PLX

; Reporting as Breakpoint (state=1) would back up the reported PC.
; We COULD add a unique state for "stop", but for now we use NMI's code,
; since it is generally used for "stop".
        LDA     #3              ;Report as NMI
        STA     SKIP_REG_REPORT ;Don't dump registers as we enter the monitor
        JMP     INT_ENTRY

ST_90:  JMP     START_OVER

;===========================================================================
;
; Initiate status reply with value from "A", then return from RX interrupt
;
SEND_STATUS_AND_RTI:
        STA     COMBUF+2        ;SET STATUS
        LDA     #1
        STA     COMBUF+1        ;SET LENGTH
;
; Initiate reply, then return from RX interrupt
;
SEND_AND_RTI:
        JSR     SEND
        PLY
        PLX
        PLA
        RTI

;===========================================================================
;
; Initiate send of COMBUF,
; then loop (interrupts enabled) until send is complete.
; Return with original interrupt enable state
;
SEND_WAIT:
        STZ     BUF_INDEX       ;index
        STZ     CHECKSUM        ;computed as each byte is sent
;
; Disable Rx, enable Tx with interrupt on Tx data register empty
        LDA     #$85
        STA     UART_CTL
;
; We expect a Tx interrupt almost immediately. Let her stuff the first byte,
; then loop until sending is complete and Tx interrupt disables transmitter
        PHP
        CLI
SA_1:   LDA     UART_CTL
        BIT     #_UART_TXE
        BNE     SA_1 
        PLP
        RTS

;===========================================================================
;
; Initiate send of COMBUF and checksum, but do not wait.
;
SEND:   STZ     BUF_INDEX       ;index
        STZ     CHECKSUM        ;computed as each byte is sent
;
; Disable Rx, enable Tx with interrupt on Tx data register empty
        LDA     #$85
        STA     UART_CTL
;
; We expect a Tx interrupt almost immediately. Let her stuff the first byte
        RTS

;===========================================================================
;
; Transmit interrupt
IRQ_AT: PHA
        PHX
        PHY
        LDA     UART_CTL
        BIT     #_UART_TXSRE
        BNE     TX_DONE         ;shift register empty: send complete
        LDX     BUF_INDEX
        LDA     COMBUF
        BMI     TX_10
;
; Sending null-terminated ASCII message
        LDA     COMBUF,X
        STA     UART_DATA
        INX
        STX     BUF_INDEX
        LDA     COMBUF,X
        BEQ     TX_90           ;next byte is null: almost done
        BRA     TX_EXIT
;
; Sending NoICE binary message
TX_10:  LDA     COMBUF+1
        INC     A
        INC     A
        CMP     BUF_INDEX
        BEQ     TX_80           ;last byte: go send the checksum
        LDA     COMBUF,X
        STA     UART_DATA       ;send the byte
        INX
        STX     BUF_INDEX

        CLC
        ADC     CHECKSUM
        STA     CHECKSUM        ;accumulate into checksum
        BRA     TX_EXIT
;
; Send the checksum
TX_80:  LDA     #0
        SEC
        SBC     CHECKSUM
        STA     UART_DATA       ;send the byte
;
; Change Tx interrupt to shift-register empty
TX_90:  LDA     #_UART_TXSRE
        TSB     UART_CTL
;
; Continue
TX_EXIT:
        PLY
        PLX
        PLA
        RTI
;
; Send complete: set for next command and return from interrupt
TX_DONE:
        JMP     START_OVER

;=================================================================================
; Default interrupt handlers: enter the monitor with a unique identifying state
DEF_PE44    PHA                 ;Save pre-interrupt A
            LDA     #44         ;State code
            BRA     DEFAULT
DEF_PE45    PHA
            LDA     #45
            BRA     DEFAULT
DEF_NE46    PHA
            LDA     #46
            BRA     DEFAULT
DEF_NE47    PHA
            LDA     #47
            BRA     DEFAULT
DEF_PE50    PHA
            LDA     #50
            BRA     DEFAULT
DEF_PE51    PHA
            LDA     #51
            BRA     DEFAULT
DEF_NE52    PHA
            LDA     #52
            BRA     DEFAULT
DEF_NE53    PHA
            LDA     #53
            BRA     DEFAULT
DEF_IRQ_E0  PHA
            LDA     #11
            BRA     DEFAULT
DEF_IRQ_E2  PHA
            LDA     #10
            BRA     DEFAULT
DEF_IRQAT   PHA
            LDA     #9
            BRA     DEFAULT
DEF_IRQAR   PHA
            LDA     #8
            BRA     DEFAULT
DEF_IRQSIB  PHA
            LDA     #7
            BRA     DEFAULT
DEF_PE54    PHA
            LDA     #54
            BRA     DEFAULT
DEF_PE55    PHA
            LDA     #55
            BRA     DEFAULT
DEF_PE56    PHA
            LDA     #56
            BRA     DEFAULT
DEF_NE57    PHA
            LDA     #57
            BRA     DEFAULT
DEF_IRQT1   PHA
            LDA     #6
            BRA     DEFAULT
DEF_IRQT2   PHA
            LDA     #5
            BRA     DEFAULT
DEF_IRQ1    PHA
            LDA     #2
            BRA     DEFAULT
DEF_IRQ2    PHA
            LDA     #4
            BRA     DEFAULT
DEF_RESET   PHA
            LDA     #0
DEFAULT:    JMP    INT_ENTRY    ;enter monitor

; NMI for use as a stop-running-program button
; Edge sensitive and not maskable, so we use a flag to block bounces
IRQ_NMI:    PHA
            LDA     #_MF_BLOCK_NMI
            TSB     MON_FLAGS
            BNE     NMI_10      ;ignore NMI bounce
            LDA     MON_FLAGS
            BIT     #_MF_IN_MONITOR
            BEQ     NMI_90      ;not in monitor: process NMI stop
NMI_10:     PLA
            RTI
;
NMI_90:     LDA     #3
            BRA     DEFAULT     ;else process new NMI
;
; Standard handling for breakpoint
IRQ_BRK:    PHA
            LDA     #1
            BRA     DEFAULT

;==================================================================================
; INTERRUPT VECTORS

  IF RUN_FROM_RAM
; Running with monitor and interrupt vectors in RAM.
; These are loaded along with the monitor with a mix or "real" and default handlers
        DATA
        ORG     USER_VECT

        WORD    DEF_PE44
        WORD    DEF_PE45
        WORD    DEF_NE46
        WORD    DEF_NE47
        WORD    DEF_PE50
        WORD    DEF_PE51
        WORD    DEF_NE52
        WORD    DEF_NE53

        WORD    DEF_IRQ_E0
        WORD    DEF_IRQ_E2
        WORD      IRQ_AT        ;FFE4 Serial Transmit
        WORD      IRQ_AR        ;FFE6 Serial Receive
        WORD    DEF_IRQSIB
        WORD    DEF_PE54
        WORD    DEF_PE55
        WORD    DEF_PE56

        WORD    DEF_NE57
        WORD    DEF_IRQT1
        WORD    DEF_IRQT2
        WORD    DEF_IRQ1
        WORD    DEF_IRQ2
        WORD      IRQ_NMI       ;FFFA NMI
        WORD      RESET         ;FFFC RESET  state 0
        WORD      IRQ_BRK       ;FFFE BRK    state 1
;
        ENDS

  ELSE
; Running with monitor and interrupt vectors in Flash.
;
; RESET, BRK, and ACI Tx and Rx always enter the monitor.
; All other interrupts re-vector through USER_VECT.
; When the monitor resets, it initializes USER_VECT with default handlers
; than enter the monitor with an appropriate monitor state
IRQ_PE44    JMP     (USER_VECT+$0)
IRQ_PE45    JMP     (USER_VECT+$2)
IRQ_NE46    JMP     (USER_VECT+$4)
IRQ_NE47    JMP     (USER_VECT+$6)
IRQ_PE50    JMP     (USER_VECT+$8)
IRQ_PE51    JMP     (USER_VECT+$A)
IRQ_NE52    JMP     (USER_VECT+$C)
IRQ_NE53    JMP     (USER_VECT+$E)

IRQ_E0      JMP     (USER_VECT+$10)
IRQ_E2      JMP     (USER_VECT+$12)
;;; IRQ_AT  JMP     (USER_VECT+$14)
;;; IRQ_AR  JMP     (USER_VECT+$16)
IRQ_SIB     JMP     (USER_VECT+$18)
IRQ_PE54    JMP     (USER_VECT+$1A)
IRQ_PE55    JMP     (USER_VECT+$1C)
IRQ_PE56    JMP     (USER_VECT+$1E)

IRQ_NE57    JMP     (USER_VECT+$20)
IRQ_T1      JMP     (USER_VECT+$22)
IRQ_T2      JMP     (USER_VECT+$24)
IRQ_IRQ1    JMP     (USER_VECT+$26)
IRQ_IRQ2    JMP     (USER_VECT+$28)
;;; IRQ_NMI JMP     (USER_VECT+$2A)
;;; RESET   JMP     (USER_VECT+$2c)
;;; IRQ_BRK JMP     (USER_VECT+$2E)


; Table used at startup to initialize RAM interrupt vectors
VEC_INIT:
        WORD    DEF_PE44
        WORD    DEF_PE45
        WORD    DEF_NE46
        WORD    DEF_NE47
        WORD    DEF_PE50
        WORD    DEF_PE51
        WORD    DEF_NE52
        WORD    DEF_NE53

        WORD    DEF_IRQ_E0
        WORD    DEF_IRQ_E2
        WORD    IRQ_AT
        WORD    IRQ_AR
        WORD    DEF_IRQSIB
        WORD    DEF_PE54
        WORD    DEF_PE55
        WORD    DEF_PE56

        WORD    DEF_NE57
        WORD    DEF_IRQT1
        WORD    DEF_IRQT2
        WORD    DEF_IRQ1
        WORD    DEF_IRQ2
        WORD    IRQ_NMI
        WORD    RESET
        WORD    IRQ_BRK
VEC_END:
VEC_SIZE EQU VEC_END-VEC_INIT
        ENDS

; HARDWARE INTERRUPT VECTORS
        DATA
        ORG     HARD_VECT

        WORD    IRQ_PE44        ;FFD0
        WORD    IRQ_PE45        ;FFD2
        WORD    IRQ_NE46        ;FFD4
        WORD    IRQ_NE47        ;FFD6
        WORD    IRQ_PE50        ;FFD8
        WORD    IRQ_PE51        ;FFDA
        WORD    IRQ_NE52        ;FFDC
        WORD    IRQ_NE53        ;FFDE

        WORD    IRQ_E0          ;FFE0
        WORD    IRQ_E2          ;FFE2
        WORD    IRQ_AT          ;FFE4 Serial Transmit
        WORD    IRQ_AR          ;FFE6 Serial Receive
        WORD    IRQ_SIB         ;FFE8
        WORD    IRQ_PE54        ;FFEA
        WORD    IRQ_PE55        ;FFEC
        WORD    IRQ_PE56        ;FFEE

        WORD    IRQ_NE57        ;FFF0
        WORD    IRQ_T1          ;FFF2
        WORD    IRQ_T2          ;FFF4
        WORD    IRQ_IRQ1        ;FFF6        state 3
        WORD    IRQ_IRQ2        ;FFF8
        WORD    IRQ_NMI         ;FFFA NMI    state 2
        WORD    RESET           ;FFFC RESET  state 0
        WORD    IRQ_BRK         ;FFFE BRK    state 1
;
        ENDS
  ENDC

        END     RESET
