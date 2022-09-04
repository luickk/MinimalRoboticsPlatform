.section ".text.mmu"

// todo => use linked symbols!!
#define DEVICE_BASE 0x3f000000
#define VA_START 0xffff000000000000

#define PHYS_MEMORY_SIZE  0x40000000  

#define PAGE_MASK 0xfffffffffffff000
#define PAGE_SHIFT 12
#define TABLE_SHIFT  9
#define SECTION_SHIFT (PAGE_SHIFT + TABLE_SHIFT)

#define PAGE_SIZE    (1 << PAGE_SHIFT)   
#define SECTION_SIZE (1 << SECTION_SHIFT)    

#define LOW_MEMORY (2 * SECTION_SIZE)
#define HIGH_MEMORY DEVICE_BASE

#define PAGING_MEMORY (HIGH_MEMORY - LOW_MEMORY)
#define PAGING_PAGES (PAGING_MEMORY/PAGE_SIZE)

#define PTRS_PER_TABLE (1 << TABLE_SHIFT)

#define PGD_SHIFT PAGE_SHIFT + 3*TABLE_SHIFT
#define PUD_SHIFT PAGE_SHIFT + 2*TABLE_SHIFT
#define PMD_SHIFT PAGE_SHIFT + TABLE_SHIFT

#define PG_DIR_SIZE   (3 * PAGE_SIZE)

#define MM_TYPE_PAGE_TABLE 0x3
#define MM_TYPE_PAGE 0x3
#define MM_TYPE_BLOCK 0x1
#define MM_ACCESS (0x1 << 10)
#define MM_ACCESS_PERMISSION  (0x01 << 6) 


#define MMU_FLAGS (MM_TYPE_BLOCK | (MT_NORMAL_NC << 2) | MM_ACCESS)   
#define MMU_DEVICE_FLAGS  (MM_TYPE_BLOCK | (MT_DEVICE_nGnRnE << 2) | MM_ACCESS)   
#define MMU_PTE_FLAGS (MM_TYPE_PAGE | (MT_NORMAL_NC << 2) | MM_ACCESS | MM_ACCESS_PERMISSION) 

#define TCR_T0SZ (64 - 48) 
#define TCR_T1SZ ((64 - 48) << 16)
#define TCR_TG0_4K (0 << 14)
#define TCR_TG1_4K (2 << 30)
#define TCR_VALUE (TCR_T0SZ | TCR_T1SZ | TCR_TG0_4K | TCR_TG1_4K)

/*
 * Memory region attributes:
 *
 *   n = AttrIndx[2:0]
 * n   MAIR
 *   DEVICE_nGnRnE  000 00000000
 *   NORMAL_NC 001 01000100
 */
#define MT_DEVICE_nGnRnE  0x0
#define MT_NORMAL_NC 0x1
#define MT_DEVICE_nGnRnE_FLAGS 0x00
#define MT_NORMAL_NC_FLAGS 0x44
#define MAIR_VALUE (MT_DEVICE_nGnRnE_FLAGS << (8 * MT_DEVICE_nGnRnE)) | (MT_NORMAL_NC_FLAGS << (8 * MT_NORMAL_NC))

.globl memzero
memzero:
    str xzr, [x0], #8
    subs x1, x1, #8
    b.gt memzero
    br lr

.macro create_pgd_entry, tbl, virt, tmp1, tmp2
    create_table_entry \tbl, \virt, PGD_SHIFT, \tmp1, \tmp2
    create_table_entry \tbl, \virt, PUD_SHIFT, \tmp1, \tmp2
.endm

.macro  create_table_entry, tbl, virt, shift, tmp1, tmp2
    lsr \tmp1, \virt, #\shift
    and \tmp1, \tmp1, #PTRS_PER_TABLE - 1           // table index
    add \tmp2, \tbl, #PAGE_SIZE
    orr \tmp2, \tmp2, #MM_TYPE_PAGE_TABLE   
    str \tmp2, [\tbl, \tmp1, lsl #3]
    add \tbl, \tbl, #PAGE_SIZE                  // next level table page
.endm

.macro  create_block_map, tbl, phys, start, end, flags, tmp1
    lsr \start, \start, #SECTION_SHIFT
    and \start, \start, #PTRS_PER_TABLE - 1         // table index

    lsr \end, \end, #SECTION_SHIFT
    and \end, \end, #PTRS_PER_TABLE - 1             // table end index

    lsr \phys, \phys, #SECTION_SHIFT
    mov \tmp1, #\flags
    orr \phys, \tmp1, \phys, lsl #SECTION_SHIFT         // table entry

9999:   str \phys, [\tbl, \start, lsl #3]               // store the entry
    add \start, \start, #1                  // next entry
    add \phys, \phys, #SECTION_SIZE // next block
    cmp \start, \end
    b.ls    9999b
.endm


.globl _init_pt_id_mapped
_init_pt_id_mapped:
    mov x29, x30 // save return address

    adrp    x0, _ttbr0_dir
    mov x1, #PG_DIR_SIZE
    bl  memzero

    adrp    x0, _ttbr0_dir
    mov x1, xzr 
    create_pgd_entry x0, x1, x2, x3

    mov     x1, xzr
    mov     x2, xzr
    // todo => fix; should be working with x3 =0x40000000
    ldr x3, =(VA_START + PHYS_MEMORY_SIZE - SECTION_SIZE)
    create_block_map x0, x1, x2, x3, MMU_FLAGS, x4

    mov x30, x29
    ret

.global _init_pt_higher_mem
_init_pt_higher_mem:
    mov x29, x30                        // save return address

    adrp    x0, _ttbr1_dir
    mov x1, #PG_DIR_SIZE
    bl  memzero

    adrp    x0, _ttbr1_dir
    mov x1, #VA_START 
    create_pgd_entry x0, x1, x2, x3

    /* Mapping kernel and init stack*/
    mov     x1, xzr                         // start mapping from physical offset 0
    mov     x2, #VA_START                       // first virtual address
    ldr x3, =(VA_START + DEVICE_BASE - SECTION_SIZE)        // last virtual address
    create_block_map x0, x1, x2, x3, MMU_FLAGS, x4

    /* Mapping device memory*/
    mov     x1, #DEVICE_BASE                    // start mapping from device base address 
    ldr     x2, =(VA_START + DEVICE_BASE)               // first virtual address
    ldr x3, =(VA_START + PHYS_MEMORY_SIZE - SECTION_SIZE)   // last virtual address
    create_block_map x0, x1, x2, x3, MMU_DEVICE_FLAGS, x4

    mov x30, x29                        // restore return address
    ret