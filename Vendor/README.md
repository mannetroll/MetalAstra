# Vendored dependencies

No dependency download is needed to build.

- [VkFFT](https://github.com/DTolm/VkFFT), revision `066a17c17068c0f11c9298d848c2976c71fad1c1`, reports version 1.3.4. Headers under `VkFFT/`; MIT license in `VkFFT-LICENSE`.
- [Apple metal-cpp](https://github.com/apple/metal-cpp), revision `27c4382b7151d55a51692cdcb27aaa98752240de`. Headers under `Metal/`, `Foundation/`, `QuartzCore/`; Apache 2.0 license in `metal-cpp-LICENSE.txt`. [Apple's memory management guidance](https://developer.apple.com/metal/cpp/) applies.

## Local VkFFT ownership fixes

Upstream explicitly released objects returned by autoreleasing Metal/Foundation factory methods. Draining the bridge's initialization autorelease pool caused an `objc_release`/`objc_msgSend` crash, reproduced under LLDB on the M1 Max.

The local patch:

1. Uses `NS::String::alloc()->init(...)` for strings that VkFFT explicitly releases.
2. Initializes compile options with `alloc()->init()` and initializes error pointers to null.
3. Removes manual releases of autoreleased command buffers and encoders in upload/download helpers and recursive plan construction. The enclosing bridge autorelease pool releases them.

Files changed: `vkFFT_InitializeApp.h`, `vkFFT_CompileKernel.h`, `vkFFT_ManageMemory.h`, `vkFFT_RecursiveFFTGenerators.h`. Numerical code is unchanged. The bridge suppresses vendored deprecation/integer-conversion compiler diagnostics locally. Test coverage includes repeated plan creation/destruction, resets, FFT transforms, and the complete simulation.

Keep these ownership fixes when updating VkFFT, or verify that upstream has resolved them. Never fix autorelease crashes by leaking a pool for the life of the application.
