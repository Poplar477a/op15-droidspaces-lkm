phDroid OP15 (Droidspaces LKM)

目标：OnePlus 15 / 原厂内核 6.12.x-android16-6（KMI gen 6）
工具链：clang-r536225，DDK android16-6.12

安装后位置：/data/adb/modules/phdroid-op15
默认带 no_boot，开机不加载，避免 bootloop。

手动加载：
  su
  MOD=/data/adb/modules/phdroid-op15
  insmod $MOD/ko/droid_lkm.ko gate=0 mqueue=1 nspid=1 nspid_append=1
  insmod $MOD/ko/droid_lkm_vendor.ko ghost=1 ghost_match=oplus_ pid_max_cap=0
  insmod $MOD/ko/droid_lkm_misc.ko
  insmod $MOD/ko/droid_lkm_pids.ko
  insmod $MOD/ko/macvlan.ko
  insmod $MOD/ko/ip6table_nat.ko

一键确认（会加载主模块）：
  sh $MOD/tools/confirm.sh load

确认稳定后开自启：
  rm $MOD/no_boot

回滚：
  安全模式启动，或 rm -rf /data/adb/modules/phdroid-op15
