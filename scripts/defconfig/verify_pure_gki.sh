#!/usr/bin/env bash
# scripts/defconfig/verify_pure_gki.sh
# 校验当前 defconfig 不含任何 KSU / SUSFS / KPM 残留符号。
# 仅在「禁用KSU」模式下需要，用作纯 GKI 构建的守门器：
#   - 上游分支 / 自定义 fragment 万一残留 =y，bazel 的 defconfig 检查会直接失败，
#     这个脚本能在「配置内核选项」步骤之前就把它抓出来，报错信息也更明确。
#
# 用法: bash scripts/defconfig/verify_pure_gki.sh <DEFCONFIG_PATH> <KSU_MODE>
set -euo pipefail

DEFCONFIG="${1:-}"
KSU_MODE="${2:-}"

if [ -z "$DEFCONFIG" ]; then
  echo "用法: $0 <DEFCONFIG_PATH> [KSU_MODE]" >&2
  exit 2
fi
if [ ! -f "$DEFCONFIG" ]; then
  echo "::error::defconfig 不存在: $DEFCONFIG" >&2
  exit 2
fi

# 非纯 GKI 模式直接放行，不做任何检查
case "$KSU_MODE" in
  禁用KSU|禁用SUSFS) ;;
  *) echo "verify_pure_gki: 非纯 GKI 模式（$KSU_MODE），跳过检查"; exit 0 ;;
esac

echo "verify_pure_gki: 检查 $DEFCONFIG"

# 需要禁止的符号清单：凡是被设成 =y/m 都视为污染
FORBIDDEN=(
  CONFIG_KSU
  CONFIG_KSU_SUSFS
  CONFIG_KSU_MANUAL_HOOK
  CONFIG_KSU_KPROBES_HOOK
  CONFIG_KSU_KPROBES_HOOK_OLD
  CONFIG_KSU_SUSFS_SUS_PATH
  CONFIG_KSU_SUSFS_SUS_MOUNT
  CONFIG_KSU_SUSFS_SUS_KSTAT
  CONFIG_KSU_SUSFS_SUS_MAP
  CONFIG_KSU_SUSFS_SPOOF_UNAME
  CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG
  CONFIG_KSU_SUSFS_OPEN_REDIRECT
  CONFIG_KSU_SUSFS_SUS_SU
  CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT
  CONFIG_KPM
)

errors=0
for sym in "${FORBIDDEN[@]}"; do
  # 精确匹配：符号名结尾必须是空格或行尾/注释，避免误伤同名前缀
  line=$(grep -E "^${sym}=[ym]" "$DEFCONFIG" || true)
  if [ -n "$line" ]; then
    echo "::error::发现禁止符号: $line" >&2
    errors=$((errors + 1))
  fi
done

if [ "$errors" -gt 0 ]; then
  echo "::error::defconfig 检出 $errors 个 KSU/SUSFS/KPM 残留符号，本次为纯 GKI 构建，请先清除" >&2
  exit 1
fi

echo "verify_pure_gki: defconfig 洁净，无 KSU/SUSFS/KPM 残留"
