;rasPow.asm V0.6 QRT210927
;
;ATTINY13 - - - - - - - - - - - - - - - - - - - - - - - - - -
;fuse bits     43210    high
;SELFPRGEN     1||||    (default off)
;DWEN           1|||    (default off)
;BODLEVEL1..0    11|    (default off) (drains power in sleep mode)
;RSTDISBL          1    (default off) (reset disable, PB5 input)
;              11111    $ff
;
;fuse bits  76543210    low
;SPIEN      0|||||||    (default on)
;EESAVE      0||||||    on (default off)
;WDTON        1|||||    (default off) (watchdog force system reset mode)
;CKDIV8        1||||    no clock div during startup
;SUT1..0        10||    64 ms + 14 CK startup (default)
;CKSEL1..0        01    4.8 MHz system clock
;           00111001    $39
;
;V0.5 initial version
;V0.6 changed long press signal

;-------------------------------------------------------------------------------

;.device ATtiny13
.include "tn13def.inc"

.cseg
.org $0000
rjmp main                               ;Reset Handler
;.org $0001
;rjmp EXT_INT0                           ;External Interrupt0 Handler
;.org $0002
;rjmp PCINT0                             ;Pin Change Interrrupt Handler
;.org $0003
;rjmp TIM0_OVF                           ;Timer0 Overflow Handler
;.org $0004
;rjmp EE_RDY                             ;EEPROM Ready Handler
;.org $0005
;rjmp ANA_COMP                           ;Analog Comparator Handler
;.org $0006
;rjmp TIM0_COMPA                         ;Timer0 Compare A
;.org $0007
;rjmp TIM0_COMPB                         ;Timer0 CompareB Handler
;.org $0008
;rjmp WATCHDOG                           ;Watchdog Interrupt Handler
;.org $0009
;rjmp ADC                                ;ADC Conversion Handler

;-------------------------------------------------------------------------------

.def    a0          =   r0              ;main registers set a
.def    a1          =   r1
.def    a2          =   r2
.def    a3          =   r3
.def    a4          =   r24             ;main registers set a immediate
.def    a5          =   r25
.def    a6          =   r16
.def    a7          =   r17

.def    systic      =   r4              ;system ticker
.def    status      =   r18             ;status
.def    time10      =   r19             ;10 ms timer 
.def    time80      =   r20             ;80
.def    keycnt      =   r21             ;key counter

.def    srsave      =   r15             ;status register save
.def    NULR        =   r31             ;NULL value register    ZH
.def    FLAGR       =   r29             ;FLAG                   YH

;-------------------------------------------------------------------------------

.equ    CTRLP       =   PORTB           ;control port
.equ    CTRLPP      =   PINB            ;        pinport
.equ    SLED        =   PINB4           ;        status LED     out
.equ    KEY0        =   PINB3           ;        on/off key     in      
.equ    CHKRUN_     =   PINB2           ;        raspi running  in      SCK
.equ    SHUT_       =   PINB1           ;              shutdown out     MISO
.equ    POWER       =   PINB0           ;              power    out     MOSI

;pin mask                 76543210
;                         ..-lkrsp      l led, k key0, r run, s shut, p pow
;                         ..-OIIOO      I input, O output, . not present, - unused
.equ    DDRBM       =   0b00010011
;                         ..-LPPHL      L low, H high, P pullup, N no pullup
.equ    PORTBM      =   0b00001110

;-------------------------------------------------------------------------------

.equ    KSHORT          =   5           ;key short time 50 ms
.equ    KLONGT          =   200         ;    long       2 s 

.equ    POWER_OFF       =   0           ;status raspi power off
.equ    POWER_ON        =   1           ;                   on
.equ    RUNNING         =   2           ;             running
.equ    REQ_SHUT        =   3           ;       request raspi shutdown
.equ    WAIT_SHUT       =   4           ;       wait     
.equ    OFF_DELAY       =   5           ;       raspi power off delay

;-------------------------------------------------------------------------------
;flags
.equ    FLAG0           =   0

;-------------------------------------------------------------------------------

.equ    UNUSED          =   SRAM_START

;-------------------------------------------------------------------------------

main:
        ldi     a4,low(RAMEND)              ;set stack pointer
        out     SPL,a4                      ;to top of RAM

        ldi     a4,PORTBM                   ;port B             initialize
        out     PORTB,a4
        ldi     a4,DDRBM                    ;ddr B
        out     DDRB,a4

        sbi     ACSR,ACD                    ;comparator off

;- - - - - - - - - - - - - - - - - - - -

        clr     NULR                        ;init NULR (ZH)
        ldi     ZL,29                       ;reset registers
        st      Z,NULR                      ;store indirect
        dec     ZL                          ;decrement address
        brpl    PC-2                        ;r0..29 = 0, ZL = $ff, ZH = 0 (NULR)

        ldi     ZL,low(SRAM_START)          ;clear SRAM
        st      Z+,NULR
        cpi     ZL,low(RAMEND-1)
        brne    PC-2

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

        rcall   delay50ms                   ;settle Cs
        sbi     CTRLP,SLED                  ;LED on
        rcall   delay50ms                   ;wait 50 ms
        sbi     CTRLP,SLED                  ;LED off

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

m00:    rcall   hKey                        ;handle key
        rcall   hWait                       ;       waits
        rcall   hTime                       ;       time
        rcall   hLed                        ;       LED

        rcall   delay10ms                   ;delay 10 ms
        rjmp    m00                         ;main loop

