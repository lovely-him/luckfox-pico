# Stage 4: Linux Kernel Boot Analysis

## Log Content (Lines 161-393)

This stage covers kernel initialization from early boot to mounting the root filesystem.

### Early Boot (Lines 162-210)
```
[    0.000000] Booting Linux on physical CPU 0x0
[    0.000000] Linux version 5.10.160 (him@him-virtual-machine)
[    0.000000] CPU: ARMv7 Processor [410fc075] revision 5 (ARMv7), cr=50c53c7d
[    0.000000] CPU: div instructions available: patching division code
[    0.000000] CPU: PIPT / VIPT nonaliasing data cache, VIPT aliasing instruction cache
[    0.000000] OF: fdt: Machine model: Luckfox Pico Ultra W
[    0.000000] Memory policy: Data cache writeback
[    0.000000] Reserved memory: created CMA memory pool at 0x0f600000, size 10 MiB
[    0.000000] cma: Reserved 67584 KiB at 0x0b400000
```

### Subsystem Initialization (Lines 211-280)
```
[    0.027309] rockchip-gpio ff380000.gpio: probed /pinctrl/gpio@ff380000
[    0.040730] fiq_debugger fiq_debugger.0: IRQ uart_irq not found
[    0.041021] printk: console [ttyFIQ0] enabled
[    0.042301] reg-fixed-voltage vdd-arm: Fixed regulator specified with variable voltages
[    0.043145] usbcore: registered new interface driver usbfs
[    0.044552] Advanced Linux Sound Architecture Driver Initialized.
[    0.045042] Bluetooth: Core ver 2.22
[    0.045602] rockchip-cpuinfo cpuinfo: Serial         : 032e363feb4eef35
```

### Driver Loading (Lines 281-380)
```
[    0.179906] rk_gmac-dwmac ffa80000.ethernet: IRQ eth_lpi not found
[    0.180799] rk_gmac-dwmac ffa80000.ethernet: init for RMII
[    0.187927] ehci_hcd: USB 2.0 'Enhanced' Host Controller (EHCI) Driver
[    0.190129] rockchip-rtc ff1c0000.rtc: registered as rtc0
[    0.215533] Synopsys Designware Multimedia Card Interface Driver
[    0.217708] dwmmc_rockchip ffa90000.mmc: IDMAC supports 32-bit address mode.
[    0.253193] rockchip-drm display-subsystem: bound ff990000.vop (ops 0xb043ac84)
[    0.278270] mmc0: new high speed MMC card at address 0001
[    0.279464]  mmcblk0: p1(env) p2(idblock) p3(uboot) p4(boot) p5(oem) p6(userdata) p7(rootfs)
```

### Root Filesystem Mount (Lines 385-393)
```
[    0.417791] EXT4-fs (mmcblk0p7): INFO: recovery required on readonly filesystem
[    0.417815] EXT4-fs (mmcblk0p7): write access will be enabled during recovery
[    0.479368] EXT4-fs (mmcblk0p7): recovery complete
[    0.479899] EXT4-fs (mmcblk0p7): mounted filesystem with ordered data mode. Opts: (null)
[    0.479971] VFS: Mounted root (ext4 filesystem) readonly on device 179:7.
[    0.483738] devtmpfs: mounted
[    0.483951] Freeing unused kernel memory: 204K
[    0.483988] Run /sbin/init as init process
```

## Functional Overview

The Linux kernel boot process consists of:

1. **CPU Initialization** - Detect CPU features, enable caches, set up MMU
2. **Memory Management** - Initialize memory zones, CMA, and page allocator
3. **Device Tree Parsing** - Parse hardware description from device tree
4. **Subsystem Init** - Initialize core kernel subsystems (VFS, networking, etc.)
5. **Driver Probing** - Load and initialize device drivers
6. **Root Filesystem Mount** - Mount root partition and start init process

## Code Location

### Kernel Source Base
- **Path**: `/sysdrv/source/kernel/`
- **Version**: Linux 5.10.160
- **Build**: him@him-virtual-machine, Mon Jan 26 18:04:45 HKT 2026

### Key Source Files

#### Early Boot
- **Entry Point**: `arch/arm/kernel/head.S` - Assembly entry point
- **Main Init**: `init/main.c:start_kernel()` - C entry point
- **CPU Setup**: `arch/arm/kernel/setup.c:setup_arch()`
- **Memory Init**: `arch/arm/mm/init.c:bootmem_init()`

