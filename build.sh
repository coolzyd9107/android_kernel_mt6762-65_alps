#!/usr/bin/env bash
# ============================================================
#  本地编译内核，默认打出可直接刷入的 AnyKernel3 包
#
#    bash build.sh                       默认 k65v1_64_bsp_defconfig
#    bash build.sh -c k79v1_64_defconfig 换配置
#    bash build.sh -j 8                  指定并发
#    bash build.sh --clean               先删 out/
#    bash build.sh --no-ak3              只出裸内核包
#    bash build.sh --debug               保留调试符号
#    bash build.sh --no-bakasu           不启用 BakaSU（默认启用）
#
#  第一次使用先跑：bash envsetup.sh
# ============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

DEFCONFIG="k65v1_64_bsp_defconfig"
JOBS="$(nproc)"
DO_CLEAN=0
MAKE_AK3=1
KEEP_DEBUG=0
BAKASU=1
OUT="out"

usage() { sed -n '2,14p' "$0"; }

while [ $# -gt 0 ]; do
	case "$1" in
		-c|--config) DEFCONFIG="$2"; shift 2 ;;
		-j|--jobs) JOBS="$2"; shift 2 ;;
		--clean) DO_CLEAN=1; shift ;;
		--no-ak3) MAKE_AK3=0; shift ;;
		--debug) KEEP_DEBUG=1; shift ;;
		--no-bakasu) BAKASU=0; shift ;;
		-h|--help) usage; exit 0 ;;
		*) echo "未知参数：$1" >&2; usage; exit 1 ;;
	esac
done

if [ ! -f "$ROOT/.buildenv" ]; then
	echo "先准备环境：bash envsetup.sh" >&2
	exit 1
fi
# shellcheck disable=SC1091
. "$ROOT/.buildenv"
if [ -z "${CC:-}" ]; then
	echo "CC 没有设置，重新跑一次 bash envsetup.sh" >&2
	exit 1
fi

CONFIG_FILE="arch/arm64/configs/$DEFCONFIG"
if [ ! -f "$CONFIG_FILE" ]; then
	echo "找不到配置：$CONFIG_FILE" >&2
	exit 1
fi

CC_WRAP="$CC"
if command -v ccache >/dev/null 2>&1; then
	CC_WRAP="ccache $CC"
fi

apply_build_fixes() {
	echo "==> 应用 GCC 兼容补丁（和 CI 一致，可重复执行）"
	sed -i 's/^inline void uclamp_se_set(/void uclamp_se_set(/' kernel/sched/sched.h
	sed -i 's/^inline void ksm_flock(/void ksm_flock(/' include/linux/keyslot-manager.h
	sed -i 's/^inline void blk_crypto_flock(/void blk_crypto_flock(/' include/linux/blk-crypto.h
	sed -i 's/^inline u32 spi_read_reg(/u32 spi_read_reg(/' drivers/misc/mediatek/cmdq/bridge/cmdq-bdg.h
	sed -i 's/^inline s32 spi_write_reg(/s32 spi_write_reg(/' drivers/misc/mediatek/cmdq/bridge/cmdq-bdg.h

	grep -rlZ -I -- "-Werror" drivers sound 2>/dev/null | tr '\0' '\n' \
		| grep -E '(Makefile|Kbuild\.mk|Kbuild)$' \
		| xargs -r sed -i 's/ *-Werror[^[:space:]]*//g'

	local dts_mk="arch/arm64/boot/dts/mediatek/Makefile"
	if ! grep -q 'mt6765\.dtb' "$dts_mk"; then
		sed -i '1a dtb-$(CONFIG_ARCH_MEDIATEK) += mt6765.dtb' "$dts_mk"
	fi
}

if [ "$DO_CLEAN" = "1" ]; then
	echo "==> 清理 $OUT/"
	rm -rf "$OUT"
fi

apply_build_fixes

echo "==> 配置：$DEFCONFIG"
make -j"$JOBS" ARCH=arm64 O="$OUT" "$DEFCONFIG"

if [ "$BAKASU" = "1" ]; then
	scripts/config --file "$OUT/.config" -e KSU -e KSU_MANUAL_HOOK -e KALLSYMS_ALL
else
	scripts/config --file "$OUT/.config" -d KSU -d KSU_MANUAL_HOOK -d KSU_TRACEPOINT_HOOK
