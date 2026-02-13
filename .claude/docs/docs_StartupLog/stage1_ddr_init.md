# Stage 1: DDR Initialization Analysis

## Log Content (Lines 1-9)

```
     1→DDR 306b9977f5 wesley.yao 23/12/21-09:28:37,fwver: v1.15
     2→S5P1
     3→4x
     4→f967
     5→rgef1
     6→DDRConf2
     7→DDR3, BW=16 Col=10 Bk=8 CS0 Row=14 CS=1 Size=256MB
     8→924MHz
     9→DDR bin out
```

## Functional Overview

This is the **first stage** of the boot process, executed by the **DDR initialization binary** (DDR init blob). This stage runs before any CPU code and is responsible for:

1. **Memory Controller Configuration** - Setting up the DDR3 memory controller
2. **Timing Parameter Configuration** - Configuring DDR3 timing parameters
3. **Memory Training** - Running memory calibration and training sequences
4. **Memory Testing** - Verifying memory integrity

## Code Location

### Binary File
- **Path**: `/sysdrv/source/uboot/rkbin/bin/rv11/rv1106_ddr_924MHz_v1.15.bin`
- **Type**: Precompiled binary (no source code available)
- **Version**: v1.15 (built by wesley.yao on 2023/12/21)

### Configuration File
- **Path**: `/sysdrv/source/uboot/rkbin/RKBOOT/RV1106MINIALL.ini`
- **Section**: `[CODE471_OPTION]`
- **Parameter**: `NUM=1` and `Path1=bin/rv11/rv1106_ddr_924MHz_v1.15.bin`

### Integration Point
The DDR init binary is loaded by the **BootROM** (hardcoded in the RV1106 chip) and executed from SRAM before U-Boot SPL.

## Key Parameters Analysis

### Line 1: Version Information
```
DDR 306b9977f5 wesley.yao 23/12/21-09:28:37,fwver: v1.15
```
- **Build ID**: `306b9977f5` (Git commit hash or build identifier)
- **Author**: wesley.yao (Rockchip engineer)
- **Build Date**: December 21, 2023, 09:28:37
- **Firmware Version**: v1.15

### Lines 2-6: Internal Debug Output
```
S5P1
4x
f967
rgef1
DDRConf2
```
These are internal debug markers from the DDR init code:
- **S5P1**: Likely indicates "Stage 5 Phase 1" or similar internal checkpoint
- **4x**: Memory configuration mode (possibly 4x mode)
- **f967, rgef1**: Internal register values or checkpoints
- **DDRConf2**: DDR configuration profile #2

### Line 7: Memory Configuration
```
DDR3, BW=16 Col=10 Bk=8 CS0 Row=14 CS=1 Size=256MB
```

Detailed breakdown:
- **DDR3**: Memory type (DDR3 SDRAM)
- **BW=16**: Bus width is 16 bits (2 bytes per transfer)
- **Col=10**: 10-bit column address (1024 columns)
- **Bk=8**: 8 banks per chip
- **CS0 Row=14**: Chip Select 0 has 14-bit row address (16384 rows)
- **CS=1**: Only 1 chip select active (single-rank memory)
- **Size=256MB**: Total memory size

**Memory Calculation Verification**:
```
Size = 2^(Col) × 2^(Row) × Banks × BW × CS
     = 2^10 × 2^14 × 8 × 2 × 1
     = 1024 × 16384 × 8 × 2
     = 268,435,456 bytes
     = 256 MB ✓
```

### Line 8: Operating Frequency
```
924MHz
```
- **DDR Clock**: 924 MHz
- **Data Rate**: 1848 MT/s (DDR = Double Data Rate)
- **Bandwidth**: 1848 MT/s × 16 bits = 29,568 Mb/s = 3.696 GB/s theoretical

### Line 9: Completion Marker
```
DDR bin out
```
Indicates successful completion of DDR initialization and handoff to next boot stage.

## Memory Architecture

