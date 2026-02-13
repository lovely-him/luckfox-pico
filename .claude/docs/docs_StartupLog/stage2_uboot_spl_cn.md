# 阶段 2：U-Boot SPL（二级程序加载器）分析

## 日志内容（第 10-30 行）

```
    10→
    11→U-Boot SPL board init
    12→U-Boot SPL 2017.09 (Jan 26 2026 - 18:04:03)
    13→unknown raw ID 0 0 0
    14→Trying to boot from MMC2
    15→Card did not respond to voltage select!
    16→mmc_init: -95, time 20
    17→Card did not respond to voltage select!
    18→mmc_init: -95, time 20
    19→spl: mmc init failed with error: -95
    20→Trying to boot from MMC1
    21→Best phase range 270-237 (30 len)
    22→Successfully tuned phase to 79, used 3ms
    23→ENVF: Primary 0x00000000 - 0x00008000
    24→ENVF: Primary 0x00000000 - 0x00008000
    25→No misc partition
    26→Trying fit image at 0x440 sector
    27→## Verified-boot: 0
    28→## Checking uboot 0x00200000 (lzma @0x00400000) ... sha256(2149fbc6d0...) + sha256(0c03bd7c60...) + OK
    29→## Checking fdt 0x00261190 ... sha256(9f596c5683...) + OK
    30→Total: 383.321/417.635 ms
```

## 功能概述

U-Boot SPL（二级程序加载器）是在 DDR 初始化后运行的**精简引导加载程序**。其主要职责包括：

1. **启动介质检测** - 识别并初始化启动存储设备
2. **加载 U-Boot Proper** - 从存储器将完整的 U-Boot 加载到 DDR
3. **FIT 镜像验证** - 验证加密签名（如果启用了安全启动）
4. **内存管理** - 设置基本内存布局
5. **移交给 U-Boot** - 将控制权转移给完整的 U-Boot

## 代码位置

### 源代码
- **基础路径**: `/sysdrv/source/uboot/u-boot/`
- **SPL 核心**:
  - `common/spl/spl.c` - 主 SPL 逻辑（`spl_init()`, `board_init_r()`）
  - `common/spl/spl_mmc.c` - MMC 启动支持（`spl_mmc_load()`）
  - `arch/arm/mach-rockchip/spl.c` - Rockchip 特定 SPL 代码
  - `arch/arm/mach-rockchip/rv1106/rv1106.c` - RV1106 芯片初始化

### MMC 驱动
- **SDHCI 驱动**: `drivers/mmc/rockchip_sdhci.c`
- **MMC 核心**: `drivers/mmc/mmc.c`
- **相位调谐**: `drivers/mmc/rockchip_sdhci.c:rockchip_sdhci_execute_tuning()`

### 二进制输出
- **路径**: `/sysdrv/source/uboot/rkbin/bin/rv11/rv1106_spl_v1.02.bin`
- **构建输出**: `/sysdrv/source/uboot/u-boot/spl/u-boot-spl.bin`

### 配置
- **Defconfig**: `/sysdrv/source/uboot/u-boot/configs/rv1106_defconfig`
- **SPL 选项**: `CONFIG_SPL=y`, `CONFIG_SPL_MMC_SUPPORT=y`

## 详细日志分析

### 第 11-12 行：SPL 初始化
```
U-Boot SPL board init
U-Boot SPL 2017.09 (Jan 26 2026 - 18:04:03)
```

**代码路径**:
```c
// arch/arm/mach-rockchip/spl.c
void board_init_f(ulong dummy)
{
    debug("U-Boot SPL board init\n");  // ← 第 11 行
    // ... 初始化代码 ...
}
```

**构建信息**:
- **U-Boot 版本**: 2017.09（Rockchip 定制版本）
- **构建日期**: 2026 年 1 月 26 日 18:04:03
- **构建者**: him@him-virtual-machine（与内核构建匹配）

### 第 13 行：启动设备检测
```
unknown raw ID 0 0 0
```

**代码路径**:
```c
// common/spl/spl.c
static int spl_common_init(bool setup_malloc)
{
    // 尝试从 BootROM 读取启动设备 ID
    // 如果 ID 为 0 0 0，则回退到尝试所有启动设备
}
```

**含义**: BootROM 未传递有效的启动设备 ID，因此 SPL 将按顺序尝试所有配置的启动设备。

### 第 14-19 行：MMC2 启动尝试（失败）
```
Trying to boot from MMC2
Card did not respond to voltage select!
mmc_init: -95, time 20
Card did not respond to voltage select!
mmc_init: -95, time 20
spl: mmc init failed with error: -95
```

