.macro setup_mmu
    bl  __create_page_tables

    mov x0, vaStart           
    add sp, x0, lowMemory

    adrp    x0, pg_dir              
    msr ttbr1_el1, x0

    ldr x0, =(tcrValue)        
    msr tcr_el1, x0

    ldr x0, =(mairValue)
    msr mair_el1, x0    
.endm

.macro create_pgd_entry, tbl, virt, tmp1, tmp2
    create_table_entry \tbl, \virt, pgdShift, \tmp1, \tmp2
    create_table_entry \tbl, \virt, pudShift, \tmp1, \tmp2
.endm

.macro create_table_entry, tbl, virt, shift, tmp1, tmp2
    lsr \tmp1, \virt, \shift
    and \tmp1, \tmp1, ptrsPerTable - 1           // table index
    add \tmp2, \tbl, pageSize
    orr \tmp2, \tmp2, mmTypePageTable   
    str \tmp2, [\tbl, \tmp1, lsl #3]
    add \tbl, \tbl, pageSize                  // next level table page
.endm

.macro create_block_map, tbl, phys, start, end, flags, tmp1
    lsr \start, \start, sectionShift
    and \start, \start, ptrsPerTable - 1         // table index
    lsr \end, \end, sectionShift
    and \end, \end, ptrsPerTable - 1             // table end index
    lsr \phys, \phys, sectionShift
    mov \tmp1, \flags
    orr \phys, \tmp1, \phys, lsl sectionShift         // table entry
9999:   str \phys, [\tbl, \start, lsl #3]               // store the entry
    add \start, \start, #1                  // next entry
    add \phys, \phys, sectionSize             // next block
    cmp \start, \end
    b.ls    9999b
.endm

__create_page_tables:
    mov x29, x30 // save return address

    adrp x0, pg_dir
    mov x1, pgDirSize
    bl  memzero

    adrp    x0, pg_dir
    mov x1, vaStart 
    create_pgd_entry x0, x1, x2, x3

    /* Mapping kernel and init stack*/
    mov x1, xzr // start mapping from physical offset 0
    mov x2, vaStart // first virtual address
    ldr x3, =(vaStart + deviceBase - sectionSize) // last virtual address
    create_block_map x0, x1, x2, x3, mmuFlags, x4

    /* Mapping device memory*/
    mov x1, deviceBase // start mapping from device base address 
    ldr x2, =(vaStart + deviceBase) // first virtual address
    ldr x3, =(vaStart + physMemorySize - sectionSize) // last virtual address
    create_block_map x0, x1, x2, x3, mmuDeviceFlags, x4

    mov x30, x29 // restore return address
    ret
