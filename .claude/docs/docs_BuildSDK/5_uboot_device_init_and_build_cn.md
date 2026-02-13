# U-Boot 设备初始化和编译流程详解

## 问题 1：U-Boot Proper 初始化设备的源码

### 初始化序列数组

**文件**：`sysdrv/source/uboot/u-boot/common/board_r.c:821`

U-Boot Proper 使用一个函数指针数组 `init_sequence_r[]` 来定义初始化顺序：

```c
static init_fnc_t init_sequence_r[] = {
    initr_trace,                    // 跟踪初始化
    initr_reloc,                    // 重定位
    initr_caches,                   // 缓存初始化
    initr_reloc_global_data,        // 重定位全局数据
    board_initr_caches_fixup,       // 缓存修复

    initr_barrier,                  // 内存屏障
    initr_malloc,                   // 内存分配器初始化
    sysmem_initr,                   // 系统内存初始化
    log_init,                       // 日志初始化
    initr_bootstage,                // 启动阶段跟踪

    interrupt_init,                 // 中断初始化
    initr_enable_interrupts,        // 使能中断

    initr_dm,                       // 驱动模型初始化
    board_init,                     // 板级初始化（重要！）

    stdio_init_tables,              // 标准 I/O 表初始化
    initr_serial,                   // ★ 串口初始化
    initr_announce,                 // 打印启动信息

    initr_env,                      // ★ 环境变量加载

    power_init_board,               // 电源初始化
    initr_mmc,                      // ★ MMC 初始化

    stdio_add_devices,              // 添加标准 I/O 设备
    initr_jumptable,                // 跳转表初始化
    console_init_r,                 // 控制台完全初始化
    show_board_info,                // ★ 显示板级信息（打印 model）

    initr_ethaddr,                  // 以太网地址初始化
    gpio_hog_probe_all,             // GPIO 初始化
    board_late_init,                // 板级后期初始化

    initr_net,                      // ★ 网络初始化
    run_main_loop,                  // 进入主循环
    // ... 更多初始化函数 ...
};
```

### 关键设备初始化函数

#### 1. 串口初始化（initr_serial）

**文件**：`common/board_r.c:203`

```c
static int initr_serial(void)
{
    serial_initialize();  // 初始化所有串口设备
    return 0;
}
```

**调用链**：
```
initr_serial()
  └─> serial_initialize()  // drivers/serial/serial.c
      └─> serial_init()
          └─> 读取设备树中的 uart 节点
          └─> 配置波特率、数据位、停止位
          └─> 使能 UART 控制器
```

**对应日志**（第 39 行）：
```
PreSerial: 2, raw, 0xff4c0000
```

#### 2. MMC 初始化（initr_mmc）

**文件**：`common/board_r.c:471`

```c
static int initr_mmc(void)
{
#ifndef CONFIG_USING_KERNEL_DTB
    puts("MMC:   ");
    mmc_initialize(gd->bd);  // 初始化所有 MMC 设备
#endif
    return 0;
}
```

**调用链**：
```
initr_mmc()
  └─> mmc_initialize()  // drivers/mmc/mmc.c
      └─> mmc_probe()
          └─> 读取设备树中的 mmc 节点
          └─> 初始化 MMC 控制器寄存器
          └─> 检测 SD 卡/eMMC
          └─> 设置时钟频率
          └─> 执行 HS200/HS400 调谐
```

**对应日志**（第 47-53 行）：
```
mmc@ffa90000: 0, mmc@ffaa0000: 1
Best phase range 270-237 (30 len)
Successfully tuned phase to 79, used 4ms
Bootdev(atags): mmc 0
MMC0: HS200, 200Mhz
```

#### 3. 板级初始化（board_init）

**文件**：`arch/arm/mach-rockchip/board.c`

```c
int board_init(void)
{
    // 1. 初始化时钟树
    rockchip_setup_clocks();

    // 2. 初始化 GPIO
    gpio_init();

    // 3. 初始化电源管理
    pmic_init();

    // 4. 初始化存储控制器
    storage_init();

    return 0;
}
```

