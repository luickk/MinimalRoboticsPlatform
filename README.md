# Embedded Robotics Kernel

## Goal

The goal is to build a minimalistic robotic platform for embedded projects. The idea is to enable applications to run on this kernel with std support as well as a kernel-provided, robotics-specific toolset. Such a toolset includes communication, control, state handling, and other critical robotic domains. This would enable an ultra-light, simplistic and highly integrated robotic platform.
The whole project is designed to support multiple boards, as for example a Raspberry Pi or a NVIDIA Jetson Nano. To begin with, basic kernel features are implemented on a virtual machine (qemu virt armv7).

The end product is meant to be a compromise between a Real Time Operating system and a Microcontroller, to offer the best of both worlds on a modern Soc.

## Why not Rust?

I began this project in Rust but decided to switch to Zig (equally modern). Here is why.
The prime argument for Rust is safety, which is also important for embedded development but has a different nature. The thing is that I very rarely (wrote) saw embedded code that really made use (at least to an extent to which it would be relevant) of Rusts safety. This is due to the fact that embedded code is mostly procedural and linear and not overly complex (opposing to higher level code). Zig on the other hand, is a real improvement compared to Rust because it does not try to solve the problem through abstraction but concepts and rules. I really tried rust at the start of this project. That lead me to this conclusion.

The Rust code can still be found in the separate [rust branch](https://github.com/luickk/rust-rtos/tree/rust_code) and includes a proper Cargo build process(without making use of an external build tools) for the Raspberry, as well as basic serial(with print! macro implementation) and interrupt controller utils.

## Bootloader and kernel separation

Because it simplifies linking and building the kernel as a whole. Linking both the kernel and bootloader is difficult(and error-prone) because it requires the linker to link symbols with VMA offsets that are not supported in size and causes more issues when it comes to relocation of the kernel. 
Both the bootloader and kernel are compiled&linked separately, then their binaries are concatenated(all in build.zig). The bootloader then prepares the exception vectors, mmu, memory drivers and relocates the kernel code.

## MMU

I rewrote a complete mmu "composer" with which one can easily configure the page dir in a simple and readable manner. Currently the composer only supports 4096 granule.

### Qemu Testing

In order to test the bootloader/ kernel, qemu offers `-kernel` but that includes a number of abstractions that are not wanted since I want to keep the development at least somewhat close to a real board. Instead, the booloader (which includes the kernel) is loaded with `-device loader`.

## Implementations

### CPU
#### Interrupt controller

The Raspberry ships with the BCM2835, which is based on the Arm A53 but does not adapt its interrupt controller. More about the BCM2835s ic can be found [here](https://www.raspberrypi.org/app/uploads/2012/02/BCM2835-ARM-Peripherals.pdf)(p109) and [here](https://xinu.cs.mu.edu/index.php/BCM2835_Interrupt_Controller). The [linux driver implementation](https://github.com/torvalds/linux/blob/master/drivers/irqchip/irq-bcm2835.c) comments are also worth looking at.


#### MMU

The best lecture to understand the MMU is probably the [official Arm documentation](https://developer.arm.com/documentation/100940/0101), which does a very good job of explaining the concepts of the mmu.
Since this project requires multiple applications running at the same time, virtual memory is indispensable for safety and performance.

