.text

.global arm_irq_handler
.global arm_fiq_handler

arm_fiq_handler:
arm_irq_handler:
      subs    pc, lr, #4
