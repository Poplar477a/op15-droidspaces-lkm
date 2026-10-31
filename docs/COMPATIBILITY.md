# 兼容性声明

## 支持范围

| 项 | 要求 |
|---|---|
| 机型 | OnePlus 15（PLK110 / CPH2745 / CPH2747 / CPH2749） |
| 内核 | GKI `6.12.x-android16-6`，**KMI generation 6** |
| 内核版本 | 实测 `6.12.77-android16-6-g********-...`；同代 6.12.x 理论可用 |
| 编译器 | 内核必须由 **clang-r536225**（Android clang 19.0.1）构建（KCFI） |
| Root | KernelSU / APatch（Magisk 未验证） |
| Droidspaces | v7.x（实测 v7.1.0） |

本仓库的模块按 **KMI gen 6** 编译（DDK `android16-6.12`，`UTS_RELEASE=6.12.76-4k`）。
开启 `CONFIG_MODVERSIONS` 后内核只比较 vermagic 第一个空格之后的部分，因此 6.12.76 编译的模块
可以加载到同代的 6.12.112 等子版本上；跨 **KMI generation**（如 `-android16-5-`）不保证。

## 内核必须已有的能力

这些是模块工作的前提，缺失时模块会加载失败或功能降级：

| 配置 | 用途 |
|---|---|
| `CONFIG_MODULES=y` | 加载 `.ko` |
| `CONFIG_MODULE_SIG_FORCE` **不是** y | 允许加载未签名模块 |
| `CONFIG_KALLSYMS_ALL=y` | 运行期符号解析（KallRecon / kprobe） |
| `CONFIG_DEBUG_INFO_BTF=y` | 运行期恢复结构体布局（Type_info） |
| `CONFIG_MODVERSIONS=y` | 跨子版本加载 |
| `CONFIG_CFI_CLANG=y` | 要求编译器匹配，否则 `CFI failure` + 关机 |
| `CONFIG_IKCONFIG_PROC=y` | 便于排查（`/proc/config.gz`） |

## 不需要内核开启的项

模块在运行期补齐：PID/IPC/mqueue 命名空间、devtmpfs、pids 控制器、macvlan、IPv6 NAT。
原厂内核里这些通常是关闭的，属于预期情况。

## 明确不支持

- 非 GKI 内核、6.12 以前的 GKI 分支；
- KMI generation 5（`6.12.23-android16-5`）未验证，需按 6.12.23 源码重建 KDIR；
- `CONFIG_MODULE_SIG_FORCE=y` 的内核（未签名模块无法加载）；
- **user namespace**（`CONFIG_USER_NS`）：编译期裁剪，模块无解；
- GrapheneOS 等限制 `unshare`/命名空间系统调用的系统；
- 其他厂商的 6.12 内核（未适配其 vendor 模块布局，尤其 OPlus 的 ddl 表结构）。

## 怎么确认兼容

```sh
su
uname -r                                  # 必须含 -android16-6-
zcat /proc/config.gz | grep -E "MODULE_SIG_FORCE|KALLSYMS_ALL|DEBUG_INFO_BTF|CFI_CLANG"
dmesg | grep -i "ddl guard"                # armed 表示 vendor 守卫挂上
droidspaces check --json                   # requirements_met=1
```

设备侧还有现成脚本：

```sh
sh /data/adb/modules/phdroid-op15/tools/preflight.sh   # 加载前体检
sh /data/adb/modules/phdroid-op15/tools/confirm.sh     # 加载/验收
```

## 版本漂移

OTA 换内核后，KMI 代次或符号可能变化。升级后先确认：

1. `uname -r` 仍是 `-android16-6-`；
2. `dmesg | grep "ddl guard"` 仍是 `armed`；
3. `droidspaces check --json` 仍 `requirements_met=1`；
4. 出现 `Unknown symbol` 时，说明设备导出符号变了，需要把对应符号改成运行期 kallsyms 解析；
5. 需要重新编译时，用与设备一致的 DDK KDIR 和 clang。
