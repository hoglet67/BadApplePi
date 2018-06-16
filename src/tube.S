#include "tube-defs.h"

.text

.global arm_irq_handler
.global arm_fiq_handler
.global gpfsel_data_idle
.global gpfsel_data_driving
.global tube


#define OFFSET_GPLEV0   (GPLEV0 - GPBASE)
#define OFFSET_GPSET0   (GPSET0 - GPBASE)
#define OFFSET_GPCLR0   (GPCLR0 - GPBASE)
#define OFFSET_GPFSEL0  (GPFSEL0 - GPBASE)


.macro WAIT_FOR_PHI2_LOW
wait_for_phi2_low\@:
        ldr     r9, [r8, #OFFSET_GPLEV0]
        tst     r9, #PHI2_MASK
        bne     wait_for_phi2_low\@
.endm

.macro WAIT_FOR_PHI2_HIGH
wait_for_phi2_high\@:
        ldr     r9, [r8, #OFFSET_GPLEV0]
        tst     r9, #PHI2_MASK
        beq     wait_for_phi2_high\@
.endm

arm_fiq_handler:
arm_irq_handler:
      subs    pc, lr, #4

   // register usage
   // r0  = memory address
   // r1  = unused
   // r2  = constant: gpfsel_data_driving[0]
   // r3  = constant: gpfsel_data_driving[1]
   // r4  = constant: gpfsel_data_driving[2]
   // r5  = constant: gpfsel_data_idle[0]
   // r6  = constant: gpfsel_data_idle[1]
   // r7  = constant: gpfsel_data_idle[2]
   // r8  = constant: GPBASE
   // r9  = register read data
   // r10 = memory data
   // r11 = working
   // r12 = constant: (0xF<<D0D3_shift) + (0xF<<D4D7_shift) constant

tube:

        // Save the address of the performance counters
        ldr     r11, =pct
        str     r2, [r11]

restart:

        // Print performance counters
#if 0
        push    {r0-r3}
        ldr     r0, =pct
        ldr     r0, [r0]
        bl      read_performance_counters
        pop     {r0-r3}
        ldr     r0, =pct
        ldr     r0, [r0]
        bl      print_performance_counters
        pop     {r0-r3}
        push    {r0-r3}
        ldr     r0, =pct
        ldr     r0, [r0]
        bl      reset_performance_counters
        pop     {r0-r3}
#endif

        // Warm up the TLB
        ldr     r0, =_binary_bad_apple_bin_start
        ldr     r1, =_binary_bad_apple_bin_end
tlb_loop:
        ldr     r2, [r0]
        add     r0, r0, #0x00100000
        cmp     r0, r1
        blt     tlb_loop

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

        // Start of the video data
        ldr     r0, =_binary_bad_apple_bin_start

        // Place the data bus in the idle state
        str     r5,  [r8, #OFFSET_GPFSEL0 + 0]
        str     r6,  [r8, #OFFSET_GPFSEL0 + 4]
        str     r7,  [r8, #OFFSET_GPFSEL0 + 8]
        str     r12, [r8, #OFFSET_GPCLR0]

        // load the first byte to be output
        ldrb    r10, [r0], #1

        mov     lr, #TEST_MASK

load_loop:

        // pre-load the next byte to be output
        ldrb    r1, [r0], #1

        // map the data to the appropriate GPIO bits
        mov     r11, r10, LSL #D0_BASE
        orr     r11, r10, LSL #D4_BASE-4
        and     r10, r11, r12
        str     r10, [r8, #OFFSET_GPSET0]

tube_loop:
        WAIT_FOR_PHI2_HIGH

        tst     r9, #NTUBE_MASK         // test for nTube going low
        beq     tube_access

        WAIT_FOR_PHI2_LOW

        b       tube_loop

tube_access:

        tst     r9, #RNW_MASK           // reset on writes
        beq     restart

        // start driving the data bus
        str     r2, [r8, #OFFSET_GPFSEL0 + 0]
        str     r3, [r8, #OFFSET_GPFSEL0 + 4]
        str     r4, [r8, #OFFSET_GPFSEL0 + 8]
        str     lr, [r8, #OFFSET_GPSET0]

        WAIT_FOR_PHI2_LOW

        // stop driving the data bus
        str     lr,  [r8, #OFFSET_GPCLR0]
        str     r7,  [r8, #OFFSET_GPFSEL0 + 8]
        str     r6,  [r8, #OFFSET_GPFSEL0 + 4]
        str     r5,  [r8, #OFFSET_GPFSEL0 + 0]
        str     r12, [r8, #OFFSET_GPCLR0]

        // transfer over the pre-loaded value
        mov     r10, r1
        b       load_loop

// Some constants for controlling the data bus
gpfsel_data_idle:
        .word 0
        .word 0
        .word 0

gpfsel_data_driving:
        .word 0
        .word 0
        .word 0

pct:
        .word 0



lock_page_table:
    // clean and invalidate the entire data cache (page 3-74)
    mov         r0, #0
    mcr         p15, 0, r0, c7, c14, 0

    // data synchronization barrier to ensure all outstanding memory transactions are complete
    mov         r0, #0
    mcr         p15, 0, r0, c7, c10, 4

    // enable d-cache way 0, lock ways 1, 2, 3 (page 3-89)
    mov         r0, #0xfffffffe
    mcr         p15, 0, r0, c9, c0, 0

    // touch the first 256 page table entries (256MB)
    ldr        r0, =PageTable
    mov        r1, #0x100
lock_loop:
    ldr        r2, [r0], #4
    add        r3, r3, r2
    subs       r1, r1, #1
    bne        lock_loop

    // data synchronization barrier to ensure all outstanding memory transactions are complete
    mov        r0, #0
    mcr        p15, 0, r0, c7, c10, 4

    // lock d-cache way 0, enable ways 1, 2, 3 (page 3-89)
    mov        r0, #0xfffffff1
    mcr        p15, 0, r0, c9, c0, 0

    mov        pc, lr


.data
.global _binary_bad_apple_bin_start
.global _binary_bad_apple_bin_end
.align 12
_binary_bad_apple_bin_start:
.incbin "../bad_apple.bin"
_binary_bad_apple_bin_end:
