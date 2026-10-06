#!/usr/bin/env bash
# Offline Zairenkai integration test: setup wiring, manual hooks, Kconfig and license embedding.
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/lib/common.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

KERNEL="$TMP/kernel"
mkdir -p "$KERNEL/drivers" "$KERNEL/fs" "$KERNEL/include/linux" "$KERNEL/kernel/sched" "$KERNEL/out"
cat > "$KERNEL/drivers/Makefile" <<'EOF'
obj-y += existing/
EOF
cat > "$KERNEL/drivers/Kconfig" <<'EOF'
menu "Device Drivers"
source "drivers/existing/Kconfig"
endmenu
EOF
cat > "$KERNEL/fs/exec.c" <<'EOF'
#include <linux/pipe_fs_i.h>
#include <linux/oom.h>
#include <linux/compat.h>
#include <linux/vmalloc.h>

#include <linux/uaccess.h>
#include <asm/mmu_context.h>
#include <asm/tlb.h>

static int __do_execve_file(void)
{
	int retval;
	struct linux_binprm *bprm = 0;
	if (bprm->argc == 0) {
		const char *argv[] = { "", NULL };
		retval = copy_strings_kernel(1, argv, bprm);
		if (retval < 0)
			goto out;
		bprm->argc = 1;
	}

	retval = exec_binprm(bprm);
	if (retval < 0)
		goto out;
out:
	return retval;
}
EOF
cat > "$KERNEL/kernel/sched/core.c" <<'EOF'
#include "sched.h"

#include "pelt.h"
#include "walt.h"

#define CREATE_TRACE_POINTS
#include <trace/events/sched.h>

void wake_up_new_task(struct task_struct *p)
{
	struct rq_flags rf;
	struct rq *rq;

	add_new_task_to_grp(p);
	raw_spin_lock_irqsave(&p->pi_lock, rf.flags);

	p->state = TASK_RUNNING;
}
EOF

git -C "$KERNEL" init -q
git -C "$KERNEL" config user.email test@example.invalid
git -C "$KERNEL" config user.name test
git -C "$KERNEL" add .
git -C "$KERNEL" commit -q -m seed

Z="$KERNEL/Zairenkai"
mkdir -p "$Z/kernel/hooks/manual" "$Z/kernel/license"
cat > "$Z/kernel/Kconfig" <<'EOF'
menuconfig ZKFC
	tristate "ZKFC"
if ZKFC
choice
	prompt "ZKFC hook mode"
	default ZKFC_HOOK_NONE
config ZKFC_HOOK_MANUAL
	bool "Manual"
config ZKFC_HOOK_NONE
	bool "None"
endchoice
config ZKFC_LICENSEE_TAG
	string "Kernel binding tag"
endif
EOF
cat > "$Z/kernel/Makefile" <<'EOF'
obj-$(CONFIG_ZKFC) += zkfc.o
EOF
cat > "$Z/kernel/hooks/manual/zkfc_hooks.h" <<'EOF'
/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef _LINUX_ZKFC_HOOKS_H
#define _LINUX_ZKFC_HOOKS_H
struct task_struct;
#if defined(CONFIG_ZKFC) && defined(CONFIG_ZKFC_HOOK_MANUAL)
void zkfc_on_exec(const char *filename);
void zkfc_on_new_task(struct task_struct *p);
#define ZKFC_HOOK_EXEC(filename)	zkfc_on_exec(filename)
#define ZKFC_HOOK_NEW_TASK(p)		zkfc_on_new_task(p)
#else
#define ZKFC_HOOK_EXEC(filename)	do { } while (0)
#define ZKFC_HOOK_NEW_TASK(p)	do { } while (0)
#endif
#endif
EOF
cat > "$Z/kernel/setup.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(pwd)"
DRIVERS="$ROOT/drivers"
ln -sfn ../Zairenkai/kernel "$DRIVERS/zkfc"
printf '%s\n' 'obj-$(CONFIG_ZKFC) += zkfc/' >> "$DRIVERS/Makefile"
printf '%s\n' 'source "drivers/zkfc/Kconfig"' >> "$DRIVERS/Kconfig"
EOF
chmod +x "$Z/kernel/setup.sh"
cat > "$KERNEL/out/.config" <<'EOF'
CONFIG_CPU_FREQ=y
CONFIG_INPUT=y
# CONFIG_ZKFC is not set
# CONFIG_ZKFC_HOOK_MANUAL is not set
EOF

printf '%s\n' "$(printf '0x%02x, ' {0..199})" > "$TMP/license.inc"
export SOURCE_DIR="$KERNEL" DEVICE=lavender KERNEL_VERSION=4.19
export ZAIRENKAI=true ZAIRENKAI_REPO="file://$Z" ZAIRENKAI_REF=local-test-ref
export ZAIRENKAI_TAG=zairenkai-sdm660-lavender ZAIRENKAI_HOOK_MODE=manual ZAIRENKAI_LICENSE_INC_FILE="$TMP/license.inc"
export KERNEL_REPO=pix106/android_kernel_xiaomi_sdm660_southwest-ng PATCH_PROFILE=none UPSTREAM_PROFILE=none ROOT_MANAGER=none
export KERNEL_OUT="$KERNEL/out" LTO_PLUS=false ENABLE_SUSFS=false TWEAKS=none

PHASE=source bash "$ROOT/scripts/apply_patch_series.sh"
[[ -L "$KERNEL/drivers/zkfc" ]] || { echo 'FAIL: ZKFC symlink missing' >&2; exit 1; }
PHASE=config bash "$ROOT/scripts/apply_patch_series.sh"
grep -q 'ZKFC_HOOK_EXEC' "$KERNEL/include/linux/zkfc_hooks.h"
grep -q 'ZKFC_HOOK_NEW_TASK' "$KERNEL/include/linux/zkfc_hooks.h"
grep -q 'ZKFC_HOOK_EXEC(bprm->filename);' "$KERNEL/fs/exec.c"
grep -q 'ZKFC_HOOK_NEW_TASK(p);' "$KERNEL/kernel/sched/core.c"
grep -q 'source "drivers/zkfc/Kconfig"' "$KERNEL/drivers/Kconfig"
grep -q 'obj-$(CONFIG_ZKFC)' "$KERNEL/drivers/Makefile"
grep -q '^CONFIG_ZKFC=y$' "$KERNEL/out/.config"
grep -q '^CONFIG_ZKFC_HOOK_MANUAL=y$' "$KERNEL/out/.config"
grep -q '^CONFIG_ZKFC_LICENSEE_TAG="zairenkai-sdm660-lavender"$' "$KERNEL/out/.config"
test "$(grep -oE '0x[0-9A-Fa-f]{2}' "$KERNEL/Zairenkai/kernel/license/zkfc_license.inc" | wc -l | tr -d ' ')" = 200
printf '%s\n' 'PASS Zairenkai integration'
