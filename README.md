# Rust RealTime Microkernel

## Goal

The goal is to build a minimalistic robotic platform for embedded projects. The idea is to enable applications to run on this kernel with std support as well as a kernel provided, robotic specific, toolset. Such a toolset includes communication, control, state handling and other ciritical robotic domains. This would enable a ultra light, simplistic and highly integrated robotic platform.

## Why not Rust?

I began this project in Rust but decided to switch to Zig (equally modern). Here is why.
The prime argument for Rust is safety, that is alsow true when it comes to embedded. The things is that I very rarely (wrote) saw embedded code that really made use (at least to an extend to which it would be relevant) of rusts safety since embedded code is mostly procedural and linear and not overly complex (opposing to higher level code). Zig on the other hand is a real improvement compared to rust bc it does not try to solve the problem through abstraction but concepts. I really tried rust in the beginning phase of this project which lead me to this conclusion.

The Rust code can still be found in the seperate [rust branch](https://github.com/luickk/rust-rtos/tree/rust_code) and includes a proper Cargo build process(without making use of an external build tool) for the raspberry, as well as basic serial(with print! macro implementation) and interrupt controller utils.

## Implementations

### CPU
#### Interrupt controller

The Raspberry ships with the BCM2835 which is based on an Arm A53 but does not adapt its interrupt controller. More about the BCM2835s ic can be found [here](https://www.raspberrypi.org/app/uploads/2012/02/BCM2835-ARM-Peripherals.pdf)(p109) and [here](https://xinu.cs.mu.edu/index.php/BCM2835_Interrupt_Controller). The [linux driver implementation](https://github.com/torvalds/linux/blob/master/drivers/irqchip/irq-bcm2835.c) comments is also worth looking at.