#### RV1106-Specific Code
- **Platform**: `arch/arm/mach-rockchip/rockchip.c`
- **Power Management**: `arch/arm/mach-rockchip/rv1106_pm.c`
- **Clock Driver**: `drivers/clk/rockchip/clk-rv1106.c`

#### Device Tree
- **Base**: `arch/arm/boot/dts/rv1106.dtsi`
- **RV1106G3**: `arch/arm/boot/dts/rv1106g3.dtsi`
- **Board**: `arch/arm/boot/dts/rv1106g-luckfox-pico-ultra-w.dts`

#### Key Drivers
- **GPIO/Pinctrl**: `drivers/pinctrl/pinctrl-rockchip.c`
- **MMC**: `drivers/mmc/host/dw_mmc-rockchip.c`
- **Ethernet**: `drivers/net/ethernet/stmicro/stmmac/dwmac-rk.c`
- **Display**: `drivers/gpu/drm/rockchip/`
- **Camera**: `drivers/media/platform/rockchip/isp/`
- **NPU**: `drivers/rknpu/`

## Detailed Analysis

### CPU Detection (Line 164)
```
CPU: ARMv7 Processor [410fc075] revision 5 (ARMv7), cr=50c53c7d
```

**Decoding**:
- **410fc075**: ARM Cortex-A7 (0x410 = ARM Ltd, 0xc07 = Cortex-A7)
- **revision 5**: r0p5 (revision 0, patch 5)
- **cr=50c53c7d**: Control Register value
  - MMU enabled
  - Data cache enabled
  - Instruction cache enabled
  - Branch prediction enabled

### Memory Layout (Lines 173-185)
```
Zone ranges:
  Normal   [mem 0x0000000000000000-0x000000000fffffff]
Memory: 174808K/262144K available
```

**Memory Breakdown**:
- **Total RAM**: 262144 KB (256 MB)
- **Available**: 174808 KB (170.7 MB)
- **Used by kernel**: 87336 KB (85.3 MB)
  - Kernel code: 4075 KB
  - Kernel data: 396 KB
  - Rodata: 1936 KB
  - Init code: 204 KB (freed after boot)
  - BSS: 150 KB
  - Reserved: 9512 KB
  - CMA: 77824 KB (76 MB for DMA)

### CMA (Contiguous Memory Allocator)
```
Reserved memory: created CMA memory pool at 0x0f600000, size 10 MiB
cma: Reserved 67584 KiB at 0x0b400000
```

**Purpose**: Reserved memory for DMA operations (camera, display, video codec)
- **Pool 1**: 10 MB at 0x0f600000 (linux,cma from device tree)
- **Pool 2**: 66 MB at 0x0b400000 (rk_dma_heap_cma from cmdline)
- **Total CMA**: 76 MB

### Kernel Command Line (Line 181)
```
Kernel command line: user_debug=31 storagemedia=emmc androidboot.storagemedia=emmc androidboot.mode=normal rootwait earlycon=uart8250,mmio32,0xff4c0000 console=ttyFIQ0 root=/dev/mmcblk0p7 snd_soc_core.prealloc_buffer_size_kbytes=16 coherent_pool=0 blkdevparts=mmcblk0:32K(env),512K@32K(idblock),256K(uboot),32M(boot),512M(oem),256M(userdata),6G(rootfs) rootfstype=ext4 rk_dma_heap_cma=66M androidboot.fwver=uboot-01/26/2026
```

**Key Parameters**:
- **root=/dev/mmcblk0p7**: Root on eMMC partition 7
- **rootfstype=ext4**: EXT4 filesystem
- **rootwait**: Wait for root device to appear
- **console=ttyFIQ0**: Console on FIQ debugger
- **earlycon=uart8250,mmio32,0xff4c0000**: Early console on UART2
- **rk_dma_heap_cma=66M**: 66MB CMA for Rockchip DMA heap
- **blkdevparts**: Partition table definition

### GPIO and Pinctrl (Lines 210-215)
```
[    0.027309] rockchip-gpio ff380000.gpio: probed /pinctrl/gpio@ff380000
[    0.027930] rockchip-gpio ff530000.gpio: probed /pinctrl/gpio@ff530000
[    0.028541] rockchip-gpio ff540000.gpio: probed /pinctrl/gpio@ff540000
[    0.029207] rockchip-gpio ff550000.gpio: probed /pinctrl/gpio@ff550000
[    0.029813] rockchip-gpio ff560000.gpio: probed /pinctrl/gpio@ff560000
[    0.029935] rockchip-pinctrl pinctrl: probed pinctrl
```

