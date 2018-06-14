#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <inttypes.h>
#include "tube-defs.h"
#include "tube.h"
#include "startup.h"
#include "rpi-aux.h"
#include "cache.h"
#include "performance.h"
#include "info.h"
#include "rpi-gpio.h"

typedef void (*func_ptr)();

int test_pin;

void init_emulator() {
   _disable_interrupts();
   
   LOG_DEBUG("Bad Apple Pi\r\n");
   
   _enable_interrupts();
}

#ifdef HAS_MULTICORE
void run_core() {
   // Write first line without using printf
   // In case the VFP unit is not enabled
#ifdef DEBUG
   int i;
   RPI_AuxMiniUartWrite('C');
   RPI_AuxMiniUartWrite('O');
   RPI_AuxMiniUartWrite('R');
   RPI_AuxMiniUartWrite('E');
   i = _get_core();
   RPI_AuxMiniUartWrite('0' + i);
   RPI_AuxMiniUartWrite('\r');
   RPI_AuxMiniUartWrite('\n');
#endif
   
   enable_MMU_and_IDCaches();
   _enable_unaligned_access();

#ifdef DEBUG   
   LOG_DEBUG("emulator running on core %d\r\n", i);
#endif

   while (1);
}

static void start_core(int core, func_ptr func) {
   LOG_DEBUG("starting core %d\r\n", core);
   *(unsigned int *)(0x4000008C + 0x10 * core) = (unsigned int) func;
}
#endif


static uint32_t host_addr_bus;
static int led_type=0;

void init_hardware()
{

  // early 26pin pins have a slightly different pin out
  
  switch (get_revision())
  {
     case 2 :
     case 3 :   
          // Write 1 to the LED init nibble in the Function Select GPIO
          // peripheral register to enable LED pin as an output
          RPI_GpioBase-> GPFSEL[1] |= 1<<18;
          host_addr_bus = (A2_PIN_26PIN << 16) | (A1_PIN_26PIN << 8) | (A0_PIN_26PIN); // address bus GPIO mapping
          RPI_SetGpioPinFunction(A2_PIN_26PIN, FS_INPUT);
          RPI_SetGpioPinFunction(A1_PIN_26PIN, FS_INPUT);
          RPI_SetGpioPinFunction(A0_PIN_26PIN, FS_INPUT);
          RPI_SetGpioPinFunction(TEST_PIN_26PIN, FS_OUTPUT);
          test_pin = TEST_PIN_26PIN;
        break;
     
         
     default :

          host_addr_bus = (A2_PIN_40PIN << 16) | (A1_PIN_40PIN << 8) | (A0_PIN_40PIN); // address bus GPIO mapping
          RPI_SetGpioPinFunction(A2_PIN_40PIN, FS_INPUT);
          RPI_SetGpioPinFunction(A1_PIN_40PIN, FS_INPUT);
          RPI_SetGpioPinFunction(A0_PIN_40PIN, FS_INPUT); 
          RPI_SetGpioPinFunction(TEST_PIN_40PIN, FS_OUTPUT);
          RPI_SetGpioPinFunction(TEST2_PIN, FS_OUTPUT);
          RPI_SetGpioPinFunction(TEST3_PIN, FS_OUTPUT);
          test_pin = TEST_PIN_40PIN;         
       break;   
  }
  
  switch (get_revision())
  {
     case 2 :
     case 3 :   led_type = 0;
         break;
     case 0xa02082: // Rpi3
     case 0xa22082:
     case 0xa32082:
         led_type = 2;
         break;
     case 0xa020d3 : // rpi3b+
         led_type = 3;
         RPI_GpioBase-> GPFSEL[2] |= 1<<27;
         break;
     default :
               // Write 1 to the LED init nibble in the Function Select GPIO
          // peripheral register to enable LED pin as an output  
          RPI_GpioBase-> GPFSEL[4] |= 1<<21;
          led_type = 1;
         break;
  }        
  
  // Configure our pins as inputs
  RPI_SetGpioPinFunction(D7_PIN, FS_INPUT);
  RPI_SetGpioPinFunction(D6_PIN, FS_INPUT);
  RPI_SetGpioPinFunction(D5_PIN, FS_INPUT);
  RPI_SetGpioPinFunction(D4_PIN, FS_INPUT);
  RPI_SetGpioPinFunction(D3_PIN, FS_INPUT);
  RPI_SetGpioPinFunction(D2_PIN, FS_INPUT);
  RPI_SetGpioPinFunction(D1_PIN, FS_INPUT);
  RPI_SetGpioPinFunction(D0_PIN, FS_INPUT);

  RPI_SetGpioPinFunction(PHI2_PIN, FS_INPUT);
  RPI_SetGpioPinFunction(NTUBE_PIN, FS_INPUT);
  RPI_SetGpioPinFunction(NRST_PIN, FS_INPUT);
  RPI_SetGpioPinFunction(RNW_PIN, FS_INPUT);

  // Initialise the info system with cached values (as we break the GPU property interface)
  init_info();

#ifdef DEBUG
  dump_useful_info();
#endif
  
}

void kernel_main(unsigned int r0, unsigned int r1, unsigned int atags)
{
     // Initialise the UART to 57600 baud
   RPI_AuxMiniUartInit( 115200, 8 );
   enable_MMU_and_IDCaches();
   _enable_unaligned_access();
   init_hardware();
   
#ifdef BENCHMARK
  // Run a short set of CPU and Memory benchmarks
  benchmark();
#endif

#ifdef HAS_MULTICORE
  LOG_DEBUG("main running on core %u\r\n", _get_core());
  start_core(1, _spin_core);
  start_core(2, _spin_core);
  start_core(3, _spin_core);
#endif
  init_emulator();

  while (1);
}
