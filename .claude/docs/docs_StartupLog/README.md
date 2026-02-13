# Luckfox Pico Ultra W Boot Log Analysis

Complete analysis of the boot process for Luckfox Pico Ultra W (RV1106G3), mapping each stage of the 802-line boot log to the corresponding SDK code and functionality.

## Analysis Overview

**Source Log**: `/mnt/hgfs/SharedFolder/log/uart.log` (802 lines)
**Analysis Date**: 2026-02-11
**SDK Version**: V1.4
**Board**: Luckfox Pico Ultra W (RV1106G3)
**Total Boot Time**: 17.8 seconds (power-on to login prompt)

## Document Structure

This analysis is divided into 6 stages, each covering a distinct phase of the boot process:

### [Stage 1: DDR Initialization](stage1_ddr_init.md) (Lines 1-9)
**Time**: 0-34ms | **Size**: 210 lines

Covers the DDR3 memory controller initialization by the Rockchip DDR init binary.

**Key Topics**:
- DDR3 configuration (256MB @ 924MHz)
- Memory training and calibration
- Binary location and configuration
- Memory architecture

**Code Locations**:
- `/sysdrv/source/uboot/rkbin/bin/rv11/rv1106_ddr_924MHz_v1.15.bin`
- `/sysdrv/source/uboot/rkbin/RKBOOT/RV1106MINIALL.ini`

---

### [Stage 2: U-Boot SPL](stage2_uboot_spl.md) (Lines 10-30)
**Time**: 34-417ms | **Size**: 361 lines

Covers the Secondary Program Loader (SPL) that loads U-Boot Proper.

**Key Topics**:
- Boot medium detection (MMC2 → MMC1)
- eMMC phase tuning
- FIT image loading and verification
- Memory layout setup

**Code Locations**:
- `/sysdrv/source/uboot/u-boot/common/spl/`
- `/sysdrv/source/uboot/u-boot/drivers/mmc/rockchip_sdhci.c`
- `/sysdrv/source/uboot/rkbin/bin/rv11/rv1106_spl_v1.02.bin`

---

### [Stage 3: U-Boot Proper](stage3_uboot_proper.md) (Lines 31-160)
**Time**: 417-1212ms | **Size**: 538 lines

Covers the full U-Boot bootloader that loads and starts the Linux kernel.

**Key Topics**:
- Hardware initialization (MMC, Ethernet, GPIO)
- Clock tree configuration (APLL, DPLL, GPLL, CPLL)
- Memory relocation and layout
- Kernel and device tree loading
- Boot parameter passing

**Code Locations**:
- `/sysdrv/source/uboot/u-boot/common/board_r.c`
- `/sysdrv/source/uboot/u-boot/arch/arm/mach-rockchip/rv1106/`
- `/sysdrv/source/uboot/u-boot/arch/arm/dts/rv1106-luckfox.dts`

---

### [Stage 4: Linux Kernel Boot](stage4_kernel_boot.md) (Lines 161-393)
**Time**: 1212-1696ms | **Size**: 370 lines

Covers Linux kernel initialization from early boot to root filesystem mount.

**Key Topics**:
- CPU detection and initialization
- Memory management (CMA, zones)
- Device tree parsing
- Subsystem initialization (GPIO, MMC, Ethernet, Display)
- Driver probing
- Root filesystem mount (EXT4)

**Code Locations**:
- `/sysdrv/source/kernel/init/main.c`
- `/sysdrv/source/kernel/arch/arm/mach-rockchip/`
- `/sysdrv/source/kernel/arch/arm/boot/dts/rv1106g-luckfox-pico-ultra-w.dts`
- `/sysdrv/source/kernel/drivers/`

---

### [Stage 5: Init System and Services](stage5_init_services.md) (Lines 394-520)
**Time**: 1696-11144ms | **Size**: 484 lines

Covers userspace initialization and service startup.

**Key Topics**:
- BusyBox init system
- Service startup order (syslog, udev, D-Bus, network, SSH, Samba)
- Filesystem checks and mounts
- USB device configuration
- Network interface setup

**Code Locations**:
- `/sysdrv/out/rootfs_uclibc_rv1106/etc/inittab`
- `/sysdrv/out/rootfs_uclibc_rv1106/etc/init.d/`
- `/sysdrv/source/buildroot/buildroot-2023.02.6/`

---

### [Stage 6: Application Drivers and Late Init](stage6_app_drivers.md) (Lines 521-802)
**Time**: 11144-17837ms | **Size**: 490 lines

Covers media drivers, WiFi initialization, and application startup.

