// SPDX-License-Identifier: GPL-2.0-only
/*
 * Copyright (C) 2026 dere3046
 */

/*
 * OPlus scheduler DDL history guard.
 *
 * The vendor source (vendor/oplus/kernel/cpu/sched/sched_assist/sa_ddl.c)
 * declares the table as a static array, not a pointer:
 *
 *     struct ddl_sinfo_data ddl_sdata[PID_MAX_DEFAULT];
 *
 *     void update_ddl_hit_history(struct task_struct *p)
 *     {
 *             ...
 *             ddl_sdata[p->pid].hit++;
 *     }
 *
 * So it cannot be replaced by swapping a pointer; the only thing that can go
 * wrong is the index. If pid_max is above PID_MAX_DEFAULT, or a pid above it
 * was allocated before pid_max was clamped, p->pid runs past the array and the
 * vendor module writes out of bounds. With UBSAN + panic_on_warn that is an
 * immediate reboot, at whatever task happens to be picked next.
 *
 * The guard is a kprobe on the function entry: calls for pid >= PID_MAX_DEFAULT
 * return without running the body, so the out-of-bounds access never happens.
 * Every pid inside the array behaves exactly as before, and the function itself
 * is not modified.
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/kprobes.h>
#include <linux/threads.h>
#include <linux/sched.h>

#include "ddl_hit.h"
#include "hk_kprobe.h"

static bool dlc_ddl_enable = true;
module_param_named(ddl, dlc_ddl_enable, bool, 0444);
MODULE_PARM_DESC(ddl,
	"1 (default): skip update_ddl_hit_history for pid >= PID_MAX_DEFAULT; 0: leave the vendor code alone");

static struct hk_kprobe dlc_ddl_kp;
static bool dlc_ddl_armed;

static int dlc_ddl_guard(struct kprobe *kp, struct pt_regs *regs)
{
	struct task_struct *p = (struct task_struct *)hk_regs_arg(regs, 0);

	if (p && (u32)READ_ONCE(p->pid) >= PID_MAX_DEFAULT) {
		hk_regs_return(regs);
		return 1;
	}
	return 0;
}

int dlc_ddl_hit_init(void)
{
	int ret;

	if (!dlc_ddl_enable) {
		pr_info("[droid_lkm_vendor] ddl guard disabled (ddl=0)\n");
		return 0;
	}

	ret = hk_kprobe_install(&dlc_ddl_kp, "update_ddl_hit_history",
				dlc_ddl_guard);
	if (ret) {
		pr_warn("[droid_lkm_vendor] ddl guard not installed: %d\n", ret);
		return 0;
	}

	dlc_ddl_armed = true;
	pr_info("[droid_lkm_vendor] ddl guard armed, pid >= %d skipped\n",
		PID_MAX_DEFAULT);
	return 0;
}

void dlc_ddl_hit_exit(void)
{
	if (!dlc_ddl_armed)
		return;

	hk_kprobe_remove(&dlc_ddl_kp);
	dlc_ddl_armed = false;
}
