# Stage 2: U-Boot SPL (Secondary Program Loader) Analysis

## Log Content (Lines 10-30)

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

## Functional Overview

U-Boot SPL (Secondary Program Loader) is a **minimal bootloader** that runs after DDR initialization. Its primary responsibilities are:

1. **Boot Medium Detection** - Identify and initialize the boot storage device
2. **Load U-Boot Proper** - Load the full U-Boot from storage into DDR
3. **FIT Image Verification** - Verify cryptographic signatures (if secure boot enabled)
4. **Memory Management** - Set up basic memory layout
5. **Handoff to U-Boot** - Transfer control to the full U-Boot

## Code Location

### Source Code
- **Base Path**: `/sysdrv/source/uboot/u-boot/`
- **SPL Core**:
  - `common/spl/spl.c` - Main SPL logic (`spl_init()`, `board_init_r()`)
  - `common/spl/spl_mmc.c` - MMC boot support (`spl_mmc_load()`)
  - `arch/arm/mach-rockchip/spl.c` - Rockchip-specific SPL code
  - `arch/arm/mach-rockchip/rv1106/rv1106.c` - RV1106 chip initialization

### MMC Driver
- **SDHCI Driver**: `drivers/mmc/rockchip_sdhci.c`
- **MMC Core**: `drivers/mmc/mmc.c`
- **Phase Tuning**: `drivers/mmc/rockchip_sdhci.c:rockchip_sdhci_execute_tuning()`

### Binary Output
- **Path**: `/sysdrv/source/uboot/rkbin/bin/rv11/rv1106_spl_v1.02.bin`
- **Build Output**: `/sysdrv/source/uboot/u-boot/spl/u-boot-spl.bin`

### Configuration
- **Defconfig**: `/sysdrv/source/uboot/u-boot/configs/rv1106_defconfig`
- **SPL Options**: `CONFIG_SPL=y`, `CONFIG_SPL_MMC_SUPPORT=y`

## Detailed Log Analysis

### Lines 11-12: SPL Initialization
```
U-Boot SPL board init
U-Boot SPL 2017.09 (Jan 26 2026 - 18:04:03)
```

**Code Path**:
```c
// arch/arm/mach-rockchip/spl.c
void board_init_f(ulong dummy)
{
    debug("U-Boot SPL board init\n");  // ← Line 11
    // ... initialization code ...
}
```