fi

if [ "$KEEP_DEBUG" != "1" ]; then
	scripts/config --file "$OUT/.config" \
		-d DEBUG_INFO -d DEBUG_INFO_DWARF4 -d DEBUG_INFO_REDUCED -d GDB_SCRIPTS
fi
make -j"$JOBS" ARCH=arm64 O="$OUT" olddefconfig

echo "==> 编译（-j$JOBS，$(basename "$CC")）"
export KBUILD_BUILD_TIMESTAMP="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
make -j"$JOBS" ARCH=arm64 O="$OUT" CC="$CC_WRAP" KCFLAGS="-Wno-error" Image.gz

echo "==> 构建设备树"
make -j"$JOBS" ARCH=arm64 O="$OUT" CC="$CC_WRAP" KCFLAGS="-Wno-error" dtbs \
	|| echo "!! dtbs 构建有失败，继续打包内核部分"

echo "==> 打包"
VERSION="$(make -s ARCH=arm64 O="$OUT" kernelrelease)"
SHORT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo local)"
NAME="kernel-${DEFCONFIG%_defconfig}-$(date +%Y%m%d)-$SHORT_SHA"
if [ "$BAKASU" = "1" ]; then
	NAME="BakaSU-$NAME"
fi
KVER="${VERSION%%.*}.$(echo "${VERSION#*.}" | cut -d. -f1)"
mkdir -p dist

if [ "$MAKE_AK3" = "1" ] && [ -f AnyKernel3/anykernel.sh ]; then
	KIND="AnyKernel3"
	ak3="$ROOT/.ak3-build"
	rm -rf "$ak3"
	cp -a AnyKernel3 "$ak3"
	cp "$OUT/arch/arm64/boot/Image.gz" "$ak3/Image.gz"

	mkdir -p "$ak3/dtb"
	for f in u1pro.dtb u1pro-overlay.dtbo mt6765.dtb; do
		if [ -f "$OUT/arch/arm64/boot/dts/mediatek/$f" ]; then
			cp "$OUT/arch/arm64/boot/dts/mediatek/$f" "$ak3/dtb/"
		fi
	done

	# 只校验内核版本、不校验机型
	sed -i "s|^kernel.string=.*|kernel.string=$NAME ($VERSION)|" "$ak3/anykernel.sh"
	sed -i "s|^EXPECTED_KVER=.*|EXPECTED_KVER=$KVER;|" "$ak3/anykernel.sh"

	{
		echo "kernel    : $VERSION"
		echo "defconfig : $DEFCONFIG"
		echo "commit    : $(git rev-parse HEAD 2>/dev/null || echo unknown)"
		echo "compiler  : $("$CC" --version | head -n 1)"
		echo "built at  : $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
	} >"$ak3/BUILD_INFO.txt"

	(cd "$ak3" && zip -qr -9 "$ROOT/dist/$NAME.zip" .)
	rm -rf "$ak3"
else
	KIND="裸内核包"
	raw="dist/$NAME"
	rm -rf "$raw"
	mkdir -p "$raw"
	cp "$OUT/arch/arm64/boot/Image.gz" "$raw/Image.gz"
	cp "$OUT/System.map" "$raw/System.map"
	cp "$OUT/.config" "$raw/config"
	mkdir -p "$raw/dtb"
	for f in u1pro.dtb u1pro-overlay.dtbo mt6765.dtb; do
		if [ -f "$OUT/arch/arm64/boot/dts/mediatek/$f" ]; then
			cp "$OUT/arch/arm64/boot/dts/mediatek/$f" "$raw/dtb/"
		fi
	done
	{
		echo "kernel    : $VERSION"
		echo "defconfig : $DEFCONFIG"
		echo "commit    : $(git rev-parse HEAD 2>/dev/null || echo unknown)"
		echo "compiler  : $("$CC" --version | head -n 1)"
		echo "built at  : $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
	} >"$raw/BUILD_INFO.txt"
	(cd dist && zip -qr -9 "$NAME.zip" "$NAME")
	rm -rf "$raw"
fi

echo
echo "==> 完成：dist/$NAME.zip（$KIND）"
echo "    内核版本：$VERSION"
echo "    包大小：$(du -h "dist/$NAME.zip" | cut -f1)"
