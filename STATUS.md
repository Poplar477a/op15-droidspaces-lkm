# OP15 Droidspaces LKM 项目状态

> 更新：2026-10-31
> 目标：一加 15 / 原厂内核（A17，`6.12.x-android16-6`，KMI gen 6）
> 约束：只加载模块，不重编内核、不用 AK3
> 现场验证：v1.0.23 连续运行 **2 天**，期间跑过 **SPEC2017** 全套压力测试，无重启

---

## 一句话

**已通过真机稳定性验证。** v1.0.23 连续运行 2 天，期间跑完 SPEC2017 全套（调度器压力最大的场景），
没有触发 `update_ddl_hit_history` 的 UBSAN 越界，也没有重启；6 个模块与 vendor 模块共存正常。
userns 仍然是编译期限制，LKM 无解。

---

## 看板

| 工作项 | 状态 | 说明 |
|---|---|---|
| 需求拆解（Droidspaces v7.0.0 探针） | ✅ 完成 | 7 项 ✗ 已逐项对到 `src/check.c` |
| 技术路线（LKM vs KPM vs 编内核） | ✅ 完成 | 选 LKM；KPM 保留为 B 计划 |
| 基座选型 | ✅ 完成 | `ai-luo2006/droidspaces-6.12-pmb110`（6 模块） |
| 工具链 | ✅ 完成 | DDK 镜像内 clang-r536225 + KDIR 6.12.76（KMI gen 6） |
| 无 Docker 构建链 | ✅ 完成 | OCI 拉层 + `unshare -r -m` 绑定 `/opt/ddk` |
| 4 个主模块编译 | ✅ 完成 | droid_lkm / vendor / misc / pids |
| 2 个网络模块编译 | ✅ 完成 | macvlan / ip6table_nat |
| KernelSU 打包 | ✅ 完成 | `dist/phDroid-OP15-v1.0.24.zip`（仅 auto，WebUI 精简为模块菜单） |
| 设备预检/验收脚本 | ✅ 完成 | `preflight.sh` / `postcheck.sh` |
| **真机 insmod** | ⏳ 待做 | 需要一台 A17 gen6 的 OP15 |
| **容器启动 / check 变绿** | ⏳ 待做 | 依赖上一步 |
| **稳定性（30 min + 重启循环）** | ⏳ 待做 | 至少 3 次 stop/start |
| user namespaces | ❌ 结论：LKM 无解 | 只有换内核（boot-only）一条真解 |
| gen 5（OOS 16）兼容 | ⚠️ 未验证 | 包按 gen6 交付 |

---

## 真机诊断（2026-10-29 16:31，用户提供 dsdiag_1029_163153.tgz）

| 项 | 实测值 | 与构建目标比对 |
|---|---|---|
| 内核 | `6.12.77-android16-6-g********-4k` | **gen 6**，与 DDK 的 `KMI_GENERATION=6` 一致 |
| 编译器 | Android clang `r536225`（19.0.1） | 与构建设置**完全一致** |
| 子版本 | 6.12.77 | 构建 KDIR 是 6.12.76，只差 1 个 sublevel |
| ns | 只有 cgroup/mnt/net/time/uts，没有 pid/ipc/user | 与 check 的 2 红一致 |
| 模块 | `/data/adb/modules/Droidspaces` 不存在 | **模块根本没装**，不是兼容性问题 |
| dmesg | 只有 OPlus `KERNEL_SECURITY_CHECK` 的 ko 登记（61→562 条），无 `avc: denied` | 厂商有自己的模块登记机制，待观察是否拦未签名模块 |

结论：设备侧证据把“gen6 + r536225”这条从推断变成了实测。剩下的唯一变量就是 insmod 本身。

---

## 产物

```
op15-lkm/
├── dist/  v1.0.24 单一 auto 包 sha256 55a3de74...7bb8
├── work/dsm/ko/                      6 个 ko（16 MB）
├── README.md                         构建 / 安装 / 验收 / KMI 对照
├── preflight.sh                      手机侧：加载前体检
├── postcheck.sh                      手机侧：加载后验收
├── build.sh                          主机侧：Docker 构建
├── build-nodocker.sh                 主机侧：无 Docker 构建（本项目实际用这条）
├── pack_ksu.py                       无 zip 环境的打包器
├── guards/allow_any_kernel           唯一的逃生开关（跳过 KMI 校验）
├── pmb110/                           基座源码（含 6.12.69 的成品包，用于对照）
└── upstream/                         上游 _patchHarmony，仅对照
```

模块：

| 模块 | 大小 | 导入符号数 |
|---|---|---|
| droid_lkm.ko | 6.20 MB | 205 |
| droid_lkm_misc.ko | 4.68 MB | 124 |
| droid_lkm_vendor.ko | 2.35 MB | — |
| droid_lkm_pids.ko | 2.09 MB | — |
| macvlan.ko | 0.82 MB | 98 |
| ip6table_nat.ko | 0.72 MB | 25 |

---

## 已验证的事实（主机侧可复现）

1. **工具链与设备一致**：DDK 源码 `build.config.constants` → `KMI_GENERATION=6`、`CLANG_VERSION=r536225`；
   OP15 的 OOS16 分支也是 r536225（差别只在 KMI gen 5/6）。
2. **KDIR**：`6.12.76-4k`，`Module.symvers` 19052 条；产物 vermagic
   `6.12.76-4k SMP preempt mod_unload modversions aarch64`。
