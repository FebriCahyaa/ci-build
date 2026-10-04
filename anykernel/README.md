# Zairenkai AnyKernel3

Vendored AnyKernel3 backend for the Zairenkai kernel CI.

Supported profiles:

- `lavender-4.4` — Linux 4.4, HMP/EAS, legacy + dynamic-partition compatible.
- `lavender-4.19` — Linux 4.19, dynamic-partition compatible.
- `garnet-gki` — Linux 5.10 GKI, A/B boot and dynamic-partition ROM compatible.

Root variants:

- `vanilla`
- `kernelsu-next`
- `resukisu`

The release matrix intentionally uses these three variants. The `kernelsu`
variant remains supported by the shared renderer for compatibility, but is not
part of the default release matrix.

## Local packaging

```bash
./build.sh lavender-4.4 vanilla kernelsu-next resukisu
./build.sh lavender-4.19 vanilla kernelsu-next resukisu
./build.sh garnet-gki vanilla kernelsu-next resukisu
```

Place the compiled kernel image at `images/<variant>/<image>`. The packager is
fail-closed: no kernel image means no ZIP is produced.
