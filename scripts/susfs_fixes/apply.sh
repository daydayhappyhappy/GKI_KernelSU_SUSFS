#!/usr/bin/env bash
# scripts/susfs_fixes/apply.sh
# 应用 SUSFS 补丁到内核源码树。
# 由 build.yml「应用 SUSFS 补丁」步骤调用，该步骤本身已通过
#   if: inputs.enable_susfs
# 门控，本脚本无需再判 ksu_mode。但保留一次防御性检查，防止被其他流程误调用。
#
# 所需环境变量（由 build.yml 在该步骤的 env 中传入）：
#   ANDROID_VERSION  KERNEL_VERSION  KSU_VARIANT  OS_PATCH_LEVEL  SUB_LEVEL
#   KERNEL_ROOT       —— 内核源码根目录，含 common/ 等
#   GITHUB_WORKSPACE  —— 仓库根目录，含 susfs4ksu/ 与 scripts/
set -euo pipefail

: "${ANDROID_VERSION:?需要 ANDROID_VERSION}"
: "${KERNEL_VERSION:?需要 KERNEL_VERSION}"
: "${KSU_VARIANT:?需要 KSU_VARIANT}"
: "${KERNEL_ROOT:?需要 KERNEL_ROOT}"

SUSFS_BRANCH="gki-${ANDROID_VERSION}-${KERNEL_VERSION}"
SUSFS_SRC="${GITHUB_WORKSPACE:-$PWD}/susfs4ksu"
COMMON="${KERNEL_ROOT}/common"

if [ ! -d "$SUSFS_SRC/.git" ] && [ ! -d "$SUSFS_SRC/kernel_patches" ]; then
  echo "::error::未找到 SUSFS 源码目录: $SUSFS_SRC（当前非 SUSFS 构建却进入了 apply 流程？）" >&2
  exit 1
fi

echo "SUSFS 分支: $SUSFS_BRANCH  变体: $KSU_VARIANT"
echo "SUSFS 源码: $SUSFS_SRC"
echo "内核 common: $COMMON"

SUSFS_PATCHES="${SUSFS_SRC}/kernel_patches"
[ -d "$SUSFS_PATCHES" ] || { echo "::error::未找到 SUSFS 补丁目录 $SUSFS_PATCHES" >&2; exit 1; }

# 1) 把 SUSFS 内核代码拷进源码树
echo "==> 拷贝 SUSFS 内核文件到 $COMMON"
cp -v "$SUSFS_PATCHES"/fs/*         "$COMMON/fs/"         2>/dev/null || true
cp -v "$SUSFS_PATCHES"/include/linux/* "$COMMON/include/linux/" 2>/dev/null || true

# 2) 找对应内核版本的补丁文件（可能有多个候选，取首个匹配）
PATCH_FILE=$(find "$SUSFS_PATCHES" -maxdepth 1 -type f -name "50_add_susfs_in_gki-${ANDROID_VERSION}-${KERNEL_VERSION}*.patch" | head -n 1)
if [ -z "$PATCH_FILE" ]; then
  # 回退：不带 android 前缀的命名
  PATCH_FILE=$(find "$SUSFS_PATCHES" -maxdepth 1 -type f -name "50_add_susfs_in_gki-*.patch" | head -n 1)
fi

if [ -z "$PATCH_FILE" ]; then
  echo "::error::未找到 50_add_susfs_in_gki 补丁（分支 $SUSFS_BRANCH）" >&2
  echo "可用补丁：" >&2
  find "$SUSFS_PATCHES" -maxdepth 1 -type f -name "*.patch" >&2 || true
  exit 1
fi

echo "==> 应用补丁: $(basename "$PATCH_FILE")"
cp "$PATCH_FILE" "$COMMON/"
(
  cd "$COMMON"
  # --fuzz=3 容忍上游行号偏移；-p1 剥一层目录前缀
  patch --fuzz=3 -p1 < "$(basename "$PATCH_FILE")" || {
    echo "::error::SUSFS 补丁应用失败，请检查是否已有改动" >&2
    exit 1
  }
)

# 3) SukiSU / ReSukiSU 还需要额外的一个补丁（susfs 与 KSU 共存的桥接）
case "$KSU_VARIANT" in
  SukiSU|ReSukiSU)
    EXTRA=$(find "$SUSFS_PATCHES" -maxdepth 1 -type f -name "10_enable_susfs_for_ksu*.patch" | head -n 1)
    if [ -n "$EXTRA" ] && [ -d "$KERNEL_ROOT/KernelSU" ]; then
      echo "==> 应用 KSU-SUSFS 桥接补丁: $(basename "$EXTRA")"
      cp "$EXTRA" "$KERNEL_ROOT/KernelSU/" 2>/dev/null || true
      ( cd "$KERNEL_ROOT/KernelSU" && patch -p1 --forward < "$(basename "$EXTRA")" ) || true
    fi
    ;;
esac

echo "SUSFS 补丁应用完成"
