# U-Boot 驱动模型与设备树机制详解

## 概述

### 为什么 arch/arm/mach-rockchip/rv1106/ 代码很少？

在查看 Luckfox Pico SDK 的 U-Boot 源码时，你可能会发现 `arch/arm/mach-rockchip/rv1106/` 目录下的代码非常少，只有三个文件：

```bash
$ ls sysdrv/source/uboot/u-boot/arch/arm/mach-rockchip/rv1106/
clk_rv1106.c  syscon_rv1106.c  rv1106.c
```

但是 GPIO、UART、MMC、以太网等设备的驱动代码在哪里？它们是如何初始化的？

**答案**：现代 U-Boot 使用**驱动模型（Driver Model, DM）**架构，驱动代码不在 `arch/` 目录下，而是在 `drivers/` 目录下，通过**设备树（Device Tree）**自动匹配和初始化。

### 现代 U-Boot 的驱动架构概览

```
传统架构（旧版 U-Boot）：
  - 驱动代码和板级代码耦合
  - 每个板子需要单独的初始化代码
  - 难以维护和移植

驱动模型架构（现代 U-Boot）：
  - 驱动代码独立于板级代码
  - 通过设备树描述硬件
  - 驱动自动匹配和初始化
  - 易于维护和移植
```

### 本文解答的核心问题

1. **驱动代码在哪里？** → `drivers/` 目录
2. **硬件信息在哪里？** → 设备树（`arch/arm/dts/`）
3. **寄存器定义在哪里？** → 头文件（`arch/arm/include/asm/arch-rockchip/`）
4. **如何匹配驱动和硬件？** → `compatible` 属性
5. **如何处理硬件差异？** → 条件编译 + 设备树属性

---

## 第一部分：驱动模型（Driver Model）基础

### 1.1 代码分布与职责

U-Boot 的代码按照职责分布在不同的目录：

| 目录 | 职责 | 示例文件 |
|------|------|---------|
| `arch/arm/mach-rockchip/rv1106/` | SoC 级别初始化（时钟、复位、系统控制器） | `clk_rv1106.c`、`syscon_rv1106.c` |
| `drivers/` | 设备驱动（GPIO、UART、MMC、网络等） | `drivers/gpio/rk_gpio.c`<br>`drivers/mmc/rockchip_dw_mmc.c` |
| `arch/arm/dts/` | 设备树（硬件描述） | `rv1106.dtsi`、`rv1106-luckfox.dts` |
| `arch/arm/include/asm/arch-rockchip/` | 寄存器定义 | `gpio.h`、`uart.h` |
| `common/` | 通用初始化代码 | `board_r.c`（初始化序列） |

**关键点**：
- `mach-rockchip/rv1106/` 只负责 SoC 特定的基础初始化
- 设备驱动都在 `drivers/` 目录，与具体 SoC 解耦
- 设备树描述硬件配置，驱动通过设备树自动匹配

### 1.2 驱动注册机制

#### U_BOOT_DRIVER() 宏

驱动通过 `U_BOOT_DRIVER()` 宏注册到 U-Boot 系统中。以 GPIO 驱动为例：

**文件**：`drivers/gpio/rk_gpio.c:190-197`

```c
U_BOOT_DRIVER(gpio_rockchip) = {
    .name   = "gpio_rockchip",           // 驱动名称
    .id     = UCLASS_GPIO,               // 驱动类别（GPIO 类）
    .of_match = rockchip_gpio_ids,       // ← 匹配表（关键！）
    .ops    = &gpio_rockchip_ops,        // 操作函数（get/set 等）
    .probe  = rockchip_gpio_probe,       // 初始化函数
    .priv_auto_alloc_size = sizeof(struct rockchip_gpio_priv),
};
```

#### of_match 匹配表

驱动通过 `of_match` 匹配表指定支持的硬件：

```c
static const struct udevice_id rockchip_gpio_ids[] = {
    { .compatible = "rockchip,gpio-bank" },  // ← 匹配字符串
    { }  // 结束标记
};
```

**工作原理**：
1. U-Boot 启动时扫描设备树
2. 读取每个节点的 `compatible` 属性
3. 查找匹配的驱动（比对 `of_match` 表）
4. 找到匹配的驱动后，调用 `probe()` 函数初始化设备

#### 设备树节点示例

**文件**：`arch/arm/dts/rv1106.dtsi`

```dts
gpio0: gpio@ff380000 {
    compatible = "rockchip,gpio-bank";  // ← 与驱动匹配
    reg = <0xff380000 0x100>;           // 寄存器地址
    clocks = <&cru PCLK_PMU_GPIO0>;     // 时钟
    gpio-controller;
    #gpio-cells = <2>;
};
```

**匹配过程**：
```
设备树节点：compatible = "rockchip,gpio-bank"
     ↓ 匹配
驱动匹配表：{ .compatible = "rockchip,gpio-bank" }
     ↓ 调用
驱动 probe()：rockchip_gpio_probe()
     ↓ 完成
设备初始化完成
```

### 1.3 驱动初始化流程

#### 初始化序列

**文件**：`common/board_r.c:821`

U-Boot Proper 使用 `init_sequence_r[]` 数组定义初始化顺序（参见文档 5）：

```c
static init_fnc_t init_sequence_r[] = {
    ...
    initr_dm,           // ← 驱动模型初始化（关键！）
    board_init,         // 板级初始化
    ...
    initr_serial,       // 串口初始化
    initr_mmc,          // MMC 初始化
    initr_net,          // 网络初始化
    ...
};
```

#### 驱动模型初始化流程

```
board_init_r()
  ↓
initr_dm()  ← 初始化驱动模型
  ↓
dm_init_and_scan()
  ↓
dm_scan_fdt()  ← 扫描设备树
  ↓
对每个设备树节点：
  1. 读取 compatible 属性
  2. 查找匹配的驱动（遍历所有 U_BOOT_DRIVER）
  3. 创建设备实例（udevice）
  4. 调用驱动的 probe() 函数
  5. 设备初始化完成
  ↓
所有设备初始化完成
```

#### 流程图

```
┌─────────────────────────────────────────────────────────┐
│ board_init_r() - U-Boot Proper 入口                     │
└─────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────┐
│ initr_dm() - 初始化驱动模型                             │
│   - 初始化设备树解析器                                  │
│   - 准备驱动匹配环境                                    │
└─────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────┐
│ dm_scan_fdt() - 扫描设备树                              │
│   - 遍历所有设备树节点                                  │
│   - 读取 compatible 属性                                │
└─────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────┐
│ 设备匹配循环                                            │
│                                                         │
│ 对每个节点：                                            │
│   1. compatible = "rockchip,gpio-bank"                  │
│   2. 查找驱动：遍历所有 U_BOOT_DRIVER                   │
│   3. 找到匹配：gpio_rockchip                            │
│   4. 创建设备实例（udevice）                            │
│   5. 读取设备树属性（reg、clocks 等）                   │
└─────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────┐
│ 调用驱动 probe() 函数                                   │
│   - rockchip_gpio_probe()                               │
│   - 初始化寄存器                                        │
│   - 配置时钟                                            │
│   - 设置 GPIO 功能                                      │
└─────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────┐
│ 设备初始化完成                                          │
│   - 设备可用                                            │
│   - 继续下一个设备                                      │
└─────────────────────────────────────────────────────────┘
```

#### 关键函数调用链

```
board_init_r()                    // common/board_r.c
  └─> initr_dm()                  // common/board_r.c
      └─> dm_init_and_scan()      // drivers/core/root.c
          └─> dm_scan_fdt()       // drivers/core/root.c
              └─> dm_scan_fdt_node()
                  └─> lists_bind_fdt()
                      └─> device_bind_by_name()
                          └─> device_probe()
                              └─> drv->probe()  // 调用驱动的 probe 函数
```

#### 与启动日志的对应

参考启动日志（`uart_StartupLog.log`），可以看到驱动初始化的输出：

```
PreSerial: 2, raw, 0xff4c0000        ← UART 驱动初始化
...
mmc@ffa90000: 0, mmc@ffaa0000: 1     ← MMC 驱动初始化
...
Net:   eth0: ethernet@ffa80000       ← 以太网驱动初始化
```

这些输出都是在 `initr_dm()` 之后，各个驱动的 `probe()` 函数中打印的。

---

### 小结

**第一部分关键点**：

1. **代码分布**：
   - `mach-rockchip/rv1106/` → SoC 基础初始化
   - `drivers/` → 设备驱动
   - `arch/arm/dts/` → 设备树

2. **驱动注册**：
   - `U_BOOT_DRIVER()` 宏注册驱动
   - `of_match` 表指定支持的硬件

3. **初始化流程**：
   - `initr_dm()` 初始化驱动模型
   - `dm_scan_fdt()` 扫描设备树
   - 匹配驱动并调用 `probe()` 函数

**下一部分**将详细介绍设备树的作用和提供的信息。

---

