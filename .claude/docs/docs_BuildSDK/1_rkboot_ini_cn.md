# RKBOOT INI 配置文件详解

## 概述

`RV1106MINIALL*.ini` 文件是 Rockchip 打包工具的配置文件，用于指定如何将各个二进制组件打包成最终的启动镜像。

## 文件位置

```
sysdrv/source/uboot/rkbin/RKBOOT/
├── RV1106MINIALL.ini                 # 普通启动
├── RV1106MINIALL_EMMC_TB.ini         # eMMC Thunderboot
├── RV1106MINIALL_SPI_NAND_TB.ini     # SPI NAND Thunderboot
├── RV1106MINIALL_EMMC_TB_NOMCU.ini   # eMMC TB 无 MCU
└── ...
```

## 配置节详解

### 示例：RV1106MINIALL.ini（普通模式）

```ini
[CHIP_NAME]
NAME=RV1106

[VERSION]
MAJOR=1
MINOR=1

[CODE471_OPTION]
NUM=1
Path1=bin/rv11/rv1106_ddr_924MHz_v1.15.bin
Sleep=1

[CODE472_OPTION]
NUM=1
Path1=bin/rv11/rv1106_usbplug_v1.09.bin

[LOADER_OPTION]
NUM=2
LOADER1=FlashData
LOADER2=FlashBoot
FlashData=bin/rv11/rv1106_ddr_924MHz_v1.15.bin
FlashBoot=bin/rv11/rv1106_spl_v1.02.bin

[OUTPUT]
PATH=rv1106_download_v1.15.108.bin
IDB_PATH=rv1106_idblock_v1.15.102.img

[SYSTEM]
NEWIDB=true

[FLAG]
471_RC4_OFF=true
RC4_OFF=true
CREATE_IDB=true
```

## 各节说明

### [CHIP_NAME]

```ini
NAME=RV1106
```

芯片型号标识，用于打包工具识别目标平台。

### [VERSION]

```ini
MAJOR=1
MINOR=1
```

配置文件版本号，用于兼容性检查。

### [CODE471_OPTION] - DDR 初始化

```ini
NUM=1
Path1=bin/rv11/rv1106_ddr_924MHz_v1.15.bin
Sleep=1
```

- **CODE471**：Rockchip 内部代号，指 DDR 初始化代码
- **Path1**：DDR 初始化二进制文件路径
- **Sleep=1**：初始化后延时（毫秒）

### [CODE472_OPTION] - USB 下载模式

```ini
NUM=1
Path1=bin/rv11/rv1106_usbplug_v1.09.bin
```

- **CODE472**：USB 下载/烧录模式代码
- 当设备进入 Maskrom 模式时，BootROM 加载此代码支持 USB 烧录

### [LOADER_OPTION] - 启动加载器组件

普通模式（2 个组件）：
```ini
NUM=2
LOADER1=FlashData
LOADER2=FlashBoot
FlashData=bin/rv11/rv1106_ddr_924MHz_v1.15.bin    # DDR 初始化
FlashBoot=bin/rv11/rv1106_spl_v1.02.bin           # U-Boot SPL
```

Thunderboot 模式（3 个组件）：
```ini
NUM=3
LOADER1=FlashData
LOADER2=Hpmcu
LOADER3=FlashBoot
FlashData=bin/rv11/rv1106_ddr_924MHz_tb_v1.15.bin
Hpmcu=bin/rv11/rv1106_hpmcu_tb_v1.01.bin          # MCU 固件
FlashBoot=bin/rv11/rv1106_spl_emmc_tb_v1.00.bin
```

### [LOADER2_PARAM] - MCU 加载参数（仅 TB 模式）

```ini
LOAD_ADDR=0x40000    # MCU 固件加载地址
FLAG=0x10007         # 启动标志
```

### [OUTPUT] - 输出文件

```ini
PATH=rv1106_download_v1.15.108.bin    # USB 下载镜像
IDB_PATH=rv1106_idblock_v1.15.102.img # ID Block 镜像
```

### [FLAG] - 功能开关

```ini
471_RC4_OFF=true    # 禁用 CODE471 的 RC4 加密
RC4_OFF=true        # 禁用整体 RC4 加密
CREATE_IDB=true     # 生成 ID Block 镜像
```

### [BOOT0_PARAM] - 启动参数（仅 eMMC TB 模式）

```ini
WORD_0=0x434D4D45   # "EMMC" 的 ASCII（小端序）
WORD_1=0x0
...
```

传递给 BootROM 的启动介质标识。

## 不同配置文件对比

| 文件 | 启动介质 | 模式 | 组件数 | 包含 MCU |
|------|----------|------|--------|----------|
| `RV1106MINIALL.ini` | 通用 | 普通 | 2 | 否 |
| `RV1106MINIALL_EMMC_TB.ini` | eMMC | Thunderboot | 3 | 是 |
| `RV1106MINIALL_SPI_NAND_TB.ini` | SPI NAND | Thunderboot | 3 | 是 |
| `RV1106MINIALL_EMMC_TB_NOMCU.ini` | eMMC | TB 无 MCU | 2 | 否 |

## Thunderboot 说明

Thunderboot（雷电启动）是 Rockchip 的快速启动技术：

- **目标**：设备在 < 1 秒内完成启动并开始工作
- **原理**：利用 RV1106 内部的 HPMCU 核心，在 U-Boot SPL 阶段就加载 MCU 固件
- **MCU 职责**：独立初始化摄像头、ISP，开始采集图像
- **CPU 职责**：继续加载内核、挂载文件系统
- **优势**：MCU 和 CPU 并行工作，大幅缩短出图时间

## INI 文件选择机制

选择优先级（从低到高）：

1. **默认值**：`RKBOOT/${RKCHIP_LOADER}MINIALL.ini`
2. **defconfig 指定**：`CONFIG_LOADER_INI="xxx.ini"`
3. **命令行参数**：`./make.sh loader xxx.ini`

## 生成的文件用途

```
rv1106_idblock_v1.15.102.img
    ↓
写入存储介质的最开头（SD卡/eMMC/SPI NAND 的第 0 扇区开始）
    ↓
包含：DDR Init + SPL（+ MCU，如果是 TB 模式）
    ↓
BootROM 上电后从这里读取并执行
```

## 相关文件

- 打包脚本：`rkbin/scripts/spl.sh`
- 打包工具：`rkbin/tools/boot_merger`
- U-Boot 构建脚本：`u-boot/make.sh`
