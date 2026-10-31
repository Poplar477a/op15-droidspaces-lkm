# 注意事项与免责声明

使用本仓库的模块前请读完。安装即表示你理解并接受以下内容。

## 1. 风险自担

- 这些模块在**内核态**修改系统行为（syscall 表、/proc 呈现、kprobe、厂商数据结构），
  错误使用可能导致**死机、随机重启、数据损坏，极端情况下无法开机**。
- 作者与贡献者不对任何设备损坏、数据丢失、保修失效或由此产生的其他损失负责。
- 请只在**你拥有并有能力恢复**的设备上使用；首次安装前做好数据备份，并确认有
  fastboot / recovery / 安全模式等救砖手段。

## 2. 非官方项目

- 本项目是社区个人作品，与 **OnePlus / OPPO / 高通 / Google / Droidspaces 上游**均无隶属或背书关系。
- 不代表任何厂商立场，不提供官方支持。
- 解锁 Bootloader、Root、加载未签名内核模块可能导致**保修失效**，并可能触发部分应用
  （银行、DRM、Play Integrity 等）的风控，这属于预期行为。

## 3. 安全边界（重要）

- **PID / IPC 命名空间是 syscall 层视图，不是内核原生的 pid_namespace**；
- **没有 user namespace**（`CONFIG_USER_NS=n`），容器里的 root **就是宿主 root**；
- 容器内 capability 基本全开，没有真正的权限隔离；
- 因此：**不要用这套方案运行来源不明的镜像、不要把密码/密钥放进容器、不要把它当沙箱**。
  它适合跑自己信任的服务（nginx、redis、自写程序），不适合多租户或不可信负载。

## 4. 合规使用

- 仅用于你合法拥有或获授权管理的设备。
- 不得用于绕过付费/授权、规避安全机制、侵犯他人隐私或其他违法用途。
- 模块会加载未签名内核代码，可能违反部分设备的使用条款；是否使用由你自行判断。

## 5. 来源与许可

- 本仓库基于 [ai-luo2006/droidspaces-6.12-pmb110](https://github.com/ai-luo2006/droidspaces-6.12-pmb110)，
  后者基于 [Dere3046/_patchHarmony](https://github.com/Dere3046/_patchHarmony)；
  详见 [NOTICE.md](../NOTICE.md)。
- 代码按 **GPL-2.0** 发布，**不提供任何担保**（见 [LICENSE](../LICENSE)）。
- 再分发（包括打包进第三方 ROM/模块）必须保留版权声明、LICENSE 与 NOTICE，并提供对应源码。

## 6. 数据与隐私

- 模块本身不收集、不上传任何数据；所有日志（`load.log`、`history.log`）都留在本机。
- 提交 issue 时请先脱敏：`dmesg` / pstore / logcat 里可能含设备序列号、账号、路径等信息。

## 7. 兼容性与变更

- 仅对 [docs/COMPATIBILITY.md](COMPATIBILITY.md) 列出的范围做过验证；其他机型/内核不保证。
- OTA、换内核、换 KMI 代次后需要重新验证，必要时重新编译。
- 作者可能随时修改或停止维护，不承诺长期支持。

## 8. 问题反馈

反馈时请附：

1. `uname -r`、设备型号、系统版本；
2. `dmesg | grep -iE "CFI failure|Unknown symbol|UBSAN|droid_lkm"` 的输出；
3. `/proc/last_boot_reason`、pstore（若有）；
4. `/data/adb/modules/phdroid-op15/load.log` 与 `history.log` 的尾部；
5. 复现步骤。

没有日志的“崩溃了/不生效”很难定位，通常会被要求先补齐上述信息。
