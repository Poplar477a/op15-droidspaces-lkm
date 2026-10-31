# 崩溃分析：`update_ddl_hit_history` 数组越界

## 现象

2026-10-29，一加 15 在一次开机后约 200–450 秒随机重启，多次崩溃栈完全一致：

```
Internal error: UBSAN: array index out of bounds: 00000000f2005512
pc : update_ddl_hit_history+0x144/0x198   [oplus_bsp_sched_assist]
lr : oplus_replace_next_task_ddl+0xd4/0x2c8
Call trace:
  update_ddl_hit_history
  oplus_replace_next_task_ddl
  android_rvh_before_pick_task_fair_handler
  __traceiter_android_rvh_before_pick_task_fair
  pick_next_task_fair → __schedule → (futex / epoll / binder 等任意路径)
```

受害者任务每次都不同（systemui、电源模块、binder 线程），说明是路径级缺陷，与容器负载无关。

## 根因（官方源码）

`vendor/oplus/kernel/cpu/sched/sched_assist/sa_ddl.h`：

```c
struct ddl_sinfo_data {
    char comm[TASK_COMM_LEN];   /* 16 */
    u64  hit;                   /* 8  -> 24 字节/项 */
};
```

`sa_ddl.c`：

```c
struct ddl_sinfo_data ddl_sdata[PID_MAX_DEFAULT];   /* 静态数组，32768 项 */

void update_ddl_hit_history(struct task_struct *p)
{
    if (p) {
        if (!strlen(ddl_sdata[p->pid].comm) || ...)
            ...
        ddl_sdata[p->pid].hit++;    /* 没有上界检查 */
    }
}
```

这台机器的 `/proc/sys/kernel/pid_max` 是 **4194304**，现场存在 `pid=146913 / 83263 / 84117`
的任务被 OPlus 查到，`ddl_sdata[p->pid]` 必然越界；内核编译了 UBSAN 且 panic_on_warn，
越界一次就复位。

注意：`ddl_sdata` 是**数组符号**，不能通过替换指针修复。基座原来的 `ddl` 替换逻辑
（`dlc_ddl_is_pointer`）在这种内核上直接走 "ddl history is an array" 分支，从未生效。

## 修复

1. **ddl kprobe 守卫**（`src/droid_lkm/src/compat/vendor/ddl_hit.c`）

```c
static int dlc_ddl_guard(struct kprobe *kp, struct pt_regs *regs)
{
    struct task_struct *p = (struct task_struct *)hk_regs_arg(regs, 0);

    if (p && (u32)READ_ONCE(p->pid) >= PID_MAX_DEFAULT) {
        hk_regs_return(regs);   /* 跳过函数体，不执行越界访问 */
        return 1;
    }
    return 0;
}
```

挂载日志：`[droid_lkm_vendor] ddl guard armed, pid >= 32768 skipped`。
表内 pid 行为完全不变，只是越界调用被跳过。

2. **pid_max clamp**（两段）

- `post-fs-data.sh`：模块加载后立即检查并写入 32768；
- `service.sh`（late_start）：等 `/sys/module/oplus_bsp_sched_assist` 出现后再兜一次，
  因为 Android 会在开机后把 `pid_max` 抬到 4194304。

## 验证

- 2026-10-29 修复前：一小时内 5 次崩溃，间隔缩短；
- 2026-10-29 至 10-31：v1.0.23 连续运行 **2 天**，跑完 **SPEC2017** 全套，无重启；
- `dmesg` 中 UBSAN/panic 计数为 0，`last_boot_reason` 停在最后一次主动重启。
