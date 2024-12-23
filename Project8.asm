;-------------------------------------------------------------------------------
;******************************************************************************
;                                  Project 8
;   Programmable timer using push buttons & 7 segment display on daughterboard
;
;                                 Tyler Lince
;                            Texas Tech University
;                                 November 2024
;******************************************************************************
;-------------------------------------------------------------------------------
            .cdecls C,LIST,"msp430.h"       ; Include device header file
;-------------------------------------------------------------------------------
            .def    RESET                   ; Export program entry-point to
                                            ; make it known to linker.
;-------------------------------------------------------------------------------
            .global _main
            .global __STACK_END
            .sect   .stack                  ; Make stack linker segment ?known?

            .text                           ; Assemble to Flash memory
            .retain                         ; Ensure current section gets linked
            .retainrefs

SEGA        .set    BIT0 ; P2.0
SEGB        .set    BIT1 ; P2.1
SEGC        .set    BIT2 ; P2.2
SEGD        .set    BIT3 ; P2.3
SEGE        .set    BIT4 ; P2.4
SEGF        .set    BIT5 ; P2.5
SEGG        .set    BIT6 ; P2.6
SEGDP       .set    BIT7 ; P2.7

DIG1        .set    BIT0 ; P3.0
DIG2        .set    BIT1 ; P3.1
DIG3        .set    BIT2 ; P3.2
DIG4        .set    BIT3 ; P3.3
DIGCOL      .set    BIT7 ; P3.7

BTN1		.set	BIT7 ; P4.7 **some boards appear to have BTN1 and BTN3 flipped?
BTN2		.set	BIT3 ; P1.3
BTN3		.set    BIT5 ; P1.5

TRUE		.set	1
FALSE		.set	0

digit       .set    R4   ; Set of flags for state machine
display     .set    R5   ; Display digits
count		.set	R6	 ; Stores 4 values to be displayed on 7 seg displays
blinking	.set	R7	 ; stores whether blinking
editing		.set	R8	 ; stores whether editing (changing value of timer)
;-------------------------------------------------------------------------------
_main
RESET       mov.w   #__STACK_END,SP         ; Initialize stackpointer
StopWDT     mov.w #WDTPW+WDTCNTCL+WDTTMSEL+7+WDTSSEL__ACLK,&WDTCTL ; Interval mode with ACLK
			bis.w #WDTIE, &SFRIE1                                       ; enable interrupts for the watchdog
;-------------------------------------------------------------------------------
; Initializes the port settings for the segments and digits
SetupSeg    bic.b   #SEGA+SEGB+SEGC+SEGD+SEGE+SEGF+SEGG+SEGDP,&P2OUT
            bic.b   #DIG1+DIG2+DIG3+DIG4+DIGCOL,&P3OUT
            bis.b   #SEGA+SEGB+SEGC+SEGD+SEGE+SEGF+SEGG+SEGDP,&P2DIR
            bis.b   #DIG1+DIG2+DIG3+DIG4+DIGCOL,&P3DIR
            bic.b   #SEGA+SEGB+SEGC+SEGD+SEGE+SEGF+SEGG+SEGDP,&P2OUT
            bic.b   #DIG1+DIG2+DIG3+DIG4,&P3OUT
            bis.b   #DIGCOL,&P3OUT

SetupP1     bic.b   #BIT0,&P1OUT            ; Clear P1.0 output latch for a defined power-on state
            bis.b   #BIT0,&P1DIR            ; Set P1.0 to output direction (RED LED)
; Initializes the port settings for the buttons
SetupPB		bic.b   #BTN1, &P4DIR
			bic.b   #BTN3+BTN2, &P1DIR
			bis.b   #BTN1, &P4REN
			bis.b   #BTN3+BTN2, &P1REN
			bis.b   #BTN1, &P4OUT
			bis.b   #BTN3+BTN2, &P1OUT
			bis.b   #BTN1, &P4IES
			bis.b   #BTN3+BTN2, &P1IES
			bis.b   #BTN1, &P4IE
			bis.b   #BTN3+BTN2, &P1IE
;-------------------------------------------------------------------------------
;***Timers***
;-------------------------------------------------------------------------------
; Left & Middle Button Debounce Timer
SetupTA0	mov.w   #CCIE,&TA0CCTL0           ; TACCR0 interrupt enabled
            mov.w   #50000,&TA0CCR0           ; count to 49999 for 50ms delay
            bis.w   #TASSEL__SMCLK+MC__STOP,TA0CTL ; SMCLK stop mode

