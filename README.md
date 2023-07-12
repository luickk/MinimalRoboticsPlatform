# Embedded Robotics Kernel

## Goal

The goal is to build a minimalistic robotic platform for embedded projects. The idea is to enable applications to run on this kernel with std support as well as a kernel-provided, robotics-specific toolset. Such a toolset includes communication, control, state handling, and other critical robotic domains. This would enable an ultra-light, simplistic and highly integrated robotic platform.
The whole project is designed to support multiple boards, as for example a Raspberry Pi or a NVIDIA Jetson Nano. To begin with, basic kernel features are implemented on a virtual machine (qemu virt armv7).
The end product is meant to be a compromise between a Real Time Operating system and a Microcontroller, to offer the best of both worlds on a modern Soc.

The idea is that the kernel and its drivers are fixed and generically usable across Arm Socs. The actual user implementation of the projects is meant to happen in `src/environment/*yourCustomEnvironmentName*` where every new dir is a new env. and every environment is built from separately compiled user/ kernel privileged apps. The apps can talk to each other with a variety of kernel provided interfaces, such as topics, services, actions and so on. Since every app is compiled on its own and completely isolated by the kernel, regarding their communications, which is compile time defined, maximum static runtime safety and security should be given.
Thanks to Zigs lazy compilation, driver handlers can be implemented and not be used or replaced, depending on the choice of board.

This project is aiming to build an experience that gives the end user (developer) as much guidance and form as necessary, to build a safe and secure platform, with as much freedom as possible. This is achieved by reducing complex runtime defined communications and allocations to an absolute minimum, whilst also being flexible enough to be used across a number of boards.

## Project Structure

The project aims to give as much guidance to the developer as possible, that also applies to where to put which component of the kernel. In general the projects layout looks like that:

```bash
├── build.zig
├── src/
│    ├── appLib/
│    │    ├── ..
│    │    └── > everything that is linked with userspace apps
│    ├── arm/
│    │    ├── ..
│    │    └── > all the "drivers" required for the arm soc. linked with the kernel
│    ├── boards/
│    │    ├── * contains drivers and board configuration files (qemuVirt.zig, raspi3b.zig..). Which board is compiled can be selected in build.zig, the respective configuration file is then selected and linked. *
│    │    ├── drivers/
│    │    │    ├── > everything that is board specific, timer, irq, io code
│    │    │    ├── bootInit/
│    │    │    │    ├── > board specific startup code that sets up the correct el, exc. vec. table,.. and and calls the bootloader entry fn. linked witht the bootloader
│    │    │    │    ├── qemuVirt_boot.S
│    │    │    │    └── ..
│    │    │    ├── interruptController/
│    │    │    │    ├── > board specific drivers for additional(to the arm gic) interrupt controllers, linked with the kernel
│    │    │    │    ├── bcm2835InterruptController.zig
│    │    │    │    └── ..
│    │    │    └── timer/
│    │    │        ├── > board specific drivers for additional(to the arm gt) timer, linked with the kernel
│    │    │        ├── bcm2835Timer.zig
│    │    │        └── ..
│    │    ├── qemuVirt.zig
│    │    └── ..
│    ├── bootloader/
│    │    ├── bins/ 
│    │    │    └── > the kernels binary (non elf format) is saved here because it is embedded by the bootloader (usings Zigs `@embedFile`) and cannot be placed outside the package path
│    │    ├── ..
│    │    └── > contains everything required to make the bootloader boot the kernel
│    ├── configTemplates/
│    │    ├── ..
│    │    └── > contains all the templates for different configurations. E.g. the board or env. configuration
│    ├── environments/
│    │    ├── > actual development space. Every environment is a set of userspace apps and kernel threads. Only one environment at a time can be compiled. Which environment is compiled can be selected in the build.zig.
│    │    ├── basicKernelFunctionalityTest/
│    │    │    ├── > environment for basic kernel integration tests. In the envConfig.zig everthing environment can be configured. E.g. how many topics, with which buffer type they operate and so on..
│    │    │    ├── envConfig.zig
│    │    │    ├── kernelThreads/
│    │    │    │    ├── > all kernel threads required by the board. E.g. a handler for the additional(or secondary) interrupt controller. linked with the kernel! 
│    │    │    │    ├── threads.zig
│    │    │    │    └── ..
│    │    │    ├── setupRoutines/
│    │    │    │    ├── > setup routines called on kernel entry. E.g. the init of additional interrupt controller handler. linked with the kernel!
│    │    │    │    ├── routines.zig
│    │    │    │    └── ..
│    │    │    └── userApps/
│    │    │        ├── > actual userspace with all the userspace apps. every app is build seperately
│    │    │        ├── _semaphoreTest/ > (apps starting with underscore and not compiled..)
│    │    │        │    ├── linker.ld
│    │    │        │    └── main.zig
│    │    │        └── mutexTest/
│    │    │            ├── linker.ld
│    │    │            └── main.zig
│    │    ├── ..
│    ├── kernel/
│    │    ├── > actual kernel space
│    │    ├── bins/
│    │    │    ├── ..
│    │    │    └── > app binaries are saved here because they are embedded by the kernel (user Zigs `@embedFile`) and cannot be placed outside the package path/
│    │    ├── exc_vec.S
│    │    ├── kernel.zig
│    │    ├── ..
│    │    ├── sharedKernelServices/
│    │    │    ├── SysCallsTopicsInterface.zig
│    │    │    ├── ..
│    │    │    └── > all services that have to be accessed over from the drivers for exampled., linked with the kernel
│    ├── kpi/
│    │    ├── secondaryInterruptControllerKpi.zig
│    │    ├── ..
│    │    └── > kernel programming interface for drivers. e.g. the timer or secondary irq handler driver. inited in the board configuration file
│    ├── periph/
│    │    ├── pl011.zig
│    │    ├── ..
│    │    └── > all the peripheral devices code
│    ├── sharedServices/
│    │    ├── Topic.zig
│    │    ├── ..
│    │    └── > code thats so basic that it's linked with both the kernel and the userspace
│    └── utils
│        └── utils.zig
```
## Why not Rust?

