# ./build.sh uboot 构建流程详解

## 概述

`./build.sh uboot` 命令用于编译和打包 U-Boot 引导加载程序，涉及启动流程的前三个阶段。

## 涉及的启动阶段

| 阶段 | 名称 | 来源 | 说明 |
|------|------|------|------|
| 1 | DDR Init | 预编译二进制 | 初始化 DDR 内存控制器 |
| 2 | U-Boot SPL | 源码编译 | 第二阶段引导程序 |
| 3 | U-Boot Proper | 源码编译 | 完整引导加载程序 |

## 预编译 vs 源码编译

### 预编译二进制文件（来自 rkbin）

这些文件由 Rockchip 提供，无源码，直接使用：

| 文件 | 路径 | 用途 |
|------|------|------|
| DDR Init | `rkbin/bin/rv11/rv1106_ddr_924MHz_v1.15.bin` | 初始化 DDR 内存 |
| USB Plug | `rkbin/bin/rv11/rv1106_usbplug_v1.09.bin` | USB 烧录模式支持 |
| MCU 固件 | `rkbin/bin/rv11/rv1106_hpmcu_tb_v1.01.bin` | Thunderboot 模式（可选） |

### 源码编译

| 组件 | 源码目录 | 输出文件 |
|------|----------|----------|
| U-Boot SPL | `u-boot/` | `spl/u-boot-spl.bin` |
| U-Boot Proper | `u-boot/` | `u-boot.bin` |

## 构建流程

```
./build.sh uboot
       │
       ▼
┌──────────────────────────────────────────────────────────────────┐
│ 步骤 1: make defconfig                                           │
│   合并 luckfox_rv1106_uboot_defconfig + rk-emmc.config           │
│   生成 .config                                                   │
└──────────────────────────────────────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────────────────────────────┐
│ 步骤 2: make.sh --spl                                            │
│   ├─ 编译 U-Boot SPL (spl/u-boot-spl.bin)     ← 源码编译         │
│   ├─ 编译 U-Boot Proper (u-boot.bin)          ← 源码编译         │
│   └─ 调用 spl.sh 打包                                            │
└──────────────────────────────────────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────────────────────────────┐
│ 步骤 3: spl.sh 打包 idblock.img                                  │
│   读取 RV1106MINIALL.ini，合并：                                 │
│   ├─ DDR Init (rv1106_ddr_924MHz_v1.15.bin)   ← 预编译           │
│   └─ U-Boot SPL (u-boot-spl.bin)              ← 刚编译的         │
│   输出 → idblock.img                                             │
└──────────────────────────────────────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────────────────────────────┐
│ 步骤 4: 打包 uboot.img                                           │
│   将 U-Boot Proper 打包成 FIT 格式                               │
│   输出 → uboot.img                                               │
└──────────────────────────────────────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────────────────────────────┐
│ 步骤 5: 复制到输出目录                                           │
│   output/image/idblock.img                                       │
│   output/image/uboot.img                                         │
│   output/image/download.bin                                      │
└──────────────────────────────────────────────────────────────────┘
```

## 输出文件

| 文件 | 典型大小 | 内容 | 用途 |
|------|----------|------|------|
| `idblock.img` | ~188 KB | DDR Init + U-Boot SPL | 写入存储介质开头，BootROM 加载 |
| `uboot.img` | ~256 KB | U-Boot Proper (FIT格式) | SPL 加载并执行 |
| `download.bin` | ~268 KB | DDR Init + SPL + USB Plug | USB 烧录模式使用 |

## 文件内部结构

### idblock.img

```
┌─────────────────────────────────────┐
│  IDB Header (ID Block 头)           │
├─────────────────────────────────────┤
│  DDR Init Binary (预编译)           │  ← rv1106_ddr_924MHz_v1.15.bin
│  - 初始化 DDR 内存控制器            │
│  - 配置 924MHz 频率                 │
├─────────────────────────────────────┤
│  U-Boot SPL (源码编译)              │  ← u-boot-spl.bin
│  - 初始化基本硬件                   │
│  - 从存储介质加载 uboot.img         │
│  - 跳转到 U-Boot Proper             │
└─────────────────────────────────────┘
```

### uboot.img

```
┌─────────────────────────────────────┐
│  FIT Header                         │
├─────────────────────────────────────┤
│  U-Boot Proper (源码编译)           │  ← u-boot.bin
│  - 完整的引导加载程序               │
│  - 加载内核和设备树                 │
│  - 启动 Linux                       │
├─────────────────────────────────────┤
│  Device Tree Blob                   │
└─────────────────────────────────────┘
```

## INI 配置文件选择机制

### 选择逻辑（优先级从低到高）

1. **默认值**：根据芯片名拼接
   ```bash
   INI_LOADER = RKBOOT/${RKCHIP_LOADER}MINIALL.ini
              = RKBOOT/RV1106MINIALL.ini
   ```

2. **defconfig 指定**：
   ```bash
   # 如果 .config 中定义了 CONFIG_LOADER_INI
   CONFIG_LOADER_INI="RV1106MINIALL_EMMC_TB.ini"
   ```

3. **命令行参数**：最高优先级

### 常用 INI 文件

| 文件 | 启动模式 | 包含 MCU |
|------|----------|----------|
| `RV1106MINIALL.ini` | 普通启动 | 否 |
| `RV1106MINIALL_EMMC_TB.ini` | eMMC Thunderboot | 是 |
| `RV1106MINIALL_SPI_NAND_TB.ini` | SPI NAND Thunderboot | 是 |

## 启动介质识别

启动介质不是由 INI 文件决定，而是通过：

1. **defconfig fragment**：`rk-emmc.config` 或 `rk-sfc.config`
2. **BootROM 自动探测**：按优先级尝试 SD卡 → eMMC → SPI NOR → SPI NAND

## 源码目录结构

```
sysdrv/source/uboot/
├── rkbin/                              # 预编译二进制文件
│   ├── bin/rv11/
│   │   ├── rv1106_ddr_924MHz_v1.15.bin
│   │   ├── rv1106_usbplug_v1.09.bin
│   │   └── rv1106_hpmcu_tb_v1.01.bin
│   ├── RKBOOT/
│   │   ├── RV1106MINIALL.ini
│   │   └── RV1106MINIALL_EMMC_TB.ini
│   └── tools/                          # 打包工具
│
└── u-boot/                             # U-Boot 源码
    ├── arch/arm/mach-rockchip/rv1106/  # RV1106 平台代码
    ├── configs/
    │   ├── luckfox_rv1106_uboot_defconfig
    │   └── rk-emmc.config
    ├── spl/                            # SPL 编译输出
    │   └── u-boot-spl.bin
    ├── u-boot.bin                      # U-Boot Proper 输出
    └── make.sh                         # 构建脚本
```

## 相关命令

```bash
# 编译 uboot
./build.sh uboot

# 清理 uboot
./build.sh clean uboot

# 查看当前配置信息
./build.sh info
```

## 参考文档

- INI 配置文件详解：见 `docs_BuildSDK/rkboot_ini_cn.md`
- 启动日志分析：见 `docs_StartupLog/` 目录
