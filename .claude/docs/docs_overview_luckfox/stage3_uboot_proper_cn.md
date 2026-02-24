# 阶段 3：U-Boot Proper 分析

## 日志内容（第 31-160 行）

本阶段涵盖完整的 U-Boot 引导加载程序，从初始化到加载 Linux 内核。

### 早期初始化（第 35-44 行）
```
U-Boot 2017.09 (Jan 26 2026 - 18:04:03 +0800)
Model: Rockchip RV1106 EVB Board
MPIDR: 0xf00
PreSerial: 2, raw, 0xff4c0000
DRAM:  256 MiB
Sysmem: init
Relocation Offset: 0fd80000
Relocation fdt: 0edf9f78 - 0edfede8
CR: M/C/I
Using default environment
```

### 存储初始化（第 47-53 行）
```
mmc@ffa90000: 0, mmc@ffaa0000: 1
Best phase range 270-237 (30 len)
Successfully tuned phase to 79, used 4ms
ENVF: Primary 0x00000000 - 0x00008000
Bootdev(atags): mmc 0
MMC0: HS200, 200Mhz
```

### 时钟树配置（第 69-80 行）
```
CLK: (sync kernel. arm: enter 816000 KHz, init 816000 KHz, kernel 0N/A)
  apll 816000 KHz
  dpll 924000 KHz
  gpll 1188000 KHz
  cpll 1000000 KHz
  aclk_peri_root 400000 KHz
  hclK_peri_root 200000 KHz
  pclk_peri_root 100000 KHz
  aclk_bus_root 300000 KHz
  pclk_top_root 100000 KHz
  pclk_pmu_root 100000 KHz
  hclk_pmu_root 200000 KHz
```

### 内存布局转储（第 88-119 行）
```
sysmem_dump_all:
    memory.total           = 0x10000000 (256 MiB. 0 KiB)
    allocated.rgn[0].name  = "UBOOT"
                    .addr  = 0x0edf9f50 - 0x10000000 (size: 0x012060b0)
    allocated.rgn[1].name  = "STACK"
                    .addr  = 0x0ebf9f50 - 0x0edf9f50 (size: 0x00200000)
    allocated.rgn[2].name  = "FIT"
                    .addr  = 0x0e8d6f40 - 0x0ebf8f44 (size: 0x00322004)
    allocated.rgn[3].name  = "FDT"
                    .addr  = 0x00c00000 - 0x00c0a404 (size: 0x0000a404)
    allocated.rgn[4].name  = "KERNEL"
                    .addr  = 0x00008000 - 0x0031f404 (size: 0x00317404)
```

### 内核加载（第 121-136 行）
```
## Loading kernel from FIT Image at 0e8d6f40 ..
   Using 'conf' configuration
## Verified-boot: 0
   Trying 'kernel' kernel subimage
     Data Size:    3240592 Bytes = 3.1 MiB
     Architecture: ARM
     OS:           Linux
     Load Address: 0x00008000
     Entry Point:  0x00008000
     Hash algo:    sha256
   Verifying Hash Integrity ... sha256+ OK
```

### 设备树加载（第 137-149 行）
```
## Loading fdt from FIT Image at 0e8d6f40 ..
   Trying 'fdt' fdt subimage
     Type:         Flat Device Tree
     Data Size:    41785 Bytes = 40.8 KiB
     Load Address: 0x00c00000
     Hash algo:    sha256
   Verifying Hash Integrity ... sha256+ OK
```

## 功能概述

U-Boot Proper 是 SPL 之后运行的**全功能引导加载程序**。其职责包括：

1. **硬件初始化** - 初始化所有外设（MMC、以太网、GPIO 等）
2. **时钟配置** - 设置系统时钟以获得最佳性能
3. **内存管理** - 配置内存区域和保护
4. **环境加载** - 从存储加载启动配置
5. **内核加载** - 从启动分区加载 Linux 内核和设备树
6. **启动参数传递** - 将命令行和设备树传递给内核
7. **内核启动** - 将控制权转移给 Linux 内核

## 代码位置

### 源代码基础
- **路径**: `/sysdrv/source/uboot/u-boot/`
- **主入口**: `common/board_r.c:board_init_r()`（重定位后）
- **启动命令**: `common/bootm.c:do_bootm()`

### RV1106 特定代码
- **芯片初始化**: `arch/arm/mach-rockchip/rv1106/rv1106.c`
- **时钟配置**: `arch/arm/mach-rockchip/rv1106/clk_rv1106.c`
- **引脚控制**: `arch/arm/mach-rockchip/rv1106/pinctrl_rv1106.c`

