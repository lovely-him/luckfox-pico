#!/bin/bash
#
# docker.sh - Docker 构建环境封装脚本
# 用法: ./docker.sh [build.sh 的任意参数]
# 示例: ./docker.sh lunch
#       ./docker.sh uboot
#       ./docker.sh kernel
#       ./docker.sh        (一键全编译, 同 ./build.sh)
#

DOCKER_IMAGE="luckfoxtech/luckfox_pico:1.0"
SDK_PATH="$(cd "$(dirname "$0")" && pwd)"

# ── 1. 若已在容器内, 直接透传给 build.sh ──────────────────────────────────────
if [ -f "/.dockerenv" ]; then
    exec "${SDK_PATH}/build.sh" "$@"
fi

# ── 2. 检查 Docker 是否安装 ────────────────────────────────────────────────────
if ! command -v docker &>/dev/null; then
    echo "[docker.sh:error] Docker 未安装"
    echo "[docker.sh:info]  安装命令: sudo apt install docker.io -y"
    exit 1
fi

# ── 3. 确定是否需要 sudo ───────────────────────────────────────────────────────
DOCKER_CMD="docker"
if ! docker info &>/dev/null 2>&1; then
    if sudo docker info &>/dev/null 2>&1; then
        DOCKER_CMD="sudo docker"
    else
        echo "[docker.sh:error] Docker 守护进程未运行或无访问权限"
        echo "[docker.sh:info]  尝试: sudo systemctl start docker"
        echo "[docker.sh:info]  或将当前用户加入 docker 组: sudo usermod -aG docker \$USER"
        exit 1
    fi
fi

# ── 4. 检查镜像, 不存在则自动拉取 ─────────────────────────────────────────────
if ! $DOCKER_CMD image inspect "${DOCKER_IMAGE}" &>/dev/null 2>&1; then
    echo "[docker.sh:info] 本地镜像 '${DOCKER_IMAGE}' 不存在, 正在拉取..."
    $DOCKER_CMD pull "${DOCKER_IMAGE}" || {
        echo "[docker.sh:error] 拉取镜像失败: ${DOCKER_IMAGE}"
        exit 1
    }
fi

# ── 5. 区分交互式指令与编译指令 ──────────────────────────────────────────────
# 交互式指令列表 (需要 TTY 且无需保存日志) 
INTERACTIVE_CMDS="lunch menuconfig"
BUILD_CMD=true
for _cmd in ${INTERACTIVE_CMDS}; do
    if [ "${1}" = "${_cmd}" ]; then
        if [ -t 1 ]; then
            BUILD_CMD=false
        else
            echo "[docker.sh:error] '${1}' 需要交互式终端, 当前环境无 TTY"
            exit 1
        fi
        break
    fi
done
unset _cmd

# ── 6. 友善提示 ───────────────────────────────────────────────────────────────
# echo "[docker.sh:info] 提示: 若曾在宿主机直接编译过, 请在进入容器前先清理中间产物:"
# echo "[docker.sh:info]   rm -rf sysdrv/source/buildroot/buildroot-2023.02.6/output"
# echo "[docker.sh:info]   ./build.sh clean sysdrv"
# echo "[docker.sh:info] (output/image 固件文件无需清理)"

# ── 7. 在容器中执行 ────────────────────────────────────────────────────────────
echo "[docker.sh:info] 使用镜像: ${DOCKER_IMAGE}"
echo "[docker.sh:info] SDK 路径: ${SDK_PATH}"

if [ "${BUILD_CMD}" = "false" ]; then
    # 交互式指令 (lunch) : 分配 TTY, 不记录日志
    $DOCKER_CMD run --rm -it --privileged \
        -v "${SDK_PATH}:/home" \
        "${DOCKER_IMAGE}" \
        bash -c 'cd /home && ./build.sh "$@"' -- "$@"
    exit $?
fi

# 编译指令: tee 同步输出到终端和日志文件
LOG_TARGET="${1:-all}"
LOG_FILE="${SDK_PATH}/output/logs/build_$(date +%Y%m%d_%H%M%S)_${LOG_TARGET}.log"
mkdir -p "${SDK_PATH}/output/logs"
echo "[docker.sh:info] 日志将同步保存至: ${LOG_FILE}"

set -o pipefail
$DOCKER_CMD run --rm -i --privileged \
    -e PYTHONUNBUFFERED=1 \
    -v "${SDK_PATH}:/home" \
    "${DOCKER_IMAGE}" \
    bash -c 'stdbuf -oL -eL sh -c "cd /home && ./build.sh \"\$@\""' -- "$@" 2>&1 | tee "${LOG_FILE}"
BUILD_EXIT=${PIPESTATUS[0]}

if [ ${BUILD_EXIT} -ne 0 ]; then
    echo "[docker.sh:error] 构建失败 (exit ${BUILD_EXIT}), 日志: ${LOG_FILE}"
else
    echo "[docker.sh:info]  构建完成, 日志: ${LOG_FILE}"
fi
exit ${BUILD_EXIT}
