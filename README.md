# Rust RealTime Microkernel

## Build

Rust is definitely not a simple language and requires build system with quite a lot of dependencies. Additionally it's built on top of C and does not have its build tools (e.g. own linker) because of which it requires complex toolchains to build. Another interesting aspect is that, similar to C++, the compiler requires certain functions to be linked against, so called lang-items. More on the topic [here](https://manishearth.github.io/blog/2017/01/11/rust-tidbits-what-is-a-lang-item/).These are partially provided by the core crate which is precompiled for most targets, but not for all. The target for which this rt kernel is build (aarch64 freestanding) does not have a core lib provided. That leaves two options, compiling it with rustups nightly `build-std=core` feature or not using it at all. Both of which are not stable. Since this is a personal project I will try to build the kernel without the core lib.
A premiss of mine was not to rely on other build tools such as many other rust kernels do (many use make with rustc for example). Instead the link script is passed to rusts linker via `.cargo/config.toml` (that's also where the target triple is defined). The boot asm is precompiled via. the `build.rs` (which requires an external crate(`cc`)...).

### With Core lib

```rust
#[panic_handler]
fn panic_handler(_info: &core::panic::PanicInfo) -> ! {
    loop {}
}
```

Build: `cargo +nightly build -Z build-std=core`

### Without Core lib

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
Build: `cargo build`

