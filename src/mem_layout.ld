MEMORY {
  BOOT_ROM : ORIGIN = 0x0, LENGTH = 502404
  KERNEL_ROM : ORIGIN = 502404, LENGTH = 502404
  RAM : org = 1004808, l = 1M
}

_bootrom_start = ORIGIN(BOOT_ROM);
_bootrom_size = LENGTH(BOOT_ROM);
_bootrom_end = ORIGIN(BOOT_ROM) + LENGTH(BOOT_ROM);
_kernelrom_start = ORIGIN(KERNEL_ROM);
_kernelrom_end = ORIGIN(KERNEL_ROM)+LENGTH(KERNEL_ROM);
_ram_start = ORIGIN(RAM);
_ram_size = LENGTH(RAM);