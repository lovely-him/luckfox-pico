# RV1106 RGB 显示管线与背光控制

> 基于 Luckfox Pico Ultra（RV1106G3）+ 720×720 RGB LCD 的实际调试经验整理。
> 设备型号：`Luckfox Pico Ultra`，DTS：`rv1106g-luckfox-pico-ultra.dts`

---

## 第 1 章：显示管线概览

### 1.1 两条独立的管线

RGB LCD 显示涉及两条**完全独立**的控制链路，理解这一点是排查问题的基础：

```
图像管线（内容）：
  应用程序 / modetest
       ↓
  DRM/KMS 框架（/dev/dri/card0）
       ↓
  VOP（视频输出处理器）
       ↓
  RGB 并行接口（18 根数据线 + CLK/hsync/vsync/den）
       ↓
  LCD 屏幕面板

背光管线（亮度）：
  sysfs /sys/class/backlight/backlight/
       ↓
  pwm-backlight 驱动
       ↓
  PWM1 硬件（引脚 pwm1m2）
       ↓
  LCD 背光 LED 驱动电路
```

**关键结论**：两条管线互不感知。图像管线工作正常时，背光可以是关闭的；背光打开但图像管线没有推送内容时，屏幕显示黑色（或上次帧缓冲的内容）。

### 1.2 为什么 `modetest` 执行后屏幕无反应？

`modetest -M rockchip -s 70@66:720x720` 只操作图像管线，对背光没有任何作用。

系统启动后背光默认处于 `bl_power=4`（强制关断）状态，即使 DRM 已经在向屏幕发送像素数据，人眼也看不到任何内容。

**必须先手动打开背光**，`modetest` 才会产生可见效果：

```bash
echo 0 > /sys/class/backlight/backlight/bl_power   # 先开背光
modetest -M rockchip -s 70@66:720x720 -v           # 再测试图像
```

### 1.3 本项目显示参数速查

| 参数 | 值 |
|------|----|
| 屏幕分辨率 | 720 × 720 |
| 刷新率 | ~49 Hz（实测 ~51 Hz） |
| 接口格式 | RGB666（18-bit） |
| DRM connector ID | 70（card0-DPI-1） |
| DRM CRTC ID | 66 |
| 背光 sysfs 路径 | `/sys/class/backlight/backlight/` |
| 背光亮度范围 | 0 ～ 255 |

---

## 第 2 章：DTB 关键节点原理

本章说明 DTS 中各显示相关节点的职责与内部工作机制，帮助理解修改配置时每个节点影响什么。

### 2.1 图像管线节点

**`&vop`**（Video Output Processor）

RV1106 的视频输出硬件模块，负责从内存读取帧缓冲数据、合成 plane、输出像素流。DRM 框架通过它操控 CRTC。必须 `status = "okay"` 图像管线才能工作。

**`&rgb_in_vop`**

VOP 内部的 RGB 输出端口使能节点。RV1106 的 VOP 可连接多种输出接口（RGB/MIPI 等），此节点激活其中的 RGB 路径。

**`&rgb`**

RGB 并行接口控制器节点，负责将 VOP 的像素数据通过 pinmux 路由到物理引脚。引用 `lcd_pins` 来配置 18 根数据线（D0–D17）加上 CLK、hsync、vsync、DEN 共 22 根引脚的复用功能。

**`panel`**

描述 LCD 面板的物理参数，使用 `simple-panel` 驱动（见文档 1 中的分类，RGB 接口不需要初始化序列，因此用 `simple-panel` 即可）。核心内容是 `display-timings`：

```dts
timing0: timing0 {
    clock-frequency = <30000000>;  // 像素时钟 30MHz
    hactive = <720>;               // 水平有效像素
    vactive = <720>;               // 垂直有效像素
    hback-porch  = <44>;
    hfront-porch = <46>;
    vback-porch  = <18>;
    vfront-porch = <16>;
    hsync-len = <2>;
    vsync-len = <2>;
    // 极性全部为低电平有效
    hsync-active = <0>;
    vsync-active = <0>;
    de-active    = <0>;
    pixelclk-active = <0>;
};
```

timing 参数直接决定屏幕刷新率，不正确会导致花屏或无信号。`bus-format = <MEDIA_BUS_FMT_RGB666_1X18>` 说明数据线宽度（18-bit RGB666）。

### 2.2 背光节点

**`backlight`（pwm-backlight）**

将 PWM 占空比映射为背光亮度的中间层驱动。`pwms = <&pwm1 0 100000 50000>` 含义：

| 字段 | 值 | 说明 |
|------|-----|------|
| `&pwm1` | - | 使用 PWM1 控制器 |
| `0` | channel | 通道 0 |
| `100000` | period_ns | 周期 100μs，即 10kHz |
| `50000` | duty_ns | 初始占空比 50%（但受 bl_power 管控） |

`brightness-levels` 数组将用户空间的 0～255 线性值映射到底层 PWM 占空比。

**`&pwm1`**

