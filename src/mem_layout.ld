MEMORY {
  ROM (rx)  : ORIGIN = 0x800, LENGTH = 256K
  RAM (!rx) : org = 0x40000000, l = 4M
}

_bootrom_start__ = ORIGIN(ROM);
_bootrom_size__ = LENGTH(ROM);
_ram_start__ = ORIGIN(RAM);
_ram_size__ = LENGTH(RAM);