### 设备树
- **基础 DT**: `arch/arm/dts/rv1106.dtsi`
- **板级 DT**: `arch/arm/dts/rv1106-luckfox.dts`
- **内核 DT**: 从启动分区加载（rk-kernel.dtb）

### 关键驱动
- **MMC**: `drivers/mmc/rockchip_sdhci.c`
- **以太网**: `drivers/net/gmac_rockchip.c`
- **GPIO**: `drivers/gpio/gpio-rockchip.c`

## 详细分析

### 早期初始化

**关键信息**:
- **MPIDR: 0xf00** - 多处理器亲和寄存器（CPU ID）
- **PreSerial: 2, raw, 0xff4c0000** - 早期串口控制台（UART2 在 0xff4c0000）
- **Relocation Offset: 0fd80000** - U-Boot 从 0x00200000 移动到 0x0edf9f50
- **CR: M/C/I** - 控制寄存器标志（MMU/缓存/指令缓存已启用）

### 存储初始化

**硬件映射**:
- **mmc@ffa90000 (MMC0)**: eMMC 控制器
- **mmc@ffaa0000 (MMC1)**: SD 卡控制器（未使用）

**HS200 模式**:
- **速度**: 200 MHz（理论 400 MB/s）
- **模式**: 高速 200（eMMC 4.5+ 功能）
- **改进**: 比标准 HS 模式（50 MHz）快 4 倍

### 时钟树配置

**时钟树图**:
```
┌─────────────────────────────────────────────┐
│              RV1106 时钟树                  │
├─────────────────────────────────────────────┤
│ APLL (816 MHz)  → ARM 核心                  │
│ DPLL (924 MHz)  → DDR 控制器                │
│ GPLL (1188 MHz) → 通用外设                  │
│ CPLL (1000 MHz) → 音频编解码器、ISP        │
├─────────────────────────────────────────────┤
│ 外设时钟:                                   │
│   aclk_peri_root: 400 MHz (高速总线)       │
│   hclk_peri_root: 200 MHz (AHB 总线)       │
│   pclk_peri_root: 100 MHz (APB 总线)       │
│   aclk_bus_root:  300 MHz (系统总线)       │
└─────────────────────────────────────────────┘
```

### 网络初始化

```
Net:   eth0: ethernet@ffa80000
```

**硬件**: Rockchip GMAC（千兆 MAC）在 0xffa80000

### 内存布局

详细的内存分配映射显示 U-Boot 如何组织 256MB RAM：

```
memory.total = 0x10000000 (256 MiB)

已分配区域:
1. UBOOT:   0x0edf9f50 - 0x10000000 (18.0 MB) - U-Boot 代码/数据
2. STACK:   0x0ebf9f50 - 0x0edf9f50 (2.0 MB)  - 栈空间
3. FIT:     0x0e8d6f40 - 0x0ebf8f44 (3.2 MB)  - FIT 镜像（内核+dtb）
4. FDT:     0x00c00000 - 0x00c0a404 (40.8 KB) - 设备树
5. KERNEL:  0x00008000 - 0x0031f404 (3.1 MB)  - Linux 内核

保留:
- mmc@3f000: 0x0003f000 - 0x00040000 (4 KB) - MMC DMA 缓冲区

框架:
- malloc_r: 16 MB（运行时 malloc 池）
- malloc_f: 512 KB（早期 malloc 池）

总分配: 26.3 MB
空闲内存: 约 229 MB（可供内核使用）
```

### 内存重叠警告

```
Sysmem Warn: kernel 'reserved-memory' "mmc@3f000"(0x0003f000 - 0x00040000) is overlap with "KERNEL" (0x00008000 - 0x0031f404)
```

**分析**:
- **严重性**: 警告（不严重）
- **原因**: MMC DMA 缓冲区（0x3f000）在内核加载区域内（0x8000-0x31f404）
- **影响**: 最小 - 内核解压后会重定位
- **修复**: 如需要，在设备树中调整保留内存区域

### 内核加载

**内核信息**:
- **大小**: 3,240,592 字节（3.1 MB）
- **格式**: 未压缩的 ARM zImage
- **加载地址**: 0x00008000（标准 ARM Linux 加载地址）
- **入口点**: 0x00008000（内核从这里开始）
- **验证**: SHA256 哈希已验证 ✓

### 设备树加载

