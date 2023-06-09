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
#define PED_PASS_REQUEST PB5
#define LIGHTS_MASK ((1 << RED_LIGHT) | (1 << YELLOW_LIGHT) | \
                     (1 << GREEN_LIGHT) | (1 << PED_RED_LIGHT) | \
                     (1 << PED_GREEN_LIGHT) | (1 << PED_PASS_REQUEST))

; Definition for the pedestrian button
#define PED_BUTTON PD2

; Using some registers as global variables
#define lights_time_base r20
#define hold_state r21

; R22 will be used to hold the state our cycle is in, we have 4 states:
;   00: Green light is on
;   01: Yellow light is on, moving to red
;   10: Red light is on
;   11: Yellow light is on, moving to green
#define state r22

; Debounce variable for the pedestrian button.
#define debounce r23

.text
.global main
main:
    ; Initialization code
    ; Initialize global variables
    ;   Load the lights_time_base counter with its max value, timer 0 will
    ;   decrement it
    ldi lights_time_base, LIGHTS_TIME_BASE_RELOAD

    ;   Start with green light on for 2 seconds
    ldi state, 0x00
    ldi hold_state, TWO_SECONDS

    ;   debounce starts as if the button was not pressed
    ldi debounce, 0x00

    ; Setup the stack
    ldi r16, hi8(RAMEND)
    sts SPH, r16
    ldi r16, lo8(RAMEND)
    sts SPL, r16

    ; Set needed pins as output and start with the green light on
    ldi r16, LIGHTS_MASK
    out _SFR_IO_ADDR(DDRB), r16
    ldi r16, ~LIGHTS_MASK
    out _SFR_IO_ADDR(PORTB), r16
    sbi _SFR_IO_ADDR(PORTB), GREEN_LIGHT
    sbi _SFR_IO_ADDR(PORTB), PED_RED_LIGHT

    ; Set the button as a pull-up input
    cbi _SFR_IO_ADDR(DDRD), PED_BUTTON
    sbi _SFR_IO_ADDR(PORTD), PED_BUTTON

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
    ; Check if the pedestrian button has been pressed
    cpi debounce, 0xFF
    brne loop

    ; A pedestrian has requested the light to change, go through the cycle
    sbi _SFR_IO_ADDR(PORTB), PED_PASS_REQUEST
    ldi lights_time_base, LIGHTS_TIME_BASE_RELOAD

cycle:
    ; Check if the time base has been hit
    tst lights_time_base
    brne cycle

    ; Reload the lights time base
    ldi lights_time_base, LIGHTS_TIME_BASE_RELOAD

    ; Check if we have to change state
    dec hold_state
    brne cycle

    ; Move to the next state
    inc state

    ; Set all lights to off and determine which to turn on
    in r16, _SFR_IO_ADDR(PINB)
    andi r16, ~LIGHTS_MASK
    out _SFR_IO_ADDR(PORTB), r16

    ; switch(state)
    sbrc state, 0
    rjmp handle_yellow
    sbrs state, 1
    rjmp handle_green

    ; Fallthrough to handle red light
handle_red:
    ldi hold_state, TWO_SECONDS

    sbi _SFR_IO_ADDR(PORTB), RED_LIGHT
    sbi _SFR_IO_ADDR(PORTB), PED_GREEN_LIGHT
    rjmp cycle

handle_green:
    ldi hold_state, TWO_SECONDS

    sbi _SFR_IO_ADDR(PORTB), GREEN_LIGHT
    sbi _SFR_IO_ADDR(PORTB), PED_RED_LIGHT

    ; Once we get back to the green light, we are done with the cycle
    ldi state, 0x00

    rjmp loop

handle_yellow:
    ldi hold_state, ONE_SECOND

    sbi _SFR_IO_ADDR(PORTB), YELLOW_LIGHT
    sbrc state, 1
    sbi _SFR_IO_ADDR(PORTB), PED_GREEN_LIGHT
    sbrs state, 1
    sbi _SFR_IO_ADDR(PORTB), PED_RED_LIGHT
    rjmp cycle

; Timer 0 interrupt handler
.global TIMER0_OVF_vect
TIMER0_OVF_vect:
    push r16
    lds r16, SREG
    push r16
    push r17

    ; Decrement the lights time base counter
    dec lights_time_base

    ; Update the pedestrian button debounce
    lsl debounce
    sbis _SFR_IO_ADDR(PIND), PED_BUTTON
    sbr debounce, 0x01

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
