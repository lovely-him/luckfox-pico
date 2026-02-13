# 设备树（Device Tree）在代码中的使用流程

## 你的问题

你看到启动日志中打印了：
```
Model: Rockchip RV1106 EVB Board
```

你想知道：**设备树文件 `*.dts*` 是如何在代码中被使用的？**

## 简短回答

是的，你的理解完全正确！设备树文件经过以下流程：

```
.dts (源文件) → dtc 编译器 → .dtb (二进制) → 加载到内存 → libfdt 解析 → C 代码读取并打印
```

## 完整流程详解

### 1. 设备树源文件（.dts）

**U-Boot 的设备树**：
```c
// 文件：sysdrv/source/uboot/u-boot/arch/arm/dts/rv1106-luckfox.dts
/ {
	model = "Rockchip RV1106 EVB2 Board";  // ← 这就是你看到的字符串！
	compatible = "rockchip,rv1106-evb2", "rockchip,rv1106";

	chosen {
		stdout-path = &uart2;
		u-boot,spl-boot-order = &sdmmc, &spi_nand, &emmc;
	};
};
```

**Linux 内核的设备树**：
```c
// 文件：sysdrv/source/kernel/arch/arm/boot/dts/rv1106g-luckfox-pico-ultra-w.dts
/ {
	model = "Luckfox Pico Ultra W";  // ← 内核启动后会打印这个
	compatible = "rockchip,rv1103g-38x38-ipc-v10", "rockchip,rv1106g3";
};
```

### 2. 编译：.dts → .dtb

**设备树编译器（dtc）** 将人类可读的 `.dts` 文件编译成二进制的 `.dtb` 文件：

```bash
# U-Boot 编译时自动执行
dtc -I dts -O dtb -o rv1106-luckfox.dtb rv1106-luckfox.dts

# 内核编译时自动执行
dtc -I dts -O dtb -o rv1106g-luckfox-pico-ultra-w.dtb rv1106g-luckfox-pico-ultra-w.dts
```

**编译过程**：
- **输入**：`.dts` 文本文件
- **输出**：`.dtb` 二进制文件（Flattened Device Tree Blob）
- **位置**：
  - U-Boot DTB：打包进 `uboot.img`
  - 内核 DTB：打包进 `boot.img`（作为 FIT 镜像的一部分）

### 3. 加载到内存

**U-Boot SPL 阶段**（你在日志第 28-29 行看到的）：
```
## Checking uboot 0x00200000 (lzma @0x00400000) ... sha256(2149fbc6d0...) + OK
## Checking fdt 0x00261190 ... sha256(9f596c5683...) + OK
```

- U-Boot 的 DTB 被加载到地址 `0x00261190`
- 内核的 DTB 稍后被加载到地址 `0x00c00000`

### 4. C 代码读取设备树

**关键代码**：`sysdrv/source/uboot/u-boot/common/board_info.c`

```c
#include <common.h>
#include <linux/libfdt.h>  // ← libfdt 库，用于解析设备树

int __weak show_board_info(void)
{
#ifdef CONFIG_OF_CONTROL
	DECLARE_GLOBAL_DATA_PTR;  // 声明全局数据指针
	const char *model;

	// ★ 关键函数：从设备树读取 "model" 属性
	model = fdt_getprop(gd->fdt_blob, 0, "model", NULL);
	//              ↑           ↑  ↑     ↑
	//              |           |  |     +-- 属性名称
	//              |           |  +-------- 节点偏移（0 = 根节点）
	//              |           +----------- 设备树二进制数据的指针
	//              +----------------------- libfdt 库函数

	if (model)
		printf("Model: %s\n", model);  // ← 这里打印！
#endif
	// ... 其他代码 ...
	return checkboard();
}
```

### 5. 函数调用链

**U-Boot 启动时的调用流程**：

```
board_init_r()                    // arch/arm/lib/board.c
  └─> stdio_init()
      └─> console_init_r()
          └─> show_board_info()   // common/board_info.c
              └─> fdt_getprop()   // lib/libfdt/fdt_ro.c
                  └─> 读取 DTB 二进制数据
                      └─> 返回 "Rockchip RV1106 EVB Board"
                          └─> printf("Model: %s\n", model)
```

## libfdt 库详解

### 什么是 libfdt？

**libfdt**（Flattened Device Tree Library）是一个用于解析设备树二进制格式的 C 库。

**核心函数**：

```c
// 1. 获取属性值
const void *fdt_getprop(const void *fdt, int nodeoffset,
                        const char *name, int *lenp);

// 2. 查找节点
int fdt_path_offset(const void *fdt, const char *path);

// 3. 获取字符串
const char *fdt_get_name(const void *fdt, int nodeoffset, int *lenp);

// 4. 遍历子节点
int fdt_first_subnode(const void *fdt, int offset);
int fdt_next_subnode(const void *fdt, int offset);
```

