#!/usr/bin/env bash
# scripts/clone_deps.sh
# 克隆构建所需的依赖仓库，按 ksu_mode / ksu_variant 门控，跳过无用的 KSU / SUSFS 仓库
# 用法: bash scripts/clone_deps.sh <KSU_MODE> <KSU_VARIANT> <ANDROID_VERSION> <KERNEL_VERSION>
#
# 调用方已在 build.yml 的「克隆依赖仓库」步骤中 export 了：
#   LEGACY_SUKISU_CONFIG  —— 来自 inputs.ksu_variant 的 SukiSU(40xxx) 固定提交配置，可为空
set -euo pipefail

KSU_MODE="${1:-关闭}"
KSU_VARIANT="${2:-SukiSU}"
ANDROID_VERSION="${3:-android15}"
KERNEL_VERSION="${4:-6.6}"

SUSFS_BRANCH="gki-${ANDROID_VERSION}-${KERNEL_VERSION}"
LEGACY_SUKISU_CONFIG="${LEGACY_SUKISU_CONFIG:-}"

# 判断是否真的需要 SUSFS 源码：禁用 KSU 时不需要；禁用 SUSFS 时也不需要
NEED_SUSFS=1
if [ "$KSU_MODE" = "禁用KSU" ] || [ "$KSU_MODE" = "禁用SUSFS" ]; then
  NEED_SUSFS=0
fi

echo "clone_deps: KSU_MODE=$KSU_MODE  KSU_VARIANT=$KSU_VARIANT  SUSFS_BRANCH=$SUSFS_BRANCH  NEED_SUSFS=$NEED_SUSFS"

# ---------- 任何模式都要的 ----------
echo "克隆 AnyKernel3..."
git clone https://github.com/WildKernels/AnyKernel3.git -b gki-2.0
rm -rf AnyKernel3/.git

echo "准备通用补丁资源..."
git clone https://github.com/WildKernels/kernel_patches.git
git clone https://github.com/Numbersf/Action-Build.git --depth=1

# ---------- 按需克隆 SUSFS ----------
if [ "$NEED_SUSFS" -eq 1 ]; then
  echo "克隆 SUSFS (分支: $SUSFS_BRANCH)..."

  if [ -n "$LEGACY_SUKISU_CONFIG" ]; then
    git clone https://gitlab.com/simonpunk/susfs4ksu.git -b "$SUSFS_BRANCH"
  elif [ "$KSU_VARIANT" = "SukiSU" ]; then
    if ! git clone https://github.com/ShirkNeko/susfs4ksu.git -b "$SUSFS_BRANCH" 2>/dev/null; then
      echo "ShirkNeko 仓库未找到分支 $SUSFS_BRANCH，回退到 simonpunk 原版..."
      git clone https://gitlab.com/simonpunk/susfs4ksu.git -b "$SUSFS_BRANCH"
    fi
  else
    git clone https://gitlab.com/simonpunk/susfs4ksu.git -b "$SUSFS_BRANCH"
  fi

  if [ -n "$LEGACY_SUKISU_CONFIG" ]; then
    SUSFS_FIXED_COMMIT=$(grep "^${SUSFS_BRANCH}=" "$LEGACY_SUKISU_CONFIG" | cut -d'=' -f2-)
    if [ -z "$SUSFS_FIXED_COMMIT" ]; then
      echo "未在 $LEGACY_SUKISU_CONFIG 配置 $SUSFS_BRANCH 的固定 SUSFS 提交" >&2
      exit 1
    fi
    echo "$KSU_VARIANT 固定 SUSFS 提交: $SUSFS_FIXED_COMMIT"
    git -C susfs4ksu checkout "$SUSFS_FIXED_COMMIT"
  fi

  CONFIG_FILE="config/config"
  if [ -z "$LEGACY_SUKISU_CONFIG" ] && [ -f "$CONFIG_FILE" ]; then
    CUSTOM_ENABLED=$(grep "^custom=" "$CONFIG_FILE" | cut -d'=' -f2)
    if [ "$CUSTOM_ENABLED" = "true" ]; then
      CUSTOM_COMMIT=$(grep "^${SUSFS_BRANCH}=" "$CONFIG_FILE" | cut -d'=' -f2)
      if [ -n "$CUSTOM_COMMIT" ]; then
        echo "切换 SUSFS 到自定义提交: $CUSTOM_COMMIT"
        git -C susfs4ksu checkout "$CUSTOM_COMMIT"
      fi
    fi
  fi

  SUSFS_LATEST_COMMIT_DATE=$(git -C susfs4ksu log -1 --date=format:'%Y-%m-%d %H:%M:%S %z' --format='%cd')
  echo "SUSFS_LATEST_COMMIT_DATE=$SUSFS_LATEST_COMMIT_DATE" >> "$GITHUB_ENV"
  echo "SUSFS 仓库最新提交日期: $SUSFS_LATEST_COMMIT_DATE"

  # SukiSU 变体需要配套的 SukiSU_patch
  if [ "$KSU_VARIANT" = "SukiSU" ]; then
    git clone https://github.com/ShirkNeko/SukiSU_patch.git
  fi
else
  echo "跳过 SUSFS 仓库克隆（ksu_mode=$KSU_MODE）"
  # 下游步骤可能读取 $SUSFS_LATEST_COMMIT_DATE，给一个兜底值
  echo "SUSFS_LATEST_COMMIT_DATE=未集成（纯 GKI 构建）" >> "$GITHUB_ENV"
fi
