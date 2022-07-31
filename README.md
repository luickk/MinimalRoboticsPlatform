# Rust RealTime Microkernel

## Goal

The goal is to build a minimalistic robotic platform for embedded projects. The idea is to enable Rust applications to run on this kernel with std support as well as a kernel provided, robotic specific, toolset. Such a toolset includes communication, control, state handling and other ciritical robotic domains. This would enable a ultra light, simplistic and highly integrated robotic platform.

## Build

Rust is definitely not a simple language and requires build system with quite a lot of dependencies. Additionally it's built on top of C and does not have its build tools (e.g. own linker) because of which it requires complex toolchains to build. Another interesting aspect is that, similar to C++, the compiler requires certain functions to be linked against, so called lang-items. More on the topic can be read [here](https://manishearth.github.io/blog/2017/01/11/rust-tidbits-what-is-a-lang-item/).These are partially provided by the core crate which is precompiled for most targets, but not for all. The target for which this rt kernel is build (`aarch64-unknown-none`) does not have a core lib provided. That leaves two options, compiling it with rustups nightly `build-std=core` feature or not using it at all. Both of which are not stable.
At first I thought I would try to build the kernel without the core lib, but since it's not only core language "features" missing, but important lang_items as well, I decided that it's not worth reimplementing half of the rusts primitive types operations.
A premiss of mine was not to rely on other build tools such as many other rust kernels do (many use make with rustc for example). Instead the link script is passed to rusts linker via `.cargo/config.toml` (that's also where the target triple is defined) and the boot asm is imported from `main.rs`.

I originally wanted to build this project for the a57, but the Core-Lib (or Rust lang) itself does not work on that chip(target triple=`aarch64-unknown-none`). This is not a major suprise since the `build-std` feature(that is require for that target triple, bc there is no precompiled core lib) is unstable. Since I had similar issues with my Zig Kernel project I circumvented this dilemma by switching to the a53 (qemu raspi3b machine) (same target triple).

### With Core lib

`main.rs`
```rust
#[panic_handler]
fn panic_handler(_info: &core::panic::PanicInfo) -> ! {
    loop {}
}
```

`cargo.toml`
```
[package]
build-std= "core"
```

### Without Core lib (not adviced)

`main.rs`
```rust
#![feature(lang_items)]
#![feature(no_core)]
#![no_core]
```
```rust
// lang items required by the compiler
#[lang = "sized"]
pub trait Sized {}
#[lang = "copy"]
pub trait Copy {}
```

