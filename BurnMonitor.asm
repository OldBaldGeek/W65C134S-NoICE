        TTL 'Burn the NoICE monitor into the SST39SF010A on W65C134SXB board
        CHIP    65C02
        PW      132
        PL      0       ;Ain't gonna print it - skip the headers

;=================================================================================
; Port 3 (PCS, PD)
;  7  P37_CS7B_Flash  set for 8000-EFFF, -FFFF if internal ROM disabled
;  6  P36_CS6B_SRAM   set for 0100-7FFF if external RAM
;  5  P35_AMS         0 for A16 bank switch
;  4  P34_FA15        0 for A15 bank switch
;  3  P33_XCS3B       0 to use LED indicator
;  2  P32_XCS2B       0 to use LED indicator
;  1  P31_XCS1B       0 to use LED indicator
;  0  P30_XCS0B       0 to use LED indicator
PD3     EQU     $0003
PCS3    EQU     $0007
PD4     EQU     $001C   ;Port 4 data
PDD4    EQU     $001E   ;Port 4 data direction
BCR     EQU     $001B

; Page zero, after the ludicrous amount eaten by the ROM monitor
; (PZ through 8F, then 9X for input buffer; Ax for output buffer)
        PAGE0
        ORG     $00B0
FLASH_ADDR  DS  2           ;Destination in Flash
RAM_ADDR    DS  2           ;Source address of data in RAM
RAM_END     DS  2           ;End+1 address of data in RAM
TMR_LOW     DS  1           ;For spin-loop timeouts
LED_TIMER   DS  2           ;Timer for LED status indication
LED_MASK    DS  1           ;Mask of bits to toggle
        ENDS                ;Ends page 0 declarations

; Vector interrupts through addresses in RAM here
USER_VECT   EQU $7FD0       ;Start of user interrupt (re)vectors

FLASH_BASE  EQU $8000       ;"ZERO" as seen by Flash

MON_DATA    EQU $2000       ;source of monitor data
MON_DATA_END EQU $3000      ;end+1 of monitor data
MON_SECT    EQU $F000       ;Sector to erase for monitor
MON_DEST    EQU $F000       ;Where to burn the monitor

VECT_SECT   EQU $F000       ;Sector to erase for vectors
VECT_DEST   EQU $FF88       ;Where to burn the vectors

STUB_SECT   EQU $8000       ;Sector to erase for vectors
STUB_DEST   EQU $8000       ;Where to burn the WDC stub

; STACK RAM (PAGE 1)
INITSTACK       EQU     $01FF   ;TOP OF STACK RAM

;=================================================================================
        CODE
        ORG     $1000
;
; g 1000 to burn the contents of RAM $2000-$2FFF to Flash at $F000-$FFFF
;        and a "WDC" stub at $8000 to jump to $F000
; g 1003 to burn a set of indirect jumps from the hardware vectors through RAM
; g 1006 to erase the sector at $8000, typically to wipe out a "WDC"
;
; These all assume entry from the WDC ROM monitor
;
BURN_MONITOR:    JMP DO_BURN_MONITOR
BURN_VECTORS:    JMP DO_BURN_VECTORS
WIPE_STUB:       JMP DO_WIPE_STUB

;=================================================================================
; Burn the contents of RAM $4000-$4FFF to Flash at $F000-$FFFF
; and a "WDC" stub at $8000 to jump to $F000
DO_BURN_MONITOR:
;
; Hide the ROM, exposing the NoICE monitor in Flash
;  7  1 External Flash $F000-$FFFF (replace ROM monitor and interrupt vectors)
;  6  0 Port 4 0-2 are port pins (vs NMI,IRQ1,IRQ2)
;  5  0 Port 5 4-7 are port pins (vs edge interrupt)
;  4  0 Port 5 0-3 are port pins (vs edge interrupt)
;  3  0 Normal mode (vs test)
;  2  0 SIB disabled
;  1  0 Port 4 4-7 are port pins (vs edge interrupt)
;  0  1 Enable memory bus (vs Port 0,1,2)
        LDA     #%10000001
        STA     BCR
;
; Port 3
;  7  1 P37_CS7B_Flash  8000-FFFF Flash (internal ROM disabled in BCR)
;  6  1 P36_CS6B_SRAM   0100-7FFF external RAM
;  5  0 P35_AMS         A16 bank switch (1=top bank for monitor)
;  4  0 P34_FA15        A15 bank switch (1=top bank for monitor)
;  3  0 P33_XCS3B       LED indicator (1=off)
;  2  0 P32_XCS2B       LED indicator (1=off)
;  1  0 P31_XCS1B       LED indicator (1=off)
;  0  0 P30_XCS0B       LED indicator (1=off)
        LDA     #%11111111      ;Flash bank3, LEDs OFF
        STA     PD3
        LDA     #%11000000
        STA     PCS3
