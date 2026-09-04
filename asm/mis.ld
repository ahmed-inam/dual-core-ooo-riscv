OUTPUT_ARCH("riscv")
ENTRY(_start)
SECTIONS { . = 0x0; .text.init : { *(.text.init) } .text : { *(.text) } . = 0x1000; .bss : { *(.bss) } _stack = 0x2000; }