## 第二部分：设备树的作用

### 2.1 设备树提供的信息类型

设备树不仅仅提供寄存器地址，它提供了完整的硬件描述信息。驱动通过读取这些信息来配置硬件。

#### 信息类型表格

| 属性名称 | 作用 | 示例 | 驱动如何使用 |
|---------|------|------|-------------|
| `compatible` | 硬件版本标识 | `"rockchip,rv1106-dw-mshc"` | 匹配驱动，选择初始化路径 |
| `reg` | 寄存器地址和大小 | `<0xff380000 0x100>` | 映射寄存器，访问硬件 |
| `interrupts` | 中断号和类型 | `<GIC_SPI 5 IRQ_TYPE_LEVEL_HIGH>` | 注册中断处理函数 |
| `clocks` | 时钟源 | `<&cru PCLK_GPIO0>` | 使能时钟，配置频率 |
| `clock-names` | 时钟名称 | `"biu", "ciu"` | 按名称获取时钟 |
| `resets` | 复位信号 | `<&cru SRST_GPIO0>` | 复位设备 |
| `gpio-controller` | 标记为 GPIO 控制器 | （无值） | 注册为 GPIO 提供者 |
| `#gpio-cells` | GPIO 引用参数数量 | `<2>` | 解析 GPIO 引用 |
| `fifo-depth` | FIFO 深度 | `<0x100>` | 配置 FIFO 大小 |
| `max-frequency` | 最大频率 | `<200000000>` | 限制时钟频率 |
| `default-sample-phase` | 采样相位 | `<90>` | 配置采样时钟相位 |
| `rockchip,use-v2-tuning` | 特性标志 | （无值） | 选择调谐算法 |
| `status` | 设备状态 | `"okay"` / `"disabled"` | 决定是否初始化 |

#### 驱动读取设备树的 API

U-Boot 提供了一系列 API 来读取设备树属性：

```c
// 读取寄存器地址
void *dev_read_addr_ptr(struct udevice *dev);

// 读取布尔属性（存在返回 true）
bool dev_read_bool(struct udevice *dev, const char *propname);

// 读取 u32 属性（带默认值）
u32 dev_read_u32_default(struct udevice *dev, const char *propname, int def);

// 读取字符串属性
const char *dev_read_string(struct udevice *dev, const char *propname);

// 获取时钟
int clk_get_by_name(struct udevice *dev, const char *name, struct clk *clk);

// 获取 GPIO
int gpio_request_by_name(struct udevice *dev, const char *list_name, int index,
                         struct gpio_desc *desc, int flags);
```

### 2.2 设备树节点示例

#### 完整的 MMC 节点

**文件**：`arch/arm/dts/rv1106.dtsi`

```dts
emmc: mmc@ffa90000 {
    compatible = "rockchip,rv1106-dw-mshc", "rockchip,rk3288-dw-mshc";
    reg = <0xffa90000 0x4000>;
    interrupts = <GIC_SPI 48 IRQ_TYPE_LEVEL_HIGH>;
    clocks = <&cru HCLK_EMMC>, <&cru CCLK_SRC_EMMC>,
             <&grf_cru SCLK_EMMC_DRV>, <&grf_cru SCLK_EMMC_SAMPLE>;
    clock-names = "biu", "ciu", "ciu-drive", "ciu-sample";
    fifo-depth = <0x100>;
    max-frequency = <200000000>;
    rockchip,use-v2-tuning;
    status = "disabled";
};
```

#### 各字段含义说明

**1. compatible（硬件版本标识）**

```dts
compatible = "rockchip,rv1106-dw-mshc", "rockchip,rk3288-dw-mshc";
```

- **作用**：指定硬件版本，用于匹配驱动
- **多个值的含义**：
  - 第一个：`rockchip,rv1106-dw-mshc` - RV1106 特定版本（优先匹配）
  - 第二个：`rockchip,rk3288-dw-mshc` - RK3288 兼容版本（回退匹配）
- **匹配机制**：驱动按顺序尝试匹配，找到第一个支持的版本

**2. reg（寄存器地址）**

```dts
reg = <0xffa90000 0x4000>;
```

- **格式**：`<地址 大小>`
- **含义**：eMMC 控制器的寄存器起始地址为 `0xffa90000`，大小为 `0x4000`（16KB）
- **驱动使用**：
  ```c
  priv->regs = dev_read_addr_ptr(dev);  // 获取寄存器基地址
  writel(value, &priv->regs->ctrl);     // 访问寄存器
  ```

**3. interrupts（中断配置）**

```dts
interrupts = <GIC_SPI 48 IRQ_TYPE_LEVEL_HIGH>;
```

- **格式**：`<中断控制器类型 中断号 触发类型>`
- **含义**：
  - `GIC_SPI`：共享外设中断（Shared Peripheral Interrupt）
  - `48`：中断号
  - `IRQ_TYPE_LEVEL_HIGH`：高电平触发
- **驱动使用**：注册中断处理函数

**4. clocks（时钟配置）**

```dts
clocks = <&cru HCLK_EMMC>, <&cru CCLK_SRC_EMMC>,
         <&grf_cru SCLK_EMMC_DRV>, <&grf_cru SCLK_EMMC_SAMPLE>;
clock-names = "biu", "ciu", "ciu-drive", "ciu-sample";
```

- **格式**：`<&时钟控制器 时钟ID>`
- **含义**：
  - `HCLK_EMMC`：总线接口时钟（biu - Bus Interface Unit）
  - `CCLK_SRC_EMMC`：卡接口时钟（ciu - Card Interface Unit）
  - `SCLK_EMMC_DRV`：驱动时钟（用于输出）
  - `SCLK_EMMC_SAMPLE`：采样时钟（用于输入）
- **驱动使用**：
  ```c
  clk_get_by_name(dev, "ciu", &priv->clk);  // 按名称获取时钟
  clk_set_rate(&priv->clk, 200000000);      // 设置频率为 200MHz
  clk_enable(&priv->clk);                   // 使能时钟
  ```

**5. 硬件参数**

```dts
fifo-depth = <0x100>;
max-frequency = <200000000>;
```

- **fifo-depth**：FIFO 深度为 256 字节
- **max-frequency**：最大工作频率为 200MHz
- **驱动使用**：
  ```c
  priv->fifo_depth = dev_read_u32_default(dev, "fifo-depth", 0x100);
  host->fifoth_val = MSIZE(DWMCI_MSIZE) |
                     RX_WMARK(priv->fifo_depth / 2 - 1) |
                     TX_WMARK(priv->fifo_depth / 2);
  ```

**6. 特性标志**

```dts
rockchip,use-v2-tuning;
```

- **作用**：标记使用 V2 版本的调谐算法
- **驱动使用**：
  ```c
  if (dev_read_bool(dev, "rockchip,use-v2-tuning")) {
      // 使用 V2 调谐算法
      host->execute_tuning = rockchip_dwmmc_execute_tuning_v2;
  }
  ```

**7. status（设备状态）**

```dts
status = "disabled";
```

- **可能的值**：
  - `"okay"`：设备启用，驱动会初始化
  - `"disabled"`：设备禁用，驱动不会初始化
- **板级设备树覆盖**：
  ```dts
  // 在 rv1106-luckfox.dts 中启用
  &emmc {
      status = "okay";
  };
  ```

#### GPIO 节点示例

**文件**：`arch/arm/dts/rv1106.dtsi`

```dts
gpio0: gpio@ff380000 {
    compatible = "rockchip,gpio-bank";
    reg = <0xff380000 0x100>;
    interrupts = <GIC_SPI 5 IRQ_TYPE_LEVEL_HIGH>;
    clocks = <&cru PCLK_PMU_GPIO0>, <&cru DBCLK_PMU_GPIO0>;

    gpio-controller;
    #gpio-cells = <2>;
    gpio-ranges = <&pinctrl 0 0 32>;
    interrupt-controller;
    #interrupt-cells = <2>;
};
```

**特殊属性说明**：

- **gpio-controller**：标记此节点为 GPIO 控制器
- **#gpio-cells**：GPIO 引用需要 2 个参数（引脚号、标志）
- **gpio-ranges**：GPIO 引脚范围映射到 pinctrl
  - 格式：`<&pinctrl 本地起始 全局起始 数量>`
  - 含义：GPIO0 的 32 个引脚映射到 pinctrl 的 0-31
- **interrupt-controller**：标记此节点也是中断控制器（GPIO 可作为中断源）
- **#interrupt-cells**：中断引用需要 2 个参数（引脚号、触发类型）

#### UART 节点示例

**文件**：`arch/arm/dts/rv1106.dtsi`

```dts
uart2: serial@ff4c0000 {
    compatible = "rockchip,rv1106-uart", "snps,dw-apb-uart";
    reg = <0xff4c0000 0x100>;
    interrupts = <GIC_SPI 33 IRQ_TYPE_LEVEL_HIGH>;
    clocks = <&cru SCLK_UART2>, <&cru PCLK_UART2>;
    clock-names = "baudclk", "apb_pclk";
    reg-shift = <2>;
    reg-io-width = <4>;
    status = "disabled";
};
```

**特殊属性说明**：

- **reg-shift**：寄存器地址偏移量（每个寄存器间隔 4 字节）
- **reg-io-width**：寄存器访问宽度（32 位）
- **compatible 链**：
  - `rockchip,rv1106-uart`：RV1106 特定版本
  - `snps,dw-apb-uart`：Synopsys DesignWare APB UART（通用版本）

### 2.3 设备树的层次结构

设备树采用分层设计：

```
rv1106.dtsi                    ← SoC 级别（定义所有硬件）
  ↓ include
rv1106-luckfox.dts             ← 板级（启用/配置特定硬件）
  ↓ 编译
rv1106-luckfox.dtb             ← 二进制设备树（U-Boot 使用）
```

**示例**：

**SoC 级别**（`rv1106.dtsi`）：
```dts
emmc: mmc@ffa90000 {
    compatible = "rockchip,rv1106-dw-mshc", "rockchip,rk3288-dw-mshc";
    reg = <0xffa90000 0x4000>;
    ...
    status = "disabled";  // 默认禁用
};
```

**板级**（`rv1106-luckfox.dts`）：
```dts
#include "rv1106.dtsi"

&emmc {
    status = "okay";      // 启用 eMMC
    bus-width = <8>;      // 配置为 8 位总线
    cap-mmc-highspeed;    // 支持高速模式
};
```

---

### 小结

**第二部分关键点**：

1. **设备树提供的信息**：
   - `compatible`：硬件版本标识
   - `reg`：寄存器地址
   - `clocks`：时钟配置
   - `interrupts`：中断配置
   - 硬件参数和特性标志

2. **驱动读取设备树**：
   - `dev_read_addr_ptr()`：读取寄存器地址
   - `dev_read_bool()`：读取布尔属性
   - `dev_read_u32_default()`：读取数值属性
   - `clk_get_by_name()`：获取时钟

3. **设备树层次结构**：
   - SoC 级别（`.dtsi`）：定义所有硬件
   - 板级（`.dts`）：启用和配置特定硬件

**下一部分**将介绍如何处理不同硬件版本的差异。

---

## 第三部分：硬件差异处理机制

### 3.1 处理机制概览

不同 SoC 或同一 SoC 的不同版本，硬件可能存在差异。U-Boot 通过以下机制处理这些差异：

| 差异类型 | 处理方式 | 配置位置 | 示例 |
|---------|---------|---------|------|
| **寄存器布局不同** | 条件编译 + 不同结构体定义 | `.config` + 头文件 | GPIO V1 vs V2 |
| **初始化序列不同** | 条件编译 + 特定代码段 | `.config` + 驱动代码 | RV1106 采样相位设置 |
| **硬件参数不同** | 设备树属性 | 设备树 | FIFO 深度、最大频率 |
| **时钟配置不同** | 设备树时钟绑定 | 设备树 | 不同 SoC 的时钟树 |
| **中断号不同** | 设备树中断属性 | 设备树 | 不同 SoC 的中断控制器 |

### 3.2 寄存器布局差异

#### GPIO V1 vs V2 对比

Rockchip 的 GPIO 控制器有两个版本，寄存器布局完全不同：

**寄存器定义**：`arch/arm/include/asm/arch-rockchip/gpio.h`

```c
#ifndef CONFIG_ROCKCHIP_GPIO_V2
// ========== GPIO V1 寄存器布局（旧版本）==========
struct rockchip_gpio_regs {
    u32 swport_dr;      // 0x00: 数据寄存器（32位）
    u32 swport_ddr;     // 0x04: 方向寄存器（32位）
    u32 reserved0[(0x30 - 0x08) / 4];
    u32 inten;          // 0x30: 中断使能（32位）
    u32 intmask;        // 0x34: 中断屏蔽（32位）
    ...
};
#else
// ========== GPIO V2 寄存器布局（新版本，RV1106 使用）==========
struct rockchip_gpio_regs {
    u32 swport_dr_l;    // 0x00: 数据寄存器低16位
    u32 swport_dr_h;    // 0x04: 数据寄存器高16位
    u32 swport_ddr_l;   // 0x08: 方向寄存器低16位
    u32 swport_ddr_h;   // 0x0c: 方向寄存器高16位
    u32 int_en_l;       // 0x10: 中断使能低16位
    u32 int_en_h;       // 0x14: 中断使能高16位
    ...
};
#endif
```

**对比表**：

| 功能 | GPIO V1 | GPIO V2 |
|------|---------|---------|
| 数据寄存器 | 1 个 32 位寄存器（0x00） | 2 个 16 位寄存器（0x00, 0x04） |
| 方向寄存器 | 1 个 32 位寄存器（0x04） | 2 个 16 位寄存器（0x08, 0x0c） |
| 中断使能 | 1 个 32 位寄存器（0x30） | 2 个 16 位寄存器（0x10, 0x14） |
| 寄存器总数 | 较少 | 较多（增加了去抖动等功能） |

#### 条件编译机制

**编译配置**：`sysdrv/source/uboot/u-boot/.config`

```makefile
CONFIG_ROCKCHIP_RV1106=y      # 指定 SoC 型号
CONFIG_ROCKCHIP_GPIO_V2=y     # 指定 GPIO 版本
```

**驱动代码适配**：`drivers/gpio/rk_gpio.c:26-47`

```c
#ifdef CONFIG_ROCKCHIP_GPIO_V2
// ========== V2 版本：需要分别操作高低16位 ==========
#define REG_L(R)    (R##_l)
#define REG_H(R)    (R##_h)

#define READ_REG(REG)   ((readl(REG_L(REG)) & 0xFFFF) | \
                        ((readl(REG_H(REG)) & 0xFFFF) << 16))

#define WRITE_REG(REG, VAL) \
{ \
    writel(((VAL) & 0xFFFF) | 0xFFFF0000, REG_L(REG)); \
    writel((((VAL) & 0xFFFF0000) >> 16) | 0xFFFF0000, REG_H(REG)); \
}

#else
// ========== V1 版本：直接操作32位寄存器 ==========
#define READ_REG(REG)           readl(REG)
#define WRITE_REG(REG, VAL)     writel(VAL, REG)
#endif
```

**使用示例**：

```c
static int rockchip_gpio_set_value(struct udevice *dev, unsigned offset, int value)
{
    struct rockchip_gpio_priv *priv = dev_get_priv(dev);
    struct rockchip_gpio_regs *regs = priv->regs;
    int mask = OFFSET_TO_BIT(offset);

    // 无论 V1 还是 V2，使用相同的宏
    CLRSETBITS_LE32(&regs->swport_dr, mask, value ? mask : 0);

    return 0;
}
```

**关键点**：
- 驱动代码使用统一的宏（`WRITE_REG`、`READ_REG`）
- 宏根据 `CONFIG_ROCKCHIP_GPIO_V2` 展开为不同的实现
- 编译时确定使用哪个版本，运行时无性能损失

### 3.3 初始化序列差异

#### RV1106 特定代码

不同 SoC 可能需要不同的初始化序列。以 MMC 驱动为例：

**文件**：`drivers/mmc/rockchip_dw_mmc.c:444-450`

```c
dwmci_setup_cfg(&plat->cfg, host, priv->minmax[1], priv->minmax[0]);
if (dev_read_bool(dev, "mmc-hs200-1_8v"))
    plat->cfg.host_caps |= MMC_MODE_HS200;

plat->mmc.default_phase = dev_read_u32_default(dev, "default-sample-phase", 0);

#ifdef CONFIG_ROCKCHIP_RV1106
// ========== RV1106 特定：需要设置采样相位 ==========
if (!(ret < 0) && (&priv->sample_clk)) {
    ret = clk_set_phase(&priv->sample_clk, plat->mmc.default_phase);
    if (ret < 0)
        debug("MMC: can not set default phase!\n");
}
#endif
```

**说明**：
- RV1106 的 MMC 控制器需要在初始化时设置采样时钟相位
- 其他 SoC（如 RK3288）不需要这个步骤
- 通过 `#ifdef CONFIG_ROCKCHIP_RV1106` 条件编译实现

#### 另一个示例：RK3128 的 stride_pio

**文件**：`drivers/mmc/rockchip_dw_mmc.c:423-427`

```c
#ifdef CONFIG_ROCKCHIP_RK3128
    host->stride_pio = true;   // RK3128 需要 stride PIO 模式
#else
    host->stride_pio = false;  // 其他 SoC 不需要
#endif
```

### 3.4 compatible 链机制

#### 优先匹配和回退匹配

设备树可以指定多个 `compatible` 字符串，驱动按顺序尝试匹配：

**设备树**：`arch/arm/dts/rv1106.dtsi`

