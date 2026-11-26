#!/usr/bin/env bash
# ============================================================
#  本地构建环境准备
#
#    bash envsetup.sh            安装依赖 + 用发行版自带的交叉 gcc
#    bash envsetup.sh --lineage  额外克隆 LineageOS 的 gcc 4.9 预编译工具链
#
#  跑完会在仓库根目录生成 .buildenv，build.sh 会自动读取。
# ============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

ENV_FILE="$ROOT/.buildenv"
TOOLCHAIN_DIR="$ROOT/.toolchain"
USE_LINEAGE=0

for arg in "$@"; do
	case "$arg" in
		--lineage) USE_LINEAGE=1 ;;
		-h|--help) sed -n '2,10p' "$0"; exit 0 ;;
		*) echo "未知参数：$arg" >&2; exit 1 ;;
	esac
done

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
	command -v sudo >/dev/null 2>&1 && SUDO="sudo" || {
		echo "需要 root 或 sudo 安装依赖" >&2
		exit 1
	}
fi

install_deps() {
	echo "==> 安装构建依赖"
	if command -v apt-get >/dev/null 2>&1; then
		$SUDO apt-get update
		$SUDO apt-get install -y --no-install-recommends \
			build-essential git curl ca-certificates bc bison flex \
			libssl-dev libelf-dev xz-utils cpio zip unzip ccache python3
		# 交叉编译器：优先 gcc-10（和 CI 一致），没有就用发行版默认版本
		$SUDO apt-get install -y --no-install-recommends gcc-10-aarch64-linux-gnu 2>/dev/null ||
			$SUDO apt-get install -y --no-install-recommends gcc-aarch64-linux-gnu
	elif command -v dnf >/dev/null 2>&1; then
		$SUDO dnf install -y git bc bison flex openssl-devel elfutils-libelf-devel \
			xz cpio zip unzip ccache make gcc gcc-aarch64-linux-gnu
	elif command -v pacman >/dev/null 2>&1; then
		$SUDO pacman -Sy --needed --noconfirm base-devel git bc bison flex openssl \
			libelf xz cpio zip unzip ccache aarch64-linux-gnu-gcc
	else
		echo "!! 没识别到包管理器，请手动安装：" >&2
		echo "   build-essential/bc/bison/flex/libssl-dev/libelf-dev/xz/cpio/zip/ccache + aarch64 交叉 gcc" >&2
	fi
}

find_toolchain() {
	if [ "$USE_LINEAGE" = "1" ]; then
		local dir="$TOOLCHAIN_DIR/aarch64-linux-android-4.9"
		if [ ! -d "$dir" ]; then
			echo "==> 克隆 LineageOS gcc 4.9 预编译工具链（约 200MB）"
			mkdir -p "$TOOLCHAIN_DIR"
			git clone --depth=1 \
				https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-android-4.9 \
				"$dir"
		fi
		CC_BIN="$dir/bin/aarch64-linux-android-gcc"
		EXTRA_PATH="$dir/bin"
	else
		CC_BIN=""
		for c in aarch64-linux-gnu-gcc-10 aarch64-linux-gnu-gcc; do
			if command -v "$c" >/dev/null 2>&1; then
				CC_BIN="$(command -v "$c")"
				break
			fi
		done
		EXTRA_PATH=""
	fi

	[ -n "${CC_BIN:-}" ] && [ -x "$CC_BIN" ] || {
		echo "!! 找不到 aarch64 交叉编译器，换 --lineage 再试一次" >&2
		exit 1
	}
}

write_env() {
	local cross
	cross="$(basename "$CC_BIN")"
	cross="${cross%%gcc*}"

	{
		echo "# 由 envsetup.sh 生成，build.sh 会自动 source"
		if [ -n "$EXTRA_PATH" ]; then
			echo "export PATH=\"$EXTRA_PATH:\$PATH\""
		fi
		echo "export CROSS_COMPILE=$cross"
		echo "export CC=$CC_BIN"
	} >"$ENV_FILE"

	echo
	echo "==> 工具链"
	"$CC_BIN" --version | head -n 1
	make --version | head -n 1
	if command -v ccache >/dev/null 2>&1; then
		ccache --version | head -n 1
	fi

	echo
	echo "==> 已写入 $ENV_FILE"
	echo "    下一步：bash build.sh"
}

install_deps
find_toolchain
write_env
