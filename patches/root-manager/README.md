# Root-manager integration patches

Provider source is tracked upstream through Git submodules under
`third_party/root-managers/`. Version-specific compatibility patches here are
applied to isolated CI checkouts of those submodules.

No upstream provider source is copied into this repository as a vendored tree.
The `.gitmodules` URLs are the synchronization source of truth.

Linux 4.4 provider series currently include strict compatibility patches for
KernelSU-Next and SukiSU Ultra. ReSukiSU uses the pinned external NonGKI source
hook layer from `patches/upstream/lokitla-nongki/4.4/`.