;-------------------------------------------------------------------------------

hKey:   sbis    CTRLPP,KEY0                 ;key pressed?  
        rjmp    keyPre                      ;yes, jump

keyRel: cpi     keycnt,KLONGT               ;key released, long press?
        brsh    ky08                        ;yes, exit
        
        cpi     keycnt,KSHORT               ;short press?
        brlo    ky08                        ;no, exit
        rcall   keyShort                    ;handle it

ky08:   clr     keycnt                      ;reset key counter
ky09:   ret                                 ;exit

keyPre: inc     keycnt                      ;key pressed, key counter ++
        brne    ky01                        ;key counter overflow?
        dec     keycnt                      ;yes, restrict counter
        ret                                 ;exit

ky01:   cpi     keycnt,KLONGT               ;long press?
        brne    ky09                        ;no, exit

;- - - - - - - - - - - - - - - - - - - -

keyLong:
        ldi     a7,10                       ;10 times
kl01:   sbi     CTRLP,SLED                  ;LED on
        rcall   delay50ms                   ;50 ms delay
        cbi     CTRLP,SLED                  ;LED off
        rcall   delay50ms                   ;50 ms delay
        dec     a7                          
        brne    kl01

;- - - - - - - - - - - - - - - - - - - -

reInit: cbi     CTRLP,POWER                 ;power off
        sbi     CTRLP,SHUT_                 ;init shut line
        clr     time10                      ;reset timer
        clr     time80                      ;           
        clr     systic                      ;      system ticker
        ldi     status,POWER_OFF            ;set status
        cbi     CTRLP,SLED                  ;LED off
        ret

;- - - - - - - - - - - - - - - - - - - -

keyShort:
        cpi     status,POWER_OFF            ;power off?
        brne    ks01                        ;no, jump
        sbi     CTRLP,POWER                 ;power on
        ldi     status,POWER_ON             ;set status
        ldi     time10,100                  ;power on delay 1 s
        ret

ks01:   cpi     status,RUNNING              ;running?
        brne    ks09                        ;no, jump
        tst     time80                      ;shut delay?
        brne    ks09                        ;yes, exit
        cbi     CTRLP,SHUT_                 ;line L
        ldi     status,REQ_SHUT             ;set status
        ldi     time10,5                    ;SHUT_ L delay 50 ms

ks09:   ret

;-------------------------------------------------------------------------------

hWait:
        cpi     status,POWER_ON             ;power on?
        brne    wa01                        ;no, jump        
        tst     time10                      ;power on delay?
        brne    wa09                        ;yes, exit
        sbic    CTRLPP,CHKRUN_              ;running?
        rjmp    wa09                        ;no, exit
        ldi     status,RUNNING              ;set status
        ldi     time80,(5000/80)            ;shut delay 5 s
        ret

wa01:   cpi     status,REQ_SHUT             ;shut request?
        brne    wa02                        ;no, jump
        tst     time10                      ;SHUT_ L delay?
        brne    wa09                        ;yes, exit
        sbi     CTRLP,SHUT_                 ;line H
        ldi     status,WAIT_SHUT            ;set status
        ret

wa02:   cpi     status,WAIT_SHUT            ;wait shut?
        brne    wa03                        ;no, jump
        sbis    CTRLPP,CHKRUN_              ;running?
        rjmp    wa09                        ;yes, exit
        ldi     status,OFF_DELAY            ;set status
        ldi     time80,(15000/80)           ;off delay 15 s
        ret

wa03:   cpi     status,OFF_DELAY            ;off delay?
        brne    wa09                        ;no, jump
        tst     time80                      ;off delay?
        brne    wa09                        ;yes, exit
        rjmp    reInit                      ;reInit

wa09:   ret

;-------------------------------------------------------------------------------

hTime:   
        tst     time10                      ;10 ms timer
        breq    ti01                        
        dec     time10                      

ti01:   tst     time80                      ;80 ms timer
        breq    ti09

        mov     a4,systic                  
        andi    a4,0x07
        brne    ti09
        dec     time80

ti09:   ret                                 

;-------------------------------------------------------------------------------

hLed:   mov     a4,systic                   ;copy systic

        cpi     status,POWER_OFF            ;.......*
        brne    le01                        ;
        andi    a4,(1<<8)-2                 ;    
        rjmp    le08                        ;

le01:   cpi     status,POWER_ON             ;.*.*.*.*
        brne    le02
        andi    a4,(1<<4)
        rjmp    le08

le02:   cpi     status,RUNNING              ;********
        brne    le03
        sbi     CTRLP,SLED
        rjmp    le09

le03:   andi    a4,(1<<5)-2                 ;...*...*, shut

le08:   breq    PC+3                        
        cbi     CTRLP,SLED                  ;LED off
        rjmp    PC+2                        
        sbi     CTRLP,SLED                  ;LED on

le09:   inc     systic                      ;systic++
        ret

;-------------------------------------------------------------------------------

delay50ms:
        ldi     a6,5-1                   
        rcall   delay10ms                   
        dec     a6
        brne    PC-2

;- - - - - - - - - - - - - - - - - - - -

delay10ms:
        ldi     a5,86                       ;delay ~ 10 ms @ 4.8 MHz
delay:  ldi     a4,185
        dec     a4
        brne    PC-1
        dec     a5
        brne    PC-4

        ret
