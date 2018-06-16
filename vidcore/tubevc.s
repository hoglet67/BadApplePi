#-------------------------------------------------------------------------
# VideoCore IV implementation of Bad Apple Pi
#-------------------------------------------------------------------------

# on entry
# GPIO pins setup by arm
# Addresses passed into vc are VC based
# gpfsel_data_idle setup

#  r0 - _bad_apple_start
#  r1 - _bad_apple_end
#  r2 - unused (was tube_delay)
#  r3 - debug pin mask (0 = no debug  xx= debug pin e.g 1<<21)

# Intenal register allocation
#  r0 - pointer to memory
#  r1 - delay counter
#  r2 - tube-delay
#  r3 - debug pin mask (0 = no debug  xx= debug pin e.g 1<<21)
#  r4 - scratch - formatted data
#  r5 - memory data
#  r6 - memory data one ahead
#  r7 - scratch register
#  r8 - GPFSEL0 constant
#  r9 - (0xF<<D0D3_shift) + (0xF<<D4D7_shift) constant
# r10 - data bus driving values idle
# r11 - data bus driving values idle
# r12 - data bus driving values idle
# r13 - data bus driving values
# r14 - data bus driving values
# r15 - data bus driving values
# r16 - _bad_apple_start
# r17 - _bad_apple_end

# GPIO registers
.equ GPFSEL0,       0x7e200000
.equ GPSET0_offset, 0x1C
.equ GPCLR0_offset, 0x28
.equ GPLEV0_offset, 0x34

# fixed pin bit positions
.equ nTUBE,        17
.equ RnW,          18
.equ CLK,           7
.equ D0D3_shift,    8
.equ D4D7_shift,   22

.equ D7_PIN,       (25)     # C2
.equ D6_PIN,       (24)     # C2
.equ D5_PIN,       (23)     # C2
.equ D4_PIN,       (22)     # C2
.equ D3_PIN,       (11)     # C1
.equ D2_PIN,       (10)     # C1
.equ D1_PIN,       (9)      # C0
.equ D0_PIN,       (8)      # C0

.equ MAGIC_C0,     ((1 << (D0_PIN * 3)) | (1 << (D1_PIN * 3)))
.equ MAGIC_C1,     ((1 << ((D2_PIN - 10) * 3)) | (1 << ((D3_PIN - 10) * 3)))
.equ MAGIC_C2,     ((1 << ((D4_PIN - 20) * 3)) | (1 << ((D5_PIN - 20) * 3)))
.equ MAGIC_C3,     ((1 << ((D6_PIN - 20) * 3)) | (1 << ((D7_PIN - 20) * 3)))

.org 0

   di

# In the ARM version, halting vidcore removes the long tail from DRAM accesses
#
#hang:
#   b hang

   # Save _bad_apple_start and _bad_apple_end
   mov    r16, r0
   mov    r17, r1
   rsb    r2, 40

   # Set up constands in r9..r15

   mov    r9, (0xF<<D0D3_shift) + (0xF<<D4D7_shift) # all the databus
   or     r9, r3       # add in test pin so that it is cleared at the end of the access

   # read GPIO registers to capture the bus idle state
   mov    r8, GPFSEL0
   ld     r10,  (r8)
   ld     r11, 4(r8)
   ld     r12, 8(r8)
   # setup the databus drive states
   mov    r13, MAGIC_C0
   mov    r14, MAGIC_C1
   mov    r15, MAGIC_C2 | MAGIC_C3
   or     r13, r10
   or     r14, r11
   or     r15, r12

restart:

# stop driving databus
   st     r10, (r8)  # Stop Driving data bus
   st     r11, 4(r8)
   st     r12, 8(r8)
   st     r9, GPCLR0_offset(r8)

# preload first byte of data
   mov    r0, r16
   ldb    r5, (r0)
   add    r0, 1

load_loop:

   # preload next byte of data
   ldb    r6, (r0)
   add    r0, 1

   # map the data to the appropriate GPIO bits
   lsl    r4, r5, 28
   lsr    r4, 28-D0D3_shift
   lsr    r5, 4
   lsl    r5, D4D7_shift
   or     r5, r4
   # Write word to data bus (not yet output-enabled)
   st     r5, GPSET0_offset(r8)

tube_loop:

rd_wait_for_clk_high:
   ld     r7, GPLEV0_offset(r8)
   btst   r7, CLK
   beq    rd_wait_for_clk_high
   ld     r7, GPLEV0_offset(r8)
   btst   r7, CLK
   beq    rd_wait_for_clk_high

   btst   r7, nTUBE
   bne    not_tube_access

   btst   r7, RnW
   beq    restart

# start driving the data bus

   st     r13, (r8)              # Drive data bus
   st     r14, 4(r8)             # Drive data bus
   st     r15, 8(r8)             # Drive data bus
   st     r3, GPSET0_offset(r8)

rd_wait_for_clk_low1:
   ld     r7, GPLEV0_offset(r8)
   btst   r7, CLK
   bne    rd_wait_for_clk_low1

# stop driving databus
   st     r10, (r8)  # Stop Driving data bus
   st     r11, 4(r8)
   st     r12, 8(r8)
   st     r9, GPCLR0_offset(r8)

   mov    r5, r6

   b    load_loop


not_tube_access:

rd_wait_for_clk_low2:
   ld     r7, GPLEV0_offset(r8)
   btst   r7, CLK
   bne    rd_wait_for_clk_low2

   b    tube_loop

## poll for nTube being low
#poll_loop:
#   mov    r1, r2
#poll_tube_low:
#   ld     r7, GPLEV0_offset(r8)
#   btst   r7, nTUBE
#   bne    poll_tube_low
#
#.rept 40
#   addcmpbeq r1,1,41,delay_done
#.endr
#
#delay_done:
#   ld     r7, GPLEV0_offset(r8)  # check ntube again to remove glitches
#   btst   r7, nTUBE
#   bne    poll_loop