```dts
emmc: mmc@ffa90000 {
    compatible = "rockchip,rv1106-dw-mshc", "rockchip,rk3288-dw-mshc";
                 ↑ 优先匹配                  ↑ 回退匹配
    ...
};
```

**驱动匹配表**：`drivers/mmc/rockchip_dw_mmc.c:468-472`

```c
static const struct udevice_id rockchip_dwmmc_ids[] = {
    { .compatible = "rockchip,rk3288-dw-mshc" },  // 支持 RK3288
    { .compatible = "rockchip,rk2928-dw-mshc" },  // 支持 RK2928
    { }
};
```

**匹配过程**：

```
步骤 1：尝试匹配 "rockchip,rv1106-dw-mshc"
  └─> 驱动匹配表中没有这个字符串
  └─> 匹配失败

步骤 2：尝试匹配 "rockchip,rk3288-dw-mshc"
  └─> 驱动匹配表中有这个字符串
  └─> 匹配成功！使用 rockchip_dwmmc_drv 驱动

步骤 3：调用 probe() 函数
  └─> rockchip_dwmmc_probe()
  └─> 在 probe() 中通过 CONFIG_ROCKCHIP_RV1106 执行 RV1106 特定代码
```

#### 为什么使用 compatible 链？

1. **向后兼容**：新 SoC 可以复用旧 SoC 的驱动
2. **渐进式支持**：先用通用驱动，再逐步添加特定优化
3. **减少代码重复**：不需要为每个 SoC 写独立的驱动

**示例**：

```dts
// RV1106 的 UART 节点
uart2: serial@ff4c0000 {
    compatible = "rockchip,rv1106-uart", "snps,dw-apb-uart";
                 ↑ RV1106 特定版本        ↑ Synopsys 通用版本
    ...
};
```

- 如果有 `rockchip,rv1106-uart` 驱动，优先使用（可以有 RV1106 特定优化）
- 如果没有，回退到 `snps,dw-apb-uart` 通用驱动（基本功能可用）

### 3.5 硬件参数差异

#### 通过设备树属性处理

不同板子或不同 SoC 的硬件参数可能不同，通过设备树属性配置：

**示例 1：FIFO 深度**

```dts
// RV1106 的 MMC
emmc: mmc@ffa90000 {
    fifo-depth = <0x100>;  // 256 字节
    ...
};

// 假设另一个 SoC 的 MMC
emmc: mmc@ff0c0000 {
    fifo-depth = <0x80>;   // 128 字节
    ...
};
```

**驱动读取**：

```c
priv->fifo_depth = dev_read_u32_default(dev, "fifo-depth", 0x100);
host->fifoth_val = MSIZE(DWMCI_MSIZE) |
                   RX_WMARK(priv->fifo_depth / 2 - 1) |
                   TX_WMARK(priv->fifo_depth / 2);
```

**示例 2：最大频率**

```dts
emmc: mmc@ffa90000 {
    max-frequency = <200000000>;  // RV1106 支持 200MHz
    ...
};

sdmmc: mmc@ffaa0000 {
    max-frequency = <150000000>;  // SD 卡只支持 150MHz
    ...
};
```

**驱动读取**：

```c
plat->cfg.f_max = dev_read_u32_default(dev, "max-frequency", 52000000);
```

#### 通过设备树特性标志

```dts
emmc: mmc@ffa90000 {
    rockchip,use-v2-tuning;  // 使用 V2 调谐算法
    cap-mmc-highspeed;       // 支持高速模式
    mmc-hs200-1_8v;          // 支持 HS200 模式
    ...
};
```

**驱动读取**：

```c
if (dev_read_bool(dev, "rockchip,use-v2-tuning")) {
    host->execute_tuning = rockchip_dwmmc_execute_tuning_v2;
}

if (dev_read_bool(dev, "mmc-hs200-1_8v")) {
    plat->cfg.host_caps |= MMC_MODE_HS200;
}
```

### 3.6 时钟和中断差异

#### 时钟配置差异

不同 SoC 的时钟树不同，通过设备树配置：

```dts
// RV1106 的 MMC 时钟
emmc: mmc@ffa90000 {
    clocks = <&cru HCLK_EMMC>, <&cru CCLK_SRC_EMMC>,
             <&grf_cru SCLK_EMMC_DRV>, <&grf_cru SCLK_EMMC_SAMPLE>;
    clock-names = "biu", "ciu", "ciu-drive", "ciu-sample";
    ...
};

// 假设另一个 SoC 的 MMC 时钟（只有 2 个时钟）
emmc: mmc@ff0c0000 {
    clocks = <&cru HCLK_EMMC>, <&cru CCLK_EMMC>;
    clock-names = "biu", "ciu";
    ...
};
```

**驱动处理**：

```c
// 获取必需的时钟
ret = clk_get_by_name(dev, "ciu", &priv->clk);
if (ret < 0)
    return ret;

// 尝试获取可选的采样时钟
ret = clk_get_by_name(dev, "ciu-sample", &priv->sample_clk);
if (ret < 0)
    debug("MMC: sample clock not found, not support hs200!\n");
```

#### 中断号差异

不同 SoC 的中断号不同，通过设备树配置：

```dts
// RV1106 的 GPIO0 中断
gpio0: gpio@ff380000 {
    interrupts = <GIC_SPI 5 IRQ_TYPE_LEVEL_HIGH>;  // 中断号 5
    ...
};

// 假设另一个 SoC 的 GPIO0 中断
gpio0: gpio@ff750000 {
    interrupts = <GIC_SPI 81 IRQ_TYPE_LEVEL_HIGH>; // 中断号 81
    ...
};
```

---

### 小结

**第三部分关键点**：

1. **寄存器布局差异**：
   - 通过条件编译（`#ifdef CONFIG_ROCKCHIP_GPIO_V2`）
   - 定义不同的寄存器结构体
   - 使用宏统一访问接口

2. **初始化序列差异**：
   - 通过条件编译（`#ifdef CONFIG_ROCKCHIP_RV1106`）
   - 在驱动中添加特定代码段

3. **compatible 链机制**：
   - 优先匹配特定版本
   - 回退到通用版本
   - 实现向后兼容

4. **硬件参数差异**：
   - 通过设备树属性配置
   - 驱动运行时读取

5. **时钟和中断差异**：
   - 通过设备树绑定
   - 驱动按名称获取

**下一部分**将通过完整的实战案例，综合应用前三部分的知识。

---

## 第四部分：完整实战案例

本部分通过完整的实战案例，展示驱动模型、设备树和硬件差异处理如何协同工作。

### 4.1 GPIO 驱动剖析

GPIO 驱动是一个典型的例子，展示了如何处理寄存器布局差异（V1 vs V2）。

#### 步骤 1：寄存器定义

**文件**：`arch/arm/include/asm/arch-rockchip/gpio.h:10-62`

```c
#ifndef CONFIG_ROCKCHIP_GPIO_V2
// GPIO V1 寄存器布局
struct rockchip_gpio_regs {
    u32 swport_dr;      // 0x00: 数据寄存器
    u32 swport_ddr;     // 0x04: 方向寄存器
    u32 reserved0[(0x30 - 0x08) / 4];
    u32 inten;          // 0x30: 中断使能
    u32 intmask;        // 0x34: 中断屏蔽
    u32 inttype_level;  // 0x38: 中断类型
    u32 int_polarity;   // 0x3c: 中断极性
    u32 int_status;     // 0x40: 中断状态
    u32 int_rawstatus;  // 0x44: 原始中断状态
    u32 debounce;       // 0x48: 去抖动
    u32 porta_eoi;      // 0x4c: 中断清除
    u32 ext_port;       // 0x50: 外部端口值
    u32 reserved1[(0x60 - 0x54) / 4];
    u32 ls_sync;        // 0x60: 电平同步
};
#else
// GPIO V2 寄存器布局（RV1106 使用）
struct rockchip_gpio_regs {
    u32 swport_dr_l;    // 0x00: 数据寄存器低16位
    u32 swport_dr_h;    // 0x04: 数据寄存器高16位
    u32 swport_ddr_l;   // 0x08: 方向寄存器低16位
    u32 swport_ddr_h;   // 0x0c: 方向寄存器高16位
    u32 int_en_l;       // 0x10: 中断使能低16位
    u32 int_en_h;       // 0x14: 中断使能高16位
    u32 int_mask_l;     // 0x18: 中断屏蔽低16位
    u32 int_mask_h;     // 0x1c: 中断屏蔽高16位
    u32 int_type_l;     // 0x20: 中断类型低16位
    u32 int_type_h;     // 0x24: 中断类型高16位
    u32 int_polarity_l; // 0x28: 中断极性低16位
    u32 int_polarity_h; // 0x2c: 中断极性高16位
    u32 int_bothedge_l; // 0x30: 双边沿中断低16位
    u32 int_bothedge_h; // 0x34: 双边沿中断高16位
    u32 debounce_l;     // 0x38: 去抖动低16位
    u32 debounce_h;     // 0x3c: 去抖动高16位
    u32 dbclk_div_en_l; // 0x40: 去抖动时钟分频使能低16位
    u32 dbclk_div_en_h; // 0x44: 去抖动时钟分频使能高16位
    u32 dbclk_div_con;  // 0x48: 去抖动时钟分频配置
    u32 reserved004c;   // 0x4c
    u32 int_status;     // 0x50: 中断状态
    u32 reserved0054;   // 0x54
    u32 int_rawstatus;  // 0x58: 原始中断状态
    u32 reserved005c;   // 0x5c
    u32 port_eoi_l;     // 0x60: 中断清除低16位
    u32 port_eoi_h;     // 0x64: 中断清除高16位
    u32 reserved0068[2];// 0x68-0x6c
    u32 ext_port;       // 0x70: 外部端口值
    u32 reserved0074;   // 0x74
    u32 ver_id;         // 0x78: 版本ID
};
#endif
```

