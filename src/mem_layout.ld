MEMORY {
  BOOT_ROM : ORIGIN = 0x0, LENGTH = 2000
  KERNEL_ROM : ORIGIN = 2000, LENGTH = 102402
  RAM : org = 104402, l = 1M
}

_bootrom_start = ORIGIN(BOOT_ROM);
_bootrom_size = LENGTH(BOOT_ROM);
_bootrom_end = ORIGIN(BOOT_ROM) + LENGTH(BOOT_ROM);
_kernelrom_start = ORIGIN(KERNEL_ROM);
_kernelrom_end = ORIGIN(KERNEL_ROM)+LENGTH(KERNEL_ROM);
_ram_start = ORIGIN(RAM);
_ram_size = LENGTH(RAM);