**Key Topics**:
- Camera sensor probing (SC3336, MIS5001)
- Media accelerators (RGA, MPP, NPU)
- WiFi/Bluetooth initialization (AIC8800DC)
- Firmware loading
- Network connection (Ethernet, WiFi, USB)
- Application startup

**Code Locations**:
- `/sysdrv/source/kernel/drivers/media/i2c/`
- `/sysdrv/source/kernel/drivers/media/platform/rockchip/`
- `/sysdrv/source/kernel/drivers/rknpu/`
- `/sysdrv/source/kernel/drivers/net/wireless/aic8800/`
- `/oem/usr/ko/aic8800dc_fw/`
- `/project/app/`

---

## Boot Time Summary

```
┌─────────────────────────────────────────────────────────┐
│              Luckfox Pico Ultra W Boot Timeline         │
├─────────────────────────────────────────────────────────┤
│ Stage                    Time (ms)    Percentage        │
├─────────────────────────────────────────────────────────┤
│ 1. DDR Init                   34         0.2%           │
│ 2. U-Boot SPL                383         2.1%           │
│ 3. U-Boot Proper             795         4.5%           │
│ 4. Kernel Boot               484         2.7%           │
│ 5. Init Services            9448        53.0%           │
│ 6. App/Drivers/WiFi         6693        37.5%           │
├─────────────────────────────────────────────────────────┤
│ Total                      17837       100.0%           │
└─────────────────────────────────────────────────────────┘
```

### Key Milestones

| Milestone | Time (s) | Description |
|-----------|----------|-------------|
| DDR Ready | 0.034 | Memory initialized |
| U-Boot Started | 0.417 | SPL loaded U-Boot |
| Kernel Started | 1.212 | U-Boot loaded kernel |
| Init Started | 1.696 | Kernel mounted root |
| Services Ready | 11.144 | All services started |
| Login Prompt | 17.837 | System fully booted |

## Hardware Configuration

### SoC: Rockchip RV1106G3
- **CPU**: ARM Cortex-A7 @ 816 MHz
- **Memory**: 256 MB DDR3 @ 924 MHz
- **Storage**: 8 GB eMMC (HS200 @ 200 MHz)
- **NPU**: 1.0 TOPS INT8 inference
- **ISP**: Image Signal Processor for camera
- **VPU**: H.264/H.265 encoder/decoder

### Peripherals
- **Ethernet**: 100 Mbps (RK630 PHY, RMII mode)
- **WiFi/BT**: AIC8800DC (802.11ax, Bluetooth 5.0)
- **USB**: USB 2.0 OTG (device mode: RNDIS, mass storage)
- **Display**: 720x720 RGB LCD support
- **GPIO**: 160 pins (5 banks × 32 pins)

### Storage Partitions

| Partition | Device | Size | Mount | Purpose |
|-----------|--------|------|-------|---------|
| env | mmcblk0p1 | 32 KB | - | U-Boot environment |
| idblock | mmcblk0p2 | 512 KB | - | Boot ID block |
| uboot | mmcblk0p3 | 256 KB | - | U-Boot binary |
| boot | mmcblk0p4 | 32 MB | - | Kernel + DTB (FIT) |
| oem | mmcblk0p5 | 512 MB | /oem | OEM data |
| userdata | mmcblk0p6 | 256 MB | /userdata | User data |
| rootfs | mmcblk0p7 | 6 GB | / | Root filesystem |

## Key Findings

### Performance Bottlenecks
1. **Init Services (53%)**: Largest contributor to boot time
   - USB device setup: 4.9s
   - Samba startup: 1.8s
   - Filesystem checks: 0.6s

2. **WiFi Initialization (27%)**: Second largest bottleneck
   - Firmware loading: 4.9s
   - Multiple firmware files loaded sequentially

3. **Kernel Boot (3%)**: Relatively fast
   - Driver probing: 250ms
   - EXT4 recovery: 62ms

### Optimization Opportunities
1. **Parallel Service Startup**: Start independent services concurrently
2. **Defer WiFi**: Load WiFi driver on-demand
3. **Skip Unused Drivers**: Disable camera drivers if not used
4. **Optimize USB**: Reduce USB enumeration delay
5. **Clean Shutdown**: Avoid EXT4 journal recovery

### Potential Boot Time Reduction
- **Current**: 17.8 seconds
- **Optimized**: ~8-10 seconds (55% reduction)
  - Parallel init: -3s
  - Defer WiFi: -5s
  - Optimize USB: -2s

## Error Analysis

### Critical Errors
None detected. System boots successfully.

