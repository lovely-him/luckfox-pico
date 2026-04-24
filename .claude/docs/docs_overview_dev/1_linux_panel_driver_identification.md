# Linux 屏幕驱动类型识别笔记

> 写给自己的嵌入式 Linux 入门笔记，基于 Luckfox Pico Ultra 和 RK3326 设备的实际 DTS 案例整理。

---

## 第 1 章：核心判断逻辑

**一句话结论：屏幕用什么驱动，取决于它用什么接口连接到芯片。**

接口决定了屏幕是否需要"初始化"才能工作：
- 有些接口（RGB/LVDS）只需要知道时序参数，芯片直接往线上丢像素数据即可
- 有些接口（MIPI DSI/SPI）需要先向屏幕控制器发送一串寄存器配置命令，屏幕才能正常显示

这个区别直接决定了驱动类型。

### 接口 → 驱动类型 速查表

| 接口类型 | 代表驱动 | 需要初始化序列 | 复杂度 |
|---|---|---|---|
| RGB 并行 | `simple-panel` | 否 | 低 |
| LVDS | `simple-panel` | 否 | 低 |
| MIPI DSI | 专用驱动（如 `sitronix,st7703`）| **是** | 高 |
| SPI/I2C 控制 | 专用驱动 | **是** | 高 |

> 注意：MIPI DSI 接口的屏幕也可以写成 `simple-panel-dsi`，但只有在不需要自定义初始化序列时才能用；实际项目中大多数 DSI 屏都需要专用驱动。

---

## 第 2 章：接口类型详解

### 2.1 RGB 并行接口

**工作原理：**
芯片通过多根数据线（通常 18 根或 24 根）直接将每个像素的颜色值并行传给屏幕。屏幕内部没有控制器，只有驱动电路，上电后直接接收并显示像素数据。

**类比：** 就像一个透明的画布，芯片直接在上面"涂色"，不需要跟画布"打招呼"。

**特点：**
- 引脚多（18~24 根数据线 + 控制线）
- 速度受引脚数限制，通常用于中小尺寸低分辨率屏（如 720x720）
- 不需要任何初始化 → 使用 `simple-panel` 驱动
- DTS 中使用 `MEDIA_BUS_FMT_RGB666_1X18` 或 `MEDIA_BUS_FMT_RGB888_1X24` 表示格式

**典型 DTS 特征：**
```dts
panel: panel {
    compatible = "simple-panel";        // 通用驱动
    bus-format = <MEDIA_BUS_FMT_RGB666_1X18>;  // RGB666 格式
    // 只需要时序参数，无初始化序列
    display-timings { ... };
    port {
        remote-endpoint = <&rgb_out_panel>;  // 连接到芯片的 RGB 输出口
    };
};
```

---

### 2.2 MIPI DSI 接口

**工作原理：**
MIPI DSI（Display Serial Interface）是一种高速串行接口，数据通过 1~4 条差分数据通道（lane）传输。屏幕内部有一个**显示控制器 IC**（如 ST7703、ILI9881C），芯片需要先通过 DSI 通道发送一系列寄存器配置命令来初始化这个控制器，屏幕才能正常工作。

**类比：** 就像打印机，使用前需要先发送配置命令告诉它"用什么模式、什么分辨率打印"，之后才能传数据。

**特点：**
- 引脚少（1~4 对差分线），适合高分辨率大屏
- 必须有初始化序列 → 需要专用驱动
- 每款屏幕控制器的初始化命令不同，驱动不通用
- `compatible` 格式固定为 `"厂商,型号"`（如 `"sitronix,st7703"`）

**典型 DTS 特征：**
```dts
dsi@ff450000 {                              // 芯片的 DSI 控制器节点
    compatible = "rockchip,px30-mipi-dsi";
    ...
    panel@0 {                               // 屏幕挂在 DSI 控制器下面
        compatible = "sitronix,st7703", "simple-panel-dsi";  // 专用驱动
        dsi,lanes = <0x04>;                 // 4 lane 高速通道
        panel-init-sequence = [...];        // 初始化寄存器命令序列
        display-timings { ... };
    };
};
```

**`panel-init-sequence` 是什么：**
这是一串十六进制字节，格式为 `[命令类型 延时 长度 数据...]`，每条对应一次向屏幕控制器写寄存器的操作。不同屏幕厂商格式不同，通常由屏幕厂商提供。例如：
```
panel-init-sequence = [15 00 02 80 ac  // 写寄存器 0x80 = 0xac
                       15 00 02 81 b8  // 写寄存器 0x81 = 0xb8
                       ...];
```

---

## 第 3 章：DTS 识别三要素

拿到一个陌生的 DTS 文件，按以下三步顺序检查即可快速判断屏幕驱动类型。

### 要素一：`compatible` 字段格式

这是最直接的判断依据。

| compatible 值 | 含义 |
|---|---|
| `"simple-panel"` | 通用驱动，RGB/LVDS 接口 |
| `"simple-panel-dsi"` | 通用 DSI 驱动，DSI 接口但无自定义初始化 |
| `"厂商,型号"` | 专用驱动，需要内核有对应的驱动文件 |
| `"厂商,型号", "simple-panel-dsi"` | 专用驱动（双 compatible，内核优先匹配前者） |

