#include <avr/io.h>

; Timer 0 will run at fclk/1024, in order to achieve a 10ms time base
; it will need to be reloaded with 0x63.
#define TIMER0_RELOAD 0x63

; Combined with timer 0, this value provides a time base for the lights to
; change state
#define LIGHTS_TIME_BASE_RELOAD 50

; Timing constants
#define ONE_SECOND 2
#define TWO_SECONDS 4

; Definitions for the lights
#define RED_LIGHT PB0
#define YELLOW_LIGHT PB1
#define GREEN_LIGHT PB2
#define PED_RED_LIGHT PB3
#define PED_GREEN_LIGHT PB4
#define LIGHTS_MASK ((1 << RED_LIGHT) | (1 << YELLOW_LIGHT) | \
                     (1 << GREEN_LIGHT) | (1 << PED_RED_LIGHT) | \
                     (1 << PED_GREEN_LIGHT))

; Using some registers as global variables
#define lights_time_base r20
#define hold_state r21

; R22 will be the used to hold the state our program is in, we have 4 states:
;   00: Red light is on
;   01: Yellow light is on, moving to green
;   10: Green light is on
;   11: Yellow light is on, moving to red
#define state r22

.text
.global main
main:
    ; Initialization code
    ; Initialize global variables
    ;   Load the lights_time_base counter with its max value, timer 0 will
    ;   decrement it
    ldi lights_time_base, LIGHTS_TIME_BASE_RELOAD

    ;   Start with red light on for 2 seconds
    ldi state, 0x00
    ldi hold_state, TWO_SECONDS

    ; Setup the stack
    ldi r16, hi8(RAMEND)
    sts SPH, r16
    ldi r16, lo8(RAMEND)
    sts SPL, r16

    ; Set needed pins as output and start with the red light on
    ldi r16, LIGHTS_MASK
    out _SFR_IO_ADDR(DDRB), r16
    ldi r16, ~LIGHTS_MASK
    out _SFR_IO_ADDR(PORTB), r16
    sbi _SFR_IO_ADDR(PORTB), RED_LIGHT
    sbi _SFR_IO_ADDR(PORTB), PED_GREEN_LIGHT

    ; Set Timer 0 to run on fclk/1024
    ldi r16, 0x05
    sts TCCR0B, r16

    ; Load the initial value for the timer0 counter
    ldi r16, TIMER0_RELOAD
    sts TCNT0, r16

    ; Enable timer 0 overflow interrupt
    ldi r16, 0x01
    sts TIMSK0, r16

    ; Enable global interrupts
    sei

loop:
    ; Main loop
    ; Check if the time base has been hit
    tst lights_time_base
    brne loop

    ; Reload the lights time base
    ldi lights_time_base, LIGHTS_TIME_BASE_RELOAD

    ; Check if we have to change state
    dec hold_state
    brne loop

    ; Move to the next state
    inc state

    ; If the state got to 4, reset it
    sbrc state, 2
    ldi state, 0x00

    ; Set all lights to off and determine which to turn on
    in r16, _SFR_IO_ADDR(PORTB)
    andi r16, ~LIGHTS_MASK
    out _SFR_IO_ADDR(PORTB), r16

    ; switch(state)
    sbrc state, 0
    rjmp handle_yellow
    sbrc state, 1
    rjmp handle_green

    ; Fallthrough to handle red light
handle_red:
    ldi hold_state, TWO_SECONDS

    sbi _SFR_IO_ADDR(PORTB), RED_LIGHT
    sbi _SFR_IO_ADDR(PORTB), PED_GREEN_LIGHT
    rjmp loop

handle_green:
    ldi hold_state, TWO_SECONDS

    sbi _SFR_IO_ADDR(PORTB), GREEN_LIGHT
    sbi _SFR_IO_ADDR(PORTB), PED_RED_LIGHT
    rjmp loop

handle_yellow:
    ldi hold_state, ONE_SECOND

    sbi _SFR_IO_ADDR(PORTB), YELLOW_LIGHT
    sbrc state, 1
    sbi _SFR_IO_ADDR(PORTB), PED_RED_LIGHT
    sbrs state, 1
    sbi _SFR_IO_ADDR(PORTB), PED_GREEN_LIGHT
    rjmp loop

; Timer 0 interrupt handler
.global TIMER0_OVF_vect
TIMER0_OVF_vect:
    push r16
    lds r16, SREG
    push r16
    push r17

    ; Decrement the lights time base counter
    dec lights_time_base

    ; Reload the timer counter
    lds r16, TCNT0
    ldi r17, TIMER0_RELOAD
    add r16, r17
    sts TCNT0, r16

    pop r17
    pop r16
    sts SREG, r16
    pop r16
    reti