I began this project in Rust but decided to switch to Zig (equally modern). Here is why.
The prime argument for Rust is safety, which is also important for embedded development but has a different nature. The thing is that I very rarely (wrote) saw embedded code that really made use (at least to an extent to which it would be relevant) of Rusts safety. This is due to the fact that embedded code is mostly procedural and linear and not overly complex (opposing to higher level code). Zig on the other hand, is a real improvement compared to Rust because it does not try to solve the problem through abstraction but concepts and rules. I really tried rust at the start of this project. That lead me to this conclusion.

The Rust code can still be found in the separate [rust branch](https://github.com/luickk/rust-rtos/tree/rust_code) and includes a proper Cargo build process(without making use of an external build tools) for the Raspberry, as well as basic serial(with print! macro implementation) and interrupt controller utils.

## Finding the perfect Board 

In order to first boot the kernel on a physical board, I'm searching for the best board. Number one priority is simplicity. The raspberry has a relatively complex multi bootstage process. That is not ideal, includes a file system on an SD Card in is pretty ugly in general.
The Jetson Nano has a similarly complex boot process. 

The Rock Pi on the other hand offer eMMC storage that can be flashed with the Maskrom directly from another device. The Rock Pi eMMC is quite elegant because it does, a) not require a file system, and b) is loaded directly by the arm cores(and not from the GPU as with the raspberry).

## Compatibility

Currently, there is support for the important Arm SOC elements such as the generic timer, interrupt controller as well as the Raspberries BCM2835 secondary interrupt controller and system timer. The project can be configured with ROM relocation and without, so most Arm SOC boards should be compatible at the moment.

## Allocation Policy

Memory allocation is an extremely powerful and basic functionality that can be very dangerous depending on when and how it's used.
For that reason the kernels allocations are only permitted at kernel boot/init time. There is no realloc, neither for userspace apps nor for the kernel. Alternatively, there are reserved memory buffers for every feature. I don't yet have a perfect solution for dealing with an out off memory event though.

There is an app allocation available in user space so that a considered decision can be made and an allocator still be used if the app is not important.

## Kernel wise features

### Topics

A way to share data streams with other processes, similar to pipes but optimized for sensor data and data distribution/ access over many processes.

How many topics and in which configuration must be setup at compiletime in the `envConfig.zig` of the project. Each Topic can be configured in its buffer type, size, identifier and so on. In the runtime phase of the platform, every topic then behaves according to its configuration and can be addressed through its fixed id.

There are two ways to communicate over a Topic, one is through SysCalls and the other is through direct mapped memory, which is very effective but less easy to use. Also, currently both ways of communicating on a Topic must not be mixed so only either one of both can be used.

#### What kind of data is it for?

