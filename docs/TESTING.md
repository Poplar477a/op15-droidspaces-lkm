# 测试记录

## 设备

| 项 | 值 |
|---|---|
| 机型 | OnePlus 15 (PLK110) |
| 内核 | `6.12.77-android16-6-g********-4k` |
| KMI | gen 6 |
| 编译器 | clang-r536225 |
| 系统 | ColorOS/OOS 16/17 |

## Droidspaces 检查

`droidspaces check --json`（v7.1.0）：

```json
{"pid_ns":1,"mnt_ns":1,"uts_ns":1,"ipc_ns":1,"devtmpfs":1,
 "macvlan":1,"ipv6_nat":1,"pids_limit":1,"user_ns":0,
 "requirements_met":1}
```

除 `user_ns` 外全部通过；`requirements_met=1` 表示必需项齐全，容器可以创建。
`user_ns` 是内核编译期 `CONFIG_USER_NS=n`，模块路线无法补。

## 容器

- `droidspaces show`：ArchLinux、Ubuntu 两个容器正常运行；
- 容器 init `NSpid: <host_pid> 1`，容器内 PID 1 视角成立；
- `/proc/<pid>/ns` 中 mnt/uts/cgroup inode 与宿主不同，net 为 host 模式（预期）；
- `uid_map` 不存在（无 user namespace，预期）。

## 稳定性

| 阶段 | 结果 |
|---|---|
| 修复前（2026-10-29） | 一小时内 5 次崩溃，栈均为 `update_ddl_hit_history+0x144` |
| v1.0.21（ddl kprobe 守卫） | 加载后不再命中该越界 |
| v1.0.23 | 连续运行 **2 天**，期间跑完 **SPEC2017** 全套，无重启 |

`dmesg` 中 `UBSAN` / `kernel panic` / `watchdog bite` 计数为 0；
`/proc/last_boot_reason` 停在最后一次主动重启。

## 自检命令

```sh
su
dmesg | grep -i "ddl guard"       # ddl guard armed, pid >= 32768 skipped
cat /proc/sys/kernel/pid_max       # 32768
grep -E "^(droid_lkm|macvlan|ip6table)" /proc/modules
droidspaces check --json
```