; Countdown Decrement Timer
SetupTA1	mov.w   #CCIE,&TA1CCTL0           ; TACCR0 interrupt enabled
            mov.w   #10000,&TA1CCR0           ; count to 9999 for 1cs
            bis.w   #TASSEL__SMCLK+MC__STOP,TA1CTL ; SMCLK stop mode
; 0.5s Blink Timer
SetupTA2	mov.w   #CCIE,&TA2CCTL0           ; TACCR0 interrupt enabled
            mov.w   #50000,&TA2CCR0           ;	count to 50000
            bis.w   #TASSEL__SMCLK+MC__UP+ID_1,TA2CTL ; SMCLK, up mode, divide by 2
            mov.w   #TAIDEX_4, &TA2EX0         ; divide by 5 = 0.5s

SetupTA3	mov.w   #CCIE,&TA3CCTL0           ; TACCR0 interrupt enabled
            mov.w   #50000,&TA3CCR0           ;	count to 50000
            bis.w   #TASSEL__SMCLK+MC__UP+ID_3,TA3CTL ; SMCLK, up mode, divide by 2
            mov.w   #TAIDEX_7, &TA3EX0         ; divide by 5 = 0.5s
;--------------------------------------------------------------------------------------------
UnlockGPIO  bic.w   #LOCKLPM5,&PM5CTL0      ; Disable the GPIO power-on default
                                            ; high-impedance mode to activate
                                            ; previously configured port settings

			bic.b   #BTN2+BTN3, &P1IFG      ; Reset interrupts here,
			bic.b   #BTN1, &P4IFG           ; unlocking the GPIO tends to trigger an interrupt
			mov.w   #5, digit				; stores digit being multiplexed
			mov.w   #0, display				;
			mov.w	#0x0000, count			; start timer at 00:00
			mov		#FALSE, blinking		; but digits shouldn't blink on startup
			mov		#TRUE, editing			; enter edit mode on startup

			nop
			bis.b   #LPM0+GIE, SR                ; enable all interrupts, enter LPM0
			nop

; Initialize the display

Mainloop    jmp     Mainloop                ; Again

;-------------------------------------------------------------------------------
; Look Up Tables
;-------------------------------------------------------------------------------
; Hex -> Segment conversion
BCD         .byte   SEGA+SEGB+SEGC+SEGD+SEGE+SEGF      ; 0
            .byte        SEGB+SEGC                     ; 1
            .byte   SEGA+SEGB+     SEGD+SEGE+     SEGG ; 2
            .byte   SEGA+SEGB+SEGC+SEGD+          SEGG ; 3
            .byte        SEGB+SEGC+          SEGF+SEGG ; 4
            .byte   SEGA+     SEGC+SEGD+     SEGF+SEGG ; 5
            .byte   SEGA+     SEGC+SEGD+SEGE+SEGF+SEGG ; 6
            .byte   SEGA+SEGB+SEGC                     ; 7
            .byte   SEGA+SEGB+SEGC+SEGD+SEGE+SEGF+SEGG ; 8
            .byte   SEGA+SEGB+SEGC+SEGD+     SEGF+SEGG ; 9
            .byte   0x00								; A (null)
;            .byte             SEGC+SEGD+SEGE+SEGF+SEGG ; b
;            .byte   SEGA+          SEGD+SEGE+SEGF      ; C
;            .byte        SEGB+SEGC+SEGD+SEGE+     SEGG ; d
;            .byte   SEGA+          SEGD+SEGE+SEGF+SEGG ; E
;            .byte   SEGA+               SEGE+SEGF+SEGG ; F

sDIG        .byte   0
			.byte   DIG1
			.byte   DIG2
			.byte   DIG3
			.byte   DIG4

;-------------------------------------------------------------------------------
WDT_ISR;    WDT Interrupt Service Routine
; Responsible for isolating digits from countdown and multiplexing them onto 7 segment displays
;-------------------------------------------------------------------------------
    		push        count		; store count in stack 1233

    		dec         digit		; decrement digit each cycle to multiplex
    		jnz         SkipReset	; if not zero, skip resetting
    		mov         #4, digit	; reset digit back to 4 if digit=0

SkipReset:
    		clr.b       &P2OUT		; clear segments of previous cycle
    		bic.b       #0x0F, &P3OUT	; clear currently stored digit port

    		bis.b       sDIG(digit), &P3OUT		; assign P3OUT to current digit being multiplexed