### 设备树在内存中的结构

```
┌─────────────────────────────────────────┐
│  FDT Header (设备树头部)                │
│  - magic: 0xd00dfeed                    │
│  - totalsize: 总大小                    │
│  - off_dt_struct: 结构块偏移            │
│  - off_dt_strings: 字符串块偏移         │
├─────────────────────────────────────────┤
│  Structure Block (结构块)               │
│  - FDT_BEGIN_NODE: "/"                  │
│  - FDT_PROP: "model"                    │
│    - len: 28                            │
│    - nameoff: 0x10                      │
│    - data: "Rockchip RV1106 EVB Board"  │
│  - FDT_PROP: "compatible"               │
│  - FDT_END_NODE                         │
├─────────────────────────────────────────┤
│  Strings Block (字符串块)               │
│  - 0x00: "model"                        │
│  - 0x10: "compatible"                   │
│  - 0x20: "chosen"                       │
└─────────────────────────────────────────┘
```

## 实际例子：读取 model 属性

### 步骤 1：设备树源文件

```dts
/ {
	model = "Rockchip RV1106 EVB Board";
	compatible = "rockchip,rv1106-evb2", "rockchip,rv1106";
};
```

### 步骤 2：编译成二进制

```bash
dtc -I dts -O dtb -o rv1106-luckfox.dtb rv1106-luckfox.dts
```

**二进制内容**（十六进制）：
```
d0 0d fe ed 00 00 0a 28 00 00 00 38 00 00 09 f0
00 00 00 28 00 00 00 11 00 00 00 10 00 00 00 00
...
52 6f 63 6b 63 68 69 70 20 52 56 31 31 30 36 20
45 56 42 20 42 6f 61 72 64 00
↑ "Rockchip RV1106 EVB Board" 的 ASCII 编码
```

### 步骤 3：加载到内存

U-Boot SPL 将 DTB 加载到 `0x00261190`：

```
内存地址 0x00261190:
d0 0d fe ed 00 00 0a 28 ...
```

### 步骤 4：C 代码读取

```c
// gd->fdt_blob 指向 0x00261190
const char *model = fdt_getprop(gd->fdt_blob, 0, "model", NULL);
// 返回指向字符串 "Rockchip RV1106 EVB Board" 的指针

printf("Model: %s\n", model);
// 输出：Model: Rockchip RV1106 EVB Board
```

## 为什么有两个设备树？

### U-Boot 设备树

- **文件**：`sysdrv/source/uboot/u-boot/arch/arm/dts/rv1106-luckfox.dts`
- **用途**：U-Boot 启动阶段使用
- **内容**：
  - 启动设备顺序（SD 卡、SPI NAND、eMMC）
  - 串口配置
  - 按键配置
- **打印**：`Model: Rockchip RV1106 EVB Board`

### Linux 内核设备树

- **文件**：`sysdrv/source/kernel/arch/arm/boot/dts/rv1106g-luckfox-pico-ultra-w.dts`
- **用途**：Linux 内核启动后使用
- **内容**：
  - 完整的硬件描述（GPIO、I2C、SPI、摄像头、显示屏等）
  - 驱动程序配置
  - 电源管理
- **打印**：`Model: Luckfox Pico Ultra W`（在内核启动日志中）

## 如何修改 model 字符串？

### 修改 U-Boot 的 model

1. **编辑设备树源文件**：
   ```bash
   vim sysdrv/source/uboot/u-boot/arch/arm/dts/rv1106-luckfox.dts
   ```

2. **修改 model 属性**：
   ```dts
   / {
   	model = "My Custom Board Name";  // ← 修改这里
   	compatible = "rockchip,rv1106-evb2", "rockchip,rv1106";
   };
   ```

3. **重新编译 U-Boot**：
   ```bash
   cd /home/him/him/luckfox-pico
   ./build.sh uboot
   ```

4. **烧录并启动**：
   ```bash
   ./build.sh firmware
   # 烧录 output/image/update.img
   ```

5. **查看结果**：
   ```
   Model: My Custom Board Name  // ← 新的输出
   ```

### 修改内核的 model

1. **编辑设备树源文件**：
   ```bash
   vim sysdrv/source/kernel/arch/arm/boot/dts/rv1106g-luckfox-pico-ultra-w.dts
   ```

2. **修改 model 属性**：
   ```dts
   / {
   	model = "My Custom Linux Board";  // ← 修改这里
   	compatible = "rockchip,rv1103g-38x38-ipc-v10", "rockchip,rv1106g3";
   };
   ```

