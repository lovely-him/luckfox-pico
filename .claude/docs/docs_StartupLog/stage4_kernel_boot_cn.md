# 阶段 4：Linux 内核启动分析

## 日志内容（第 161-393 行）

本阶段涵盖从早期启动到挂载根文件系统的内核初始化。

### 早期启动（第 162-210 行）
```
[    0.000000] Booting Linux on physical CPU 0x0
[    0.000000] Linux version 5.10.160 (him@him-virtual-machine)
[    0.000000] CPU: ARMv7 Processor [410fc075] revision 5 (ARMv7), cr=50c53c7d
[    0.000000] OF: fdt: Machine model: Luckfox Pico Ultra W
[    0.000000] Memory policy: Data cache writeback
[    0.000000] Reserved memory: created CMA memory pool at 0x0f600000, size 10 MiB
[    0.000000] cma: Reserved 67584 KiB at 0x0b400000
```

### 子系统初始化（第 211-280 行）
```
[    0.027309] rockchip-gpio ff380000.gpio: probed /pinctrl/gpio@ff380000
[    0.040730] fiq_debugger fiq_debugger.0: IRQ uart_irq not found
[    0.041021] printk: console [ttyFIQ0] enabled
[    0.043145] usbcore: registered new interface driver usbfs
[    0.044552] Advanced Linux Sound Architecture Driver Initialized.
[    0.045042] Bluetooth: Core ver 2.22
```

### 驱动加载（第 281-380 行）
```
[    0.179906] rk_gmac-dwmac ffa80000.ethernet: init for RMII
[    0.187927] ehci_hcd: USB 2.0 'Enhanced' Host Controller (EHCI) Driver
[    0.215533] Synopsys Designware Multimedia Card Interface Driver
[    0.278270] mmc0: new high speed MMC card at address 0001
[    0.279464]  mmcblk0: p1(env) p2(idblock) p3(uboot) p4(boot) p5(oem) p6(userdata) p7(rootfs)
```

### 根文件系统挂载（第 385-393 行）
```
[    0.417791] EXT4-fs (mmcblk0p7): INFO: recovery required on readonly filesystem
[    0.479368] EXT4-fs (mmcblk0p7): recovery complete
[    0.479899] EXT4-fs (mmcblk0p7): mounted filesystem with ordered data mode
[    0.479971] VFS: Mounted root (ext4 filesystem) readonly on device 179:7.
[    0.483988] Run /sbin/init as init process
```

## 功能概述

Linux 内核启动过程包括：

1. **CPU 初始化** - 检测 CPU 功能，启用缓存，设置 MMU
2. **内存管理** - 初始化内存区域、CMA 和页面分配器
3. **设备树解析** - 从设备树解析硬件描述
4. **子系统初始化** - 初始化核心内核子系统（VFS、网络等）
5. **驱动探测** - 加载并初始化设备驱动
6. **根文件系统挂载** - 挂载根分区并启动 init 进程

## 代码位置

### 内核源代码基础
- **路径**: `/sysdrv/source/kernel/`
- **版本**: Linux 5.10.160
- **构建**: him@him-virtual-machine, Mon Jan 26 18:04:45 HKT 2026

### 关键源文件

#### 早期启动
- **入口点**: `arch/arm/kernel/head.S` - 汇编入口点
- **主初始化**: `init/main.c:start_kernel()` - C 入口点
- **CPU 设置**: `arch/arm/kernel/setup.c:setup_arch()`
- **内存初始化**: `arch/arm/mm/init.c:bootmem_init()`

#### RV1106 特定代码
- **平台**: `arch/arm/mach-rockchip/rockchip.c`
- **电源管理**: `arch/arm/mach-rockchip/rv1106_pm.c`
- **时钟驱动**: `drivers/clk/rockchip/clk-rv1106.c`

#### 设备树
- **基础**: `arch/arm/boot/dts/rv1106.dtsi`
- **RV1106G3**: `arch/arm/boot/dts/rv1106g3.dtsi`
- **板级**: `arch/arm/boot/dts/rv1106g-luckfox-pico-ultra-w.dts`

#### 关键驱动
- **GPIO/Pinctrl**: `drivers/pinctrl/pinctrl-rockchip.c`
- **MMC**: `drivers/mmc/host/dw_mmc-rockchip.c`
- **以太网**: `drivers/net/ethernet/stmicro/stmmac/dwmac-rk.c`
- **显示**: `drivers/gpu/drm/rockchip/`
- **摄像头**: `drivers/media/platform/rockchip/isp/`
- **NPU**: `drivers/rknpu/`