CheckDig4: ; rightmost
    		cmp         #4, digit		; are we currently mpxing digit 4?
    		jne         CheckDig3		; if not, skip to test next digit
    		and         #0x000F, count	; mask rightmost digit from countdown variable
    		mov.b       BCD(count), &P2OUT	; move digits respective segments to P2OUT for display
    		jmp         WDT_ISR_END

CheckDig3:
    		rra.w       count			; roll right x4 on countdown variable to make 3rd digit rightmost
    		rra.w       count			;
    		rra.w       count			;
    		rra.w       count			; 1234=count 0123 = 0003
    		cmp         #3, digit		; are we currently mpxing digit 3?
    		jne         CheckDig2		; if not, skip to next digit
    		and         #0x000F, count	; mask rightmost digit from countdown variable
    		mov.b       BCD(count), &P2OUT	; move digits respective segments to P2OUT for display
    		jmp         WDT_ISR_END

CheckDig2:
    		rra.w       count			; roll right x4 on countdown variable to make 3rd digit (originally 2nd digit) rightmost
    		rra.w       count			;
    		rra.w       count			;
    		rra.w       count			; 0012
    		cmp         #2, digit		; are we currently mpxing digit 2?
    		jne         CheckDig1		; if not, skip to next digit
    		and         #0x000F, count	; mask rightmost digit from countdown variable 0002
    		mov.b       BCD(count), &P2OUT	; move digits respective segments to P2OUT for display
    		jmp         WDT_ISR_END

