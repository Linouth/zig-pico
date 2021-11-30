MEMORY {
    ROM(rx) : ORIGIN = 0x00000000, LENGTH = 16k
    CACHE(rwx) : ORIGIN = 0x15000000, LENGTH = 16k
    RAM(rwx) : ORIGIN =  0x20000000, LENGTH = 256k
    SCRATCH_X(rwx) : ORIGIN = 0x20040000, LENGTH = 4k
    SCRATCH_Y(rwx) : ORIGIN = 0x20041000, LENGTH = 4k
}

ENTRY (_entry)

SECTIONS {
    .text : {
        *(.reset.entry)
        *(.reset*)

        . = ALIGN(256);
        __vector_table_start = .;
        KEEP(*(.vector_table))
        __vector_table_end = .;

        *(.text)
        *(.text*)
    } > RAM

    .rodata : {
        *(.rodata*)
    } > RAM

    . = ALIGN(4);
    .data : {
        *(.data*)
    } > RAM

    .bss : {
        . = ALIGN(4);
        __bss_start = .;
        *(.bss*)
        . = ALIGN(4);
        __bss_end = .;
    } > RAM

    /DISCARD/ :
    {
        *(.ARM.exidx)
    }
}

PROVIDE(__stack = ORIGIN(RAM) + LENGTH(RAM));
