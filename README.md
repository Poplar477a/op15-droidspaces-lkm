# op15-droidspaces-lkm

在 **一加 15（OnePlus 15，PLK110 / CPH2745 / CPH2747 / CPH2749）原厂 GKI 内核**上，
只通过加载内核模块补齐 [Droidspaces](https://github.com/ravindu644/Droidspaces-OSS) 需要的能力。
不重编内核，不用 AnyKernel3，不替换 vendor_dlkm。

> **本仓库是 [ai-luo2006/droidspaces-6.12-pmb110](https://github.com/ai-luo2006/droidspaces-6.12-pmb110) 的分支/衍生。**
> 该基座又基于 [Dere3046/_patchHarmony](https://github.com/Dere3046/_patchHarmony) 的 GKI 6.x LKM。
> 命名空间/IPC 的核心实现、KallRecon / Type_info / KernCall / HooKern 依赖、加载器框架都来自上述项目；
> 本分支的改动集中在：OP15 机型适配、KMI-only 校验、OPlus ddl kprobe 守卫、pid_max 两段 clamp、精简 WebUI。

## 状态

| 项 | 值 |
|---|---|
| 设备 | OnePlus 15 (PLK110)，ColorOS/OOS 16/17 |
| 内核 | `6.12.77-android16-6-g...`，KMI **gen 6** |
| 编译器 | clang **r536225**（必须一致，KCFI） |
| 稳定性 | 连续运行 **2 天**，期间跑完 **SPEC2017** 全套，无重启 |
| Droidspaces | v7.1.0 `check --json`：除 `user_ns` 外全绿，`requirements_met=1` |

## 补了什么

| 能力 | 模块 | 说明 |
|---|---|---|
| PID / IPC / mqueue 命名空间 | `droid_lkm.ko` | syscall/nsfs 层实现，非内核原生 pid_namespace |
| OPlus 兼容（ghost task、ddl 守卫、pid_max） | `droid_lkm_vendor.ko` | 见 [docs/CRASH-ANALYSIS.md](docs/CRASH-ANALYSIS.md) |
| devtmpfs、userns 视图 | `droid_lkm_misc.ko` | userns 只做视图，内核未编译 `CONFIG_USER_NS` |
| pids 控制器（显示 + 限制） | `droid_lkm_pids.ko` | 在 memory 控制器上挂 `pids.max`，fork 超限返回 `-EAGAIN` |
| macvlan | `macvlan.ko` | 独立 `.ko`，符号 shim |
| IPv6 NAT | `ip6table_nat.ko` | 独立 `.ko`，符号 shim |

**补不了的**：`CONFIG_USER_NS`。内核编译期没有该功能，`make_kuid/from_kuid` 被内联成恒等，
模块无法在运行时补出真正的 user namespace。容器 root 就是宿主 root，不要跑不可信镜像。

## 安装

1. 装包：KernelSU / APatch 里安装 `phDroid-OP15-*.zip`（或 `ksud module install`），重启。
2. 默认 **auto**：开机自动加载 6 个模块，带 bootloop 守卫。
3. 打开模块 WebUI：只剩模块加载菜单（勾选模块、加载、全部卸载、日志）。
4. 验证：

```sh
su
dmesg | grep -i "ddl guard"        # ddl guard armed, pid >= 32768 skipped
cat /proc/sys/kernel/pid_max        # 32768（service 阶段 clamp）
droidspaces check --json            # requirements_met=1（user_ns 仍为 0）
```

手动加载/卸载：

```sh
su -c sh /data/adb/modules/phdroid-op15/load.sh     # 加载
su -c sh /data/adb/modules/phdroid-op15/tools/confirm.sh   # 体检
```

## 构建

必须用 **Android DDK** 的 KDIR 与 clang（本机为 `android16-6.12`，`UTS_RELEASE=6.12.76-4k`，
`KMI_GENERATION=6`，`clang-r536225`）。用错编译器不是报错，是 `CFI failure` + 关机。

### 方式 A：Docker

```sh
docker pull docker.cnb.cool/ylarod/ddk/ddk-min:android16-6.12
scripts/build-docker.sh android16-6.12
scripts/package.sh
```

### 方式 B：没有 Docker（把 DDK 镜像解包）

```sh
# 任选其一拿到 DDK rootfs，使 $DDK_ROOT/opt/ddk/kdir/android16-6.12 存在
DDK_ROOT=/path/to/ddk/root scripts/build-nodocker.sh android16-6.12
scripts/package.sh
```

细节见 [docs/BUILD.md](docs/BUILD.md)。

## 目录

```
src/droid_lkm/        droid_lkm / vendor / misc / pids 四个模块的源码
src/net_macvlan/      macvlan.ko
src/net_ip6nat/       ip6table_nat.ko
module/               KernelSU 模块模板（脚本、WebUI、检查工具）
scripts/              构建、打包、设备诊断脚本
docs/                 构建、崩溃分析、测试记录、研究笔记
```

## 兼容性

- **支持**：OnePlus 15（PLK110 / CPH2745 / 2747 / 2749），GKI `6.12.x-android16-6`（**KMI gen 6**），
  内核由 **clang-r536225** 构建，KernelSU / APatch；实测 6.12.77 + Droidspaces v7.1.0。
- **不保证**：KMI gen 5（`6.12.23-android16-5`）、非 GKI、`MODULE_SIG_FORCE=y`、
  其他厂商的 6.12 内核、user namespace。
- 完整的配置前提、自检命令、OTA 后的版本漂移处理见 **[docs/COMPATIBILITY.md](docs/COMPATIBILITY.md)**。

## 循环重启与恢复

加载器有三道守卫：`insmod.inflight`、`blocked`、以及 `boot_pending` + `service.sh` 120 秒存活窗口。
最坏情况只崩一次，下一次开机会自动停止加载，不会形成无限重启。

解除阻断、安全模式、删模块、pstore 排查的完整步骤见 **[docs/BOOTLOOP.md](docs/BOOTLOOP.md)**。

## 注意事项

- 内核态修改有风险：可能死机、重启、数据损坏，**风险自担**；请先备份并确认有救砖手段。
- 非官方项目，与 OnePlus / OPPO / 高通 / Google / Droidspaces 上游无隶属关系；Root 与未签名模块可能导致保修失效、触发应用风控。
- **没有 user namespace**：容器 root 就是宿主 root，capability 基本全开。不要跑不可信镜像，不要把它当沙箱。
- 仅用于合法拥有/授权的设备，不得用于绕过授权或安全机制。
- GPL-2.0，无担保；再分发需保留 LICENSE、NOTICE 与源码。

完整条款见 **[docs/DISCLAIMER.md](docs/DISCLAIMER.md)**。

## 已知边界

- `user_ns` 永远红（编译期决定，LKM 无解）；
- `/proc/<pid>/ns/` 目录不显示 `pid`/`ipc` 链接（只拦了 access/readlink，未拦 readdir），
  Droidspaces 的探针用 `access()`，所以检查通过；
- PID/IPC 是 syscall 层视图，不是内核原生命名空间；
- 容器 root = 宿主 root，32 个 capability 全开；
- OTA 换内核后 KMI/符号可能变，重测前先看 `dmesg | grep "ddl guard"` 与 `check --json`。

## Credits

- [ai-luo2006/droidspaces-6.12-pmb110](https://github.com/ai-luo2006/droidspaces-6.12-pmb110) — 本仓库的基座（分支来源）
- [Dere3046/_patchHarmony](https://github.com/Dere3046/_patchHarmony) — GKI 6.x LKM 上游
- [Dere3046/KallRecon](https://github.com/Dere3046/KallRecon) / Type_info / KernCall / HooKern — 运行期符号与 hook 基础设施
- [ravindu644/Droidspaces-OSS](https://github.com/ravindu644/Droidspaces-OSS) — 目标容器运行时
- OnePlusOSS 的内核源码与 DDK 工具链

## License

GPL-2.0。见 [LICENSE](LICENSE) 与 [NOTICE.md](NOTICE.md)。