CheckDig1:
    		rra.w       count			; roll right x4 on countdown variable to make 3rd digit (originally 1st digit) rightmost
    		rra.w       count			;
    		rra.w       count			;
    		rra.w       count			;1234= 0001
    		cmp         #1, digit		; are we currently mpxing digit 1?
    		jne         WDT_ISR_END		; if not, leave (not sure how we'd get here)
    		and         #0x000F, count	; mask rightmost digit from countdown variable 0001
    		mov.b       BCD(count), &P2OUT	; move digits respective segments to P2OUT for display

WDT_ISR_END:
    		pop.w       count	; pop original countdown value back onto count variable 1234



WDT_reti:    	reti


;-------------------------------------------------------------------------------
TIMER0_A0_ISR;    Timer0_A3 CC0 Interrupt Service Routine
; Responsible for button debouncing on BTN2 and BTN3, also handles incrementing and decrementing timer
;-------------------------------------------------------------------------------
            bit.b	#BTN2, &P1IN 		; test delay for BTN2 debounce
            jnz		TestBtn1			; if BTN2 not pressed, check BTN3
            							;
										; if BTN2 is presssed:
										; (BTN2 decrements by 1 second)
			cmp		#0x0100, count		;
			jlo		TA0Exit				; if count = 0, dont decrement, exit ISR and remain at 00:00
            clrc						; if count =/= 0, clear carry bit for decimal add
            dadd.w	#0x9900, count		; dadd.w #0x9900 = decimal subtract #0x0100 (-1 second)
            jmp		TA0Exit					; leave
TestBtn1:
			bit.b	#BTN3, &P1IN		; test delay for BTN3 debounce
			jnz		TA0Exit				; if neither button pressed after debounce, exit without doing anything
										; if BTN3 is pressed:
										; (BTN3 increments by 1 second)
            clrc						; clear carry bit for decimal add
			dadd.w  #0x0100, count		; decimal add 0100 (1 second)

TA0Exit:
			bic.w   #MC__UP,&TA0CTL			; stop debounce timer
			reti

;-------------------------------------------------------------------------------
TIMER1_A0_ISR;    Timer0_A3 CC0 Interrupt Service Routine
; Responsible for decrementing count variable whenever right button is pressed
;-------------------------------------------------------------------------------
			cmp		#0x0000, count
			jeq		TA1_Exit
			dadd.w  #0x9999, count		; 9999 = 0001's two's complement, so decimal subtract 0001 (1ms)
TA1_Exit	reti

;-------------------------------------------------------------------------------
TIMER2_A0_ISR;    Timer0_A3 CC0 Interrupt Service Routine
; Responsible for blinking display at 0.5s interval whenever timer reaches zero
;-------------------------------------------------------------------------------
			cmp		#TRUE, editing		; are we in editing mode?
			jeq		TA2Exit				; if we are, don't blink
			cmp		#TRUE, blinking		; are we in blinking mode?
			jne		TA2Exit				; if we aren't, don't blink

			cmp		#0x0000, count		; is count=0000?
			jeq		onoff				; if it is, jump to turn count off

offon:		mov.w	#0x0000, count		; if it isn't, count is probably AAAA, so turn back to 0000
			reti
onoff:		mov.w	#0xAAAA, count		; A = null, so moving AAAA to count makes display show nothing
TA2Exit:	reti

;-------------------------------------------------------------------------------
TIMER3_A0_ISR;    Timer0_A3 CC0 Interrupt Service Routine
; Responsible 3 second right button press reset
;-------------------------------------------------------------------------------
TA31		bit.b	#BTN1, &P4IN
			jnz		TA3Exit
			bit		#TAIFG, &TA3CTL
			jz		TA31
			mov.w	#MC_0, &TA1CTL
			bis.w	#TACLR, &TA1CTL
			mov.w	#0x0000, count
			mov.w	#TRUE, editing
			mov.w	#FALSE, blinking

TA3Exit
			bic.b   #BTN1,&P4IFG
			bic		#TAIFG, &TA3CTL
			clr.w 	&TA3R
			reti

;-------------------------------------------------------------------------------
PORT1_ISR;    Timer0_A3 CC0 Interrupt Service Routine
; Come here whenever left or middle button is pressed
;-------------------------------------------------------------------------------
			cmp		#TRUE, blinking		; were we in blinking mode when L or M button was pressed?
			jeq		WasBlinking			; if we were jump to WasBlinking
			cmp		#FALSE, editing		; were we in editing mode when L or M button was pressed?
			jeq		WasRunning			; if we were, jump to WasRunning
			jmp		Debounce			; if neither, we've been in editing mode, jump to debounce

WasBlinking:	mov.w	#0x0000, count		; if we were blinking, move 0000 incase AAAA was stored there
WasRunning:		mov.w	#TRUE, editing		; if L or M buttton was pressed, we want to enter editting mode
				mov.w	#FALSE, blinking	; and we want to exit blinking mode
				jmp		StopTA1andExit		; if timer was running or blinking when button was pressed,
											;we don't want to increment or decrement on that press. exit

Debounce:	bis.w	#MC__UP+TACLR, &TA0CTL  ; go to debounce timer for increment and decrement

StopTA1andExit:
			bic.b   #BTN3+BTN2,&P1IFG	; clear L and M button interrupt flags
			mov.w		#MC_0, &TA1CTL	; set TA1 to stop mode
			bis.w		#TACLR, &TA1CTL	; clear TA1
			reti
;-------------------------------------------------------------------------------
PORT4_ISR;    Timer0_A3 CC0 Interrupt Service Routine
; Responsible for starting countdown timer whenever right button is pressed
;-------------------------------------------------------------------------------
			bic		#TAIFG, &TA3CTL		; start the countdown decrement timer
			clr.w 	&TA3R

			cmp		#TRUE, blinking		; were we in blinking mode before R button was pressed?
			jne		FTP4ISR				; if we weren't, skip ahead
			mov.w	#0x0000, count		; if we were, move 0000 to count incase AAAA was there

FTP4ISR:	mov.w	#FALSE, editing		; if R button is pressed, we want to run timer,
			mov.w	#FALSE, blinking	; so turn off blinking and editing mode

			bic		#TAIFG, &TA1CTL		; start the countdown decrement timer
			mov		#MC_1, &TA1CTL
			bis		#TASSEL_2+TACLR, &TA1CTL

            bic.b   #BTN1,&P4IFG		; clear port 4 interrupt flag
            reti
;------------------------------------------------------------------------------
;           Interrupt Vectors
;------------------------------------------------------------------------------
            .sect   ".reset"                ; MSP430 RESET Vector
            .short  RESET
            .sect   WDT_VECTOR              ; Watchdog Timer
            .short  WDT_ISR
            .sect   TIMER0_A0_VECTOR        ; Timer0_A0 CC0 Interrupt Vector
            .short  TIMER0_A0_ISR
            .sect   TIMER1_A0_VECTOR        ; Timer1_A0 CC0 Interrupt Vector
            .short  TIMER1_A0_ISR
            .sect   TIMER2_A0_VECTOR        ; Timer2_A0 CC0 Interrupt Vector
            .short  TIMER2_A0_ISR
            .sect   TIMER3_A0_VECTOR        ; Timer2_A0 CC0 Interrupt Vector
            .short  TIMER3_A0_ISR
            .sect   PORT1_VECTOR        ; BTN2+BTN3 Interrupt Vector
            .short  PORT1_ISR
            .sect   PORT4_VECTOR        ; BTN1 Interrupt Vector
            .short  PORT4_ISR
            .end