**对应日志**（第 69-80 行）：
```
CLK: (sync kernel. arm: enter 816000 KHz, init 816000 KHz, kernel 0N/A)
  apll 816000 KHz
  dpll 924000 KHz
  gpll 1188000 KHz
  cpll 1000000 KHz
  aclk_peri_root 400000 KHz
  hclk_peri_root 200000 KHz
  pclk_peri_root 100000 KHz
  aclk_bus_root 500000 KHz
  pclk_top_root 100000 KHz
  pclk_pmu_root 100000 KHz
  hclk_pmu_root 200000 KHz
```

#### 4. 环境变量加载（initr_env）

**文件**：`common/board_r.c:925`

```c
static int initr_env(void)
{
    env_relocate();  // 从存储介质加载环境变量
    return 0;
}
```

**调用链**：
```
initr_env()
  └─> env_relocate()  // env/common.c
      └─> env_load()
          └─> env_mmc_load()  // env/mmc.c
              └─> mmc_read(offset=0x0, size=32KB)
              └─> crc32_verify()
              └─> env_import()
```

**对应日志**（第 45、50-51 行）：
```
Using default environment

ENVF: Primary 0x00000000 - 0x00008000
ENVF: Primary 0x00000000 - 0x00008000
```

#### 5. 网络初始化（initr_net）

**文件**：`common/board_r.c:1020`

```c
static int initr_net(void)
{
    puts("Net:   ");
    eth_initialize();  // 初始化以太网
    return 0;
}
```

**调用链**：
```
initr_net()
  └─> eth_initialize()  // net/eth-uclass.c
      └─> eth_probe()
          └─> 读取设备树中的 gmac 节点
          └─> 初始化 PHY
          └─> 配置 MAC 地址
```

**对应日志**（第 81-87 行）：
```
Net:   eth0: ethernet@ffa80000
Hit key to stop autoboot('CTRL+C'):  0
```

### 设备初始化流程图

```
┌─────────────────────────────────────────────────────────┐
│ board_init_r() 入口                                     │
│ - 从 SPL 跳转而来                                       │
│ - gd->fdt_blob 指向设备树                               │
└─────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────┐
│ 遍历 init_sequence_r[] 数组                             │
│ for (i = 0; init_sequence_r[i]; i++) {                 │
│     ret = init_sequence_r[i]();                         │
│     if (ret) hang();                                    │
│ }                                                       │
└─────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────┐
│ 1. initr_serial() - 串口初始化                          │
│    - 读取设备树 uart2 节点                              │
│    - 配置波特率 1500000                                 │
│    - 打印 "PreSerial: 2, raw, 0xff4c0000"               │
└─────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────┐
│ 2. board_init() - 板级初始化                            │
│    - 初始化时钟树（APLL、DPLL、GPLL、CPLL）             │
│    - 打印时钟频率信息                                   │
└─────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────┐
│ 3. initr_mmc() - MMC 初始化                             │
│    - 读取设备树 mmc0、mmc1 节点                         │
│    - 初始化 eMMC 控制器（mmc@ffa90000）                 │
│    - 执行 HS200 调谐                                    │
│    - 打印 "MMC0: HS200, 200Mhz"                         │
└─────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────┐
│ 4. initr_env() - 环境变量加载                           │
│    - 从 eMMC 读取环境分区（32KB @ 0x0）                 │
│    - 验证 CRC32                                         │
│    - 如果失败，使用默认环境                             │
│    - 打印 "Using default environment"                   │
└─────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────┐
│ 5. show_board_info() - 显示板级信息                     │
│    - 读取设备树 model 属性                              │
│    - 打印 "Model: Rockchip RV1106 EVB Board"            │
└─────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────┐
│ 6. initr_net() - 网络初始化                             │
│    - 读取设备树 gmac 节点                               │
│    - 初始化以太网 PHY                                   │
│    - 打印 "Net:   eth0: ethernet@ffa80000"              │
└─────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────┐
│ 7. run_main_loop() - 进入主循环                         │
│    - 加载内核                                           │
│    - 启动 Linux                                         │
└─────────────────────────────────────────────────────────┘
```