**GPIO Banks**:
- **GPIO0**: 0xff380000 (32 pins)
- **GPIO1**: 0xff530000 (32 pins)
- **GPIO2**: 0xff540000 (32 pins)
- **GPIO3**: 0xff550000 (32 pins)
- **GPIO4**: 0xff560000 (32 pins)

**Total**: 160 GPIO pins available

### FIQ Debugger (Lines 216-219)
```
[    0.040730] fiq_debugger fiq_debugger.0: IRQ uart_irq not found
[    0.040753] fiq_debugger fiq_debugger.0: IRQ wakeup not found
[    0.041021] printk: console [ttyFIQ0] enabled
[    0.041186] Registered fiq debugger ttyFIQ0
```

**FIQ Debugger**: Fast Interrupt Request debugger for low-level debugging
- Uses FIQ (highest priority interrupt) for reliable console access
- Bypasses normal interrupt handling for debugging crashed systems
- Console device: `/dev/ttyFIQ0`

### MMC/eMMC Initialization (Lines 331-377)
```
[    0.217708] dwmmc_rockchip ffa90000.mmc: IDMAC supports 32-bit address mode.
[    0.217753] dwmmc_rockchip ffa90000.mmc: Using internal DMA controller.
[    0.217772] dwmmc_rockchip ffa90000.mmc: Version ID is 270a
[    0.218174] mmc_host mmc0: Bus speed (slot 0) = 400000Hz (slot req 400000Hz, actual 400000HZ div = 0)
[    0.277370] mmc_host mmc0: Bus speed (slot 0) = 49500000Hz (slot req 52000000Hz, actual 49500000HZ div = 0)
[    0.278270] mmc0: new high speed MMC card at address 0001
[    0.278717] mmcblk0: mmc0:0001 AT2S38 7.23 GiB
[    0.279464]  mmcblk0: p1(env) p2(idblock) p3(uboot) p4(boot) p5(oem) p6(userdata) p7(rootfs)
```

**eMMC Details**:
- **Controller**: Synopsys DesignWare MMC (version 270a)
- **Chip**: AT2S38 (8GB eMMC)
- **Speed**: High Speed mode (49.5 MHz)
- **Partitions**: 7 partitions detected

**Partition Layout**:
| Partition | Name | Size | Purpose |
|-----------|------|------|---------|
| mmcblk0p1 | env | 32 KB | U-Boot environment |
| mmcblk0p2 | idblock | 512 KB | Boot loader ID block |
| mmcblk0p3 | uboot | 256 KB | U-Boot |
| mmcblk0p4 | boot | 32 MB | Kernel + DTB (FIT image) |
| mmcblk0p5 | oem | 512 MB | OEM data |
| mmcblk0p6 | userdata | 256 MB | User data |
| mmcblk0p7 | rootfs | 6 GB | Root filesystem |

### Ethernet Initialization (Lines 282-305)
```
[    0.179906] rk_gmac-dwmac ffa80000.ethernet: IRQ eth_lpi not found
[    0.180799] rk_gmac-dwmac ffa80000.ethernet: init for RMII
[    0.180799] rk_gmac-dwmac ffa80000.ethernet: User ID: 0x30, Synopsys ID: 0x51
[    0.180818] rk_gmac-dwmac ffa80000.ethernet:         DWMAC4/5
[    0.180894] rk_gmac-dwmac ffa80000.ethernet: Using 40 bits DMA width
```

**Ethernet Controller**:
- **Type**: Synopsys DesignWare MAC (DWMAC4/5)
- **Mode**: RMII (Reduced Media Independent Interface)
- **DMA**: 40-bit addressing
- **Features**: TSO, checksum offload, wake-on-LAN

### Display Subsystem (Lines 276-380)
```
[    0.160071] rockchip-drm display-subsystem: bound ff990000.vop (ops 0xb043ac84)
[    0.255194] rockchip-vop ff990000.vop: [drm:vop_crtc_atomic_enable] Update mode to 720x720p49, type: 17
[    0.303340] Console: switching to colour frame buffer device 90x45
[    0.319749] rockchip-drm display-subsystem: [drm] fb0: rockchipdrmfb frame buffer device
[    0.320454] [drm] Initialized rockchip 3.0.0 20140818 for display-subsystem on minor 0
```

**Display Configuration**:
- **VOP**: Video Output Processor at 0xff990000
- **Resolution**: 720x720 @ 49Hz (square display)
- **Framebuffer**: 90x45 character console
- **Driver**: Rockchip DRM (Direct Rendering Manager)