#### 步骤 2：驱动代码

**文件**：`drivers/gpio/rk_gpio.c`

**2.1 驱动私有数据结构**

```c
struct rockchip_gpio_priv {
    struct rockchip_gpio_regs *regs;  // 寄存器基地址
    struct udevice *pinctrl;          // pinctrl 设备
    int bank;                         // GPIO bank 编号
    char name[2];                     // GPIO 名称
};
```

**2.2 GPIO 操作函数**

```c
// 设置 GPIO 方向为输入
static int rockchip_gpio_direction_input(struct udevice *dev, unsigned offset)
{
    struct rockchip_gpio_priv *priv = dev_get_priv(dev);
    struct rockchip_gpio_regs *regs = priv->regs;

    // 清除方向寄存器对应位（0=输入）
    CLRBITS_LE32(&regs->swport_ddr, OFFSET_TO_BIT(offset));

    return 0;
}

// 设置 GPIO 方向为输出
static int rockchip_gpio_direction_output(struct udevice *dev, unsigned offset, int value)
{
    struct rockchip_gpio_priv *priv = dev_get_priv(dev);
    struct rockchip_gpio_regs *regs = priv->regs;
    int mask = OFFSET_TO_BIT(offset);

    // 先设置输出值
    CLRSETBITS_LE32(&regs->swport_dr, mask, value ? mask : 0);
    // 再设置方向为输出（1=输出）
    SETBITS_LE32(&regs->swport_ddr, mask);

    return 0;
}

// 读取 GPIO 值
static int rockchip_gpio_get_value(struct udevice *dev, unsigned offset)
{
    struct rockchip_gpio_priv *priv = dev_get_priv(dev);
    struct rockchip_gpio_regs *regs = priv->regs;

    // 读取外部端口寄存器
    return readl(&regs->ext_port) & OFFSET_TO_BIT(offset) ? 1 : 0;
}

// 设置 GPIO 值
static int rockchip_gpio_set_value(struct udevice *dev, unsigned offset, int value)
{
    struct rockchip_gpio_priv *priv = dev_get_priv(dev);
    struct rockchip_gpio_regs *regs = priv->regs;
    int mask = OFFSET_TO_BIT(offset);

    // 设置数据寄存器对应位
    CLRSETBITS_LE32(&regs->swport_dr, mask, value ? mask : 0);

    return 0;
}
```

**关键点**：
- 使用 `CLRBITS_LE32`、`SETBITS_LE32` 等宏操作寄存器
- 这些宏会根据 `CONFIG_ROCKCHIP_GPIO_V2` 展开为不同的实现
- 驱动代码无需关心 V1 还是 V2

**2.3 驱动 probe 函数**

```c
static int rockchip_gpio_probe(struct udevice *dev)
{
    struct gpio_dev_priv *uc_priv = dev_get_uclass_priv(dev);
    struct rockchip_gpio_priv *priv = dev_get_priv(dev);
    struct rockchip_pinctrl_priv *pctrl_priv;
    struct rockchip_pin_bank *bank;
    char *end = NULL;
    int id = -1, ret;

    // 1. 从设备树读取寄存器地址
    priv->regs = dev_read_addr_ptr(dev);

    // 2. 获取 pinctrl 设备
    ret = uclass_get_device_by_seq(UCLASS_PINCTRL, 0, &priv->pinctrl);
    if (ret) {
        ret = uclass_first_device_err(UCLASS_PINCTRL, &priv->pinctrl);
        if (ret) {
            dev_err(dev, "failed to get pinctrl device %d\n", ret);
            return ret;
        }
    }

    pctrl_priv = dev_get_priv(priv->pinctrl);
    if (!pctrl_priv) {
        dev_err(dev, "failed to get pinctrl priv\n");
        return -EINVAL;
    }

    // 3. 从设备名称解析 GPIO bank ID
    end = strrchr(dev->name, '@');
    if (end)
        id = trailing_strtoln(dev->name, end);
    if (id < 0)
        dev_read_alias_seq(dev, &id);

    if (id < 0 || id >= pctrl_priv->ctrl->nr_banks) {
        dev_err(dev, "nr_banks=%d, bank id=%d invalid\n",
                pctrl_priv->ctrl->nr_banks, id);
        return -EINVAL;
    }

    // 4. 获取 GPIO bank 信息
    bank = &pctrl_priv->ctrl->pin_banks[id];
    if (bank->bank_num != id) {
        dev_err(dev, "bank id mismatch with pinctrl\n");
        return -EINVAL;
    }

    // 5. 设置 GPIO 控制器信息
    priv->bank = bank->bank_num;
    uc_priv->gpio_count = bank->nr_pins;  // GPIO 数量
    uc_priv->gpio_base = bank->pin_base;  // GPIO 起始编号
    uc_priv->bank_name = bank->name;      // GPIO 名称（如 "gpio0"）

    return 0;
}
```

**2.4 驱动注册**

```c
// GPIO 操作函数表
static const struct dm_gpio_ops gpio_rockchip_ops = {
    .direction_input  = rockchip_gpio_direction_input,
    .direction_output = rockchip_gpio_direction_output,
    .get_value        = rockchip_gpio_get_value,
    .set_value        = rockchip_gpio_set_value,
    .get_function     = rockchip_gpio_get_function,
};

// 驱动匹配表
static const struct udevice_id rockchip_gpio_ids[] = {
    { .compatible = "rockchip,gpio-bank" },
    { }
};

// 驱动注册
U_BOOT_DRIVER(gpio_rockchip) = {
    .name   = "gpio_rockchip",
    .id     = UCLASS_GPIO,
    .of_match = rockchip_gpio_ids,
    .ops    = &gpio_rockchip_ops,
    .priv_auto_alloc_size = sizeof(struct rockchip_gpio_priv),
    .probe  = rockchip_gpio_probe,
};
```

#### 步骤 3：设备树配置

**文件**：`arch/arm/dts/rv1106.dtsi`

```dts
gpio0: gpio@ff380000 {
    compatible = "rockchip,gpio-bank";
    reg = <0xff380000 0x100>;
    interrupts = <GIC_SPI 5 IRQ_TYPE_LEVEL_HIGH>;
    clocks = <&cru PCLK_PMU_GPIO0>, <&cru DBCLK_PMU_GPIO0>;

    gpio-controller;
    #gpio-cells = <2>;
    gpio-ranges = <&pinctrl 0 0 32>;
    interrupt-controller;
    #interrupt-cells = <2>;
};

gpio1: gpio@ff530000 {
    compatible = "rockchip,gpio-bank";
    reg = <0xff530000 0x100>;
    interrupts = <GIC_SPI 7 IRQ_TYPE_LEVEL_HIGH>;
    clocks = <&cru PCLK_GPIO1>, <&cru DBCLK_GPIO1>;

    gpio-controller;
    #gpio-cells = <2>;
    gpio-ranges = <&pinctrl 0 32 32>;
    interrupt-controller;
    #interrupt-cells = <2>;
};

// ... gpio2, gpio3, gpio4
```

#### 步骤 4：编译配置

**文件**：`sysdrv/source/uboot/u-boot/.config`

```makefile
CONFIG_ROCKCHIP_RV1106=y      # 指定 SoC 型号
CONFIG_ROCKCHIP_GPIO_V2=y     # 指定 GPIO 版本
CONFIG_DM_GPIO=y              # 启用驱动模型 GPIO
```

#### 步骤 5：初始化流程

```
board_init_r()
  ↓
initr_dm()
  ↓
dm_scan_fdt()
  ↓
扫描设备树，找到 gpio@ff380000 节点
  ↓
读取 compatible = "rockchip,gpio-bank"
  ↓
匹配驱动：rockchip_gpio_ids
  ↓
创建设备实例（udevice）
  ↓
调用 rockchip_gpio_probe()
  ├─> 读取寄存器地址：0xff380000
  ├─> 获取 pinctrl 设备
  ├─> 解析 GPIO bank ID：0
  ├─> 设置 GPIO 数量：32
  └─> 初始化完成
  ↓
GPIO0 可用
  ↓
继续初始化 GPIO1, GPIO2, ...
```