## 详细分析

### CPU 检测（第 164 行）
```
CPU: ARMv7 Processor [410fc075] revision 5 (ARMv7), cr=50c53c7d
```

**解码**:
- **410fc075**: ARM Cortex-A7（0x410 = ARM Ltd，0xc07 = Cortex-A7）
- **revision 5**: r0p5（修订版 0，补丁 5）
- **cr=50c53c7d**: 控制寄存器值
  - MMU 已启用
  - 数据缓存已启用
  - 指令缓存已启用
  - 分支预测已启用

### 内存布局（第 173-185 行）
```
Zone ranges:
  Normal   [mem 0x0000000000000000-0x000000000fffffff]
Memory: 174808K/262144K available
```

**内存分解**:
- **总 RAM**: 262144 KB（256 MB）
- **可用**: 174808 KB（170.7 MB）
- **内核使用**: 87336 KB（85.3 MB）
  - 内核代码: 4075 KB
  - 内核数据: 396 KB
  - 只读数据: 1936 KB
  - 初始化代码: 204 KB（启动后释放）
  - BSS: 150 KB
  - 保留: 9512 KB
  - CMA: 77824 KB（76 MB 用于 DMA）

### CMA（连续内存分配器）
```
Reserved memory: created CMA memory pool at 0x0f600000, size 10 MiB
cma: Reserved 67584 KiB at 0x0b400000
```

**目的**: 为 DMA 操作保留内存（摄像头、显示、视频编解码器）
- **池 1**: 10 MB 在 0x0f600000（来自设备树的 linux,cma）
- **池 2**: 66 MB 在 0x0b400000（来自命令行的 rk_dma_heap_cma）
- **总 CMA**: 76 MB

### 内核命令行（第 181 行）

**关键参数**:
- **root=/dev/mmcblk0p7**: eMMC 分区 7 上的根文件系统
- **rootfstype=ext4**: EXT4 文件系统
- **rootwait**: 等待根设备出现
- **console=ttyFIQ0**: FIQ 调试器上的控制台
- **earlycon=uart8250,mmio32,0xff4c0000**: UART2 上的早期控制台
- **rk_dma_heap_cma=66M**: 66MB CMA 用于 Rockchip DMA 堆
- **blkdevparts**: 分区表定义

### GPIO 和 Pinctrl（第 210-215 行）

**GPIO 组**:
- **GPIO0**: 0xff380000（32 个引脚）
- **GPIO1**: 0xff530000（32 个引脚）
- **GPIO2**: 0xff540000（32 个引脚）
- **GPIO3**: 0xff550000（32 个引脚）
- **GPIO4**: 0xff560000（32 个引脚）

**总计**: 160 个 GPIO 引脚可用

### FIQ 调试器（第 216-219 行）

**FIQ 调试器**: 用于低级调试的快速中断请求调试器
- 使用 FIQ（最高优先级中断）实现可靠的控制台访问
- 绕过正常中断处理以调试崩溃的系统
- 控制台设备: `/dev/ttyFIQ0`

### MMC/eMMC 初始化（第 331-377 行）

**eMMC 详情**:
- **控制器**: Synopsys DesignWare MMC（版本 270a）
- **芯片**: AT2S38（8GB eMMC）
- **速度**: 高速模式（49.5 MHz）
- **分区**: 检测到 7 个分区

**分区布局**:
| 分区 | 名称 | 大小 | 用途 |
|------|------|------|------|
| mmcblk0p1 | env | 32 KB | U-Boot 环境 |
| mmcblk0p2 | idblock | 512 KB | 引导加载程序 ID 块 |
| mmcblk0p3 | uboot | 256 KB | U-Boot |
| mmcblk0p4 | boot | 32 MB | 内核 + DTB（FIT 镜像）|
| mmcblk0p5 | oem | 512 MB | OEM 数据 |
| mmcblk0p6 | userdata | 256 MB | 用户数据 |
| mmcblk0p7 | rootfs | 6 GB | 根文件系统 |

### 以太网初始化（第 282-305 行）