---

### 要素二：节点挂载位置

找到 `panel` 节点，看它的**父节点**是谁：

```
根节点 / 的直接子节点
    → RGB/LVDS 接口 → simple-panel

dsi@xxxxxxxx { 的子节点
    → MIPI DSI 接口 → 专用驱动
```

**查找方法：** 在 DTS 中搜索 `panel`，然后往上看一层缩进是什么节点。

---

### 要素三：是否含初始化序列

搜索以下关键字，有任意一个出现即为专用驱动：

```
panel-init-sequence
panel-exit-sequence
init-cmds
display-on-cmds
```

`simple-panel` 不需要也不支持这些字段，只需要 `display-timings`（时序参数）。

---

### 三要素综合判断流程

```
拿到 DTS
    ↓
搜索 compatible = "..."
    ↓
是 "simple-panel" 或 "simple-panel-dsi"？
    ├─ 是 → 通用驱动，确认
    └─ 否（含厂商名）→ 专用驱动，确认
              ↓（可选验证）
         找父节点 + 搜索 init-sequence 进一步确认
```

---

## 第 4 章：实例对照

以下两个实际案例完整演示三要素判断推导过程。

---

### 案例 A：Luckfox Pico Ultra — LF40-720720-ARK 屏幕

**来源文件：** `sysdrv/source/kernel/arch/arm/boot/dts/rv1106-luckfox-pico-ultra-ipc.dtsi`

**关键 DTS 片段：**
```dts
/ {
    panel: panel {
        compatible = "simple-panel";
        bus-format = <MEDIA_BUS_FMT_RGB666_1X18>;
        width-mm = <85>;
        height-mm = <85>;

        display-timings {
            timing0: timing0 {
                clock-frequency = <30000000>;
                hactive = <720>;
                vactive = <720>;
                hback-porch = <44>;
                hfront-porch = <46>;
                ...
            };
        };

        port {
            panel_in_rgb: endpoint {
                remote-endpoint = <&rgb_out_panel>;
            };
        };
    };
};

&rgb {
    status = "okay";
    pinctrl-0 = <&lcd_pins>;
    ports {
        rgb_out: port@1 {
            rgb_out_panel: endpoint@0 {
                remote-endpoint = <&panel_in_rgb>;
            };
        };
    };
};
```

**三要素推导：**

| 要素 | 检查结果 | 结论 |
|---|---|---|
| ① compatible | `"simple-panel"` | 通用驱动 ✅ |
| ② 父节点 | 根节点 `/` 的直接子节点 | RGB 接口 ✅ |
| ③ 初始化序列 | 无 `panel-init-sequence` | 不需要初始化 ✅ |

**最终结论：RGB 并行接口，`simple-panel` 通用驱动，只需 DTS 时序参数即可工作。**

---

### 案例 B：RK3326 设备 — ST7703 屏幕

**来源文件：** `runtime_from_sys_firmware_fdt.dts`（从运行中设备 `/sys/firmware/fdt` 导出）

**关键 DTS 片段：**
```dts
dsi@ff450000 {
    compatible = "rockchip,px30-mipi-dsi";
    ...
    panel@0 {
        compatible = "sitronix,st7703", "simple-panel-dsi";
        dsi,flags = <0xa03>;
        dsi,format = <0x00>;
        dsi,lanes = <0x04>;
        prepare-delay-ms = <0x02>;
        reset-delay-ms = <0x01>;

        panel-init-sequence = [
            15 00 02 80 ac
            15 00 02 81 b8
            15 00 02 82 09
            ...
        ];

        display-timings {
            timing0 {
                clock-frequency = <0x2faf080>;  // 50MHz
                hactive = <0x400>;              // 1024
                vactive = <0x258>;              // 600
                ...
            };
        };
    };
};
```

**三要素推导：**

| 要素 | 检查结果 | 结论 |
|---|---|---|
| ① compatible | `"sitronix,st7703"` — 含厂商名 | 专用驱动 ✅ |
| ② 父节点 | `dsi@ff450000` 的子节点 | MIPI DSI 接口 ✅ |
| ③ 初始化序列 | 有 `panel-init-sequence` | 须发送初始化命令 ✅ |

**最终结论：MIPI DSI 接口，4 lane，需要 `st7703` 专用驱动，内核必须有 `drivers/gpu/drm/panel/panel-sitronix-st7703.c`。**

---

### 两案例对比总结

| | 案例 A（Luckfox） | 案例 B（RK3326） |
|---|---|---|
| 屏幕型号 | LF40-720720-ARK | ST7703 控制器屏 |
| 接口 | RGB 并行 | MIPI DSI 4-lane |
| 分辨率 | 720×720 | 1024×600 |
| compatible | `simple-panel` | `sitronix,st7703` |
| 父节点 | 根节点 | `dsi@ff450000` |
| 初始化序列 | 无 | 有 |
| 驱动类型 | **通用** | **专用** |
| 移植难度 | 低（改时序参数即可）| 高（需要对应驱动文件）|