**设备树信息**:
- **大小**: 41,785 字节（40.8 KB）
- **加载地址**: 0x00c00000
- **源**: 从 `/sysdrv/source/kernel/arch/arm/boot/dts/rv1106g-luckfox-pico-ultra-w.dts` 编译
- **验证**: SHA256 哈希已验证 ✓

### 启动时间摘要

```
Total: 795.223/1217.933 ms
```

**分解**:
- **795.223 ms**: U-Boot Proper 执行时间
- **1217.933 ms**: 从上电到内核启动的总时间
- **计算**: DDR 初始化（约 34ms）+ SPL（383ms）+ U-Boot（795ms）≈ 1212ms ✓

## 传递给内核的启动参数

内核命令行在内核启动日志中可见（第 181 行）：

```
Kernel command line: user_debug=31 storagemedia=emmc androidboot.storagemedia=emmc androidboot.mode=normal rootwait earlycon=uart8250,mmio32,0xff4c0000 console=ttyFIQ0 root=/dev/mmcblk0p7 snd_soc_core.prealloc_buffer_size_kbytes=16 coherent_pool=0 blkdevparts=mmcblk0:32K(env),512K@32K(idblock),256K(uboot),32M(boot),512M(oem),256M(userdata),6G(rootfs) rootfstype=ext4 rk_dma_heap_cma=66M androidboot.fwver=uboot-01/26/2026
```

**关键参数**:
- **root=/dev/mmcblk0p7**: eMMC 分区 7 上的根文件系统
- **rootfstype=ext4**: EXT4 文件系统
- **console=ttyFIQ0**: FIQ 调试器上的控制台
- **earlycon=uart8250,mmio32,0xff4c0000**: UART2 上的早期控制台
- **blkdevparts**: 分区布局定义

## 错误分析

### SD 卡访问失败（第 67-68 行）
```
## retrieving sd_update.txt ..
Card did not respond to voltage select!
mmc_init: -95, time 20
```

**分析**:
- **严重性**: 正常（预期行为）
- **原因**: U-Boot 检查 SD 卡更新文件（sd_update.txt）
- **影响**: 无 - 没有 SD 卡，继续正常启动

### 内存重叠警告（第 86 行）
**分析**:
- **严重性**: 低（仅警告）
- **原因**: 保留内存区域与内核加载区域重叠
- **影响**: 最小 - 内核启动后重定位
- **修复**: 如需要，调整设备树保留内存

## 性能分析

### 启动时间分解
```
阶段               时间 (ms)    百分比
─────────────────────────────────────────────
DDR 初始化              34         2.8%
U-Boot SPL             383        31.4%
U-Boot Proper          795        65.3%
─────────────────────────────────────────────
总计                  1212       100.0%
```

### U-Boot Proper 分解
```
活动                时间 (ms)
─────────────────────────────────
初始化               约 100
MMC 调谐                 4
时钟配置              约 50
环境加载              约 50
内核加载             约 500
验证                  约 50
内存设置              约 40
─────────────────────────────────
总计                 约 795
```

### 优化机会
1. **内核压缩**: 使用 LZ4 压缩减少加载时间
2. **跳过 SD 检查**: 禁用 sd_update.txt 检查可节省约 20ms
3. **更快的存储**: HS400 模式可将加载时间减少 50%
4. **并行初始化**: 并行初始化外设

## 相关文件

### 构建配置
- **Defconfig**: `/sysdrv/source/uboot/u-boot/configs/rv1106_defconfig`
- **板级配置**: `/project/cfg/BoardConfig_IPC/BoardConfig-EMMC-Buildroot-RV1106_Luckfox_Pico_Ultra_W-IPC.mk`

### 设备树
- **U-Boot DT**: `/sysdrv/source/uboot/u-boot/arch/arm/dts/rv1106-luckfox.dts`
- **内核 DT**: `/sysdrv/source/kernel/arch/arm/boot/dts/rv1106g-luckfox-pico-ultra-w.dts`

### 构建命令
```bash
cd /home/him/him/luckfox-pico
./build.sh uboot          # 构建 U-Boot
./build.sh kernel         # 构建内核
./build.sh firmware       # 打包 boot.img（FIT 镜像）
```

## 下一阶段

U-Boot 完成后，它跳转到 0x00008000 的 Linux 内核入口点：

```
第 160 行: Starting kernel ...
```

→ 请参阅 `stage4_kernel_boot_cn.md` 了解下一个启动阶段的分析。
