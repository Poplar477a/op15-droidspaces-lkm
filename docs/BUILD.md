# 构建

目标是产出 6 个 `.ko`：`droid_lkm`、`droid_lkm_vendor`、`droid_lkm_misc`、`droid_lkm_pids`、
`macvlan`、`ip6table_nat`。

## 硬性条件

| 项 | 值 | 为什么 |
|---|---|---|
| KDIR | DDK `android16-6.12`（`UTS_RELEASE=6.12.76-4k`，KMI gen 6） | 提供 `Module.symvers` 与头文件 |
| 编译器 | `clang-r536225` | 与目标内核一致；KCFI 校验函数签名，错版本会 `CFI failure` 并关机 |
| 架构 | arm64，`LLVM=1 LLVM_IAS=1 CROSS_COMPILE=aarch64-linux-gnu-` | |
| 宿主工具 | git、make、python3、binutils（`strings`） | |

DDK 镜像：`docker.cnb.cool/ylarod/ddk/ddk-min:android16-6.12`
（内含 `/opt/ddk/clang/clang-r536225`、`/opt/ddk/kdir/android16-6.12`）。

## 方式 A：Docker

```sh
docker pull docker.cnb.cool/ylarod/ddk/ddk-min:android16-6.12
scripts/build-docker.sh android16-6.12
scripts/package.sh
```

产物：`build/out/android16-6.12/*.ko`，模块包：`dist/phDroid-OP15-<version>.zip`。

## 方式 B：没有 Docker

把 DDK 镜像的 rootfs 解出来，使 `$DDK_ROOT/opt/ddk/kdir/android16-6.12` 存在，然后：

```sh
DDK_ROOT=/path/to/ddk/root scripts/build-nodocker.sh android16-6.12
scripts/package.sh
```

原理：DDK 的 KDIR 里 `Makefile` 用绝对路径 `/opt/ddk/src/...`，所以脚本在
`unshare -r -m` 里 `mount --bind $DDK_ROOT/opt/ddk /opt/ddk`，再调用镜像里的 clang。
不需要 root。

### 拉取镜像层（无 Docker）

```sh
reg=docker.cnb.cool; repo=ylarod/ddk/ddk-min
TOK=$(curl -sS "https://$reg/service/token?service=cnb-registry&scope=repository:$repo:pull" \
      | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')
# 取 amd64 manifest，按 layers 顺序下载 blobs/<digest>.tar.gz，再按 manifest 顺序解包
```

注意：

- **必须按 manifest 顺序解包**，乱序会让 `/usr/lib` 里 libc 与 libm 来自不同层，
  表现为 `GLIBC_2.43 not found` 或 segfault；
- 宿主没有 `libdw` 时，`gendwarfksyms` 与 `pahole` 会失败。脚本会把镜像里的
  `libdw.so.1` / `libelf.so.1` 单独放到 `.libs/` 并通过 `LD_LIBRARY_PATH` 指过去，
  不要直接把整个镜像 `/usr/lib` 加进路径。

## 打包

```sh
scripts/package.sh
```

会把 `module/` 与 `build/out/<kmi>/*.ko` 打成一个 KernelSU 模块 zip，
权限规范化为 `.sh=0755`、其余 `0644`，根目录必须有 `module.prop`。

## 常见失败

| 输出 | 原因 | 处理 |
|---|---|---|
| `CFI failure` + 关机 | clang 与内核不一致 | 用 DDK 里的 clang |
| `Unknown symbol` | 内核未导出该符号 | 换成运行期 kallsyms 解析 |
| `vermagic ... should be ...` | vermagic 后缀不一致 | 确认 KMI 分支与 `MODVERSIONS` |
| `No rule to make target .../vendorcompat/deps.mk` | 缺 `.sdk/builtin` | 从完整源码树复制，不要只拷 `src/` |