PWM1 硬件控制器，通过 `pinctrl-0 = <&pwm1m2_pins>` 将 PWM 信号路由到具体的物理引脚（连接至 LCD 背光驱动电路）。

### 2.3 `&route_rgb`——仅用于开机 Logo

`route_rgb` 是 **Rockchip DRM 框架的 SoC 级节点**，定义在 `rv1106.dtsi` 中，与 Luckfox 无关。其唯一职责是让 U-Boot 和内核启动阶段显示 logo 图像。

```dts
route_rgb: route-rgb {
    status = "disabled";         // IPC 场景下关闭，节省启动时间
    logo,uboot   = "logo.bmp";   // U-Boot 阶段显示的图片文件名
    logo,kernel  = "logo_kernel.bmp"; // 内核阶段显示的图片文件名
    logo,mode    = "center";     // 居中显示
    connect      = <&vop_out_rgb>;
};
```

**`route_rgb` 与运行时显示完全无关**。无论它是 `okay` 还是 `disabled`，应用程序使用 DRM/framebuffer 驱动屏幕的行为都不受影响。

启用 logo 需要将对应 BMP 文件打包进 `resource.img`（FIT 镜像的 resource 分区），并把 `drm_logo` reserved-memory 的 `reg` 分配足够大小（如 2MB）。这是额外工程，若不需要开机 logo 保持 `disabled` 即可。

### 2.4 节点依赖关系总结

```
panel
  └─ port → panel_in_rgb
              ↑
           rgb_out_panel ← &rgb（激活 RGB 控制器，绑定 lcd_pins）
                               ↑
                         &rgb_in_vop（激活 VOP→RGB 路径）
                               ↑
                             &vop（VOP 主模块）

backlight ← &pwm1（PWM 硬件）← pwm1m2_pins（物理引脚）
```

六个节点全部 `status = "okay"` 才能完整工作，缺少任何一个会导致 DRM probe 失败或背光无响应。

---

## 第 3 章：背光控制接口（sysfs）

### 3.1 两个控制节点的区别

背光 sysfs 目录 `/sys/class/backlight/backlight/` 下有两个关键节点，它们的作用层次不同：

| 节点 | 作用层次 | 值域 | 类比 |
|------|---------|------|------|
| `bl_power` | **电源开关** | 0=开，4=关断 | 电闸 |
| `brightness` | **亮度调节** | 0 ～ 255 | 调光旋钮 |

两者是**串联关系**：`bl_power=4` 时无论 `brightness` 是多少，背光都不亮。只有 `bl_power=0` 时，`brightness` 才生效。

### 3.2 `bl_power` 的值含义

值来自 Linux 内核 `FB_BLANK_*` 常量：

| 值 | 常量名 | 含义 |
|----|--------|------|
| 0 | `FB_BLANK_UNBLANK` | 正常工作，背光点亮 |
| 1 | `FB_BLANK_NORMAL` | 视频信号关闭但背光仍开 |
| 2 | `FB_BLANK_VSYNC_SUSPEND` | 省电状态 |
| 3 | `FB_BLANK_HSYNC_SUSPEND` | 省电状态 |
| 4 | `FB_BLANK_POWERDOWN` | 完全断电，背光熄灭 |

**为什么启动后默认是 4？**

`pwm-backlight` 驱动在 probe 时（即 `pwm_bl.ko` 加载时），若没有其他组件主动请求背光开启，背光状态默认为 `FB_BLANK_POWERDOWN`。

官方镜像（Ultra W）启动时 `route_rgb = okay`，DRM 框架在初始化时会调用 `drm_fb_helper_initial_config` 流程，其中包含对 connector 的背光激活操作，因此官方镜像开机后背光自动点亮。

编译版 `route_rgb = disabled`，DRM 不走 logo 初始化路径，背光保持驱动加载时的默认关闭状态。

### 3.3 常用操作

```bash
# 打开背光（使用屏幕前必须执行）
echo 0 > /sys/class/backlight/backlight/bl_power

# 关闭背光（节能，DRM 继续输出信号但不可见）
echo 4 > /sys/class/backlight/backlight/bl_power

# 设置亮度为 50%（bl_power=0 时才有效）
echo 128 > /sys/class/backlight/backlight/brightness

# 最大亮度
echo 255 > /sys/class/backlight/backlight/brightness

# 查看当前实际亮度（驱动输出的真实值，排除 bl_power 影响）
cat /sys/class/backlight/backlight/actual_brightness

# 查看背光状态（0=正常开，4=关断）
cat /sys/class/backlight/backlight/bl_power
```

---

## 第 4 章：显示验证流程与应用程序接管

### 4.1 用 modetest 验证图像管线

`modetest` 是 libdrm 提供的测试工具，直接操作 DRM KMS 接口，用于在没有应用程序的情况下验证显示管线是否通路正常。

**第一步：查询 DRM 资源 ID**

```bash
modetest -M rockchip
```

输出中关注三类 ID：