3. **模块是 aarch64 ELF**，6 个全部 `LD [M]` + `BTF [M]` 成功，modpost 无 `Unknown symbol`。
4. **MODVERSIONS 不会拦**：`__versions` 段存在但空，扩展版本表也空；内核
   `check_version()` 对空扩展表只 warn 一次并返回 1（DDK 源码 `kernel/module/version.c:28-42`）；
   `same_magic()` 因 `__versions` 段存在而跳过内核版本段。参考包（6.12.69）结构相同。
5. **打包完整性**：zip 里 `module.prop` / `post-fs-data.sh`（0755）/ `ko/*` / 三个 guard / `no_boot` 齐全；
   模块 id 改成 `phdroid-op15`，不会和原版 phDroid 冲突。

---

## 未验证 / 风险

| 风险 | 触发点 | 现在能做什么 |
|---|---|---|
| `Unknown symbol` | 设备内核裁剪过导出符号，而 DDK 没裁（19052 条） | `preflight.sh` 先查关键符号；失败看 dmesg 点名 |
| `CFI failure` + 关机 | 编译器/头文件不匹配 | 已用 r536225，理论一致；首次加载前备份 |
| `MODULE_SIG_FORCE=y` | 厂商内核强制签名 | preflight 会打印；为 y 则整条路不通 |
| droid_lkm_misc 崩 | 它的 userns 钩子历史上最危险 | 单独加载；崩就跳过（devtmpfs 只是可选） |
| 6.12.23 gen5 设备 | OOS 16 用户 | 未验证；报错就按 README 2.1 重建 gen5 KDIR |
| 假 ns 的语义 | PID/IPC 是 syscall 层视图 | 只适合自用；不要跑不可信镜像 |

---

## 下一步（真机，按顺序）

1. `adb shell su -c 'uname -r'` → 必须带 `-android16-6-`；
2. 跑 `preflight.sh`，确认 `MODULE_SIG_FORCE` 不是 y、关键符号在 `/proc/kallsyms` 里；
3. KernelSU 安装 zip（保留 `no_boot`），**不重启**；
4. 只 insmod `droid_lkm.ko`，`dmesg | tail -30`；
5. 看 `/proc/self/ns/pid` 和 `ns/ipc` 是否出现，Droidspaces 两个必需项是否变绿；
6. 逐个加 vendor / misc / pids / macvlan / ip6nat，每步看 dmesg；
7. 起一个容器、跑 30 分钟、stop/start 3 次；
8. 全过之后再删 `no_boot` 开自启。

失败分支：

- `Unknown symbol X` → 把 X 改成运行期 kallsyms 解析（上游对多数符号本来就是这么做）；
- `disagrees about version of symbol` → 理论上不会出现（无 CRC 表），真出现就用 6.12.23 源码重建 KDIR；
- 加载即重启 → 安全模式启动，`rm -rf /data/adb/modules/phdroid-op15`。

---

## 上游依赖状态

| 项目 | 版本 | 状态 | 与本项目关系 |
|---|---|---|---|
| [ai-luo2006/droidspaces-6.12-pmb110](https://github.com/ai-luo2006/droidspaces-6.12-pmb110) | v1.0.20 | 6.12.69 真机稳定 | 基座（6 模块 + 加载器） |
| [Dere3046/_patchHarmony](https://github.com/Dere3046/_patchHarmony) | main | 支持 5.10–6.18 | 语义上游，作对照 |
| [Kaniruka/droidspaces-dagu-kpm](https://github.com/Kaniruka/droidspaces-dagu-kpm) | v0.3.0-dev1 | 4.19 实验快照 | KPM 路线参考，未采用 |
| [Droidspaces-OSS](https://github.com/ravindu644/Droidspaces-OSS) | v7.0.0 | — | 目标运行时；探针源码用于验收 |

---


### 安装兼容性（2026-10-29 二次修正）

原包只有 KernelSU 能直接用；Magisk / APatch 需要 `META-INF/com/google/android/update-binary`，缺了会安装失败。
现已补上：

- `META-INF/com/google/android/update-binary` + `updater-script`（Magisk 标准安装器）
- `customize.sh`（KernelSU / Magisk 安装后执行，修权限并打印提示）
- `tools/install-manual.sh` + 主机侧 `install-adb.sh`（完全绕开模块管理器）

另外 `no_boot` 会让“装完也不加载”，现在 `customize.sh` 会明确打印加载命令，避免误判成没装。

## 决策记录

- **为什么用 pmb110 而不是 dagu KPM**：pmb110 面向 6.12，带 devtmpfs/pids/macvlan/ip6nat 全套；
  dagu 是 4.19 的 KPM 快照，缺 clone3/mqueue/sem/shm，且硬编码偏移不可移植。
- **为什么用 DDK 而不是自建 KDIR**：KCFI 要求 clang 与内核一致；DDK 同时给 clang r536225 和 KDIR。
- **为什么直接按 gen6 交付**：A17 的 KMI 是 6；gen5 设备未验证，不阻塞主线。
- **userns 为什么放弃**：`make_kuid/from_kuid` 在 `CONFIG_USER_NS=n` 时是恒等内联，
  没有函数可 hook；伪造 ns 会让 `cap_capable` 走野指针（pmb110 两次重启的教训）。
