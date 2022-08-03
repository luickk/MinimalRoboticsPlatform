cargo build
#-machine virt -cpu cortex-a57
qemu-system-aarch64 -machine raspi3b -kernel target/aarch64-unknown-none/debug/rust-rtos -serial stdio -display none
