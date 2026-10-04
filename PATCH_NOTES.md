# Patch Notes — Root Manager Integration Fix 4

## ReSukiSU 4.19 patch format

Fixed malformed unified-diff context lines in the ReSukiSU 4.19 root-manager
patch set. Empty context lines must be represented by a single leading space
inside a unified diff hunk; raw empty lines are rejected by `git apply` as a
corrupt patch.

The same formatting defect was removed from all root-manager patch files found
under `patches/root-manager`, including legacy/non-series compatibility patches.

Validation:

- no root-manager patch reports `corrupt patch`
- ReSukiSU 4.19 policy test passes locally
- AnyKernel render matrix passes locally
- changelog regression passes locally