```
Encoders:
  id=69  type=DPI  crtc=66          ← 编码器，固定绑定 CRTC

Connectors:
  id=70  status=connected  name=DPI-1  ← connector ID（物理接口）

CRTCs:
  id=66  fb=71  size=(720x720)        ← CRTC ID（扫描引擎）
```

**第二步：推送测试图像**

```bash
# 格式：-s <connector_id>@<crtc_id>:<分辨率>
# -v 参数让 modetest 自己生成渐变色测试画面并持续刷新
modetest -M rockchip -s 70@66:720x720 -v
```

执行后 modetest 独占 DRM，终止（Ctrl+C）后屏幕回到 framebuffer 状态。

> **注意**：必须先执行 `echo 0 > /sys/class/backlight/backlight/bl_power` 开背光，否则输出存在但不可见。

### 4.2 应用程序如何接管屏幕

#### 方式一：通过 Framebuffer（/dev/fb0）

最简单的方式，直接写入像素数据：

```bash
# 快速测试：将随机噪点写满屏幕
cat /dev/urandom > /dev/fb0

# 清屏（黑色）
dd if=/dev/zero of=/dev/fb0 bs=4096
```

framebuffer 格式为 ARGB8888（32bpp，720×720），应用程序 `mmap /dev/fb0` 后直接写入像素即可，无需了解 DRM。

#### 方式二：通过 DRM/KMS（libdrm）

应用程序（如 Qt、RKIPC 的 RKMedia 视频输出模块）使用 libdrm 直接操控 DRM，获得低延迟和硬件 plane 合成能力。这是生产环境推荐方式。

DRM 的使用流程（以背光控制为例，RKIPC 的实现思路）：

1. `open("/dev/dri/card0")` 打开 DRM 设备
2. `drmModeGetResources()` 获取 connector/CRTC/encoder ID
3. `drmModeSetCrtc()` 配置显示模式并绑定 framebuffer
4. 应用程序在上述步骤完成后**自行负责背光开启**，通常通过写 sysfs 实现

#### 方式三：RKIPC 接管（RkLunch.sh）

`/oem/usr/bin/RkLunch.sh` 是 OEM 分区的启动脚本，负责调起 `rkipc` 进程。rkipc 内部通过 RKMedia 框架创建 VO（Video Output）通道，底层使用 DRM 接管屏幕。

rkipc 启动后会：
1. 通过 RKMedia VO 模块将视频流推送到 DRM plane
2. 通过 `luckfox-config` 脚本（`/usr/bin/luckfox-config`）配置 USB 网络，其中会调用背光相关的初始化

> 当前编译镜像 OEM 分区缺少 `rkipc.ini`，RkLunch.sh 提前退出（`Error: not found rkipc.ini`），因此 rkipc 未启动，屏幕没有被接管，也没有触发背光开启。

### 4.3 临时开机自动点亮背光

在 rkipc 未接管屏幕的情况下，可在 `S25backlight` 中补充背光点亮逻辑：

文件位置：`project/cfg/BoardConfig_IPC/overlay/overlay-luckfox-buildroot-rgb/etc/init.d/S25backlight`

```sh
start(){
    if [ -f "/oem/usr/ko/pwm_bl.ko" ]; then
        sleep 1
        insmod /oem/usr/ko/pwm_bl.ko
        # 加载后主动点亮背光
        echo 0 > /sys/class/backlight/backlight/bl_power
    fi
}
```

此修改需重新打包 OEM 镜像后烧录生效。

---

## 附录：配置文件位置速查

| 文件 / 目录 | 路径 | 作用 |
|-------------|------|------|
| BoardConfig | `project/cfg/BoardConfig_IPC/BoardConfig-EMMC-Buildroot-RV1106_Luckfox_Pico_Ultra-IPC.mk` | 指定 DTS、defconfig、overlay 等编译参数 |
| 主 DTS | `sysdrv/source/kernel/arch/arm/boot/dts/rv1106g-luckfox-pico-ultra.dts` | 板级顶层 DTS，指定 model 名称，包含 ipc.dtsi |
| 显示+背光 DTSI | `sysdrv/source/kernel/arch/arm/boot/dts/rv1106-luckfox-pico-ultra-ipc.dtsi` | panel/backlight/rgb/route_rgb 节点定义 |
| SoC pinctrl | `sysdrv/source/kernel/arch/arm/boot/dts/rv1106-pinctrl.dtsi` | `lcd_pins`（18 位 RGB + 控制线）定义 |
| DTS 软链接 | `config/dts_config` → 上述主 DTS | build.sh 通过此链接引用当前 DTS |
| RGB overlay | `project/cfg/BoardConfig_IPC/overlay/overlay-luckfox-buildroot-rgb/` | 背光 ko 加载脚本 `S25backlight`、分辨率切换工具 |
| U-Boot RGB config | `sysdrv/source/uboot/u-boot/configs/rv1106-luckfox-rgb-reset.config` | 启用 `CONFIG_LUCKFOX_EXECUTE_CMD`，U-Boot 启动时拉高 LCD MCU 复位引脚（`gpio set 1 1`） |