### 设备树驱动的初始化

U-Boot 使用**驱动模型（Driver Model, DM）**，设备初始化由设备树驱动：

```c
// 示例：MMC 驱动绑定
U_BOOT_DRIVER(rockchip_rk_mmc) = {
    .name = "rockchip_rk_mmc",
    .id = UCLASS_MMC,
    .of_match = rockchip_mmc_ids,  // 匹配设备树节点
    .probe = rockchip_mmc_probe,   // 探测函数
    .ops = &rockchip_mmc_ops,      // 操作函数
};

// 设备树节点
&mmc0 {
    compatible = "rockchip,rk-mmc";  // ← 匹配这个字符串
    reg = <0xffa90000 0x4000>;       // 寄存器地址
    clocks = <&cru HCLK_EMMC>;       // 时钟
    status = "okay";                 // 启用
};
```

**初始化流程**：
1. `initr_dm()` 初始化驱动模型
2. 扫描设备树，查找 `status = "okay"` 的节点
3. 根据 `compatible` 属性匹配驱动
4. 调用驱动的 `probe()` 函数
5. 设备初始化完成

---

## 问题 2：环境变量镜像和编译流程

### 环境变量是单独的镜像文件

**是的！** 环境变量是一个独立的镜像文件：`env.img`

```bash
$ ls -lh output/image/env.img
-rw-rw-r-- 1 him him 32K Jan 26 18:27 env.img
```

### 编译输出的所有镜像文件

**位置**：`output/image/`

| 文件 | 大小 | 说明 | 编译命令 |
|------|------|------|---------|
| `env.img` | 32 KB | 环境变量镜像 | `./build.sh env` |
| `idblock.img` | 184 KB | ID Block（DDR Init + SPL） | `./build.sh uboot` |
| `uboot.img` | 256 KB | U-Boot Proper + DTB | `./build.sh uboot` |
| `boot.img` | 3.3 MB | 内核 + 设备树（FIT 镜像） | `./build.sh kernel` |
| `rootfs.img` | 397 MB | 根文件系统 | `./build.sh rootfs` |
| `oem.img` | 48 MB | OEM 分区（应用程序） | `./build.sh firmware` |
| `userdata.img` | 9.6 MB | 用户数据分区 | `./build.sh firmware` |
| `update.img` | 458 MB | 完整固件包（包含所有镜像） | `./build.sh firmware` |
| `download.bin` | 263 KB | 下载工具用的引导文件 | `./build.sh uboot` |

### 编译命令和镜像生成关系

#### 1. `./build.sh uboot` - 编译 U-Boot

**生成的镜像**：
- `idblock.img` - ID Block（DDR Init + SPL）
- `uboot.img` - U-Boot Proper + U-Boot DTB
- `download.bin` - 下载工具引导文件

**编译流程**：

```bash
./build.sh uboot
  ↓
build_uboot()  # build.sh:692
  ↓
make uboot -C sysdrv/  # 调用 sysdrv 的 Makefile
  ↓
sysdrv/Makefile:
  1. 编译 U-Boot SPL
     - 源码：sysdrv/source/uboot/u-boot/
     - 输出：u-boot-spl.bin
  
  2. 编译 U-Boot Proper
     - 源码：sysdrv/source/uboot/u-boot/
     - 输出：u-boot.bin
  
  3. 编译 U-Boot DTB
     - 源码：arch/arm/dts/rv1106-luckfox.dts
     - 输出：rv1106-luckfox.dtb
  
  4. 打包 ID Block
     - 工具：rkbin/tools/boot_merger
     - 输入：ddr_init.bin + u-boot-spl.bin
     - 输出：idblock.img
  
  5. 打包 U-Boot 镜像
     - 工具：rkbin/tools/loaderimage
     - 输入：u-boot.bin + rv1106-luckfox.dtb
     - 输出：uboot.img
  
  6. 复制到输出目录
     - cp idblock.img output/image/
     - cp uboot.img output/image/
```

