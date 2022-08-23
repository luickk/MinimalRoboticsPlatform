MEMORY {
  BOOT_ROM (rx) : ORIGIN = 0x0, LENGTH = 102048
  KERNEL_ROM (rx) : ORIGIN = 0x18ea0, LENGTH = 102048
  RAM (!rx) : org = 0x31d40, l = 1M
}

_bootrom_start = ORIGIN(BOOT_ROM);
_bootrom_size = LENGTH(BOOT_ROM);
_bootrom_end = ORIGIN(BOOT_ROM) + LENGTH(BOOT_ROM);
_kernelrom_start = ORIGIN(KERNEL_ROM);
_ram_start = ORIGIN(RAM);
_ram_size = LENGTH(RAM);