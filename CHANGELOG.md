# 变更记录

## v1.0.24-op15 (2026-10-31)

- 只保留 **auto** 一个包（safe / lite 删除），文件名简化为 `phDroid-OP15-v1.0.24.zip`。
- WebUI 精简为**只保留模块加载菜单**：6 个模块复选框、加载选中、全部卸载、状态点、输出日志；删除容器管理、主题、诊断、网络优化、userns 等页面。
- 加载按依赖顺序逐个 `insmod`（已加载跳过），卸载按倒序 `rmmod`。
- 其余不变：ddl kprobe 守卫、pid_max 两段 clamp、KMI 校验、bootloop 守卫。

## v1.0.21-op15 (2026-10-29)

- **vendor ddl 守卫**：改为 kprobe 挂在 `update_ddl_hit_history` 入口，`p->pid >= PID_MAX_DEFAULT` 的调用直接返回，不再执行函数体。
  依据官方源码 `sa_ddl.c`：`ddl_sdata[PID_MAX_DEFAULT]` 是静态数组，`ddl_sdata[p->pid]` 无上界检查；旧版“替换指针”的方案在该内核上根本不生效。
- 参数语义：`ddl=1`（默认）挂守卫；`ddl=0` 完全不动 vendor 代码。
- 加载器显式传 `ddl=1`。
- 版本号统一升到 `v1.0.21-op15`（versionCode 10022），三个变体同时重打包。

## v1.0.20-op15

- 首次产出 6 个模块：`droid_lkm` / `vendor` / `misc` / `pids` / `macvlan` / `ip6table_nat`，基于 pmb110 基座 + DDK `android16-6.12`（KMI gen 6，clang-r536225）。
- 机型限制删除，只保留 KMI 校验（`*-android16-6-*`）。
- 修复 WebUI 把模块目录写死成 `/data/adb/modules/Droidspaces` 导致的“缺少 post-fs-data.sh”。
- 增加 `META-INF` 安装器、`customize.sh`、`load.sh`、`tools/confirm.sh` / `preflight.sh` / `postcheck.sh` / `crashlog.sh`。
- 三个变体：`auto`（无 no_boot，开机加载）、`safe`（带 no_boot）、`lite`（只加载 droid_lkm + vendor）。