**关键配置文件**：
- `sysdrv/source/uboot/u-boot/.config` - U-Boot 配置
- `project/cfg/BoardConfig_IPC/BoardConfig-*.mk` - 板级配置

#### 2. `./build.sh env` - 编译环境变量镜像

**生成的镜像**：
- `env.img` - 环境变量镜像（32 KB）

**编译流程**：

```bash
./build.sh env
  ↓
build_env()  # build.sh:761
  ↓
1. 生成环境变量配置文件
   - 文件：output/env.txt
   - 内容：
     bootcmd=run distro_bootcmd
     bootargs=console=ttyFIQ0 root=/dev/mmcblk0p7
     sd_parts=mmcblk0:16K@512(env),512K@32K(idblock),...
  
2. 使用 mkenvimage 工具生成镜像
   - 工具：tools/linux/Linux_Pack_Firmware/rockdev/mkenvimage
   - 命令：mkenvimage -s 32768 -p 0x0 -o env.img env.txt
   - 参数：
     -s 32768: 大小 32KB
     -p 0x0: 填充字节 0x00
     -o env.img: 输出文件
     env.txt: 输入配置文件
  
3. 复制到输出目录
   - cp env.img output/image/
```

**源码位置**：`build.sh:761-782`

```bash
function build_env() {
    msg_info "============Start building env============"
    
    # 检查是否需要构建环境镜像
    check_config ENV_SIZE || return 0
    
    local env_cfg_img
    env_cfg_img=$RK_PROJECT_OUTPUT_IMAGE/env.img
    
    # 构建 mkenvimage 工具（如果不存在）
    if [ ! -f "$RK_PROJECT_PATH_PC_TOOLS/mkenvimage" ]; then
        build_tool
    fi
    
    # 添加启动参数到环境配置文件
    echo "$SYS_BOOTARGS" >> $ENV_CFG_FILE
    echo "sd_parts=mmcblk0:16K@512(env),512K@32K(idblock),4M(uboot)" >> $ENV_CFG_FILE
    
    # 生成 env.img
    $RK_PROJECT_PATH_PC_TOOLS/mkenvimage -s $ENV_SIZE -p 0x0 -o $env_cfg_img $ENV_CFG_FILE
    chmod +r $env_cfg_img
    
    finish_build
}
```

#### 3. `./build.sh kernel` - 编译内核

**生成的镜像**：
- `boot.img` - 内核 + 设备树（FIT 镜像）

**编译流程**：

```bash
./build.sh kernel
  ↓
build_kernel()
  ↓
1. 编译 Linux 内核
   - 源码：sysdrv/source/kernel/
   - 配置：arch/arm/configs/luckfox_rv1106_linux_defconfig
   - 输出：arch/arm/boot/Image
  
2. 编译设备树
   - 源码：arch/arm/boot/dts/rv1106g-luckfox-pico-ultra-w.dts
   - 输出：rv1106g-luckfox-pico-ultra-w.dtb
  
3. 打包 FIT 镜像
   - 工具：mkimage
   - 输入：Image + rv1106g-luckfox-pico-ultra-w.dtb
   - 输出：boot.img
  
4. 复制到输出目录
   - cp boot.img output/image/
```

#### 4. `./build.sh firmware` - 打包固件

**生成的镜像**：
- `env.img` - 环境变量（调用 build_env）
- `oem.img` - OEM 分区
- `rootfs.img` - 根文件系统
- `userdata.img` - 用户数据分区
- `update.img` - 完整固件包

**编译流程**：