;
; Erase the monitor sector
        LDA     #>MON_SECT
        STA     FLASH_ADDR+1
        LDA     #<MON_SECT
        STA     FLASH_ADDR
        JSR     ERASE_SECTOR
        BCS     BM_9            ;Erase failed
;
; Burn the monitor
        LDA     #>MON_DATA
        STA     RAM_ADDR+1
        LDA     #<MON_DATA
        STA     RAM_ADDR

        LDA     #>MON_DATA_END
        STA     RAM_END+1
        LDA     #<MON_DATA_END
        STA     RAM_END

        LDA     #>MON_DEST
        STA     FLASH_ADDR+1
        LDA     #<MON_DEST
        STA     FLASH_ADDR
        JSR     BURN_RANGE
        BCS     BM_9            ;Burn failed
;
; Erase the stub sector
        LDA     #>STUB_SECT
        STA     FLASH_ADDR+1
        LDA     #<STUB_SECT
        STA     FLASH_ADDR
        JSR     ERASE_SECTOR
        BCS     BM_9            ;Erase failed
;
; Burn the stub
        LDA     #>STUB_DATA
        STA     RAM_ADDR+1
        LDA     #<STUB_DATA
        STA     RAM_ADDR

        LDA     #>STUB_DATA_END
        STA     RAM_END+1
        LDA     #<STUB_DATA_END
        STA     RAM_END

        LDA     #>STUB_DEST
        STA     FLASH_ADDR+1
        LDA     #<STUB_DEST
        STA     FLASH_ADDR
        JSR     BURN_RANGE
;
BM_9:   JMP     SHOW_RESULTS

;=================================================================================
; Burn a set of indirect jumps from the hardware vectors through RAM
DO_BURN_VECTORS:
;
; Hide the ROM, exposing the NoICE monitor in Flash
;  7  1 External Flash $F000-$FFFF (replace ROM monitor and interrupt vectors)
;  6  0 Port 4 0-2 are port pins (vs NMI,IRQ1,IRQ2)
;  5  0 Port 5 4-7 are port pins (vs edge interrupt)
;  4  0 Port 5 0-3 are port pins (vs edge interrupt)
;  3  0 Normal mode (vs test)
;  2  0 SIB disabled
;  1  0 Port 4 4-7 are port pins (vs edge interrupt)
;  0  1 Enable memory bus (vs Port 0,1,2)
        LDA     #%10000001
        STA     BCR
;
; Port 3
;  7  1 P37_CS7B_Flash  8000-FFFF Flash (internal ROM disabled in BCR)
;  6  1 P36_CS6B_SRAM   0100-7FFF external RAM
;  5  0 P35_AMS         A16 bank switch (1=top bank for monitor)
;  4  0 P34_FA15        A15 bank switch (1=top bank for monitor)
;  3  0 P33_XCS3B       LED indicator (1=off)
;  2  0 P32_XCS2B       LED indicator (1=off)
;  1  0 P31_XCS1B       LED indicator (1=off)
;  0  0 P30_XCS0B       LED indicator (1=off)
        LDA     #%11111111      ;Flash bank3, LEDs OFF
        STA     PD3
        LDA     #%11000000
        STA     PCS3
;
        LDA     #>VECT_SECT
        STA     FLASH_ADDR+1
        LDA     #<VECT_SECT
        STA     FLASH_ADDR
        JSR     ERASE_SECTOR
        BCS     BV_9            ;Erase failed
;
        LDA     #>VECT_DATA
        STA     RAM_ADDR+1
        LDA     #<VECT_DATA
        STA     RAM_ADDR

        LDA     #>VECT_DATA_END
        STA     RAM_END+1
        LDA     #<VECT_DATA_END
        STA     RAM_END

        LDA     #>VECT_DEST
        STA     FLASH_ADDR+1
        LDA     #<VECT_DEST
        STA     FLASH_ADDR
        JSR     BURN_RANGE
;
BV_9:   JMP     SHOW_RESULTS

;=================================================================================
; Erase the sector at $8000, typically to wipe out a "WDC"
DO_WIPE_STUB:
;
; Port 3
;  7  1 P37_CS7B_Flash  8000-FFFF Flash (internal ROM disabled in BCR)
;  6  1 P36_CS6B_SRAM   0100-7FFF external RAM
;  5  0 P35_AMS         A16 bank switch (1=top bank for monitor)
;  4  0 P34_FA15        A15 bank switch (1=top bank for monitor)
;  3  0 P33_XCS3B       LED indicator (1=off)
;  2  0 P32_XCS2B       LED indicator (1=off)
;  1  0 P31_XCS1B       LED indicator (1=off)
;  0  0 P30_XCS0B       LED indicator (1=off)
        LDA     #%11111111      ;Flash bank3, LEDs OFF
        STA     PD3
        LDA     #%11000000
        STA     PCS3
