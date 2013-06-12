;----------------------------------------------------------------------
; NAME: LED Color Baby Thermomoter for	PIC 12F675
; BY: 	Nathan Pahucki
;----------------------------------------------------------------------

;****************************************************************************
;* 12F675								    *								*
;*                             -----uu-----                                 *
;*                   +5 V ----| vdd    vss |---- Gnd                        *
;*              BLUE LED  <---| gp5    gp0 |---> TEMP_IN     			    *
;*              GREEN LED <---| gp4    gp1 |---> VREF                       *
;*              NC        --->| gp3    gp2 |<--- RED LED                    *
;*                             ------------                                 *
;*                                                                          *
;****************************************************************************


	list      p=12f675            ; list directive to define processor
	#include <p12f675.inc>        ; processor specific variable definitions

;----------------------------------------------------------------------
; Config
	__CONFIG _INTRC_OSC_NOCLKOUT & _WDT_OFF & _PWRTE_ON & _MCLRE_OFF & _CP_OFF & _CPD_OFF
	ERRORLEVEL -302
;----------------------------------------------------------------------

;----------------------------------------------------------------------
; Constants
;----------------------------------------------------------------------
#define TEMP_IN		GPIO0

#define BLUE_LED_MASK	1 << GPIO5
#define GREEN_LED_MASK	1 << GPIO4
#define RED_LED_MASK	1 << GPIO2

;#define USE_VREF


#define ADC_COLD .136	;    // 18C
#define ADC_COOL .144	;    // 22C    
#define ADC_WARM .152	;    // 26C
#define ADC_HOT .160	;     // 30C

#define MIN_DUTY_CYCLE .30
#define MODULATE_HOLD_CYCLES .5
#define FADE_STEPS .1
#define FADE_CYCLES_BEFORE_SENSOR_CHECK .30

;----------------------------------------------------------------------
; RAM VARIABLES DEFINITIONS
;----------------------------------------------------------------------
; Bank0 = 20h-5Fh

	CBLOCK	0x020
	multiplier: 1		; the BAM bit position
	period: 1			; the BAM delay for the current multiplier
	dutyCycle: 1		; the current duty cycle 
	cycleCount: 1		; the number of LED modulate cycles
	gpioState: 1		; current valu3 to write to GPIO
	sensorCheckCnt : 1	; sensor check counter - number of fade counts 
	ENDC


;********************************************************************** 
;  Program
;**********************************************************************
	ORG     0x000           	; processor reset vector
	goto    MAIN            	; go to beginning of program

;-----------------------------------------------------------------------------
;	Interrupt service routine
;-----------------------------------------------------------------------------
	ORG     0x004  			; interrupt vector location
	RETFIE					; return from interrupt

;-----------------------------------------------------------------------------
;	 Main starts here
;-----------------------------------------------------------------------------
	ORG     0x010
MAIN:
;-----------------------------------------------------------------------------
; Init_Prog
;  - Initialize program & setups
;  - Initilaize all ports to known state before setup routines are called
;-----------------------------------------------------------------------------
	; int osc calibration / Calibrarea oscilatorului intern de 4 Mhz
	banksel OSCCAL
	call	0x3FF		; get the calibration value
	movwf 	OSCCAL
	; make sure IRQ gets disabled
IRQ_DISABLE
	banksel INTCON
	bcf	INTCON,GIE	; Disable global interrupt
	btfsc INTCON,GIE	; check if disabled 
	goto IRQ_DISABLE		; nope, try again

	; ports init / initializare porturi
	banksel GPIO
	clrf	GPIO			; init GPIO
	banksel CMCON
	movlw	b'00000111'		; Comparator configuration
	movwf	CMCON			; Comparator off
	banksel OPTION_REG
	bcf     OPTION_REG,5	; TMR0 internal instruction cycle clock (CLKOUT)
	bsf	OPTION_REG,7		; GPIO pull-ups: is disabled
	banksel WPU
	clrf	WPU				; Clear weak pull-up register
	banksel IOC
	clrf	IOC				; Clear Interrupt-on-change register
	banksel TRISIO
	movlw   ~(BLUE_LED_MASK | GREEN_LED_MASK | RED_LED_MASK) ; 7) data direction TRISO 0: output, 1: input (Hi-Z mode)
	movwf   TRISIO         	; 0-Output 1-Input
	; Setup ADC
	banksel ADCON0	
	bsf ADCON0,ADON 		; activate AD converter
	bsf ADCON0,ADFM 		; right justified register reads
	#ifdef USE_VREF
	bsf ADCON0,VCFG			; use VREF
	#endif
	; use only channel AN0
	bcf ADCON0,CHS0
	bcf ADCON0,CHS1
	; use internal osc
	banksel ANSEL
	bsf ANSEL,ADCS1
	bsf ANSEL,ADCS2
	bsf ANSEL,ANS0			; GPIO/AN0 enabled for analog
	bcf ANSEL,ANS1			; digital
	bcf ANSEL,ANS2			; digital
	bcf ANSEL,ANS3			; digital	

	; initialize the gpio buffer to show white (all LEDs) for first cycle.
	movlw BLUE_LED_MASK | GREEN_LED_MASK | RED_LED_MASK
	movwf gpioState
	
	; initialize the sensorCheckCnt
	movlw FADE_CYCLES_BEFORE_SENSOR_CHECK
	movwf sensorCheckCnt


;-----------------------------------------------------------------------------
; Program loop
;-----------------------------------------------------------------------------

cycle:
	call set_led_color		; set the LED color, this should take a contant amount of time for any one color 
	clrf dutyCycle			; reset dutyCycle
	comf dutyCycle, F		; set to max duty cycle
fade_down_loop:
	call modulate_led
	movlw FADE_STEPS
	subwf dutyCycle, F	
	movlw MIN_DUTY_CYCLE
	subwf dutyCycle, W
	skpnc
	goto fade_down_loop
fade_up_loop:
	call modulate_led
	movlw FADE_STEPS
	addwf dutyCycle, F
	skpc
	goto fade_up_loop
    goto cycle				; done, read adc again and start fade again	

modulate_led:
	clrf multiplier
	bsf multiplier, 0
modulate_led_loop:
	banksel GPIO
	movfw dutyCycle
	andwf multiplier,W
	skpnz					; for this cycle, we don't activate the LED
	goto modulate_led_off	
	movfw gpioState
	movwf GPIO				; turn the LEDs on and wait for a time proportional to the 'bit angle'
	goto modulate_period_delay
modulate_led_off
	clrf GPIO	 
modulate_period_delay:
	movfw multiplier		; just one cycle per part of period
	movwf period
modulate_period_delay_loop:
	movlw MODULATE_HOLD_CYCLES
	movwf cycleCount		; hold the modulation for N loops
cycle_delay_loop:
	decfsz cycleCount, F
	goto cycle_delay_loop
	decfsz period, F
	goto modulate_period_delay_loop
; do the next multiplier, or return 
	bcf STATUS, C			; we don't want to roll any value into the first bit position
	rlf multiplier,1
	skpc
	goto modulate_led_loop
	return					; bit rolled off end, we are done since we've gone through all 8 bits

set_led_color:
	decfsz sensorCheckCnt, F
	return
	movlw FADE_CYCLES_BEFORE_SENSOR_CHECK
	movwf sensorCheckCnt
	banksel ADCON0
   	bsf ADCON0,GO          	; start conversion right away
wait_adc_ready
	btfsc ADCON0, NOT_DONE	 
	goto wait_adc_ready
	call test_temp			; load the color for the current temp into W
	movwf gpioState			; save the color LED mask in memory for use later
	return 

test_temp:
	; if either of the high order bits is set, then we are out of range on the hot side
  	banksel ADRESH
	btfsc ADRESH,0
	retlw RED_LED_MASK
	btfsc ADRESH,1
    retlw RED_LED_MASK

	; For some odd reason, the other half of the ADC register is in BANK1
  	banksel ADRESL
	; if ADRESL < ADC_COLD
	movfw ADRESL   
    sublw ADC_COLD
	btfsc STATUS,C
	retlw BLUE_LED_MASK
	; if ADRESL < ADC_COOL
	movfw ADRESL   
    sublw ADC_COOL
	btfsc STATUS,C
	retlw BLUE_LED_MASK | GREEN_LED_MASK
	; if ADRESL < ADC_WARM
	movfw ADRESL   
    sublw ADC_WARM
	btfsc STATUS,C
	retlw GREEN_LED_MASK
	; if ADRESL < ADC_HOT
	movfw ADRESL   
    sublw ADC_HOT
	btfsc STATUS,C
	retlw GREEN_LED_MASK | RED_LED_MASK
	; Default is HOT
	retlw RED_LED_MASK

;-----------------------------------------------------------------------------
; calibrarea oscilator intern
;-----------------------------------------------------------------------------
	org 3FFh
; [34]9Ch for  pic 12F675
	retlw 0x9C	;
;-----------------------------------------------------------------------------
	END                    ; directive 'end of program'
;-----------------------------------------------------------------------------