### Warnings (Non-Critical)
1. **Camera Sensors Not Detected**: SC3336 and MIS5001 sensors return ID 0x000000
   - **Cause**: Sensors not physically connected
   - **Impact**: None if camera not used

2. **Memory Overlap Warning**: MMC DMA buffer overlaps kernel load area
   - **Cause**: Reserved memory configuration
   - **Impact**: Minimal - kernel relocates after boot

3. **D-Bus PulseAudio Warning**: Unknown username "pulse"
   - **Cause**: PulseAudio not installed
   - **Impact**: None - D-Bus works correctly

4. **USB Function Errors**: MTP and ACM functions not available
   - **Cause**: Not enabled in kernel config
   - **Impact**: Only RNDIS and mass storage available

## SDK Structure

### Key Directories
```
luckfox-pico/
├── project/              # Build scripts and board configs
│   ├── build.sh          # Main build script
│   └── cfg/              # Board configuration files
├── sysdrv/               # System drivers (U-Boot, Kernel, Rootfs)
│   ├── source/
│   │   ├── uboot/        # U-Boot source and binaries
│   │   ├── kernel/       # Linux kernel source
│   │   └── buildroot/    # Buildroot for rootfs
│   └── out/              # Build output
├── media/                # Rockchip media libraries (RGA, MPP, NPU)
├── tools/                # Toolchain and utilities
├── output/               # Final firmware images
│   └── image/            # boot.img, rootfs.img, etc.
└── IMAGE/                # Precompiled firmware packages
```

### Build Commands
```bash
cd /home/him/him/luckfox-pico

# Configure board
./build.sh lunch

# Build components
./build.sh uboot          # Build U-Boot
./build.sh kernel         # Build kernel
./build.sh rootfs         # Build root filesystem
./build.sh media          # Build media libraries
./build.sh app            # Build applications

# Build everything
./build.sh all            # Build all components
./build.sh firmware       # Pack firmware images

# Configuration
./build.sh kernelconfig   # Configure kernel
./build.sh buildrootconfig # Configure Buildroot
```

## Related Documentation

### Official Documentation
- **Luckfox Wiki**: https://wiki.luckfox.com/zh/Luckfox-Pico-Pro-Max/
- **SDK README**: [README_CN.md](../README_CN.md)
- **Update Log**: [UPDATE_LOG_CN.md](../UPDATE_LOG_CN.md)
- **Project Instructions**: [CLAUDE.md](../CLAUDE.md)

### Rockchip Documentation
- **RV1106 TRM**: Technical Reference Manual (contact Rockchip)
- **RV1106 Datasheet**: Hardware specifications
- **RKNN SDK**: Neural network SDK documentation

### Linux Kernel
- **Device Tree Bindings**: `Documentation/devicetree/bindings/`
- **ARM Boot**: `Documentation/arm/booting.rst`

## Verification Methods

To verify this analysis:

1. **Code Cross-Reference**: Search for log strings in source code
   ```bash
   cd /home/him/him/luckfox-pico
   grep -r "Successfully tuned phase" sysdrv/source/uboot/
   grep -r "Booting Linux on physical CPU" sysdrv/source/kernel/
   ```

2. **Modify and Rebuild**: Change log messages and rebuild
   ```bash
   # Edit source file
   vim sysdrv/source/uboot/u-boot/drivers/mmc/rockchip_sdhci.c
   # Rebuild
   ./build.sh uboot
   ./build.sh firmware
   ```

3. **Device Tree Comparison**: Compare log addresses with device tree
   ```bash
   # Decompile device tree
   dtc -I dtb -O dts output/image/boot.img -o boot.dts
   # Search for addresses
   grep "ffa80000" boot.dts  # Ethernet controller
   ```

4. **Timing Analysis**: Add timestamps to measure boot stages
   ```bash
   # Enable initcall_debug in kernel command line
   # Add to U-Boot environment or device tree
   ```

## Conclusion

This comprehensive analysis provides a complete mapping of the Luckfox Pico Ultra W boot process, from power-on to login prompt. Each stage is documented with:

- ✓ Original log content with line numbers
- ✓ Functional description
- ✓ Source code locations
- ✓ Key parameters and configurations
- ✓ Error analysis and troubleshooting
- ✓ Performance optimization suggestions

The analysis covers all 802 lines of the boot log across 6 distinct stages, totaling 2,453 lines of detailed documentation.

**Total Documentation**: 2,453 lines across 6 files (86 KB)

---

**Generated**: 2026-02-11
**SDK Version**: V1.4
**Board**: Luckfox Pico Ultra W (RV1106G3)
**Kernel**: Linux 5.10.160
**U-Boot**: 2017.09
**Buildroot**: 2023.02.6