#### 与启动日志的对应

GPIO 初始化在 `initr_dm()` 之后，但没有明显的日志输出。可以通过以下方式验证：

```bash
# U-Boot 命令行
=> gpio status
Bank gpio0:
gpio0@0  (gpio 0) input
gpio0@1  (gpio 1) input
...
```

---

### 4.2 MMC 驱动剖析

MMC 驱动展示了如何处理初始化序列差异（RV1106 特定代码）和 compatible 链机制。

#### 步骤 1：寄存器定义

MMC 驱动使用 Synopsys DesignWare MMC 控制器，寄存器定义在通用头文件中：

**文件**：`include/dwmmc.h`（部分）

```c
struct dwmci_host {
    const char *name;
    void *ioaddr;           // 寄存器基地址
    unsigned int quirks;
    unsigned int caps;
    unsigned int version;
    unsigned int clock;
    unsigned int bus_hz;
    unsigned int div;
    int dev_index;
    int dev_id;
    int buswidth;
    u32 fifoth_val;
    struct mmc *mmc;
    // ... 更多字段
};
```

**寄存器偏移**（`include/dwmmc.h`）：

```c
#define DWMCI_CTRL      0x000  // 控制寄存器
#define DWMCI_PWREN     0x004  // 电源使能
#define DWMCI_CLKDIV    0x008  // 时钟分频
#define DWMCI_CLKSRC    0x00c  // 时钟源
#define DWMCI_CLKENA    0x010  // 时钟使能
#define DWMCI_TMOUT     0x014  // 超时
#define DWMCI_CTYPE     0x018  // 卡类型
#define DWMCI_BLKSIZ    0x01c  // 块大小
#define DWMCI_BYTCNT    0x020  // 字节计数
// ... 更多寄存器
```

#### 步骤 2：驱动代码

**文件**：`drivers/mmc/rockchip_dw_mmc.c`

**2.1 驱动私有数据结构**

```c
struct rockchip_dwmmc_priv {
    struct dwmci_host host;       // DW MMC 主机
    int fifo_depth;               // FIFO 深度
    bool fifo_mode;               // FIFO 模式
    u32 minmax[2];                // 最小/最大频率
    u32 usrid;                    // 用户ID
    struct clk clk;               // 时钟
    struct clk sample_clk;        // 采样时钟
};
```

**2.2 驱动 probe 函数**（简化版）

```c
static int rockchip_dwmmc_probe(struct udevice *dev)
{
    struct rockchip_mmc_plat *plat = dev_get_platdata(dev);
    struct mmc_uclass_priv *upriv = dev_get_uclass_priv(dev);
    struct rockchip_dwmmc_priv *priv = dev_get_priv(dev);
    struct dwmci_host *host = &priv->host;
    int ret;

    // 1. 从设备树读取配置（参见 ofdata_to_platdata）
    // 已在 ofdata_to_platdata 中完成

    // 2. 获取时钟
    ret = clk_get_by_index(dev, 0, &priv->clk);
    if (ret < 0)
        return ret;

    // 3. 尝试获取采样时钟（可选）
    ret = clk_get_by_name(dev, "ciu-sample", &priv->sample_clk);
    if (ret < 0)
        debug("MMC: sample clock not found, not support hs200!\n");

    // 4. 配置 FIFO
    host->fifoth_val = MSIZE(DWMCI_MSIZE) |
                       RX_WMARK(priv->fifo_depth / 2 - 1) |
                       TX_WMARK(priv->fifo_depth / 2);

    host->fifo_mode = priv->fifo_mode;

    // 5. 配置 stride_pio（RK3128 特定）
#ifdef CONFIG_ROCKCHIP_RK3128
    host->stride_pio = true;
#else
    host->stride_pio = false;
#endif

    // 6. 配置 MMC
    dwmci_setup_cfg(&plat->cfg, host, priv->minmax[1], priv->minmax[0]);

    // 7. 检查 HS200 支持
    if (dev_read_bool(dev, "mmc-hs200-1_8v"))
        plat->cfg.host_caps |= MMC_MODE_HS200;

    // 8. 读取默认采样相位
    plat->mmc.default_phase = dev_read_u32_default(dev, "default-sample-phase", 0);

    // 9. RV1106 特定：设置采样相位
#ifdef CONFIG_ROCKCHIP_RV1106
    if (!(ret < 0) && (&priv->sample_clk)) {
        ret = clk_set_phase(&priv->sample_clk, plat->mmc.default_phase);
        if (ret < 0)
            debug("MMC: can not set default phase!\n");
    }
#endif

    // 10. 初始化 MMC
    plat->mmc.init_retry = 0;
    host->mmc = &plat->mmc;
    host->mmc->priv = &priv->host;
    host->mmc->dev = dev;
    upriv->mmc = host->mmc;

    return dwmci_probe(dev);
}
```

**2.3 从设备树读取配置**

```c
static int rockchip_dwmmc_ofdata_to_platdata(struct udevice *dev)
{
    struct rockchip_dwmmc_priv *priv = dev_get_priv(dev);
    struct dwmci_host *host = &priv->host;

    // 读取寄存器地址
    host->ioaddr = dev_read_addr_ptr(dev);

    // 读取 FIFO 深度
    priv->fifo_depth = dev_read_u32_default(dev, "fifo-depth", 0);

    // 读取 FIFO 模式
    priv->fifo_mode = dev_read_bool(dev, "fifo-mode");

    // 读取最小/最大频率
    dev_read_u32_array(dev, "clock-freq-min-max", priv->minmax, 2);

    // 读取总线宽度
    host->buswidth = dev_read_u32_default(dev, "bus-width", 4);

    return 0;
}
```

**2.4 驱动注册**

```c
// 驱动匹配表
static const struct udevice_id rockchip_dwmmc_ids[] = {
    { .compatible = "rockchip,rk3288-dw-mshc" },
    { .compatible = "rockchip,rk2928-dw-mshc" },
    { }
};

// 驱动注册
U_BOOT_DRIVER(rockchip_dwmmc_drv) = {
    .name     = "rockchip_rk3288_dw_mshc",
    .id       = UCLASS_MMC,
    .of_match = rockchip_dwmmc_ids,
    .ofdata_to_platdata = rockchip_dwmmc_ofdata_to_platdata,
    .ops      = &dm_dwmci_ops,
    .bind     = rockchip_dwmmc_bind,
    .probe    = rockchip_dwmmc_probe,
    .priv_auto_alloc_size = sizeof(struct rockchip_dwmmc_priv),
    .platdata_auto_alloc_size = sizeof(struct rockchip_mmc_plat),
};
```

#### 步骤 3：设备树配置

**文件**：`arch/arm/dts/rv1106.dtsi`

```dts
emmc: mmc@ffa90000 {
    compatible = "rockchip,rv1106-dw-mshc", "rockchip,rk3288-dw-mshc";
    reg = <0xffa90000 0x4000>;
    interrupts = <GIC_SPI 48 IRQ_TYPE_LEVEL_HIGH>;
    clocks = <&cru HCLK_EMMC>, <&cru CCLK_SRC_EMMC>,
             <&grf_cru SCLK_EMMC_DRV>, <&grf_cru SCLK_EMMC_SAMPLE>;
    clock-names = "biu", "ciu", "ciu-drive", "ciu-sample";
    fifo-depth = <0x100>;
    max-frequency = <200000000>;
    rockchip,use-v2-tuning;
    status = "disabled";
};

sdmmc: mmc@ffaa0000 {
    compatible = "rockchip,rv1106-dw-mshc", "rockchip,rk3288-dw-mshc";
    reg = <0xffaa0000 0x4000>;
    interrupts = <GIC_SPI 52 IRQ_TYPE_LEVEL_HIGH>;
    clocks = <&cru HCLK_SDMMC>, <&cru CCLK_SRC_SDMMC>,
             <&grf_cru SCLK_SDMMC_DRV>, <&grf_cru SCLK_SDMMC_SAMPLE>;
    clock-names = "biu", "ciu", "ciu-drive", "ciu-sample";
    cd-gpios = <&gpio3 RK_PA1 GPIO_ACTIVE_HIGH>;
    fifo-depth = <0x100>;
    max-frequency = <200000000>;
    status = "disabled";
};
```

**板级设备树**（`rv1106-luckfox.dts`）：

```dts
&emmc {
    status = "okay";
    bus-width = <8>;
    cap-mmc-highspeed;
    mmc-hs200-1_8v;
    supports-emmc;
    non-removable;
};
```

#### 步骤 4：编译配置

**文件**：`sysdrv/source/uboot/u-boot/.config`

```makefile
CONFIG_ROCKCHIP_RV1106=y      # 指定 SoC 型号
CONFIG_MMC=y                  # 启用 MMC 支持
CONFIG_DM_MMC=y               # 启用驱动模型 MMC
CONFIG_MMC_DW=y               # 启用 DesignWare MMC
CONFIG_MMC_DW_ROCKCHIP=y      # 启用 Rockchip DW MMC
```