3. **重新编译内核**：
   ```bash
   ./build.sh kernel
   ```

## 设备树的其他用途

### 1. 配置硬件参数

```dts
&uart2 {
	status = "okay";           // 启用 UART2
	pinctrl-names = "default";
	pinctrl-0 = <&uart2m0_xfer>;
};

&i2c0 {
	status = "okay";           // 启用 I2C0
	clock-frequency = <400000>; // 400 kHz
};
```

### 2. 定义 GPIO

```dts
&gpio1 {
	status = "okay";
};

led {
	compatible = "gpio-leds";
	led-0 {
		gpios = <&gpio1 RK_PA0 GPIO_ACTIVE_HIGH>;
		label = "status-led";
	};
};
```

### 3. 配置时钟

```dts
&cru {
	assigned-clocks = <&cru ARMCLK>;
	assigned-clock-rates = <816000000>;  // 816 MHz
};
```

## 调试技巧

### 1. 查看编译后的设备树

```bash
# 反编译 DTB 文件
dtc -I dtb -O dts -o output.dts input.dtb

# 查看 U-Boot 的设备树
dtc -I dtb -O dts -o uboot.dts output/image/uboot.dtb
```

### 2. 在运行时查看设备树

**在 U-Boot 命令行**：
```
=> fdt addr ${fdtcontroladdr}
=> fdt print /
```

**在 Linux 系统中**：
```bash
# 查看当前设备树
cat /proc/device-tree/model
# 输出：Luckfox Pico Ultra W

# 查看完整设备树
ls -la /proc/device-tree/
```

### 3. 添加调试信息

```c
// 在 board_info.c 中添加
printf("FDT blob address: %p\n", gd->fdt_blob);
printf("FDT size: %d bytes\n", fdt_totalsize(gd->fdt_blob));

const char *compatible = fdt_getprop(gd->fdt_blob, 0, "compatible", NULL);
printf("Compatible: %s\n", compatible);
```

## 总结

### 设备树使用流程

```
┌─────────────────────────────────────────────────────────────┐
│ 1. 编写设备树源文件 (.dts)                                  │
│    - 人类可读的文本格式                                     │
│    - 描述硬件配置                                           │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 2. 编译成二进制 (.dtb)                                      │
│    - 使用 dtc 编译器                                        │
│    - 生成 Flattened Device Tree Blob                        │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 3. 打包进固件镜像                                           │
│    - U-Boot DTB → uboot.img                                 │
│    - 内核 DTB → boot.img (FIT 镜像)                         │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 4. 加载到内存                                               │
│    - SPL 加载 U-Boot DTB 到 0x00261190                      │
│    - U-Boot 加载内核 DTB 到 0x00c00000                      │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 5. C 代码解析和使用                                         │
│    - 使用 libfdt 库                                         │
│    - fdt_getprop() 读取属性                                 │
│    - printf() 打印信息                                      │
└─────────────────────────────────────────────────────────────┘
```

### 关键函数

| 函数 | 用途 | 示例 |
|------|------|------|
| `fdt_getprop()` | 读取属性值 | `fdt_getprop(fdt, 0, "model", NULL)` |
| `fdt_path_offset()` | 查找节点 | `fdt_path_offset(fdt, "/chosen")` |
| `fdt_get_name()` | 获取节点名称 | `fdt_get_name(fdt, offset, NULL)` |
| `fdt_first_subnode()` | 获取第一个子节点 | `fdt_first_subnode(fdt, 0)` |
| `fdt_next_subnode()` | 获取下一个子节点 | `fdt_next_subnode(fdt, offset)` |

### 相关文件

| 文件 | 说明 |
|------|------|
| `sysdrv/source/uboot/u-boot/arch/arm/dts/rv1106-luckfox.dts` | U-Boot 设备树源文件 |
| `sysdrv/source/kernel/arch/arm/boot/dts/rv1106g-luckfox-pico-ultra-w.dts` | 内核设备树源文件 |
| `sysdrv/source/uboot/u-boot/common/board_info.c` | 打印 model 的代码 |
| `sysdrv/source/uboot/u-boot/lib/libfdt/` | libfdt 库源码 |
| `sysdrv/source/uboot/u-boot/include/linux/libfdt.h` | libfdt 头文件 |

## 参考资料

- **Device Tree Specification**: https://www.devicetree.org/
- **Linux Kernel Device Tree Documentation**: `Documentation/devicetree/`
- **U-Boot Device Tree Documentation**: `doc/README.fdt-control`
- **libfdt API Documentation**: `lib/libfdt/libfdt.h`