;
        LDA     #>STUB_SECT
        STA     FLASH_ADDR+1
        LDA     #<STUB_SECT
        STA     FLASH_ADDR
        JSR     ERASE_SECTOR
        JMP     SHOW_RESULTS

; CY=0 success: show LED 0 flashing
; CY=1 failure: alternate LED 0 and LED 3
SHOW_RESULTS:
        LDA     #%0001
        TRB     PD3             ;LED 0 on immediately
        BCC     SR_1
        LDA     #%1001
SR_1:   STA     LED_MASK
;
; 3.6864 MHz crystal gives 271.267 nsec instruction cycle
; so 65536 8-cycle loops is 142 msec
SR_5:   DEC     LED_TIMER       ;5
        BNE     SR_5            ;3 = 8 cycles (2.17 usec) per loop
        DEX
        BNE     SR_5

        LDA     PD3
        EOR     LED_MASK
        STA     PD3
        BRA     SR_5

;=================================================================================
; Erase the 4k sector at FLASH_ADDR
; Return A=CY=0 for success, else CY=1 on failure (timeout)
ERASE_SECTOR:
        SEI                     ;No interrupts while we play with Flash
        LDA     #$AA
        STA     FLASH_BASE+$5555   ;our Flash base + SST magic number
        LDA     #$55
        STA     FLASH_BASE+$2AAA
        LDA     #$80
        STA     FLASH_BASE+$5555
        LDA     #$AA
        STA     FLASH_BASE+$5555
        LDA     #$55
        STA     FLASH_BASE+$2AAA
        LDA     #$30
        STA     (FLASH_ADDR),Y  ;start the erase

; Loop until erased: D7 will read complement of final data; D6 will toggle
; Datasheet says 25 msec max
; 3.6864 MHz crystal gives 271.267 nsec instruction cycle.
; 1 msec is 3686 cycles, so a 30 msec timeout is 110,592 cycles
; or 5530 20-cycle loops.
        LDX     #>(5530+255)
        STZ     TMR_LOW
ER_1:   LDA     (FLASH_ADDR),Y  ;5
        CMP     (FLASH_ADDR),Y  ;5
        BEQ     ER_9            ;2 Exit on consistent read
        DEC     TMR_LOW         ;5
        BNE     ER_1            ;3
                                ;= 20 cycles per loop
        DEX
        BNE     ER_1
        LDA     #$EE            ;Error return
        SEC
        BRA     ER_10

ER_9:   LDA     #0              ;Success return
        CLC

ER_10:  LDA     #$80
        TRB     BCR             ;enable internal ROM so we can use the monitor
        CLI
        RTS

;=================================================================================
; Burn the byte at (RAM_ADDR) to (FLASH_ADDR)
; Return A=CY=0 for success, else CY=1 on failure (timeout)
BURN_BYTE:
        LDA     #$AA
        STA     FLASH_BASE+$5555   ;our Flash offset + SST magic number
        LDA     #$55
        STA     FLASH_BASE+$2AAA
        LDA     #$A0
        STA     FLASH_BASE+$5555

        LDY     #0
        LDA     (RAM_ADDR),Y
        STA     (FLASH_ADDR),Y  ;start the write

; Loop on read: D7 will read complement of final data; D6 will toggle
; Datasheet says 20 usec max
; 3.6864 MHz crystal gives 271.267 nsec instruction cycle
; so a 30 Usec timeout is 111 cycles
; or 10 12-cycle loops.
        LDX     #10
BU_1:   CMP     (FLASH_ADDR),Y  ;5
        BEQ     BU_9            ;2 Exit on consistent read
        DEX                     ;2
        BNE     BU_1            ;3
                                ;= 12 cycles per loop
        LDA     #$EE            ;Error return
        SEC
        RTS

BU_9:   LDA     #0              ;Success return
        CLC
        RTS

;=================================================================================
; Burn the byteS from (RAM_ADDR) through (RAM_END-1) to (FLASH_ADDR)
; Return A=CY=0 for success, else CY=1 on failure
BURN_RANGE:
        SEI                     ;No interrupts while we play with Flash
        LDA     #$80
        TSB     BCR             ;hide internal ROM so we can burn

        JSR     BURN_BYTE
        BCS     BR_9            ;exit on failure

        INC     FLASH_ADDR
        BNE     BR_1
        INC     FLASH_ADDR+1

BR_1:   INC     RAM_ADDR
        BNE     BR_2
        INC     RAM_ADDR+1
BR_2:   LDA     RAM_ADDR
        CMP     RAM_END
        BNE     BURN_RANGE
        LDA     RAM_ADDR+1
        CMP     RAM_END+1
        BNE     BURN_RANGE
        LDA     #0              ;success return
        CLC

