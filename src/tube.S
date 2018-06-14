#include "tube-defs.h"

#define A2_MASK (1 << A2_PIN_26PIN)
#define A1_MASK (1 << A1_PIN_26PIN)
#define A0_MASK (1 << A0_PIN_26PIN)
   
.text

.global arm_irq_handler
.global arm_fiq_handler
.global gpfsel_data_idle
.global gpfsel_data_driving
.global tube


arm_fiq_handler:
arm_irq_handler:
      subs    pc, lr, #4


   // register usage
   // r0 = memory address
   // r1 = preload memory address

   // r2  = gpfsel_data_driving[0] 
   // r3  = gpfsel_data_driving[1]
   // r4  = gpfsel_data_driving[2]
   // r5  = gpfsel_data_idle[0] 
   // r6  = gpfsel_data_idle[1] 
   // r7  = gpfsel_data_idle[2] 
   // r8  = GPBASE
   // r9  = register read data
   // r10 = memory data
   // r11 = working
   // r12 = (0xF<<D0D3_shift) + (0xF<<D4D7_shift) constant
   
#define OFFSET_GPLEV0   (GPLEV0 - GPBASE)
#define OFFSET_GPSET0   (GPSET0 - GPBASE)
#define OFFSET_GPCLR0   (GPCLR0 - GPBASE)
#define OFFSET_GPFSEL0  (GPFSEL0 - GPBASE)
   
tube: 

        // Load constants
        ldr     r0, =(gpfsel_data_driving)
        ldr     r2, [r0]
        ldr     r3, [r0, #4]
        ldr     r4, [r0, #8]
        ldr     r0, =(gpfsel_data_idle)
        ldr     r5, [r0]
        ldr     r6, [r0, #4]
        ldr     r7, [r0, #8]
        ldr     r8, =GPBASE
        mov     r12, #D30_MASK
        orr     r12, #D74_MASK




        // Warm up the TLB
        ldr     r0, =_binary_bad_apple_bin_start
tlb_loop:   
        ldr     r1, [r0]
        add     r0, r0, #0x00100000
        cmp     r0, #0x04000000
        blt     tlb_loop

   
        // Warm up the cache
        pld     [r0, #0x00]
        pld     [r0, #0x20]
        pld     [r0, #0x40]
        pld     [r0, #0x60]


        // Start of the video data
        ldr     r0, =_binary_bad_apple_bin_start
//        ldr     r0, =test_data
   
   
        // Place the data bus in the idle state
        str     r5,  [r8, #OFFSET_GPFSEL0 + 0]      
        str     r6,  [r8, #OFFSET_GPFSEL0 + 4]
        str     r7,  [r8, #OFFSET_GPFSEL0 + 8]
        str     r12, [r8, #OFFSET_GPCLR0]
   
load_loop:

        //preload next cache line
        pld     [r0, #0x20]   
        ldrb    r10, [r0], #1          // load the next word to be output
   
        //tst     r0, #7
        //subeq   r0, r0, #1
        //biceq   r0, r0, #7

        mov     r11, r10, LSL #D0_BASE  // low nibble now aligned to GPIO
        and     r11, r11, #D30_MASK
        mov     r10, r10, LSL #D4_BASE-4
        and     r10, r10, #D74_MASK     // high nibble in the right place
        orr     r10, r10, r11
        str     r10, [r8, #OFFSET_GPSET0]

//rd_wait_for_phi2_low:
//        ldr     r9, [r8, #OFFSET_GPLEV0]
//        tst     r9, #PHI2_MASK
//        bne     rd_wait_for_phi2_low

        // wait for phi2 to go high
rd_wait_for_phi2_high:
        ldr     r9, [r8, #OFFSET_GPLEV0]
        tst     r9, #PHI2_MASK
        beq     rd_wait_for_phi2_high

        tst     r9, #NTUBE_MASK         // test for nTube going low
        bne     rd_wait_for_phi2_low2  

        tst     r9, #RNW_MASK           // reset on writes
        beq     tube
   
        // start driving the data bus
        str     r2, [r8, #OFFSET_GPFSEL0 + 0]
        str     r3, [r8, #OFFSET_GPFSEL0 + 4]
        str     r4, [r8, #OFFSET_GPFSEL0 + 8]

        // wait for phi2 to fall
rd_wait_for_phi2_low:
        ldr     r9, [r8, #OFFSET_GPLEV0]
        tst     r9, #PHI2_MASK
        bne     rd_wait_for_phi2_low

        // stop driving the data bus
        str     r5,  [r8, #OFFSET_GPFSEL0 + 0]      
        str     r6,  [r8, #OFFSET_GPFSEL0 + 4]
        str     r7,  [r8, #OFFSET_GPFSEL0 + 8]
        str     r12, [r8, #OFFSET_GPCLR0]
   
        b       load_loop

rd_wait_for_phi2_low2:
        ldr     r9, [r8, #OFFSET_GPLEV0]
        tst     r9, #PHI2_MASK
        bne     rd_wait_for_phi2_low2
        b       rd_wait_for_phi2_high

   
// Some constants for controlling the data bus
gpfsel_data_idle:
        .word 0
        .word 0
        .word 0

gpfsel_data_driving:
        .word 0
        .word 0
        .word 0

        .ltorg

.data
   
.global _binary_bad_apple_bin_start
.global _binary_bad_apple_bin_end

.align 12
test_data:
        .word 0xE04C00A0
        .word 0xFEE04CFE
test_data_end:
   
.align 12

_binary_bad_apple_bin_start:
.incbin "../bad_apple.bin"
_binary_bad_apple_bin_end:

