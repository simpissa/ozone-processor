ENTRY(start)
SECTIONS {
  . = 0x20000000;
  .text.boot : { *(.text.boot) }
  .exception_vectors : { 
    . = ALIGN(2048);
    *(.exception_vectors)
  }
  .config_data : { 
    . = ALIGN(8);
    _CONFIG_START = .;
    QUAD(0x40f000); /* _SP_EL0 */
    QUAD(0x20100000); /* _SP_EL1 */
    QUAD(0x20000800); /* _VBAR_EL1 */
    QUAD(0x0); /* _SPSR_EL1 */
    QUAD(0x400000); /* _ELR_EL1 */
    QUAD(0x1000); /* _TTBR0_EL1 */
    QUAD(0xdead); /* _TERMINATE_VAL */
    QUAD(0x80); /* _NUM_STACK_PAGES */
  }
  . = 0x400000;
  .text : { *(.text) }
  .data : { *(.data) }
  .bss : { *(.bss) }
}
