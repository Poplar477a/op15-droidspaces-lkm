# 循环重启：原因、守卫与恢复

模块在内核态改行为，最坏情况是 panic 后重启；如果模块每次开机都自动加载，就可能形成
“开机 → 崩 → 重启 → 再崩”的循环。本仓库的加载器专门为此设计了三道守卫。

## 一、可能的原因

| 现象 | 原因 | 判断 |
|---|---|---|
| `insmod` 当场关机/重启 | 编译器与内核不一致（KCFI） | dmesg 有 `CFI failure` |
| `insmod` 返回错误 | 符号不存在 / 签名被拒 | `Unknown symbol` / `Required key not available` |
| 加载后几十秒到几分钟崩 | 模块 hook 的内存/生命周期问题 | pstore 里有 `Unable to handle` / `UBSAN` / `BUG:` |
| 息屏或调度密集时崩 | 厂商 ddl 数组越界（本仓库已用 kprobe 守卫处理） | 栈在 `update_ddl_hit_history` |

## 二、守卫怎么工作

加载器在 `post-fs-data.sh` 里维护三个标记文件：

```
insmod.inflight   开始 insmod 前写入，全部成功后删除
blocked           只要存在，本次及以后开机都跳过加载
boot_pending      insmod 成功后写入
.boot_ok          service.sh 等 120 秒确认系统还活着后写入，然后删 boot_pending
```

判定规则：

1. 开机看到 `insmod.inflight` 还在 → 说明上次崩在 insmod 阶段 → 写 `blocked`，跳过；
2. 开机看到 `boot_pending` 在、`.boot_ok` 不在 → 说明上次加载后没撑过存活窗口 → 写 `blocked`，跳过；
3. 看到 `blocked` → 永久跳过，直到手动删除。

也就是说：**最坏情况只崩一次，下一次开机会自动停加载**，不会无限循环。

## 三、恢复

### 还能开机

```sh
su
ls /data/adb/modules/phdroid-op15/{blocked,boot_pending,.boot_ok,insmod.inflight} 2>/dev/null
# 解除阻断，下次手动加载
rm -f /data/adb/modules/phdroid-op15/blocked
# 或者只想先停掉自启
touch /data/adb/modules/phdroid-op15/no_boot
```

### 开不了机 / 正在循环

按顺序尝试：

1. **KernelSU 安全模式**：开机按住音量下，模块不会加载；
2. 能进系统后删除模块目录：
   ```sh
   rm -rf /data/adb/modules/phdroid-op15
   ```
   然后重启；
3. 进不了系统：用 TWRP / recovery 的文件管理器删除同一目录，或 `adb shell`（若可用）；
4. 仍然循环：刷回原厂 `boot.img`（模块不涉及 boot 分区，通常不需要）。

### 卸载

```sh
su
rm -rf /data/adb/modules/phdroid-op15
reboot
```

## 四、排查顺序

```sh
su
cat /proc/last_boot_reason                 # kernel crash Minidump / reboot
ls -l /sys/fs/pstore; tail -100 /sys/fs/pstore/console-ramoops* 2>/dev/null
dmesg | grep -iE "CFI failure|Unknown symbol|UBSAN|Kernel panic|droid_lkm" | tail -40
tail -40 /data/adb/modules/phdroid-op15/load.log
tail -20 /data/adb/modules/phdroid-op15/history.log
```

对照处理：

| 关键字 | 处理 |
|---|---|
| `CFI failure` | 用与内核一致的 clang 重新编译（本项目用 DDK 的 r536225） |
| `Unknown symbol` | 把该符号改成 `kallsyms_lookup_name` 运行期解析 |
| `vermagic ... should be` | 检查 KMI 分支与 `CONFIG_MODVERSIONS` |
| `Required key not available` | 内核开了 `MODULE_SIG_FORCE`，此路不通 |
| `update_ddl_hit_history` | 确认 `ddl=1`，看 `ddl guard armed` 是否出现 |

## 六、延迟崩溃：守卫抓不到的情况（2026-10-29 实例）

这次“循环重启”不是加载即崩，而是**每次开机后 196–449 秒**才在调度路径崩：

```
update_ddl_hit_history+0x144  (UBSAN: array index out of bounds)
→ oplus_replace_next_task_ddl
→ pick_next_task_fair → __schedule
→ KernelPatch 转储 → 看门狗复位
```

因为崩溃时间**超过了 `service.sh` 的 120 秒存活窗口**，`.boot_ok` 已经写入、`boot_pending` 已删除，
所以 `blocked` 守卫不会触发——表现就是“每次都能开机，用几分钟又重启”，看起来像循环重启，
实际不是加载阶段的问题。

处理方式：

1. **立刻止血**（不改代码）：
   ```sh
   touch /data/adb/modules/phdroid-op15/no_boot   # 停自启
   reboot
   ```
   或卸载模块目录；进不了系统就用 KernelSU 安全模式 / recovery 删除。
2. **让守卫覆盖更长窗口**（临时）：
   ```sh
   echo 600 > /data/adb/modules/phdroid-op15/alive_sec
   ```
   这样加载后 10 分钟内崩，下次开机会被 `blocked` 拦住。
3. **根因修复**：这次的正解不是调大窗口，而是
   - 在 `update_ddl_hit_history` 入口挂 kprobe，`pid >= PID_MAX_DEFAULT` 直接跳过；
   - 把 `pid_max` 从 4194304 压回 32768（post-fs-data + late service 两段）。
   细节见 [CRASH-ANALYSIS.md](CRASH-ANALYSIS.md)。

教训：**bootloop 守卫只覆盖“加载阶段/存活窗口内”的崩溃**；分钟级的延迟崩溃要靠
`alive_sec` 扩大窗口，或者从根因上消除。看到“能开机、用一会重启”时，不要只怀疑加载失败，
先取 `/proc/last_boot_reason` 和 pstore。

## 五、把风险降到最低

1. 第一次安装后**不要直接重启**：先 `touch /data/adb/modules/phdroid-op15/no_boot`，重启后手动
   `sh /data/adb/modules/phdroid-op15/load.sh`，观察 30 分钟；
2. 确认 `dmesg | grep "ddl guard"` 出现 `armed`、`droidspaces check --json` 为
   `requirements_met=1` 后，再删除 `no_boot` 开自启；
3. 只加载需要的模块：在模块目录里放 `skip_misc` / `skip_pids` / `skip_net`（加载器会跳过对应模块）；
4. 保留 `tools/crashlog.sh`，出问题先收集 pstore 再重试。
