# AnyKernel3 ↔ ci-build integration

`anykernel.sh` and `banner` are source templates. `ci-patch.sh` renders them for
one target profile and one root variant immediately before packaging.

## Profiles

| Profile | Kernel | Scheduler model | Dynamic Partition | GKI/A-B |
|---|---|---|---|---|
| `lavender-4.4` | Linux 4.4 | HMP/EAS | supported | legacy |
| `lavender-4.19` | Linux 4.19 | EAS/WALT | required | legacy |
| `garnet-gki` | Linux 5.10 GKI | EAS | required | GKI/A-B |

## Root variants

The release matrix is:

```text
vanilla
kernelsu-next
resukisu
```

`kernelsu` is still accepted by the renderer for older callers, but is not in
the default release matrix.

## Rendering

```bash
./ci-patch.sh --profile lavender-4.4 --variant vanilla --dir .
./ci-patch.sh --profile lavender-4.19 --variant kernelsu-next --dir .
./ci-patch.sh --profile garnet-gki --variant resukisu --dir .
```

The renderer fails when a profile is missing or an `@PLACEHOLDER@` token
remains unresolved.

## Packaging

```bash
./build.sh lavender-4.4 vanilla kernelsu-next resukisu
./build.sh lavender-4.19 vanilla kernelsu-next resukisu
./build.sh garnet-gki vanilla kernelsu-next resukisu
```

The expected image is selected from each profile's `KERNEL_IMAGES` order under
`images/<variant>/`. Packaging is fail-closed: if no accepted kernel image is
found, the ZIP is not created. Every generated ZIP is checked with `unzip -t`.

## CI ownership

The source of truth for target selection is `ci-build/profiles/targets/` and
for flash metadata it is `anykernel/profiles/`. Do not create another target
registry inside workflow files.
