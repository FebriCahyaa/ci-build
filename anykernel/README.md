# Zairenkai AnyKernel3

Vendored AnyKernel3 backend for the Zairenkai kernel CI. `anykernel.sh` and
`banner` are templates rendered by `ci-patch.sh` from `profiles/<profile>.conf`
and the root variant right before packaging.

| Profile | Kernel | Scheduler model | Dynamic partitions | Boot |
|---|---|---|---|---|
| `lavender-4.4` | Linux 4.4 | HMP/EAS | supported | legacy |
| `lavender-4.19` | Linux 4.19 | EAS/WALT | required | legacy |
| `garnet-gki` | Linux 5.10 GKI | EAS | required | A/B, Image only (vendor DTBO untouched) |

Root variants: `vanilla`, `kernelsu`, `kernelsu-next`, `resukisu`,
`sukisu-ultra` (aliases such as `ksun`, `sukisu` are accepted).

## Rendering

```bash
./ci-patch.sh --profile lavender-4.19 --variant kernelsu-next --dir .
```

The renderer fails when a profile is missing or an `@PLACEHOLDER@` token
remains unresolved. Values are inserted literally (`&` is not special).

## Local packaging

Place compiled images at `images/<variant>/<image>` (first match of the
profile's `KERNEL_IMAGES` order wins), then:

```bash
./build.sh lavender-4.4 vanilla kernelsu-next resukisu
./build.sh garnet-gki vanilla sukisu-ultra
```

Packaging is fail-closed: no accepted kernel image means no ZIP. Every ZIP is
checked with `unzip -t`. Target selection is owned by `profiles/targets/` in
ci-build; do not add another registry in workflow files.