Topics can be used for all kinds of statically sized data. Depending on the amount of data per time unit, there a re different methods of retrievals. 
- `userSysCallInterface.waitForTopicUpdate(..)` (which leverages a semaphore) can be used to wait for data in a separate thread

Uses sys-calls as interface. Pushes/reads n units of the latest(depending on the buffer type) data
- `userSysCallInterface.popFromTopic(..)` 
- `userSysCallInterface.pushToTopic(..)`

Uses direct mapped memory to read/write to a Topic. Is also bound to all preconfigured parameters including the buffer type.
- `ShareMemTopicsInterface.read(..)` 
- `ShareMemTopicsInterface.write(..)`

### Status Control

A way to centrally communicate state and adapt the system appropriatly. 
Since the status of a sensor, service, io device, or more abstract concepts  is not just a tool but one of the most important control aspects in a robotic system, this funcitonality is deeply integrated and not just meant for state sharing but also as a state machine at the heart of the system.

// todo

### Actions

// todo

# Kernel details

## Bootloader and kernel separation

Because it simplifies linking and building the kernel as a whole. Linking both the kernel and bootloader is difficult(and error-prone) because it requires the linker to link symbols with VMA offsets that are not supported in size and causes more issues when it comes to relocation of the kernel. 
Both the bootloader and kernel are compiled&linked separately, then their binaries are concatenated(all in build.zig). The bootloader then prepares the exception vectors, mmu, memory drivers and relocates the kernel code.

The bootloader is really custom and does a few things differently. One of the primary goals is to keep non static memory allocations to an absolute minimum. This is also true for the stack/ paging tables, which have to be loaded at runtime. At the moment both, bootloader stack and page tables are allocated on the ram, to be more specific in the specified userspace section. This allows to boot from rom(non writable memory...) whilst still supporting boot from ram.

## MMU

I wrote a mmu "composer" with which one can simply configure and then generate/ write the pagetables. The page table generation supports 3 lvls and 4-16k granule. 64k is also possible but another level has to be added to the `TransLvl` enum in `src/board/boardConfig.zig` and it's not fully tested yet.
Ideally I wanted the page tables to be generated at comptime, but in order to have multiple translation levels, the mmu needs absolute physical addresses, which cannot be known at compile time(only relative addresses). Alternatively the memory can be statically reserved and written at runtime, which is not an option for the bootloader though because it is possibly located in rom, and cannot write to statically reserved memory, leaving the only option, allocating the bootloader page table on the ram (together with the stack). The kernel on the other hand could reserve at least the kernel space page tables, since they are static in size, but for consistency reasons kernel and userspace have linker-reserved memory.

### Addresses

The Arm mmu is really powerful and complex in order to be flexible. For this project the mmu is not required to be flexible, but safe and simple. For an embedded robotics platform it's neither required to have a lot of storage, nor to control the granularity in an extremely fine scope since most of the memory is static anyways.

Additionally devices as for example the Raspberry Pi forbid Lvl 0 translation at all since it's 512gb at 4k granule which is unnecessary for such a device.

With those constraints in place, this project only supports translation tables beginning at lvl 1, which is also why, `vaStart` is `0xFFFFFF8000000000`, since that's the lowest possible virtual address in lvl 1.

### Qemu Testing

In order to test the bootloader/ kernel, qemu offers `-kernel` but that includes a number of abstractions that are not wanted since I want to keep the development at least somewhat close to a real board. Instead, the booloader (which includes the kernel) is loaded with `-device loader`.

## Implementations

### CPU
#### Interrupt controller

The Raspberry ships with the BCM2835, which is based on the Arm A53 but does not adapt its interrupt controller. More about the BCM2835s ic can be found [here](https://www.raspberrypi.org/app/uploads/2012/02/BCM2835-ARM-Peripherals.pdf)(p109) and [here](https://xinu.cs.mu.edu/index.php/BCM2835_Interrupt_Controller). The [linux driver implementation](https://github.com/torvalds/linux/blob/master/drivers/irqchip/irq-bcm2835.c) comments are also worth looking at.


#### MMU

The best lecture to understand the MMU is probably the [official Arm documentation](https://developer.arm.com/documentation/100940/0101), which does a very good job of explaining the concepts of the mmu.
Since this project requires multiple applications running at the same time, virtual memory is indispensable for safety and performance.

## Installation

### Dependencies:

- zig (last tested version 0.10.1)
- qemu (for testing)

### Run

- `zig build qemu`
Builds and runs the project. The environment and board as well as all the other parameters for the build can be configured in build.zig