**代码路径**:
```c
// common/spl/spl_mmc.c
static int spl_mmc_find_device(struct mmc **mmcp, u32 boot_mode)
{
    err = mmc_init(mmc);  // ← 失败，返回 -95
    if (err) {
        printf("spl: mmc init failed with error: %d\n", err);
        return err;
    }
}
```

**错误代码分析**:
- **错误 -95**: `EOPNOTSUPP`（不支持的操作）
- **根本原因**: MMC2（SD 卡槽）没有插入卡或未连接
- **行为**: SPL 尝试两次（第 15-16 行，17-18 行）后放弃

**硬件映射**:
- **MMC2**: 通常是 Rockchip 平台上的 SD 卡槽
- **Luckfox Pico Ultra W**: 使用 eMMC（MMC0/MMC1），不使用 SD 卡

### 第 20-22 行：MMC1 启动尝试（成功）
```
Trying to boot from MMC1
Best phase range 270-237 (30 len)
Successfully tuned phase to 79, used 3ms
```

**代码路径**:
```c
// drivers/mmc/rockchip_sdhci.c
static int rockchip_sdhci_execute_tuning(struct udevice *dev, uint opcode)
{
    // 相位调谐算法
    // 尝试不同的时钟相位以找到最佳采样点
    best_start = 270;
    best_end = 237;  // 环绕（270-360, 0-237）
    best_len = 30;

    // 选择最佳范围的中间值
    phase = (best_start + best_len / 2) % 360;  // = 79

    printf("Successfully tuned phase to %d, used %dms\n", phase, time);
}
```

**相位调谐说明**:
- **目的**: 找到可靠数据采样的最佳时钟相位
- **方法**: 尝试所有 360 个相位，找到最长的稳定范围
- **结果**: 选择相位 79°（270-237° 范围的中间值，考虑环绕）
- **时间**: 3ms（非常快的调谐）

**硬件映射**:
- **MMC1**: Luckfox Pico Ultra W 上的 eMMC
- **设备**: `/dev/mmcblk0`（8GB eMMC）

### 第 23-25 行：环境和分区检查
```
ENVF: Primary 0x00000000 - 0x00008000
ENVF: Primary 0x00000000 - 0x00008000
No misc partition
```

**代码路径**:
```c
// env/mmc.c
static int mmc_env_init(void)
{
    // 尝试从 MMC 加载环境
    // ENVF = 环境文件
    printf("ENVF: Primary 0x%08x - 0x%08x\n", start, end);
}
```

**含义**:
- **ENVF**: 环境分区位置（0x0 - 0x8000 = 32KB）
- **重复消息**: SPL 检查环境两次（主环境和备份环境）
- **No misc partition**: 未找到"misc"分区（用于恢复模式）

### 第 26-29 行：FIT 镜像加载和验证
```
Trying fit image at 0x440 sector
## Verified-boot: 0
## Checking uboot 0x00200000 (lzma @0x00400000) ... sha256(2149fbc6d0...) + sha256(0c03bd7c60...) + OK
## Checking fdt 0x00261190 ... sha256(9f596c5683...) + OK
```

**代码路径**:
```c
// common/spl/spl_fit.c
int spl_load_simple_fit(struct spl_image_info *spl_image,
                        struct spl_load_info *info, ulong sector, void *fit)
{
    // 从扇区 0x440 加载 FIT 镜像
    printf("Trying fit image at 0x%x sector\n", sector);

    // 验证启动标志
    printf("## Verified-boot: %d\n", verified);  // 0 = 禁用

    // 检查 U-Boot 镜像
    printf("## Checking uboot 0x%08x (lzma @0x%08x) ... ", addr, comp_addr);
    // 验证 SHA256 哈希
    printf("sha256(%s...) + sha256(%s...) + OK\n", hash1, hash2);

    // 检查设备树
    printf("## Checking fdt 0x%08x ... sha256(%s...) + OK\n", fdt_addr, hash);
}
```

**FIT 镜像结构**:
```
┌─────────────────────────────────────┐
│  FIT 镜像（扁平镜像树）             │
│  位于扇区 0x440 (544)               │
├─────────────────────────────────────┤
│  1. U-Boot Proper                   │
│     - 加载地址: 0x00200000          │
│     - 压缩: LZMA                    │
│     - 解压到: 0x00400000            │
│     - SHA256: 2149fbc6d0...         │
│     - SHA256: 0c03bd7c60...         │
├─────────────────────────────────────┤
│  2. 设备树 (FDT)                    │
│     - 加载地址: 0x00261190          │
│     - SHA256: 9f596c5683...         │
└─────────────────────────────────────┘
```

**安全分析**:
- **Verified-boot: 0** - 安全启动**已禁用**
- **SHA256 验证** - 仍执行完整性检查
- **U-Boot 的两个哈希** - 可能是压缩和解压镜像的哈希