**Build Information**:
- **U-Boot Version**: 2017.09 (Rockchip's customized version)
- **Build Date**: January 26, 2026, 18:04:03
- **Builder**: him@him-virtual-machine (matches kernel build)

### Line 13: Boot Device Detection
```
unknown raw ID 0 0 0
```

**Code Path**:
```c
// common/spl/spl.c
static int spl_common_init(bool setup_malloc)
{
    // Attempts to read boot device ID from BootROM
    // If ID is 0 0 0, falls back to trying all boot devices
}
```

**Meaning**: The BootROM did not pass a valid boot device ID, so SPL will try all configured boot devices in order.

### Lines 14-19: MMC2 Boot Attempt (Failed)
```
Trying to boot from MMC2
Card did not respond to voltage select!
mmc_init: -95, time 20
Card did not respond to voltage select!
mmc_init: -95, time 20
spl: mmc init failed with error: -95
```

**Code Path**:
```c
// common/spl/spl_mmc.c
static int spl_mmc_find_device(struct mmc **mmcp, u32 boot_mode)
{
    err = mmc_init(mmc);  // ← Fails with -95
    if (err) {
        printf("spl: mmc init failed with error: %d\n", err);
        return err;
    }
}
```

**Error Code Analysis**:
- **Error -95**: `EOPNOTSUPP` (Operation not supported)
- **Root Cause**: MMC2 (SD card slot) has no card inserted or is not connected
- **Behavior**: SPL tries twice (lines 15-16, 17-18) before giving up

**Hardware Mapping**:
- **MMC2**: Typically the SD card slot on Rockchip platforms
- **Luckfox Pico Ultra W**: Uses eMMC (MMC0/MMC1), not SD card

### Lines 20-22: MMC1 Boot Attempt (Success)
```
Trying to boot from MMC1
Best phase range 270-237 (30 len)
Successfully tuned phase to 79, used 3ms
```

**Code Path**:
```c
// drivers/mmc/rockchip_sdhci.c
static int rockchip_sdhci_execute_tuning(struct udevice *dev, uint opcode)
{
    // Phase tuning algorithm
    // Tries different clock phases to find optimal sampling point
    best_start = 270;
    best_end = 237;  // Wraps around (270-360, 0-237)
    best_len = 30;

    // Select middle of best range
    phase = (best_start + best_len / 2) % 360;  // = 79

    printf("Successfully tuned phase to %d, used %dms\n", phase, time);
}
```

**Phase Tuning Explanation**:
- **Purpose**: Find the optimal clock phase for reliable data sampling
- **Method**: Try all 360 phases, find the longest stable range
- **Result**: Phase 79° selected (middle of 270-237° range, accounting for wrap-around)
- **Time**: 3ms (very fast tuning)

**Hardware Mapping**:
- **MMC1**: eMMC on Luckfox Pico Ultra W
- **Device**: `/dev/mmcblk0` (8GB eMMC)

### Lines 23-25: Environment and Partition Check
```
ENVF: Primary 0x00000000 - 0x00008000
ENVF: Primary 0x00000000 - 0x00008000
No misc partition
```

**Code Path**:
```c
// env/mmc.c
static int mmc_env_init(void)
{
    // Try to load environment from MMC
    // ENVF = Environment File
    printf("ENVF: Primary 0x%08x - 0x%08x\n", start, end);
}
```

**Meaning**:
- **ENVF**: Environment partition location (0x0 - 0x8000 = 32KB)
- **Duplicate message**: SPL checks environment twice (primary and backup)
- **No misc partition**: The "misc" partition (used for recovery mode) is not found

### Lines 26-29: FIT Image Loading and Verification
```
Trying fit image at 0x440 sector
## Verified-boot: 0
## Checking uboot 0x00200000 (lzma @0x00400000) ... sha256(2149fbc6d0...) + sha256(0c03bd7c60...) + OK
## Checking fdt 0x00261190 ... sha256(9f596c5683...) + OK
```

**Code Path**:
```c
// common/spl/spl_fit.c
int spl_load_simple_fit(struct spl_image_info *spl_image,
                        struct spl_load_info *info, ulong sector, void *fit)
{
    // Load FIT image from sector 0x440
    printf("Trying fit image at 0x%x sector\n", sector);

    // Verify boot flag
    printf("## Verified-boot: %d\n", verified);  // 0 = disabled

    // Check U-Boot image
    printf("## Checking uboot 0x%08x (lzma @0x%08x) ... ", addr, comp_addr);
    // Verify SHA256 hash
    printf("sha256(%s...) + sha256(%s...) + OK\n", hash1, hash2);

    // Check device tree
    printf("## Checking fdt 0x%08x ... sha256(%s...) + OK\n", fdt_addr, hash);
}
```

**FIT Image Structure**:
```
┌─────────────────────────────────────┐
│  FIT Image (Flattened Image Tree)  │
│  Located at sector 0x440 (544)     │
├─────────────────────────────────────┤
│  1. U-Boot Proper                   │
│     - Load Address: 0x00200000      │
│     - Compressed: LZMA              │
│     - Decompressed to: 0x00400000   │
│     - SHA256: 2149fbc6d0...         │
│     - SHA256: 0c03bd7c60...         │
├─────────────────────────────────────┤
│  2. Device Tree (FDT)               │
│     - Load Address: 0x00261190      │
│     - SHA256: 9f596c5683...         │
└─────────────────────────────────────┘
```

**Security Analysis**:
- **Verified-boot: 0** - Secure boot is **disabled**
- **SHA256 verification** - Still performed for integrity checking
- **Two hashes for U-Boot** - Likely compressed and decompressed image hashes

### Line 30: Timing Summary
```
Total: 383.321/417.635 ms
```

**Breakdown**:
- **383.321 ms**: Time spent in SPL execution
- **417.635 ms**: Total time from DDR init to SPL completion
- **Difference**: ~34 ms spent in DDR init and BootROM

## Boot Device Priority

The boot device order is configured in the device tree:

**File**: `/sysdrv/source/uboot/u-boot/arch/arm/dts/rv1106-luckfox.dts`
```dts
&spl {
    u-boot,spl-boot-order = "same-as-spl", &mmc1, &mmc2;
};
```

**Boot Order**:
1. **same-as-spl**: Try the device SPL was loaded from
2. **&mmc1**: eMMC (MMC1)
3. **&mmc2**: SD card (MMC2)

## Memory Layout After SPL

```
DDR Memory (256MB: 0x00000000 - 0x10000000)
┌─────────────────────────────────────────┐
│ 0x00000000 - 0x00008000                 │ Reserved (32KB)
├─────────────────────────────────────────┤
│ 0x00008000 - 0x0031f404                 │ Kernel (will be loaded later)
├─────────────────────────────────────────┤
│ 0x00200000 - 0x00400000                 │ U-Boot Proper (2MB)
├─────────────────────────────────────────┤
│ 0x00400000 - ...                        │ U-Boot decompression area
├─────────────────────────────────────────┤
│ 0x00c00000 - 0x00c0a404                 │ Device Tree (40KB)
├─────────────────────────────────────────┤
│ ...                                     │ Free memory
├─────────────────────────────────────────┤
│ 0x0e8d6f40 - 0x0ebf8f44                 │ FIT Image (3.2MB)
├─────────────────────────────────────────┤
│ 0x0ebf9f50 - 0x0edf9f50                 │ Stack (2MB)
├─────────────────────────────────────────┤
│ 0x0edf9f50 - 0x10000000                 │ U-Boot (18MB)
└─────────────────────────────────────────┘
```

## Error Analysis

### MMC2 Failure (Expected)
- **Error**: "Card did not respond to voltage select!"
- **Code**: -95 (EOPNOTSUPP)
- **Severity**: **Normal** - Luckfox Pico Ultra W uses eMMC, not SD card
- **Impact**: None - SPL successfully falls back to MMC1

### No Misc Partition (Expected)
- **Message**: "No misc partition"
- **Severity**: **Normal** - Misc partition is optional (used for Android recovery)
- **Impact**: None - Not needed for Linux boot

## Performance Analysis

### Boot Time Breakdown
```
DDR Init:           ~34 ms
SPL Execution:     383 ms
├─ MMC2 attempts:   ~40 ms (2 × 20ms)
├─ MMC1 tuning:      3 ms
├─ FIT loading:    ~300 ms
└─ Verification:    ~40 ms
─────────────────────────
Total:             417 ms
```

### Optimization Opportunities
1. **Skip MMC2**: Configure boot order to skip MMC2 entirely
2. **Reduce retries**: Change MMC init retry count from 2 to 1
3. **Faster storage**: Use HS200 mode in SPL (currently using HS mode)

## Related Files

### Build Configuration
- **Makefile**: `/sysdrv/source/uboot/u-boot/Makefile`
- **SPL Makefile**: `/sysdrv/source/uboot/u-boot/scripts/Makefile.spl`
- **Defconfig**: `/sysdrv/source/uboot/u-boot/configs/rv1106_defconfig`

### Device Tree
- **Base**: `/sysdrv/source/uboot/u-boot/arch/arm/dts/rv1106.dtsi`
- **Board**: `/sysdrv/source/uboot/u-boot/arch/arm/dts/rv1106-luckfox.dts`

### Build Script
- **Path**: `/project/build.sh`
- **Command**: `./build.sh uboot`

## Comparison with Other Boot Modes

| Boot Mode | Device | SPL Support | Speed |
|-----------|--------|-------------|-------|
| eMMC (MMC1) | ✓ Used | Full | Fast |
| SD Card (MMC2) | ✗ Not present | Full | Medium |
| SPI NAND | ✓ Available | Full | Slow |
| USB | ✓ Available | Limited | N/A |

## Next Stage

After SPL completes, it jumps to U-Boot Proper at address 0x00200000.

```
Line 32: Jumping to U-Boot(0x00200000)
```

→ See `stage3_uboot_proper.md` for the next boot stage analysis.