**以太网控制器**:
- **类型**: Synopsys DesignWare MAC（DWMAC4/5）
- **模式**: RMII（简化媒体独立接口）
- **DMA**: 40 位寻址
- **功能**: TSO、校验和卸载、网络唤醒

### 显示子系统（第 276-380 行）

**显示配置**:
- **VOP**: 视频输出处理器在 0xff990000
- **分辨率**: 720x720 @ 49Hz（方形显示）
- **帧缓冲**: 90x45 字符控制台
- **驱动**: Rockchip DRM（直接渲染管理器）

### 根文件系统挂载（第 385-393 行）

**挂载过程**:
1. **日志恢复**: EXT4 日志重放（62ms）
2. **挂载**: 文件系统最初以只读方式挂载
3. **devtmpfs**: 设备文件系统已挂载
4. **Init 启动**: `/sbin/init` 已启动（PID 1）

**设备号**: 179:7
- **179**: MMC 块设备主设备号
- **7**: 分区 7（rootfs）

## 启动时间分析

### 内核启动阶段
```
阶段                    时间 (ms)    累计
────────────────────────────────────────────────
早期初始化 (0-50ms)          50          50
子系统初始化 (50-150ms)     100         150
驱动探测 (150-400ms)        250         400
根挂载 (400-484ms)           84         484
────────────────────────────────────────────────
内核启动总计               484 ms
```

### 总启动时间
```
阶段                时间 (ms)
──────────────────────────────
DDR 初始化               34
U-Boot SPL              383
U-Boot Proper           795
内核启动                484
──────────────────────────────
到 init 总计           1696 ms
```

## 错误分析

### 非严重警告

#### 1. DRM Logo 内存（第 169 行）
```
OF: fdt: Reserved memory: failed to reserve memory for node 'drm-logo@00000000': base 0x00000000, size 0 MiB
```
- **严重性**: 低
- **原因**: Logo 内存区域未配置
- **影响**: 不显示启动 logo（仅外观）

#### 2. 固定稳压器错误（第 220-221 行）
```
reg-fixed-voltage vdd-arm: Fixed regulator specified with variable voltages
reg-fixed-voltage: probe of vdd-arm failed with error -22
```
- **严重性**: 低
- **原因**: 设备树配置问题
- **影响**: 无 - CPU 电压调节通过其他方式工作

#### 3. 蓝牙 RFKILL 错误（第 352-359 行）
```
[BT_RFKILL]: Failed to get bt_default_wake_host gpio.
rfkill_bt: probe of wireless-bluetooth failed with error -1
```
- **严重性**: 低
- **原因**: GPIO 配置不匹配
- **影响**: 蓝牙仍然工作（稍后由 WiFi 驱动初始化）

## 性能优化

### 当前瓶颈
1. **驱动探测**: 250ms（内核启动时间的 52%）
2. **EXT4 恢复**: 62ms（内核启动时间的 13%）
3. **显示初始化**: 约 60ms（内核启动时间的 12%）

### 优化策略
1. **并行驱动初始化**: 启用异步探测
2. **干净关机**: 通过干净卸载避免日志恢复
3. **延迟显示**: 将显示初始化延迟到用户空间
4. **内核压缩**: 使用 LZ4 以加快解压速度

## 相关文件

### 构建配置
- **Defconfig**: `/sysdrv/source/kernel/arch/arm/configs/luckfox_rv1106_linux_defconfig`
- **板级配置**: `/project/cfg/BoardConfig_IPC/BoardConfig-EMMC-Buildroot-RV1106_Luckfox_Pico_Ultra_W-IPC.mk`

### 设备树
- **基础**: `/sysdrv/source/kernel/arch/arm/boot/dts/rv1106.dtsi`
- **变体**: `/sysdrv/source/kernel/arch/arm/boot/dts/rv1106g3.dtsi`
- **板级**: `/sysdrv/source/kernel/arch/arm/boot/dts/rv1106g-luckfox-pico-ultra-w.dts`

### 构建命令
```bash
cd /home/him/him/luckfox-pico
./build.sh kernelconfig    # 配置内核
./build.sh kernel          # 构建内核
./build.sh firmware        # 打包 boot.img
```

## 下一阶段

内核挂载根文件系统并启动 `/sbin/init` 后，系统进入用户空间初始化。

```
第 393 行: Run /sbin/init as init process
```

→ 请参阅 `stage5_init_services_cn.md` 了解下一个启动阶段的分析。
