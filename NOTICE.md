# NOTICE / 来源与许可

本仓库是 **OnePlus 15 适配分支**，不是从零实现。以下来源必须保留。

## 分支来源

- **基座**：[ai-luo2006/droidspaces-6.12-pmb110](https://github.com/ai-luo2006/droidspaces-6.12-pmb110)
  （GPL-2.0）。`src/droid_lkm`、`src/net_macvlan`、`src/net_ip6nat`、`module/` 的加载器与
  WebUI 框架来自该仓库；本分支在其上做 OP15 适配与修复。

- **上游语义**：[Dere3046/_patchHarmony](https://github.com/Dere3046/_patchHarmony)（GPL-2.0）。
  PID/IPC 命名空间、SysV IPC、mqueue 的实现在这里定义，pmb110 是其 6.12 适配分支。

- **目标运行时**：[ravindu644/Droidspaces-OSS](https://github.com/ravindu644/Droidspaces-OSS)（GPL-3.0）。
  本仓库不包含它的代码，只提供其所需的内核能力。

## 第三方依赖（随 `src/droid_lkm/deps` 一起分发）

| 项目 | 用途 | 许可 |
|---|---|---|
| [KallRecon](https://github.com/Dere3046/KallRecon) | 运行期从内核镜像恢复 kallsyms | GPL-2.0 |
| [Type_info](https://github.com/Dere3046/Type_info) | 运行期 BTF/DWARF 恢复结构体布局 | GPL-2.0 |
| [KernCall](https://github.com/Dere3046/KernCall) | syscall 表改写 | GPL-2.0 |
| [HooKern](https://github.com/Dere3046/HooKern) | inline hook / kprobe 引擎 | GPL-2.0 |
| vendorcompat（KMSDK 内置） | OPlus 厂商兼容层 | GPL-2.0 |

## 厂商源码

- 崩溃分析引用了 OnePlusOSS 公开的 `android_kernel_modules_and_devicetree_oneplus_sm8850`
  中 `vendor/oplus/kernel/cpu/sched/sched_assist/sa_ddl.c` 的实现，仅作接口/布局说明。

## 许可

本仓库整体按 **GPL-2.0** 发布。各第三方组件保留其原始版权与许可。