#### 步骤 5：初始化流程

```
board_init_r()
  ↓
initr_mmc()
  ↓
mmc_initialize()
  ↓
（MMC 设备已在 initr_dm() 时创建）
  ↓
mmc_probe()
  ↓
rockchip_dwmmc_probe()
  ├─> 读取寄存器地址：0xffa90000
  ├─> 获取时钟：HCLK_EMMC, CCLK_SRC_EMMC, ...
  ├─> 读取 FIFO 深度：0x100
  ├─> 读取最大频率：200000000
  ├─> 配置 FIFO
  ├─> 读取默认采样相位
  ├─> [RV1106] 设置采样时钟相位
  └─> 调用 dwmci_probe() 初始化 MMC 控制器
  ↓
MMC 初始化完成
  ↓
检测 eMMC 卡
  ├─> 发送 CMD0（复位）
  ├─> 发送 CMD1（识别）
  ├─> 读取 CID/CSD
  ├─> 设置工作模式（HS200）
  └─> 执行调谐（tuning）
  ↓
eMMC 可用
```

#### 与启动日志的对应

参考启动日志（`uart_StartupLog.log`）：

```
MMC:   mmc@ffa90000: 0, mmc@ffaa0000: 1
Loading Environment from MMC... Best phase range 270-237 (30 len)
Successfully tuned phase to 79, used 4ms
Bootdev(atags): mmc 0
MMC0: HS200, 200Mhz
PartType: EFI
```

**日志解析**：
- `mmc@ffa90000: 0`：eMMC 初始化为 mmc0
- `mmc@ffaa0000: 1`：SD 卡初始化为 mmc1
- `Best phase range 270-237`：调谐找到最佳相位范围
- `Successfully tuned phase to 79`：设置采样相位为 79 度
- `MMC0: HS200, 200Mhz`：eMMC 工作在 HS200 模式，200MHz

---

### 小结

**第四部分关键点**（GPIO 和 MMC）：

1. **GPIO 驱动**：
   - 展示了寄存器布局差异处理（V1 vs V2）
   - 使用宏统一访问接口
   - 通过条件编译适配不同版本

2. **MMC 驱动**：
   - 展示了初始化序列差异处理（RV1106 特定代码）
   - 展示了 compatible 链机制（优先匹配 + 回退匹配）
   - 展示了设备树属性读取（FIFO 深度、最大频率等）

**下一部分**将继续介绍 UART 驱动案例，然后是快速参考和常见问题。

### 4.3 UART 驱动剖析

UART 驱动展示了如何复用通用驱动（NS16550）并添加 Rockchip 适配层。

#### 驱动架构

```
Rockchip UART 驱动架构：
  ├─> serial_rockchip.c（Rockchip 适配层）
  │     └─> 读取设备树配置
  │     └─> 转换为 NS16550 格式
  └─> ns16550.c（通用 NS16550 驱动）
        └─> 实际的 UART 操作
```

#### 驱动代码（简化版）

**文件**：`drivers/serial/serial_rockchip.c`

```c
static int rockchip_serial_probe(struct udevice *dev)
{
    struct rockchip_uart_platdata *plat = dev_get_platdata(dev);

    // 从设备树读取配置，转换为 NS16550 格式
    plat->plat.base = plat->dtplat.reg[0];           // 寄存器地址
    plat->plat.reg_shift = plat->dtplat.reg_shift;   // 寄存器偏移
    plat->plat.clock = plat->dtplat.clock_frequency; // 时钟频率
    plat->plat.fcr = UART_FCR_DEFVAL;                // FIFO 控制
    dev->platdata = &plat->plat;

    // 调用通用 NS16550 驱动
    return ns16550_serial_probe(dev);
}

U_BOOT_DRIVER(rockchip_rk3288_uart) = {
    .name   = "rockchip_rk3288_uart",
    .id     = UCLASS_SERIAL,
    .priv_auto_alloc_size = sizeof(struct NS16550),
    .platdata_auto_alloc_size = sizeof(struct rockchip_uart_platdata),
    .probe  = rockchip_serial_probe,
    .ops    = &ns16550_serial_ops,  // 使用 NS16550 操作函数
    .flags  = DM_FLAG_PRE_RELOC,    // 重定位前初始化
};
```

#### 设备树配置

**文件**：`arch/arm/dts/rv1106.dtsi`

```dts
uart2: serial@ff4c0000 {
    compatible = "rockchip,rv1106-uart", "snps,dw-apb-uart";
    reg = <0xff4c0000 0x100>;
    interrupts = <GIC_SPI 33 IRQ_TYPE_LEVEL_HIGH>;
    clocks = <&cru SCLK_UART2>, <&cru PCLK_UART2>;
    clock-names = "baudclk", "apb_pclk";
    reg-shift = <2>;        // 寄存器间隔 4 字节
    reg-io-width = <4>;     // 32 位访问
    status = "disabled";
};
```

#### 与启动日志的对应

参考启动日志（`uart_StartupLog.log`）：

```
PreSerial: 2, raw, 0xff4c0000
```

- `PreSerial: 2`：UART2 初始化
- `0xff4c0000`：寄存器地址

---

## 第五部分：快速参考

### 5.1 关键文件速查表

| 设备类型 | 驱动文件 | 寄存器定义 | 设备树节点 | 配置选项 |
|---------|---------|-----------|-----------|---------|
| **GPIO** | `drivers/gpio/rk_gpio.c` | `arch/arm/include/asm/arch-rockchip/gpio.h` | `gpio@ff380000` | `CONFIG_ROCKCHIP_GPIO_V2`<br>`CONFIG_DM_GPIO` |
| **MMC** | `drivers/mmc/rockchip_dw_mmc.c` | `include/dwmmc.h` | `mmc@ffa90000` | `CONFIG_MMC_DW_ROCKCHIP`<br>`CONFIG_DM_MMC` |
| **UART** | `drivers/serial/serial_rockchip.c`<br>`drivers/serial/ns16550.c` | `include/ns16550.h` | `serial@ff4c0000` | `CONFIG_DM_SERIAL`<br>`CONFIG_SYS_NS16550` |
| **以太网** | `drivers/net/gmac_rockchip.c` | `arch/arm/include/asm/arch-rockchip/gmac.h` | `ethernet@ffa80000` | `CONFIG_GMAC_ROCKCHIP`<br>`CONFIG_DM_ETH` |
| **I2C** | `drivers/i2c/rk_i2c.c` | `arch/arm/include/asm/arch-rockchip/i2c.h` | `i2c@ff3f0000` | `CONFIG_SYS_I2C_ROCKCHIP`<br>`CONFIG_DM_I2C` |
| **SPI** | `drivers/spi/rk_spi.c` | `arch/arm/include/asm/arch-rockchip/spi.h` | `spi@ff4d0000` | `CONFIG_ROCKCHIP_SPI`<br>`CONFIG_DM_SPI` |

### 5.2 常用 API 速查

#### 设备树读取 API

```c
// 读取寄存器地址
void *dev_read_addr_ptr(struct udevice *dev);
fdt_addr_t dev_read_addr(struct udevice *dev);

// 读取布尔属性
bool dev_read_bool(struct udevice *dev, const char *propname);

// 读取 u32 属性
u32 dev_read_u32_default(struct udevice *dev, const char *propname, int def);
int dev_read_u32(struct udevice *dev, const char *propname, u32 *outp);
int dev_read_u32_array(struct udevice *dev, const char *propname, u32 *out, size_t sz);

// 读取字符串属性
const char *dev_read_string(struct udevice *dev, const char *propname);

// 读取别名序号
int dev_read_alias_seq(struct udevice *dev, int *devnump);
```

#### 时钟 API

```c
// 获取时钟
int clk_get_by_index(struct udevice *dev, int index, struct clk *clk);
int clk_get_by_name(struct udevice *dev, const char *name, struct clk *clk);

// 时钟操作
ulong clk_get_rate(struct clk *clk);
ulong clk_set_rate(struct clk *clk, ulong rate);
int clk_enable(struct clk *clk);
int clk_disable(struct clk *clk);

// 时钟相位（RV1106 特定）
int clk_set_phase(struct clk *clk, int degrees);
```

#### GPIO API

```c
// 请求 GPIO
int gpio_request_by_name(struct udevice *dev, const char *list_name, int index,
                         struct gpio_desc *desc, int flags);

// GPIO 操作
int dm_gpio_set_value(const struct gpio_desc *desc, int value);
int dm_gpio_get_value(const struct gpio_desc *desc);
int dm_gpio_set_dir_flags(struct gpio_desc *desc, ulong flags);
```

### 5.3 调试命令速查

#### U-Boot 命令行调试