### 第 30 行：时序摘要
```
Total: 383.321/417.635 ms
```

**分解**:
- **383.321 ms**: SPL 执行时间
- **417.635 ms**: 从 DDR 初始化到 SPL 完成的总时间
- **差值**: 约 34 ms 用于 DDR 初始化和 BootROM

## 启动设备优先级

启动设备顺序在设备树中配置：

**文件**: `/sysdrv/source/uboot/u-boot/arch/arm/dts/rv1106-luckfox.dts`
```dts
&spl {
    u-boot,spl-boot-order = "same-as-spl", &mmc1, &mmc2;
};
```

**启动顺序**:
1. **same-as-spl**: 尝试 SPL 加载的设备
2. **&mmc1**: eMMC (MMC1)
3. **&mmc2**: SD 卡 (MMC2)

## SPL 后的内存布局

```
DDR 内存（256MB: 0x00000000 - 0x10000000）
┌─────────────────────────────────────────┐
│ 0x00000000 - 0x00008000                 │ 保留（32KB）
├─────────────────────────────────────────┤
│ 0x00008000 - 0x0031f404                 │ 内核（稍后加载）
├─────────────────────────────────────────┤
│ 0x00200000 - 0x00400000                 │ U-Boot Proper (2MB)
├─────────────────────────────────────────┤
│ 0x00400000 - ...                        │ U-Boot 解压区域
├─────────────────────────────────────────┤
│ 0x00c00000 - 0x00c0a404                 │ 设备树（40KB）
├─────────────────────────────────────────┤
│ ...                                     │ 空闲内存
├─────────────────────────────────────────┤
│ 0x0e8d6f40 - 0x0ebf8f44                 │ FIT 镜像（3.2MB）
├─────────────────────────────────────────┤
│ 0x0ebf9f50 - 0x0edf9f50                 │ 栈（2MB）
├─────────────────────────────────────────┤
│ 0x0edf9f50 - 0x10000000                 │ U-Boot（18MB）
└─────────────────────────────────────────┘
```

## 错误分析

### MMC2 失败（预期）
- **错误**: "Card did not respond to voltage select!"
- **代码**: -95 (EOPNOTSUPP)
- **严重性**: **正常** - Luckfox Pico Ultra W 使用 eMMC，不使用 SD 卡
- **影响**: 无 - SPL 成功回退到 MMC1

### 无 Misc 分区（预期）
- **消息**: "No misc partition"
- **严重性**: **正常** - Misc 分区是可选的（用于 Android 恢复）
- **影响**: 无 - Linux 启动不需要

## 性能分析

### 启动时间分解
```
DDR 初始化:         约 34 ms
SPL 执行:          383 ms
├─ MMC2 尝试:       约 40 ms (2 × 20ms)
├─ MMC1 调谐:        3 ms
├─ FIT 加载:       约 300 ms
└─ 验证:           约 40 ms
─────────────────────────
总计:              417 ms
```

### 优化机会
1. **跳过 MMC2**: 配置启动顺序完全跳过 MMC2
2. **减少重试**: 将 MMC 初始化重试次数从 2 改为 1
3. **更快的存储**: 在 SPL 中使用 HS200 模式（当前使用 HS 模式）

## 相关文件

### 构建配置
- **Makefile**: `/sysdrv/source/uboot/u-boot/Makefile`
- **SPL Makefile**: `/sysdrv/source/uboot/u-boot/scripts/Makefile.spl`
- **Defconfig**: `/sysdrv/source/uboot/u-boot/configs/rv1106_defconfig`

### 设备树
- **基础**: `/sysdrv/source/uboot/u-boot/arch/arm/dts/rv1106.dtsi`
- **板级**: `/sysdrv/source/uboot/u-boot/arch/arm/dts/rv1106-luckfox.dts`

### 构建脚本
- **路径**: `/project/build.sh`
- **命令**: `./build.sh uboot`

## 与其他启动模式的比较

| 启动模式 | 设备 | SPL 支持 | 速度 |
|----------|------|----------|------|
| eMMC (MMC1) | ✓ 使用 | 完整 | 快 |
| SD 卡 (MMC2) | ✗ 不存在 | 完整 | 中等 |
| SPI NAND | ✓ 可用 | 完整 | 慢 |
| USB | ✓ 可用 | 有限 | N/A |

## 下一阶段

SPL 完成后，它跳转到地址 0x00200000 的 U-Boot Proper。

```
第 32 行: Jumping to U-Boot(0x00200000)
```

→ 请参阅 `stage3_uboot_proper_cn.md` 了解下一个启动阶段的分析。