```bash
./build.sh firmware
  ↓
build_firmware()  # build.sh:2494
  ↓
1. 构建环境变量镜像
   build_env()  # ← 这里生成 env.img
  
2. 打包根文件系统
   build_mkimg rootfs $RK_PROJECT_PACKAGE_ROOTFS_DIR
   - 输入：output/out/rootfs_uclibc_rv1106/
   - 输出：rootfs.img
  
3. 打包 OEM 分区
   build_mkimg oem $RK_PROJECT_PACKAGE_OEM_DIR
   - 输入：output/out/oem/
   - 输出：oem.img
  
4. 打包用户数据分区
   build_mkimg userdata $RK_PROJECT_PACKAGE_USERDATA_DIR
   - 输入：output/out/userdata/
   - 输出：userdata.img
  
5. 生成完整固件包
   build_updateimg()
   - 工具：afptool + rkImageMaker
   - 输入：所有镜像文件
   - 输出：update.img
```

**源码位置**：`build.sh:2494-2579`

```bash
function build_firmware() {
    check_config RK_PARTITION_CMD_IN_ENV || return 0
    
    # 1. 构建环境变量镜像
    build_env  # ← 这里！
    
    # 2. 构建 meta（如果启用快速启动）
    if [ "$RK_ENABLE_FASTBOOT" = "y" ]; then
        build_meta
    fi
    
    # 3. 打包根文件系统
    __PACKAGE_ROOTFS
    build_mkimg $GLOBAL_ROOT_FILESYSTEM_NAME $RK_PROJECT_PACKAGE_ROOTFS_DIR
    
    # 4. 打包 OEM 分区
    __PACKAGE_OEM
    build_mkimg $GLOBAL_OEM_NAME $RK_PROJECT_PACKAGE_OEM_DIR
    
    # 5. 打包用户数据分区
    __PACKAGE_USERDATA
    build_mkimg userdata $RK_PROJECT_PACKAGE_USERDATA_DIR
    
    # 6. 生成完整固件包
    build_updateimg
    
    finish_build
}
```

### 编译命令总结

| 命令 | 生成的镜像 | 说明 |
|------|-----------|------|
| `./build.sh uboot` | idblock.img, uboot.img, download.bin | 只编译 U-Boot |
| `./build.sh kernel` | boot.img | 只编译内核 |
| `./build.sh rootfs` | rootfs.tar | 只编译根文件系统（未打包） |
| `./build.sh env` | env.img | 只生成环境变量镜像 |
| `./build.sh firmware` | env.img, oem.img, rootfs.img, userdata.img, update.img | 打包所有镜像 |
| `./build.sh all` | 所有镜像 | 编译所有组件并打包 |

### 完整编译流程

```
./build.sh all
  ↓
┌─────────────────────────────────────────────────────────┐
│ 1. build_uboot()                                        │
│    - 编译 DDR Init                                      │
│    - 编译 U-Boot SPL                                    │
│    - 编译 U-Boot Proper                                 │
│    - 编译 U-Boot DTB                                    │
│    - 打包 idblock.img                                   │
│    - 打包 uboot.img                                     │
└─────────────────────────────────────────────────────────┘
  ↓
┌─────────────────────────────────────────────────────────┐
│ 2. build_kernel()                                       │
│    - 编译 Linux 内核                                    │
│    - 编译内核设备树                                     │
│    - 打包 boot.img（FIT 镜像）                          │
└─────────────────────────────────────────────────────────┘
  ↓
┌─────────────────────────────────────────────────────────┐
│ 3. build_rootfs()                                       │
│    - 编译 Buildroot                                     │
│    - 生成根文件系统                                     │
│    - 输出 rootfs.tar                                    │
└─────────────────────────────────────────────────────────┘
  ↓
┌─────────────────────────────────────────────────────────┐
│ 4. build_firmware()                                     │
│    ┌───────────────────────────────────────────────┐   │
│    │ 4.1 build_env()                               │   │
│    │     - 生成 env.txt                            │   │
│    │     - 使用 mkenvimage 生成 env.img            │   │
│    └───────────────────────────────────────────────┘   │
│    ┌───────────────────────────────────────────────┐   │
│    │ 4.2 打包根文件系统                            │   │
│    │     - 解压 rootfs.tar                         │   │
│    │     - 添加应用程序                            │   │
│    │     - 生成 rootfs.img                         │   │
│    └───────────────────────────────────────────────┘   │
│    ┌───────────────────────────────────────────────┐   │
│    │ 4.3 打包 OEM 分区                             │   │
│    │     - 复制应用程序到 oem/                     │   │
│    │     - 生成 oem.img                            │   │
│    └───────────────────────────────────────────────┘   │
│    ┌───────────────────────────────────────────────┐   │
│    │ 4.4 打包用户数据分区                          │   │
│    │     - 创建空目录                              │   │
│    │     - 生成 userdata.img                       │   │
│    └───────────────────────────────────────────────┘   │
│    ┌───────────────────────────────────────────────┐   │
│    │ 4.5 生成完整固件包                            │   │
│    │     - 使用 afptool 打包分区表                 │   │
│    │     - 使用 rkImageMaker 生成 update.img       │   │
│    └───────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

### env.img 的内容

**查看 env.img 内容**：

```bash
# 方法 1：使用 hexdump
hexdump -C output/image/env.img | head -20

