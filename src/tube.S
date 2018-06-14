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


tube: 

   

loop:

        ldr     r8, =GPLEV0
   
        ldr     r9, [r8]
        tst     r9, #NTUBE_MASK         // test for nTube going low
        bne     loop

        ldr     r9, [r8]
        tst     r9, #NTUBE_MASK         // test again for glitches
        bne     loop
   
        tst     r9, #RNW_MASK           // ignore writes
        beq     loop

// READ_CYCLE
        mov     r10, #0
        tst     r9, #A0_MASK
        orrne   r10, #1
        tst     r9, #A1_MASK
        orrne   r10, #2
        tst     r9, #A2_MASK
        orrne   r10, #4

        // for now return r10  

        mov     r11, r10, LSL #D0_BASE  // low nibble now aligned to GPIO
        and     r11, r11, #D30_MASK
        mov     r10, r10, LSL #D4_BASE-4
        and     r10, r10, #D74_MASK      // high nibble in the right place
        orr     r10, r10, r11

        ldr     r8, =GPSET0
        str     r10, [r8]
        eor     r10, r10, #D30_MASK
        eor     r10, r10, #D74_MASK
        ldr     r8, =GPCLR0
        str     r10, [r8]

        ldr     r8, =GPFSEL0
        ldr     r11, =(gpfsel_data_driving)
        ldr     r10, [r11]
        str     r10, [r8]
        ldr     r10, [r11, #4]
        str     r10, [r8, #4]
        ldr     r10, [r11, #8]
        str     r10, [r8, #8]

        ldr     r8, =GPLEV0

rd_wait_for_phi2_low:
        ldr     r10, [r8]
        tst     r10, #PHI2_MASK
        movne   r9, r10
        bne     rd_wait_for_phi2_low

        ldr     r8, =GPFSEL0
        ldr     r11, =(gpfsel_data_idle)
        ldr     r10, [r11]
        str     r10, [r8]
        ldr     r10, [r11, #4]
        str     r10, [r8, #4]
        ldr     r10, [r11, #8]
        str     r10, [r8, #8]

        b       loop


// Some constants for controlling the data bus
gpfsel_data_idle:
        .word 0
        .word 0
        .word 0

gpfsel_data_driving:
        .word 0
        .word 0
        .word 0


