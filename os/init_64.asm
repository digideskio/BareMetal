; =============================================================================
; BareMetal -- a 64-bit OS written in Assembly for x86-64 systems
; Copyright (C) 2008-2009 Return Infinity -- see LICENSE.TXT
;
; INIT_64
; =============================================================================

align 16
db 'DEBUG: INIT_64  '
align 16


init_64:
	xor rdi, rdi 			; create the 64-bit IDT (at linear address 0x0000000000000000) as defined by Pure64

	; Create exception gate stubs (Pure64 has already set the correct gate markers)
	mov rcx, 32
make_exception_gate_stubs:
	mov rax, exception_gate
	call create_gate
	dec rcx
	jnz make_exception_gate_stubs

	; Create interrupt gate stubs (Pure64 has already set the correct gate markers)
	mov rcx, 256-32
make_interrupt_gate_stubs:
	mov rax, interrupt_gate
	call create_gate
	dec rcx
	jnz make_interrupt_gate_stubs

	; Set up the exception gates for all of the CPU exceptions
	mov rcx, 20
	xor rdi, rdi
	mov rax, exception_gate_00
make_exception_gates:
	call create_gate
	inc rdi
	add rax, 16			; The exception gates are aligned at 16 bytes
	dec rcx
	jnz make_exception_gates

	; Set up the IRQ handlers
	mov rdi, 0x20
	mov rax, timer
	call create_gate
	mov rdi, 0x21
	mov rax, keyboard
	call create_gate
	mov rdi, 0x22
	mov rax, cascade
	call create_gate
	mov rdi, 0x28
	mov rax, rtc
	call create_gate
	mov rdi, 0x80
	mov rax, ap_wakeup
	call create_gate
	mov rdi, 0x81
	mov rax, ap_call
	call create_gate

	; Set up RTC
	; Rate defines how often the RTC interrupt is triggered
	; Rate is a 4-bit value from 1 to 15. 1 = 32768Hz, 6 = 1024Hz, 15 = 2Hz
	; RTC value must stay at 32.768KHz or the computer will not keep the correct time
	mov al, 0x0a
	out 0x70, al
	mov al, 00101101b ; RTC@32.768KHz (0010), Rate@8Hz (1101)
	out 0x71, al
	mov al, 0x0b
	out 0x70, al
	mov al, 01000010b ; Periodic(6), 24H clock(2)
	out 0x71, al

	; Clear the task data (4096 bytes, each CPU uses 16 bytes)
	mov rdi, taskdata
	mov rax, 0xFFFFFFFFFFFFFFFF
	xor rbx, rbx
	xor rcx, rcx
cleartaskdata:
	stosq
	xchg rax, rbx
	stosq
	xchg rax, rbx
	inc rcx
	cmp rcx, 256
	jne cleartaskdata

	;Grab data from Pure64's infomap
	mov rsi, 0xf000
	xor rax, rax
	lodsd
	mov [os_LocalAPICAddress], rax
	lodsd
	mov [os_IOAPICAddress], rax
	mov rsi, 0xf012
	lodsw
	mov [os_NumCores], ax

	; Initialize all AP's to run our sleep code. Skip the BSP
	xor rax, rax
	xor rcx, rcx
	mov rsi, 0x000000000000F700	; Location in memory of the Pure64 CPU data

next_ap:
	cmp rcx, 128			; enable up to this amount of CPUs
	je no_more_aps
	lodsb				; Load the CPU parameters
	bt rax, 0			; Check if the CPU is enabled
	jnc skip_ap
	bt rax, 1			; test to see if this is the BSP (Do not init!)
	jc skip_ap
	mov rax, rcx
	mov rbx, ap_clear
	call os_smp_call
skip_ap:
	inc rcx
	jmp next_ap

no_more_aps:	

	; Enable specific interrupts
	; To be replaced with IOAPIC instead of PIC.
	in al, 0x21
	mov al, 11111000b		; enable cascade, keyboard, timer
	out 0x21, al
	in al, 0xA1
	mov al, 11111110b		; enable rtc
	out 0xA1, al

	sti				; Re-enable interupts.

ret

; create_gate
; rax = address of handler
; rdi = gate to set up
create_gate:
	push rdi
	push rax
	
	shl rdi, 4	; quickly multiply rdi by 16
	stosw		; store the low word (15..0)
	shr rax, 16
	add rdi, 4	; skip the gate marker
	stosw		; store the high word (31..16)
	shr rax, 32
	stosd		; store the high dword (63..32)

	pop rax
	pop rdi
ret


; =============================================================================
; EOF