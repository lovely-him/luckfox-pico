# Luckfox Pico Max SDK 项目

## 项目概述
这是 Luckfox Pico Max (RV1106G3) 开发板的 SDK，基于 Rockchip 官方 SDK 定制。
- **芯片**: RV1106G3 (ARM Cortex-A7)
- **Linux 内核**: 5.10.160
- **根文件系统**: Buildroot（完整功能）或 Busybox（快速启动）
- **启动介质**: SD 卡 / SPI NAND
- **开发环境**: Ubuntu 22.04（用于交叉编译）

## 目录结构

```
luckfox-pico/
├── project/         # 项目配置和构建脚本
│   ├── cfg/         # 板级配置文件
│   ├── app/         # 应用程序源码
│   └── build.sh     # 主构建脚本
├── sysdrv/          # 系统驱动（U-Boot、Kernel、Rootfs）
├── media/           # Rockchip 媒体库
├── tools/           # 工具链和烧录工具
├── output/          # 编译输出目录
│   └── image/       # 最终固件镜像
└── IMAGE/           # 预编译固件包
```

## 参考文档

- 详细使用说明: @README_CN.md
- 硬件参考信息: https://wiki.luckfox.com/zh/Luckfox-Pico-Pro-Max/
- 更新日志: @UPDATE_LOG_CN.md

## 文件操作规范

**创建/写入文件**：

- ✅ **优先使用** `Write` 工具 - 适用于所有文件大小
  ```typescript
  // Write 工具是 Claude Code 推荐的标准方法
  // 支持中小型文件（< 1000 行）
  // 类型安全，简单直接
  ```
- ✅ **大文件策略** - 当文件超过 1000 行时：
  - **方案 A**：分段创建多个小文件，最后合并
  - **方案 B**：使用 Write 工具创建主体，Edit 工具补充细节
  - **方案 C**：创建文件骨架，让用户补充内容
- ❌ **禁止使用** `Bash` 的 `cat`/`echo`/`printf` 创建文件
  - 原因：违反项目规范，难以维护，不利于类型检查
  - 例外：仅在 Write 工具确实无法工作时作为紧急备用

**文件操作最佳实践**：

1. **读取优先**：编辑现有文件前必须先用 `Read` 工具读取
2. **精确编辑**：使用 `Edit` 工具进行精确字符串替换
3. **路径规范**：始终使用绝对路径，避免相对路径
4. **编码安全**：确保文件使用 UTF-8 编码
5. **验证结果**：文件操作后使用 `Read` 或 `Bash ls` 验证
