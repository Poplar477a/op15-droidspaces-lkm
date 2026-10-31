# 一加 15（6.12.23-android16-5 / GKI）用 KPM 实现 Droidspaces 支持

> 研究时间：2026-10-29
> 目标机：OnePlus 15（CPH2745 / CPH2747 / CPH2749 / PLK110，SM8850，OOS 16.0.10.601）
> 目标内核：`6.12.23-android16-5-*`（GKI，KMI generation 5）
> 约束：不重编内核、不用 AnyKernel3、不破坏 GKI/kABI（vendor 模块必须继续能加载）
> 参考实现：[`Kaniruka/droidspaces-dagu-kpm`](https://github.com/Kaniruka/droidspaces-dagu-kpm)（Xiaomi dagu / 4.19.157）、[`Dere3046/_patchHarmony`](https://github.com/Dere3046/_patchHarmony)（GKI 6.x LKM）

---

## 0. 结论先行

1. **dagu KPM 不能直接搬到一加 15。** 它是为「单一设备 + 单一 boot + 4.19.157」写的：结构体偏移硬编码、KernelPatch 内部函数地址硬编码、proc/dentry 布局按 4.19 写死，而且 `clone3`、SysV sem/shm、POSIX mqueue、userns、devtmpfs 都没实现。换到 6.12 GKI 上，它不是"改个宏"能解决的问题。

2. **但它的"形态"是对的，而且和 GKI 兼容的目标一致。** KPM 只 hook 函数入口/syscall 表，不往 `task_struct` 里加字段、不改结构体布局、不 enable 任何 CONFIG —— 这正是"不破坏 vendor 模块"的前提。问题只在于：**基础设施必须换成运行期自适应的那一套**（BTF 读布局 + kallsyms 解析符号），而不是编译期写死。

3. **一加 15 有两条可行路线：**

   | 路线 | 形态 | 现成度 | 工作量 | 适用 |
   |---|---|---|---|---|
   | **A. 上游 LKM**（`_patchHarmony`，声明支持 `android16-6.12`） | `.ko` + KernelSU `insmod` | 高，已有 6.12 分支 | 小（编译 + 机型适配） | 只要 Droidspaces 能跑，最快 |
   | **B. KPM 移植**（dagu 骨架 + 上游语义） | `.kpm` + APatch/KernelPatch | 低，需自己写 | 大（基础设施重做） | 必须用 APatch / 不能 insmod |

4. **如果目标是"完整支持"，A 的完整度更高**：上游已实现 pid/ipc/mqueue + SysV msg/sem/shm，dagu KPM 只做到 PID/IPC + SysV msg。B 要补齐这些，等于把上游 6.x 的 ipcns 代码整体搬到 KPM 环境。

5. **GKI 兼容的底线（无论 A 还是 B）**：不改结构体布局、不依赖导出符号、不改 kABI、不 enable CONFIG、运行期探测版本、失败即拒绝加载。详见第 3 节。

---

## 1. dagu KPM 解剖：哪些能学，哪些是坑

### 1.1 它是什么

面向 Xiaomi dagu（Android 15 / Linux 4.19.157）的 KernelPatch Module，给 Droidspaces v6.6.0 提供 **fake PID/IPC namespace**：KPM 自己维护 namespace 状态，并让进程、`/proc`、SysV 消息队列反映出该状态。作者明确写了「不把 `unshare()` 空成功视为实现」——这一点比很多"假成功"方案严谨。

已验证范围（以作者 `docs/VALIDATION.md` 为准）：单机上的 PID/IPC `unshare()`、PID 1、部分 `clone()/setns()`、SysV 消息队列隔离、Droidspaces 核心容器流程；v0.3.0-dev1 还做了有限的双容器并发。

### 1.2 组件职责

| 文件 | 作用 |
|---|---|
| `dagu_v02.c` | KPM 元信息、符号/ABI 初始化、syscall hook 生命周期、卸载守卫 |
| `abi.h` | **目标 boot 的硬编码结构体偏移**（task_struct / nsproxy / pid / pid_namespace / proc_dir_entry…） |
| `nsproxy_bridge.c` | `unshare()`/`clone()`/`setns()` 与 fake ns 状态的连接 |
| `pid_namespace.c` / `pid_lifecycle.c` | PID ns 状态、进程身份、生命周期 |
| `ipc_namespace.c` / `msg_core.c` / `msg_syscalls.c` | IPC ns 身份 + SysV 消息队列实现 |
| `proc_bridge.c` / `status_bridge.c` / `proc_mount_refs.c` | `/proc` namespace link、`NSpid` 等呈现 |
| `pid_exit_guard.c` | PID 1 退出陷阱保护 |
| `reboot_syscalls.c` | Droidspaces 停止路径用到的 scoped reboot |
| `usercopy.c` | 内核/用户地址受控拷贝 |

### 1.3 三个"设备锁"，全是 GKI 兼容的反面教材

**（1）`abi.h` 硬编码偏移**

```c
#define DAGU_TASK_THREAD_PID   0x6a0U
#define DAGU_TASK_NSPROXY      0x818U
#define DAGU_PIDNS_LEVEL       0x48U
#define DAGU_INFERRED_PIDNS_REBOOT 0xb8U  /* derived from Android 4.19 layout */
```

文件头自己写着 "Selected current-boot offsets. Inferred fields require more proof before use."

这在 4.19 单机上没问题；在 GKI 6.12 上，**一次 OTA / KMI 更新就可能整体错位**，而错位的后果不是 `-EINVAL`，是内核 panic / 重启。GKI 上必须改成运行期读 BTF（一加 15 的 `CONFIG_DEBUG_INFO_BTF=y`，`/sys/kernel/btf/vmlinux` 可直接读），或用 KernelPatch 的 `task_struct_offset` / `cred_offset`（`<ksyms.h>`）兜底。

**（2）硬编码 KernelPatch 内部地址**

```c
#define DAGU_KP_HOOK_SYSCALLN_LINK 0x20270UL
#define DAGU_KP_UNLOAD_MODULE_LINK 0x24070UL
#define DAGU_KP_UNLOAD_MODULE_PROLOGUE_0 0xa9bb7bfdU
...
```

它靠 "hook_syscalln 的函数体 + 固定偏移" 推 `unload_module` 地址，还校验 4 条指令的 prologue。**换一个 KernelPatch 版本/编译参数就失效**。正确做法是直接用 `hook_syscalln()` / `fp_hook_syscalln()` / `kallsyms_lookup_name()` 这些导出 API（KernelPatch 文档里有），不要碰 loader 内部布局。

**（3）4.19 的 proc/dentry 布局**

`proc_dir_entry`、`dentry`、`dir_context` 的偏移在 6.x 全变了（`proc_dir_entry` 在 5.6 之后被 `proc_ops`/`pde_data` 重构过）。这段代码在 6.12 上等于重写。

### 1.4 可以复用的是什么

- **语义参考**：fake ns 的状态机、PID 1 退出保护、`setns()` 祖先关系限制、reboot scoping —— 这些和内核版本无关，是设计资产。
- **KPM 生命周期模式**：`KPM_INIT/KPM_EXIT`、init 失败逐级回滚、`unload guard`（防止容器还在跑就卸载）。
- **测试思路**：ARM64 上的 namespace/msg/setns 探针（`tests/`），可以直接改造成一加 15 的验收用例。
- **明确的能力边界写法**：`docs/LIMITATIONS.md` 那种"未实现就是未实现"的记录方式，建议照抄。

---

## 2. 一加 15 的 GKI 事实（源码级）

| 项 | 值 | 来源 |
|---|---|---|
| 内核版本 | `6.12.23` | OnePlusOSS `android_kernel_common_oneplus_sm8850` 的 `Makefile`：`VERSION=6 PATCHLEVEL=12 SUBLEVEL=23` |
| 分支 | `oneplus/sm8850_b_16.0.0_oneplus_15` | OnePlusOSS |
| KMI | `android16-6.12`，**generation 5** | `build.config.constants`：`BRANCH=android16-6.12`、`KMI_GENERATION=5` |
| 编译器 | `clang-r536225` | 同上 `CLANG_VERSION=r536225` |
| BTF | `CONFIG_DEBUG_INFO_BTF=y` | `arch/arm64/configs/gki_defconfig` |
| CFI | `CONFIG_CFI_CLANG=y` | 同上 |
| 符号 | `CONFIG_KALLSYMS_ALL=y` | 同上（APatch 的硬性要求也满足） |
| 模块 | `CONFIG_MODULES=y`、`CONFIG_MODVERSIONS=y`、`CONFIG_MODULE_SIG=y`（**未见 `MODULE_SIG_FORCE`**） | 同上 |
| 配置读取 | `CONFIG_IKCONFIG_PROC=y`（`/proc/config.gz` 可用） | 同上 |
| 容器相关 | `PID_NS=n`（显式 `# CONFIG_PID_NS is not set`）、`SYSVIPC/POSIX_MQUEUE/IPC_NS/USER_NS/DEVTMPFS/CGROUP_PIDS/MACVLAN` 均未开 | 同上 |
| 已有 | `NET_NS`、`UTS_NS`、`CGROUPS`、`OVERLAY_FS`、`BRIDGE`、`VETH`、`IP_NF_NAT`、大量 xt 模块 | 同上 |

> 注意：`gki_defconfig` 是 GKI 基线；一加自己的 `configs/sun_perf.bzl` / `sun_consolidate.bzl` 只覆盖调试/性能项，**没有**打开上述容器选项。最终以设备上 `zcat /proc/config.gz` 为准。

### 2.1 为什么 6.12 上"补不出来"

`kernel/nsproxy.c`（v6.12）里：

```c
#ifndef CONFIG_PID_NS
    if (flags & CLONE_NEWPID)
        return -EINVAL;
#endif
#ifndef CONFIG_IPC_NS
    if (flags & CLONE_NEWIPC)
        return -EINVAL;
#endif
#ifndef CONFIG_USER_NS
    if (flags & CLONE_NEWUSER)
        return -EINVAL;
#endif
```

而 `PID_NS` / `IPC_NS` / `SYSVIPC` / `POSIX_MQUEUE` 在 Kconfig 里都是 **bool**：

```
config PID_NS
    bool "PID Namespaces"
config SYSVIPC
    bool "System V IPC"
config POSIX_MQUEUE
    bool "POSIX Message Queues"
config IPC_NS
    bool "IPC namespace"
    depends on (SYSVIPC || POSIX_MQUEUE)
```

**bool = 只能 `=y` 或 `=n`，没有 `=m`。** 所以"模块补"从来不是"加载一个模块就把 CONFIG 打开"，而是在 **syscall/nsfs 层做等价行为**：拦截 `unshare`/`clone`/`clone3`/`setns`，自己维护 namespace 对象与 pid 映射，再把 `/proc` 的呈现改掉。这就是 `_patchHarmony` 和 dagu KPM 在做的事。

---

## 3. GKI 兼容的硬规则（照做，vendor 模块才不会被带崩）

| # | 规则 | 原因 |
|---|---|---|
| R1 | **绝不改结构体布局/大小/字段顺序**，不在 `task_struct`、`nsproxy`、`cred` 里加东西 | 预编译 vendor 模块（GPU/相机/基带）按固定偏移访问；改了就崩 |
| R2 | **不新增/修改导出符号**，尽量不依赖 `__ksymtab` | GKI 对导出符号做 KMI 裁剪；很多内部符号根本没有导出条目 |
| R3 | **不改 kABI、不改 syscall 号、不 enable/disable CONFIG** | 内核镜像 ABI 必须与 KMI 一致 |
| R4 | hook 只发生在**函数入口/syscall 表/函数指针**，且必须可卸载、可回滚 | 崩溃面最小；卸载安全 |
| R5 | 版本适配靠**运行期探测**（BTF、符号存在性、`kver`），探测失败就**拒绝加载**而不是猜 | 跨 6.12.x 子版本、跨 KMI generation |
| R6 | 不碰 vendor 私有语义（`oplus_` ddl 等），需要时只做"查不到再兜底" | 厂商钩子改了会连带 GPU/调度崩 |
| R7 | 卸载顺序：先停容器 → 再卸模块；模块自身要挡住"运行中卸载" | dagu 的 `pid_exit_guard` / unload guard 就是干这个的 |

**两个容易误解的点：**

- **vermagic**：6.12 的 `same_magic()` 在 `CONFIG_MODVERSIONS=y` 时会跳过第一个空格前的字段（内核 release），只比后面 `SMP preempt mod_unload modversions aarch64`。所以**子版本不同（6.12.23 vs 6.12.69）通常仍可加载**，真正卡人的是符号 CRC（KMI generation 必须一致）。这一点对路线 A 很关键。
- **签名**：一加 15 的 GKI 基线只有 `CONFIG_MODULE_SIG=y`，没有 `MODULE_SIG_FORCE`。未签名 `.ko` 会带 taint 加载（前提：SELinux 允许 `insmod`、`CAP_SYS_MODULE`）。**但必须在设备上确认**：`zcat /proc/config.gz \| grep MODULE_SIG_FORCE`。若厂商开了 FORCE，路线 A 直接判死，只剩路线 B。

---

## 4. 两条路线对比

| 维度 | A. 上游 LKM（`_patchHarmony`） | B. KPM（dagu 骨架 + 上游语义） |
|---|---|---|
| 交付物 | `droid_lkm.ko` 等 2~6 个 `.ko` | 单个 `.kpm` ELF |
| 前置 | KernelSU/APatch 的 su + `insmod` | APatch（KernelPatch loader），需 patch boot |
| vermagic/CRC | 需要，但 MODVERSIONS 放宽子版本；KMI gen 必须对 | **不需要**（KPM 不是 `.ko`） |
| 签名 | 依赖 `MODULE_SIG_FORCE=n` | 不涉及 |
| 现成度 | 6.12 已在支持矩阵内，ipcns/mqueue/SysV 全有 | dagu 只到 4.19，缺 clone3/sem/shm/mqueue |
| 主要工作量 | 用 DDK/自建 KDIR 编译 + 改机型守卫 | 基础设施重写（BTF、符号、proc 桥）+ 功能补齐 |
| 崩溃面 | 模块加载失败通常只影响自身 | KPM 崩 = 内核崩，可能 bootloop |
| 适合 | 想尽快跑起来 | 设备只能用 APatch，或必须避开 `.ko` 签名/CRC |

> 如果一加 15 上 APatch/KernelPatch 可用（README 声称 Android 3.18–6.12），路线 B 在"免签名/免 CRC"上确实更省事；但它把复杂度从"构建"转移到了"实现"。

---

## 5. 路线 B：把 dagu KPM 改造成一加 15（6.12 GKI）的方案

### 5.1 基础设施替换表

| dagu 的做法 | 6.12 GKI 上必须换成 |
|---|---|
| `abi.h` 硬编码偏移 | 运行期 BTF 解析（`/sys/kernel/btf/vmlinux`），字段缺失则失败；KernelPatch `<ksyms.h>` 的 `task_struct_offset`/`cred_offset` 作兜底 |
| 硬编码 KP 内部地址（0x20270…） | 只用 `hook_syscalln` / `fp_hook_syscalln` / `inline_hook_syscalln` / `hook_wrap*` / `kallsyms_lookup_name` |
| 4.19 `proc_dir_entry`/`dentry` 偏移 | 6.12 的 `proc_ns_operations`、nsfs inode、`/proc/<pid>/ns/*` 链接；必要时用 `proc_pid_ns`/`ns_get_link` 符号 hook |
| 自己实现 msg 队列 | 可参考上游 `src/main/ipcns/sysv/*`（GPL-2.0），但要按 KPM 内存分配器改写（`kp_malloc`） |
| `clone` 单一入口 | 6.12 有 `__arm64_sys_clone`、`__arm64_sys_clone3`（nr 435）、`kernel_clone`/`kernel_clone3`；三处都要覆盖 |

### 5.2 syscall 号（arm64 generic）

| syscall | nr | 用途 |
|---|---|---|
| `unshare` | 97 | CLONE_NEWPID/NEWIPC 的入口 |
| `clone` | 220 | 新进程/线程创建 |
| `clone3` | 435 | dagu 明确没做，6.12 必须做（systemd/glibc 会用） |
| `setns` | 268 | 进入已有 ns |
| `msgget/msgsnd/msgrcv/msgctl` | 186/189/188/187 | SysV 消息队列 |
| `semget/semop/semctl` | 190/193/191 | 上游有，dagu 没有 |
| `shmget/shmat/shmdt/shmctl` | 194/196/195/197 | 上游有，dagu 没有 |
| `mq_open/mq_unlink/…` | 180/181… | POSIX mqueue，上游有 |

### 5.3 需要 hook 的内核函数（6.12）

| 符号 | 位置 | 为什么 |
|---|---|---|
| `ksys_unshare` | `kernel/nsproxy.c` | 在 `#ifndef CONFIG_*_NS` 返回 EINVAL 之前接管 |
| `copy_namespaces` / `create_new_namespaces` | `kernel/nsproxy.c` | `clone` 路径建立 ns |
| `kernel_clone` / `kernel_clone3` | `kernel/fork.c` | 新任务的 ns/pid 归属 |
| `alloc_pid` / `free_pid` / `attach_pid` | `kernel/pid.c` | pid 分配/回收，fake ns 的编号来源 |
| `__task_pid_nr_ns` / `task_active_pid_ns` | `kernel/pid.c` / `include/linux/pid.h` | `getpid()`、`/proc`、`NSpid` 的呈现 |
| `proc_pid_ns` / nsfs `ns_get_link` | `fs/proc/...`、`fs/nsfs.c` | `/proc/<pid>/ns/pid` 的 inode 与数字 |
| `do_exit` 路径 / `zap_pid_ns_processes` | `kernel/exit.c`、`kernel/pid_namespace.c` | PID 1 退出、ns 销毁 |
| `kernel_restart` / reboot syscall | `kernel/reboot.c` | 容器 `reboot` 只影响容器 |
| `ksys_msgget` 等 | `ipc/msg.c` | 按 fake IPC ns 分流 |

> 这些符号在一加 15 上是否都存在、是否被内联，必须逐项用 `kallsyms_lookup_name` 实测；拿不到就降级或拒绝加载（R5）。

### 5.4 状态模型（最小可用）

```
struct ds_ns {            // 模块自建，不塞进内核结构体
    u32 inum;             // 伪造的 ns inode 号，用于 /proc 呈现
    struct ds_ns *parent;
    refcount_t ref;
    struct list_head tasks;
    struct ds_ipc *ipc;   // SysV 对象表
};

struct ds_task_ext {      // 用 KernelPatch task_local 或模块自带哈希表
    struct ds_ns *pid_ns;
    struct ds_ns *ipc_ns;
    pid_t vpid;           // 容器内可见 pid
};
```

要点：
- **不要**把 `ds_ns` 挂到内核 `task_struct->nsproxy` 上（那是结构体布局/语义侵入）；用模块自己的 per-task 映射（KernelPatch 的 `reg_task_local` 最干净）。
- pid 号：容器内 `getpid()` 走 hook 返回 `vpid`；宿主侧仍用真实 pid。映射表在 `alloc_pid`/`free_pid` 处维护。
- `/proc`：只改"读出来看到什么"（`readlink`、`NSpid` 字段），不改内核对象。

### 5.5 分阶段计划（每阶段都要能在真机上回滚）

| 阶段 | 内容 | 验收 | 失败即停 |
|---|---|---|---|
| P0 | KPM 空壳：`KPM_INIT` 里打印 `kver`、解析 5 个关键符号、读 BTF 打印 `task_struct` 字段偏移 | `dmesg` 有输出、系统正常 | 符号缺失就停 |
| P1 | 只 hook `unshare`/`clone`，**不建状态**，只记录 flags | 连续 30 分钟无异常 | 任何 panic |
| P2 | fake PID ns：`unshare(CLONE_NEWPID)` 建对象、`clone` 归属、`getpid` 映射 | 容器内 `echo \$\$`、`ps` 正常 | PID 1 退出导致内核崩 |
| P3 | IPC ns + SysV msg（先只 msg，再 sem/shm） | `ipcs`、容器内两个进程通信隔离 | 对象泄漏 |
| P4 | `/proc` 呈现（ns link、NSpid）+ `setns` 限制 | `readlink /proc/self/ns/pid` 与宿主不同 | 误伤宿主 `/proc` |
| P5 | mqueue、clone3、reboot scoping、Droidspaces 全流程 + 连续重启 | 验收清单全过 | 任何 bootloop |

### 5.6 卸载与救砖

- KPM 没有 `.ko` 的 refcount，必须在 `KPM_EXIT` 里先拒绝"有容器在跑"，再拆 hook（顺序与安装相反）。
- 安装前先确认 APatch 的"安全模式"可用（音量键启动），并能通过 adb 删除 `/data/adb/ap/...` 下的 KPM。
- 首次只手动加载，不开机自启；确认 30 分钟稳定后再考虑。

---

## 6. 路线 A：直接上上游 LKM（更短的路径）

1. 取 `Dere3046/_patchHarmony`（GPL-2.0），确认 `android16-6.12` 分支。
2. 构建：用 `android16-6.12` 的 DDK（或自建 KDIR：OnePlusOSS 源码 + 设备 `/proc/config.gz` + `clang-r536225`），产出 `droid_lkm.ko` / `droid_lkm_vendor.ko`。
3. 适配：把机型/内核守卫从 PMB110 改成 `CPH2745|CPH2747|CPH2749|PLK110` + `6.12.23-*`；保留 `no_boot` 等价物。
4. 加载：KernelSU 的 su 域 `insmod`，先主模块、再 vendor、最后 misc/pids；每步看 `dmesg`。
5. 验收：容器能起/能进、pid/mnt 隔离、`apt` 可用、连续 stop/start 不崩。

> 关键前提仍是：`MODULE_SIG_FORCE` 必须为 n；KMI generation 必须为 5（与 `android16-6.12` gen5 DDK 对齐）。

---

## 7. 风险清单

| 风险 | 触发条件 | 缓解 |
|---|---|---|
| 开机即崩 / bootloop | 结构体偏移错、hook 装错、PID 1 退出路径 | 分阶段、no_boot、安全模式、先备机 |
| CFI failure 后断电 | 编译 clang 与内核不一致（A 路线） | 用 `clang-r536225`；不要混用系统 clang |
| vendor 模块崩 | 改了结构体布局/kABI | 严守 R1/R3；只 hook 不改布局 |
| 符号找不到 | KMI 裁剪 / 厂商改名 / 内联 | 运行期解析 + 缺失即拒绝加载 |
| 假隔离被误当安全边界 | fake ns ≠ 真 ns；容器 root = 宿主 root | 文档写清；不要跑不可信镜像 |
| 模块/loader 版本漂移 | KernelPatch 升级（B 路线） | 只用公开 API；不碰内部偏移 |

---

## 8. 建议

- **先做 A，再做 B。** A 能在一天内验证"一加 15 到底缺什么、缺的是不是只有那几项"；B 的实现可以复用 A 验证过的符号/偏移结论。
- **不要从 dagu 的 `abi.h` 开始改。** 那是最不可移植的部分；从 BTF + `kallsyms_lookup_name` 的 P0 空壳开始。
- **一切以设备实测为准**：`/proc/config.gz`、`/proc/kallsyms`、`dmesg`、`/sys/kernel/btf/vmlinux` 四个来源交叉验证，别信文档。

---

## 9. 实测对照：Droidspaces v7.0.0 检查输出（一加 15 stock）

一加 15 原厂内核上的检查结果与上面的源码推断逐项吻合。每一项的探针在 Droidspaces 源码里是确定的，补的时候必须"让探针看到它想看的东西"，而不是只让功能勉强能用：

| 检查项 | 探针实现（v7.0.0） | 为什么 ✗ | 补法 | 修好后 |
|---|---|---|---|---|
| PID namespace（必需） | `src/check.c:49` `check_ns(CLONE_NEWPID)`：先 `access("/proc/self/ns/pid")`，再 fork 出子进程 `unshare(CLONE_NEWPID)` | `CONFIG_PID_NS=n`，两件事都不成立：proc 里没有 `ns/pid`，unshare 返回 EINVAL | `droid_lkm`：建 ns 对象 + 挂 `proc_ns_operations` 让 `/proc/<pid>/ns/pid` 出现 + hook unshare/fork | ✓（fake ns） |
| IPC namespace（必需） | `src/check.c:198` 同上，`ns/ipc` | `CONFIG_IPC_NS=n` | `droid_lkm` 的 IPC 部分 | ✓（fake ns） |
| devtmpfs | `src/check.c:387`：`grep_file("/proc/filesystems", "devtmpfs")` | `CONFIG_DEVTMPFS=n` | `droid_lkm_misc`：`register_filesystem()` 注册一个同名 shmem 文件系统，挂载/填节点交给 Droidspaces | ✓ |
| Macvlan | `src/net/netlink.c:318`：netlink 建 veth 再建 macvlan | `CONFIG_MACVLAN=n` | 独立 `macvlan.ko`（`-DCONFIG_MACVLAN=1` + 符号 shim） | ✓（WiFi 驱动可能丢包，见 §1） |
| IPv6 NAT | `src/net/iptables.c:1167`：`IP6T_SO_GET_REVISION_TARGET` 查 `nat` 表的 `MASQUERADE` | 缺 `IP6_NF_NAT` / `IP6_NF_TARGET_MASQUERADE` | 独立 `ip6table_nat.ko`（9 个符号 shim） | ✓ |
| Process limit | `src/cgroup.c:202` `ds_cgroup_has_controller("pids")`：读 cgroup2 根 `cgroup.controllers`，回退 `/proc/cgroups` | `CONFIG_CGROUP_PIDS=n`，控制器根本不存在 | `droid_lkm_pids`：**显示层** hook `cgroup_controllers_show`/`proc_cgroupstats_show` 让名字出现；**功能层** 在 memory 控制器上挂 `pids.max` 并在 fork 路径返回 `-EAGAIN` | ✓（名字是假的，限制是真的） |
| Sandboxing (user namespaces) | `src/check.c:469` `check_ns(CLONE_NEWUSER)` | `CONFIG_USER_NS=n` | **无解** | ✗ 永远红 |

### 9.1 两个容易踩的细节

1. **PID/IPC 必须"文件存在 + unshare 成功"同时满足。** 只让 `unshare` 假成功，`access()` 那一步还是红；只造 `/proc/self/ns/pid` 文件，子进程 `unshare` 还是 EINVAL。两边都要做，而且 unshare 是在 fork 出来的子进程里调的，hook 必须对子进程同样生效。
2. **网络探针有按 boot 的缓存。** `macvlan_caps` / `nat_caps` 落在 `/data/local/Droidspaces/Net/`，模块装好后如果不重启，检查可能仍显示旧结果；删掉这两个文件再跑，或直接重启。

### 9.2 修好后的预期

- 装 `droid_lkm` 后，两个 **必需项** 变绿，Summary 从 "2 required feature(s) missing" 变成 "All required features found!"，容器可以启动。
- 再装 `misc` / `pids` / `macvlan` / `ip6nat` 后，除 **Sandboxing** 外全绿。
- **Sandboxing 永远红**，这是内核编译期决定的，模块方案的上限就在这里。

---

## 附录：参考

- dagu KPM：https://github.com/Kaniruka/droidspaces-dagu-kpm （`v0.3dev`，`docs/ARCHITECTURE.md`、`docs/LIMITATIONS.md`）
- 上游 LKM：https://github.com/Dere3046/_patchHarmony （支持矩阵含 `android16-6.12`）
- Droidspaces 内核配置：https://github.com/Dere3046/Droidspaces/blob/main/Documentation/zh-CN/Kernel-Configuration.md
- KernelPatch KPM 文档：https://github.com/bmax121/KernelPatch/blob/main/doc/zh-CN/module.md
- APatch 支持范围：https://github.com/bmax121/APatch （Android 3.18–6.12）
- 一加 15 内核源码：https://github.com/OnePlusOSS/android_kernel_oneplus_sm8850 、https://github.com/OnePlusOSS/android_kernel_common_oneplus_sm8850 （分支 `oneplus/sm8850_b_16.0.0_oneplus_15`）
- Linux v6.12 `kernel/nsproxy.c`、`kernel/module/main.c`（vermagic/MODVERSIONS 行为）
