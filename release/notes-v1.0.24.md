## v1.0.24-op15

OnePlus 15（PLK110，6.12.77-android16-6，KMI gen 6）的 Droidspaces 内核模块支持。

- 只保留 **auto** 一个模块包：开机自动加载 6 个模块；
- WebUI 精简为**模块加载菜单**（勾选、加载、全部卸载、状态、日志）；
- vendor 的 ddl 表替换改为 **kprobe 守卫**：`update_ddl_hit_history` 对 `pid >= PID_MAX_DEFAULT` 的调用直接跳过，
  修复 OPlus 调度器 UBSAN 数组越界导致的随机重启；
- `pid_max` 在 post-fs-data 与 late service 两段压回 32768；
- 基线校验只看 KMI（`*-android16-6-*`），不锁机型。

验证：连续运行 2 天，跑完 SPEC2017 全套，无重启；`droidspaces check --json` 除 `user_ns` 外全绿。

本仓库是 [ai-luo2006/droidspaces-6.12-pmb110](https://github.com/ai-luo2006/droidspaces-6.12-pmb110) 的分支，
后者基于 [Dere3046/_patchHarmony](https://github.com/Dere3046/_patchHarmony)。

sha256: `6887d9e81a063a03ba0c0c40356695d8a50e72a27e6498e8a242425d57f331db`

> 2026-10-31 重新打包：修正 `module.prop` 的作者字段（基座作者 ai-luo 见 NOTICE/README）。
