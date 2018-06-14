#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <inttypes.h>
#include "tube-defs.h"
#include "tube.h"
#include "tube-ula.h"
#include "startup.h"
#include "rpi-aux.h"
#include "cache.h"
#include "performance.h"
#include "info.h"
#include "rpi-gpio.h"

#ifdef INCLUDE_DEBUGGER
#include "cpu_debug.h"
#endif

typedef void (*func_ptr)();

extern int test_pin;

#include "copro-65tube.h"

#ifdef DEBUG
static const char * emulator_names[] = {
   "65C02 (65tube)"
};
#endif

static const func_ptr emulator_functions[] = {
   copro_65tube_emulator
};

volatile unsigned int copro;
volatile unsigned int copro_speed;
volatile unsigned int copro_memory_size = 0;
unsigned int tube_delay = 0;

int arm_speed;

static func_ptr emulator;

// This magic number come form cache.c where we have relocated the vectors to 
// Might be better to just read the vector pointer register instead.
#define SWI_VECTOR (HIGH_VECTORS_BASE + 0x28)
#define FIQ_VECTOR (HIGH_VECTORS_BASE + 0x3C)

unsigned char * copro_mem_reset(int length)
{
     // Wipe memory
     // Memory starts at zero now vectors have moved.
   unsigned char * mpu_memory = 0;  
#pragma GCC diagnostic ignored "-Wnonnull"   
   memset(mpu_memory, 0, length);
#pragma GCC diagnostic pop   
   // return pointer to memory
   return mpu_memory;
}

void init_emulator() {
   _disable_interrupts();
   
      // Set up FIQ handler 
   
   tube_irq = 0; // Make sure everything is clear
   *((uint32_t *) FIQ_VECTOR) = (uint32_t) arm_fiq_handler_flag1;
   
   // Direct Mail box to FIQ handler
   
   (*(volatile uint32_t *)MBOX0_CONFIG) = MBOX0_DATAIRQEN;
   (*(volatile uint32_t *)FIQCTRL) = 0x80 +65;       
   

#ifndef MINIMAL_BUILD
   if (copro == COPRO_ARMNATIVE) {
      *((uint32_t *) SWI_VECTOR) = (uint32_t) copro_armnative_swi_handler;
      *((uint32_t *) FIQ_VECTOR) = (uint32_t) copro_armnative_fiq_handler;
   }
#endif

   copro &= 127 ; // Clear top bit which is used to signal full reset 
   // Make sure that copro number is valid
   if (copro >= sizeof(emulator_functions) / sizeof(func_ptr)) {
      LOG_DEBUG("using default co pro\r\n");
      copro = DEFAULT_COPRO;
   }

   LOG_DEBUG("Raspberry Pi Direct %u %s Client\r\n", copro,emulator_names[copro]);

   emulator = emulator_functions[copro];

#ifdef INCLUDE_DEBUGGER
   // reinitialize the debugger as the Co Pro has changed
   debug_init();
#endif
   
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

   do {
      // Run the emulator
      emulator();

      // Reload the emulator as copro may have changed
      init_emulator();
     
   } while (1);
}

static void start_core(int core, func_ptr func) {
   LOG_DEBUG("starting core %d\r\n", core);
   *(unsigned int *)(0x4000008C + 0x10 * core) = (unsigned int) func;
}
#endif


static unsigned int get_copro_number() {
   unsigned int copro = DEFAULT_COPRO;
   char *copro_prop = get_cmdline_prop("copro");
   
   if (copro_prop) {
      copro = atoi(copro_prop);
   }
   if (copro >= sizeof(emulator_functions) / sizeof(func_ptr)){
      copro = DEFAULT_COPRO;
   }
   return copro;
}

static void get_copro_speed() {
   char *copro_prop = get_cmdline_prop("copro1_speed");
   copro_speed = 3; // default to 3MHz 
   if (copro_prop) {
      copro_speed = atoi(copro_prop);
   }
   if (copro_speed > 255){
      copro_speed = 0;
   }
   LOG_DEBUG("emulator speed %u\r\n", copro_speed);
   if (copro_speed !=0)
      copro_speed = (arm_speed/(1000000/256) / copro_speed);
}

static void get_copro_memory_size() {
   char *copro_prop = get_cmdline_prop("copro13_memory_size");
   copro_memory_size = 0; // default 
   if (copro_prop) {
      copro_memory_size = atoi(copro_prop);
   }
   if (copro_memory_size > 32*1024 *1024){
      copro_memory_size = 0;
   }
   LOG_DEBUG("Copro Memory size %u\r\n", copro_memory_size);
}

static void get_tube_delay() {
   char *copro_prop = get_cmdline_prop("tube_delay");
   tube_delay = 0; // default 
   if (copro_prop) {
      tube_delay = atoi(copro_prop);
   }
   if (tube_delay > 40){
      tube_delay = 40;
   }
   LOG_DEBUG("Tube ULA sample delay  %u\r\n", tube_delay);
}


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

   arm_speed = get_clock_rate(ARM_CLK_ID);
   get_tube_delay();
   start_vc_ula();

   copro = get_copro_number();
   get_copro_speed();
   get_copro_memory_size();
   
   
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

  RPI_GpioBase->GPSET0 = (1 << test_pin);

  do {
     // Run the emulator
     emulator();

     // Reload the emulator as copro may have changed
     init_emulator();
     
  } while (1);
  
}