BR_9:   LDA     #$80
        TRB     BCR             ;enable internal ROM so we can use the monitor
        CLI
        RTS

;=================================================================================
; Burn this at $8000 to be detected and run by the WDC monitor
; This code MUST be relocatable
STUB_DATA:
        BYTE    "WDC",0
;
; Set CPU mode to safe state
        SEI                     ;INTERRUPTS OFF
        CLD                     ;USE BINARY MODE
        LDX     #<INITSTACK
        TXS

        STZ     PDD4
        NOP
        LDA     PD4
        BIT     #%00000001      ;Check Port4.0 / NMI
        BNE     START_NOICE     ;high (N.C.): run the NoICE monitor
;
; Back to ROM monitor
        LDA     #%00000001      ;Disable Flash at F000, enable ROM; ports 4 and 5
        STA     BCR
        LDA     #%11000000      ;Keep Flash and RAM chip selects
        STA     PCS3
        JMP     $F057           ;Back the ROM who ran us

; Hide the ROM, exposing the NoICE monitor in Flash
;  7  1 External Flash $F000-$FFFF (replace ROM monitor and interrupt vectors)
;  6  0 Port 4 0-2 are port pins (vs NMI,IRQ1,IRQ2)
;  5  0 Port 5 4-7 are port pins (vs edge interrupt)
;  4  0 Port 5 0-3 are port pins (vs edge interrupt)
;  3  0 Normal mode (vs test)
;  2  0 SIB disabled
;  1  0 Port 4 4-7 are port pins (vs edge interrupt)
;  0  1 Enable memory bus (vs Port 0,1,2)
START_NOICE:
        LDA     #%10000001
        STA     BCR
;
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

        JMP     $F000
STUB_DATA_END   EQU *

;=================================================================================
; Data to be burned.
VECT_DATA:
;
; Jumps through RAM (3 bytes each)
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
IRQ_AT      JMP     (USER_VECT+$14)
IRQ_AR      JMP     (USER_VECT+$16)
IRQ_SIB     JMP     (USER_VECT+$18)
IRQ_PE54    JMP     (USER_VECT+$1A)
IRQ_PE55    JMP     (USER_VECT+$1C)
IRQ_PE56    JMP     (USER_VECT+$1E)

IRQ_NE57    JMP     (USER_VECT+$20)
IRQ_T1      JMP     (USER_VECT+$22)
IRQ_T2      JMP     (USER_VECT+$24)
IRQ_IRQ1    JMP     (USER_VECT+$26)
IRQ_IRQ2    JMP     (USER_VECT+$28)
IRQ_NMI     JMP     (USER_VECT+$2A)
RESET       JMP     (USER_VECT+$2c)
IRQ_BRK     JMP     (USER_VECT+$2E)

VEC_OFFSET EQU VECT_DEST-VECT_DATA

; These will be the hardware vectors (2 bytes each)
        WORD    VEC_OFFSET+IRQ_PE44        ;FFD0
        WORD    VEC_OFFSET+IRQ_PE45        ;FFD2
        WORD    VEC_OFFSET+IRQ_NE46        ;FFD4
        WORD    VEC_OFFSET+IRQ_NE47        ;FFD6
        WORD    VEC_OFFSET+IRQ_PE50        ;FFD8
        WORD    VEC_OFFSET+IRQ_PE51        ;FFDA
        WORD    VEC_OFFSET+IRQ_NE52        ;FFDC
        WORD    VEC_OFFSET+IRQ_NE53        ;FFDE

        WORD    VEC_OFFSET+IRQ_E0          ;FFE0
        WORD    VEC_OFFSET+IRQ_E2          ;FFE2
        WORD    VEC_OFFSET+IRQ_AT          ;FFE4 Serial Transmit
        WORD    VEC_OFFSET+IRQ_AR          ;FFE6 Serial Receive
        WORD    VEC_OFFSET+IRQ_SIB         ;FFE8
        WORD    VEC_OFFSET+IRQ_PE54        ;FFEA
        WORD    VEC_OFFSET+IRQ_PE55        ;FFEC
        WORD    VEC_OFFSET+IRQ_PE56        ;FFEE

        WORD    VEC_OFFSET+IRQ_NE57        ;FFF0
        WORD    VEC_OFFSET+IRQ_T1          ;FFF2
        WORD    VEC_OFFSET+IRQ_T2          ;FFF4
        WORD    VEC_OFFSET+IRQ_IRQ1        ;FFF6        state 3
        WORD    VEC_OFFSET+IRQ_IRQ2        ;FFF8
        WORD    VEC_OFFSET+IRQ_NMI         ;FFFA NMI    state 2
        WORD    VEC_OFFSET+RESET           ;FFFC RESET  state 0
        WORD    VEC_OFFSET+IRQ_BRK         ;FFFE BRK    state 1
VECT_DATA_END   EQU *

        ENDS