# 输出示例：
00000000  12 34 56 78                                       |.4Vx|  ← CRC32
00000004  00                                                |.|     ← 标志
00000005  62 6f 6f 74 63 6d 64 3d  72 75 6e 20 64 69 73 74  |bootcmd=run dist|
00000015  72 6f 5f 62 6f 6f 74 63  6d 64 00                 |ro_bootcmd.|
00000020  62 6f 6f 74 61 72 67 73  3d 63 6f 6e 73 6f 6c 65  |bootargs=console|
00000030  3d 74 74 79 46 49 51 30  20 72 6f 6f 74 3d 2f 64  |=ttyFIQ0 root=/d|
00000040  65 76 2f 6d 6d 63 62 6c  6b 30 70 37 00           |ev/mmcblk0p7.|

# 方法 2：使用 strings
strings output/image/env.img

# 输出示例：
bootcmd=run distro_bootcmd
bootargs=console=ttyFIQ0 root=/dev/mmcblk0p7 rootfstype=ext4
sd_parts=mmcblk0:16K@512(env),512K@32K(idblock),4M(uboot),32M(boot),...
```

### mkenvimage 工具

**源码位置**：`tools/linux/Linux_Pack_Firmware/rockdev/mkenvimage`

**用法**：
```bash
mkenvimage -s <size> -p <padding> -o <output> <input>

参数：
  -s <size>     : 镜像大小（字节）
  -p <padding>  : 填充字节（十六进制）
  -o <output>   : 输出文件
  <input>       : 输入配置文件
```

**示例**：
```bash
# 生成 32KB 的环境变量镜像
mkenvimage -s 32768 -p 0x0 -o env.img env.txt
```

### 环境变量配置文件

**位置**：`output/env.txt`（临时文件）

**内容示例**：
```bash
# 启动命令
bootcmd=run distro_bootcmd

# 启动参数
bootargs=console=ttyFIQ0 root=/dev/mmcblk0p7 rootfstype=ext4 rw rootwait

# 分区表
sd_parts=mmcblk0:16K@512(env),512K@32K(idblock),256K(uboot),32M(boot),48M(oem),397M(rootfs),10M(userdata)

# 网络配置
ipaddr=192.168.1.100
serverip=192.168.1.1
```

### 总结

1. **环境变量是单独的镜像文件**：`env.img`（32 KB）

2. **编译命令**：
   - `./build.sh env` - 只生成 env.img
   - `./build.sh firmware` - 生成所有镜像（包括 env.img）
   - `./build.sh all` - 编译所有组件并打包

3. **一起编译的镜像**：
   - `./build.sh uboot` → idblock.img + uboot.img + download.bin
   - `./build.sh firmware` → env.img + oem.img + rootfs.img + userdata.img + update.img

4. **env.img 生成流程**：
   ```
   env.txt (配置文件) → mkenvimage 工具 → env.img (32KB 镜像)
   ```

5. **env.img 在固件中的位置**：
   - 分区：env（32KB @ 偏移 0）
   - 扇区：0-63
   - 用途：存储 U-Boot 环境变量

