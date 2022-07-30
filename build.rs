extern crate cc;

fn main() {
    // Use the `cc` crate to build a C file and statically link it.
    cc::Build::new()
        .file("src/boot.s")
        .compile("boot");
}