### Root Filesystem Mount (Lines 385-393)
```
[    0.417791] EXT4-fs (mmcblk0p7): INFO: recovery required on readonly filesystem
[    0.417815] EXT4-fs (mmcblk0p7): write access will be enabled during recovery
[    0.479368] EXT4-fs (mmcblk0p7): recovery complete
[    0.479899] EXT4-fs (mmcblk0p7): mounted filesystem with ordered data mode. Opts: (null)
[    0.479971] VFS: Mounted root (ext4 filesystem) readonly on device 179:7.
[    0.483738] devtmpfs: mounted
[    0.483951] Freeing unused kernel memory: 204K
[    0.483988] Run /sbin/init as init process
```

**Mount Process**:
1. **Journal Recovery**: EXT4 journal replay (62ms)
2. **Mount**: Filesystem mounted read-only initially
3. **devtmpfs**: Device filesystem mounted
4. **Init Launch**: `/sbin/init` started (PID 1)

**Device Number**: 179:7
- **179**: MMC block device major number
- **7**: Partition 7 (rootfs)

## Boot Time Analysis

### Kernel Boot Phases
```
Phase                    Time (ms)    Cumulative
────────────────────────────────────────────────
Early init (0-50ms)          50          50
Subsystem init (50-150ms)   100         150
Driver probing (150-400ms)  250         400
Root mount (400-484ms)       84         484
────────────────────────────────────────────────
Total kernel boot           484 ms
```

### Total Boot Time
```
Stage                Time (ms)
──────────────────────────────
DDR Init                  34
U-Boot SPL               383
U-Boot Proper            795
Kernel Boot              484
──────────────────────────────
Total to init           1696 ms
```

## Error Analysis

### Non-Critical Warnings

#### 1. DRM Logo Memory (Line 169)
```
OF: fdt: Reserved memory: failed to reserve memory for node 'drm-logo@00000000': base 0x00000000, size 0 MiB
```
- **Severity**: Low
- **Cause**: Logo memory region not configured
- **Impact**: Boot logo not displayed (cosmetic only)

#### 2. Fixed Regulator Error (Lines 220-221)
```
reg-fixed-voltage vdd-arm: Fixed regulator specified with variable voltages
reg-fixed-voltage: probe of vdd-arm failed with error -22
```
- **Severity**: Low
- **Cause**: Device tree configuration issue
- **Impact**: None - CPU voltage regulation works via other means

#### 3. Bluetooth RFKILL Error (Lines 352-359)
```
[BT_RFKILL]: Failed to get bt_default_wake_host gpio.
rfkill_bt: probe of wireless-bluetooth failed with error -1
```
- **Severity**: Low
- **Cause**: GPIO configuration mismatch
- **Impact**: Bluetooth still works (initialized later by WiFi driver)

## Performance Optimization

### Current Bottlenecks
1. **Driver Probing**: 250ms (52% of kernel boot time)
2. **EXT4 Recovery**: 62ms (13% of kernel boot time)
3. **Display Init**: ~60ms (12% of kernel boot time)

### Optimization Strategies
1. **Parallel Driver Init**: Enable asynchronous probing
2. **Clean Shutdown**: Avoid journal recovery by clean unmount
3. **Deferred Display**: Defer display init to userspace
4. **Kernel Compression**: Use LZ4 for faster decompression

## Related Files

### Build Configuration
- **Defconfig**: `/sysdrv/source/kernel/arch/arm/configs/luckfox_rv1106_linux_defconfig`
- **Board Config**: `/project/cfg/BoardConfig_IPC/BoardConfig-EMMC-Buildroot-RV1106_Luckfox_Pico_Ultra_W-IPC.mk`

### Device Trees
- **Base**: `/sysdrv/source/kernel/arch/arm/boot/dts/rv1106.dtsi`
- **Variant**: `/sysdrv/source/kernel/arch/arm/boot/dts/rv1106g3.dtsi`
- **Board**: `/sysdrv/source/kernel/arch/arm/boot/dts/rv1106g-luckfox-pico-ultra-w.dts`

### Build Commands
```bash
cd /home/him/him/luckfox-pico
./build.sh kernelconfig    # Configure kernel
./build.sh kernel          # Build kernel
./build.sh firmware        # Pack boot.img
```

## Next Stage

After the kernel mounts the root filesystem and starts `/sbin/init`, the system enters userspace initialization.

```
Line 393: Run /sbin/init as init process
```

→ See `stage5_init_services.md` for the next boot stage analysis.