```bash
# 查看设备树
=> fdt addr ${fdtcontroladdr}
=> fdt list /

# 查看 GPIO 状态
=> gpio status
=> gpio set <pin>
=> gpio clear <pin>

# 查看 MMC 信息
=> mmc list
=> mmc dev 0
=> mmc info

# 查看环境变量
=> printenv
=> setenv <var> <value>
=> saveenv

# 查看内存
=> md.l <address> <count>
=> mw.l <address> <value>

# 查看设备
=> dm tree
=> dm uclass
```

#### 编译时调试

```bash
# 启用调试输出
CONFIG_LOG=y
CONFIG_LOG_MAX_LEVEL=7
CONFIG_LOG_DEFAULT_LEVEL=7

# 在代码中使用
debug("MMC: sample clock not found\n");
log_debug("GPIO probe: bank=%d\n", priv->bank);
```

---

## 第六部分：常见问题

### 6.1 驱动不匹配

**问题**：设备树节点存在，但驱动未加载

**可能原因**：
1. `compatible` 字符串不匹配
2. 驱动未编译进 U-Boot
3. `status = "disabled"`

**解决方法**：

```bash
# 1. 检查 compatible 匹配
# 设备树：
compatible = "rockchip,gpio-bank";

# 驱动匹配表：
static const struct udevice_id rockchip_gpio_ids[] = {
    { .compatible = "rockchip,gpio-bank" },  // ← 必须完全匹配
    { }
};

# 2. 检查驱动是否编译
$ grep CONFIG_DM_GPIO sysdrv/source/uboot/u-boot/.config
CONFIG_DM_GPIO=y  # ← 必须为 y

# 3. 检查设备树状态
&gpio0 {
    status = "okay";  // ← 必须为 "okay"
};
```

### 6.2 寄存器访问错误

**问题**：驱动加载但功能异常，寄存器读写错误

**可能原因**：
1. 寄存器地址错误
2. 时钟未使能
3. 寄存器布局版本不匹配（如 GPIO V1 vs V2）

**解决方法**：

```bash
# 1. 检查寄存器地址
# 设备树：
reg = <0xff380000 0x100>;

# 驱动：
priv->regs = dev_read_addr_ptr(dev);
printf("GPIO regs: %p\n", priv->regs);  // 调试输出

# 2. 检查时钟
# 设备树：
clocks = <&cru PCLK_GPIO0>;

# 驱动：
ret = clk_get_by_index(dev, 0, &clk);
if (ret < 0) {
    printf("Failed to get clock: %d\n", ret);
    return ret;
}
clk_enable(&clk);

# 3. 检查寄存器版本
$ grep CONFIG_ROCKCHIP_GPIO_V2 sysdrv/source/uboot/u-boot/.config
CONFIG_ROCKCHIP_GPIO_V2=y  # ← RV1106 必须为 y
```

### 6.3 时钟/复位问题

**问题**：设备初始化失败，超时或无响应

**可能原因**：
1. 时钟未使能或频率错误
2. 设备未复位
3. 时钟源配置错误

**解决方法**：

```c
// 1. 检查时钟使能
ret = clk_get_by_name(dev, "ciu", &priv->clk);
if (ret < 0) {
    debug("Failed to get clock\n");
    return ret;
}

ret = clk_enable(&priv->clk);
if (ret < 0) {
    debug("Failed to enable clock\n");
    return ret;
}

// 2. 检查时钟频率
ulong rate = clk_get_rate(&priv->clk);
debug("Clock rate: %lu Hz\n", rate);

// 3. 复位设备（如果需要）
ret = reset_get_by_index(dev, 0, &priv->reset);
if (!ret) {
    reset_assert(&priv->reset);
    udelay(10);
    reset_deassert(&priv->reset);
}
```

### 6.4 如何添加新设备支持

**步骤清单**：

1. **定义寄存器结构体**（如果是新类型设备）
   ```c
   // arch/arm/include/asm/arch-rockchip/new_device.h
   struct new_device_regs {
       u32 ctrl;
       u32 status;
       // ...
   };
   ```

2. **编写驱动代码**
   ```c
   // drivers/new_device/rk_new_device.c
   static int rk_new_device_probe(struct udevice *dev) {
       // 初始化代码
   }

   U_BOOT_DRIVER(rk_new_device) = {
       .name = "rk_new_device",
       .id = UCLASS_NEW_DEVICE,
       .of_match = rk_new_device_ids,
       .probe = rk_new_device_probe,
   };
   ```

3. **添加设备树节点**
   ```dts
   // arch/arm/dts/rv1106.dtsi
   new_device: new_device@ff500000 {
       compatible = "rockchip,rv1106-new-device";
       reg = <0xff500000 0x1000>;
       clocks = <&cru CLK_NEW_DEVICE>;
       status = "disabled";
   };
   ```

4. **配置编译选项**
   ```makefile
   # sysdrv/source/uboot/u-boot/.config
   CONFIG_NEW_DEVICE=y
   CONFIG_DM_NEW_DEVICE=y
   ```

5. **测试验证**
   ```bash
   # 编译
   ./build.sh uboot

   # 启动后检查
   => dm tree
   => dm uclass
   ```

**注意事项**：
- 遵循 U-Boot 驱动模型规范
- 使用设备树描述硬件，避免硬编码
- 添加适当的错误处理和调试输出
- 参考现有驱动的实现

---

## 第七部分：总结

### 7.1 核心概念回顾

**三句话总结**：

1. **驱动模型**：驱动代码在 `drivers/` 目录，通过 `U_BOOT_DRIVER()` 注册，使用 `compatible` 属性匹配设备树节点。

2. **设备树**：提供完整的硬件描述（寄存器地址、时钟、中断、硬件参数），驱动通过 `dev_read_*()` API 读取配置。

3. **硬件差异**：通过条件编译（`#ifdef CONFIG_*`）、设备树属性和 compatible 链机制处理不同 SoC 的差异。

### 7.2 与其他文档的关联

- **文档 5**（`5_uboot_device_init_and_build_cn.md`）：介绍了 U-Boot Proper 的初始化序列，本文档详细解释了 `initr_dm()` 之后的驱动初始化过程。

- **启动日志**（`uart_StartupLog.log`）：本文档中的所有案例都可以在启动日志中找到对应的输出，帮助理解实际的初始化流程。

### 7.3 参考资料

**U-Boot 官方文档**：
- Driver Model: https://u-boot.readthedocs.io/en/latest/develop/driver-model/index.html
- Device Tree: https://u-boot.readthedocs.io/en/latest/develop/devicetree/index.html

**Linux 设备树规范**：
- Device Tree Specification: https://www.devicetree.org/specifications/

**Rockchip 技术文档**：
- RV1106 TRM（Technical Reference Manual）
- Rockchip U-Boot 开发指南

**本 SDK 相关文档**：
- `README_CN.md`：SDK 使用说明
- `CLAUDE.md`：项目概述
- `.claude/docs_BuildSDK/`：其他构建相关文档

---

## 附录：完整的驱动初始化流程图

```
┌─────────────────────────────────────────────────────────────┐
│ U-Boot SPL 加载 U-Boot Proper 到内存                        │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ board_init_r() - U-Boot Proper 入口                         │
│ - 设置栈指针                                                │
│ - 初始化全局数据                                            │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 遍历 init_sequence_r[] 数组                                 │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ initr_dm() - 初始化驱动模型                                 │
│   ↓                                                         │
│ dm_init_and_scan()                                          │
│   ↓                                                         │
│ dm_scan_fdt() - 扫描设备树                                  │
│   ↓                                                         │
│ 对每个设备树节点：                                          │
│   1. 读取 compatible 属性                                   │
│   2. 查找匹配的驱动（遍历所有 U_BOOT_DRIVER）               │
│   3. 创建设备实例（udevice）                                │
│   4. 调用驱动的 probe() 函数                                │
│      ├─> GPIO 驱动 probe                                    │
│      ├─> MMC 驱动 probe                                     │
│      ├─> UART 驱动 probe                                    │
│      └─> 其他驱动 probe                                     │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 所有设备初始化完成                                          │
│ - GPIO 可用                                                 │
│ - MMC 可用                                                  │
│ - UART 可用                                                 │
│ - 网络可用                                                  │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 继续执行 init_sequence_r[] 中的其他初始化函数              │
│ - initr_serial()                                            │
│ - initr_env()                                               │
│ - initr_mmc()                                               │
│ - initr_net()                                               │
│ - ...                                                       │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ run_main_loop() - 进入主循环                                │
│ - 加载内核                                                  │
│ - 启动 Linux                                                │
└─────────────────────────────────────────────────────────────┘
```

---

**文档完成！**

本文档详细介绍了 U-Boot 驱动模型与设备树机制，通过 GPIO、MMC、UART 三个完整的实战案例，展示了驱动代码、设备树配置、硬件差异处理如何协同工作。希望这份文档能帮助你深入理解 Luckfox Pico SDK 的 U-Boot 驱动架构。