### Physical Layout
```
┌─────────────────────────────────────┐
│         RV1106 SoC                  │
│  ┌──────────────────────────────┐   │
│  │   DDR Controller             │   │
│  │   - 16-bit bus width         │   │
│  │   - 924 MHz clock            │   │
│  │   - Single channel           │   │
│  └──────────┬───────────────────┘   │
└─────────────┼───────────────────────┘
              │ 16-bit data bus
              ↓
     ┌────────────────────┐
     │   DDR3 Chip        │
     │   256MB (CS0)      │
     │   8 Banks          │
     │   1024 Columns     │
     │   16384 Rows       │
     └────────────────────┘
```

## Boot Flow Context

```
┌──────────────┐
│  BootROM     │ ← Hardcoded in chip, loads DDR init from storage
│  (in chip)   │
└──────┬───────┘
       │
       ↓
┌──────────────┐
│  DDR Init    │ ← **WE ARE HERE** (Lines 1-9)
│  v1.15       │   Configures memory controller
└──────┬───────┘
       │
       ↓
┌──────────────┐
│  U-Boot SPL  │ ← Next stage (Lines 10-30)
│  2017.09     │
└──────────────┘
```

## Configuration Files

### Board Configuration
The DDR binary selection is controlled by the board configuration file:
- **Path**: `/project/cfg/BoardConfig_IPC/BoardConfig-EMMC-Buildroot-RV1106_Luckfox_Pico_Ultra_W-IPC.mk`
- **Variable**: `RK_LOADER_UPDATE_SPL` (points to the RKBOOT INI file)

### RKBOOT INI File
```ini
[CODE471_OPTION]
NUM=1
Path1=bin/rv11/rv1106_ddr_924MHz_v1.15.bin
Load=0x00000000
Mask=1
```

## Error Analysis

**No errors detected in this stage.** The DDR initialization completed successfully with:
- ✓ Correct memory size detected (256MB)
- ✓ Proper frequency configured (924MHz)
- ✓ Clean exit ("DDR bin out")

## Performance Characteristics

### Memory Bandwidth
- **Theoretical Peak**: 3.696 GB/s
- **Practical Bandwidth**: ~2.5-3.0 GB/s (accounting for protocol overhead)

### Latency
- **CAS Latency**: Not shown in log (typically CL=6 or CL=7 for DDR3-1866)
- **tRCD, tRP, tRAS**: Not shown (configured internally by DDR init binary)

## Comparison with Other Luckfox Models

| Model | DDR Type | Size | Frequency | Bus Width |
|-------|----------|------|-----------|-----------|
| Pico (RV1103) | DDR3 | 64MB | 528MHz | 16-bit |
| Pico Plus (RV1103) | DDR3 | 128MB | 528MHz | 16-bit |
| **Pico Ultra W (RV1106)** | **DDR3** | **256MB** | **924MHz** | **16-bit** |
| Pico Pro Max (RV1106) | DDR3 | 256MB | 924MHz | 16-bit |

## Optimization Considerations

### Frequency Tuning
The DDR frequency can be changed by using a different binary:
- **Available binaries**: Check `/sysdrv/source/uboot/rkbin/bin/rv11/` for other frequency options
- **Common options**: 528MHz, 664MHz, 784MHz, 924MHz, 1056MHz

### Memory Size
The memory size is **hardware-dependent** and cannot be changed via software. The Luckfox Pico Ultra W has 256MB soldered on the board.

## Related Documentation

- **Rockchip RV1106 TRM** (Technical Reference Manual) - DDR Controller chapter
- **DDR3 JEDEC Standard** - JESD79-3F
- **Luckfox Wiki**: https://wiki.luckfox.com/zh/Luckfox-Pico-Pro-Max/

## Next Stage

After DDR initialization completes, the BootROM loads **U-Boot SPL** from the boot medium (eMMC in this case) into the now-initialized DDR memory and transfers control to it.

→ See `stage2_uboot_spl.md` for the next boot stage analysis.
