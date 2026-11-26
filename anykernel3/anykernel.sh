### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers
## 适配 ALPS MT6762/MT6765 (4.19) — kernel.string 由 CI 打包时自动填写
##
## 注意：这块主板被很多机型使用，所以不做机型校验（do.devicecheck=0），
##       只核对设备当前内核版本与目标版本是否一致。

### AnyKernel setup
# global properties
properties() { '
kernel.string=MT6762/MT6765 Kernel
do.devicecheck=0
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties

### AnyKernel install
## boot files attributes
boot_attributes() {
set_perm_recursive 0 0 755 644 $RAMDISK/*;
set_perm_recursive 0 0 750 750 $RAMDISK/init* $RAMDISK/sbin;
} # end attributes

# boot shell variables
# MTK 机型 boot 分区路径不统一，从常见路径里挑一个存在的
BLOCK=/dev/block/platform/bootdevice/by-name/boot;
[ -e /dev/block/bootdevice/by-name/boot ] && BLOCK=/dev/block/bootdevice/by-name/boot;
[ -e /dev/block/by-name/boot ] && BLOCK=/dev/block/by-name/boot;
IS_SLOT_DEVICE=0;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

# 目标内核版本（CI 打包时按实际内核改写，这里只是兜底值）
EXPECTED_KVER=4.19;

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh;

# 只核对内核版本，不校验机型（同主板多机型）
cur_kver=$(sed -n 's/^Linux version \([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' /proc/version 2>/dev/null | head -n1);
if [ -n "$cur_kver" ] && [ "$cur_kver" != "$EXPECTED_KVER" ]; then
  abort "当前内核版本 ${cur_kver}.x 与目标 ${EXPECTED_KVER}.x 不一致，已停止刷入";
fi;

# boot install
dump_boot;
write_boot;
## end boot install
