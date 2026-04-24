# BUG: AIC8800DC WiFi 6 (HE) 高吞吐下 RX 路径停止响应

**状态**: 未解决（已用临时方案绕过）  
**设备**: Luckfox Pico Ultra W (RV1106G3)  
**芯片**: AIC8800DC (SDIO, 2.4GHz, 802.11ax WiFi 6)  
**驱动路径**: `sysdrv/drv_ko/wifi/aic8800dc/aic8800_fdrv/`  
**记录日期**: 2026-04-10  

---

## 问题描述

`he_on=1`（默认值，WiFi 6 启用）时，持续高吞吐量场景下 WiFi
数据平面会停止工作。`he_on=0` 则完全稳定。

---

## 实验数据

### 受控测试：iperf3 180 秒，宿主机→设备（设备 RX 方向）

| 时间段 | he_on=1 吞吐 | he_on=0 吞吐 |
|-------|-------------|-------------|
| 0–30s | 37.3 Mbps | 36.3 Mbps |
| 30–60s | 16.8 Mbps ↘（TCP Cwnd 塌缩至 1.41 KB） | 36.5 Mbps |
| 60–90s | **0 Mbps** | 37.5 Mbps |
| 90–150s | **0 Mbps** | ~35 Mbps |
| 150–180s | **0 Mbps** | 36.2 Mbps |
| 合计 | ~193 MB（前 30s 有效） | **774 MB 全程稳定** |

### ping 对比（iperf3 运行中）

- `he_on=1` 失败期间：`ping -I wlo1 192.168.63.115` → **100% 丢包**（ICMP 层面）
- `he_on=0` 全程：**0% 丢包**，延迟 2–30 ms

### iw link 速率指标

```
# he_on=1 稳态：
rx bitrate: 1.0 MBit/s          ← 仅 Beacon 速率（单播 RX 已停止）
tx bitrate: 114.7 MBit/s HE-MCS 9  ← TX 完全正常

# he_on=0 稳态：
rx bitrate: 65.0 MBit/s MCS 7   ← HT 速率，正常
tx bitrate: 103.2 MBit/s HE-MCS 8  ← 注：驱动 TX 仍用 HE MCS（VHT？）
```

### mac80211 层确认

```
# he_on=1：
ieee80211 phy4: HT supp 1, VHT supp 1, HE supp 1

# he_on=0：
ieee80211 phy5: HT supp 1, VHT supp 1, HE supp 0
```

---

## 已确认的信息

### 已排除的因素

| 因素 | 结论 |
|------|------|
| `CONFIG_SDIO_PWRCTRL` | 已修复（已编译 `n`），不是本问题原因 |
| `ps_on`（mac80211 省电） | 独立变量，`ps_on=1/0` 均不影响 he_on=0 稳定性 |
| SDIO 总线带宽 | `he_on=0/1` 均约 36 Mbps，SDIO 是瓶颈，非 WiFi PHY 差异 |

### 失败特征

- **失败约在 30–60 秒内触发**（定时器相关？HE TWT？）
- TCP Cwnd 从 676 KB 降至 1.41 KB，之后无法恢复
- **无 `deinit:macaddr` dmesg 日志**（不同于 RTSP 场景），说明是 RX 路径静默停止
  而非固件发 SM_DISCONNECT_IND
- wpa_supplicant 仍显示 ASSOCIATED 状态——固件认为连接存在，但数据不通

---

## 两种失败模式的区别（待进一步验证）

| 场景 | 触发时间 | dmesg | wpa_supplicant 状态 |
|------|---------|-------|-------------------|
| RTSP 流推流（eth0 同时在用） | ~60s | `deinit:macaddr` 出现 | 断联后重连 |
| iperf3 高吞吐（纯 wlan0） | 30–60s | **无** deinit | 仍显示 ASSOCIATED |

**疑点 1**：两者是否同一根因的不同表现，还是两个独立 bug，尚未验证。  
可能 RTSP 场景有额外触发条件（eth0+wlan0 同时活跃、或 rkipc 进程的流量模式）。

**疑点 2**：RTSP 场景的 `deinit:macaddr` 仅观测到有限次数，尚未确认是 100% 必现；  
可能存在偶发性，需要重复测试（至少 5 次以上）才能确认与 `he_on` 的因果关系。

**疑点 3**：`he_on=0/1` 两种模式 iperf3 均为 ~36 Mbps，看似不合理，实则合理——  
AIC8800DC 通过 SDIO 接 RV1106，SDIO 总线是实际瓶颈（非 WiFi PHY）；  
HE PHY 速率提升（114 Mbps HE-MCS9）在 SDIO 界面上无法体现，故两者在实测吞吐上相近。  
这也意味着 he_on=0 的 "降级" 对实际应用无吞吐影响。

---

## 未测试的变量（留待下次）

- [ ] **更换路由器**：当前路由器 (12:5f:02:1e:90:07) 可能启用了 HE 特性如 BSS Coloring、
  MU-OFDMA DL，换台不支持 WiFi 6 的路由器看是否仍然失败
- [ ] **AP 模式（设备发热点）**：用 AIC8800DC 开 AP，笔记本连上后发起 iperf3，  
  测试 AP RX 路径，与 STA 模式 RX 路径对比
- [ ] **UDP 测试**：改用 `iperf3 -u`，排除 TCP Cwnd 的干扰，直接测 WiFi 层丢包率
- [ ] **HE 子功能精细关闭**：尝试组合参数  
  如 `he_on=1 he_ul_on=0`、关闭 LDPC (`ldpc_on=0`)，定位具体哪个 HE 特性触发 bug
- [ ] **固件升级**：`fmacfw_patch_8800dc_u02.bin` 版本（2025-03-17）是否有已知 HE bug fix

---

## 驱动 HE 能力注册位置

`sysdrv/drv_ko/wifi/aic8800dc/aic8800_fdrv/rwnx_mod_params.c`  
Line 1418：`if (!rwnx_hw->mod_params->he_on)` — 整块 HE cap 注册  
Line 1528：`IEEE80211_HE_PHY_CAP9_RX_FULL_BW_SU_USING_MU_WITH_NON_COMP_SIGB` — 声明支持  
Line 1525：AIC8800DC chipid 分支：`mcs_map` 限制为 `MCS_SUPPORT_0_9`

---

## 临时解决方案

**方案**：在设备上原地修改 `/oem/usr/ko/insmod_wifi.sh`，加载驱动时传 `he_on=0`，重启生效。

**操作步骤**（串口终端或 SSH 执行）：

```bash
# 修改设备上的 insmod_wifi.sh
sed -i 's/insmod aic8800_fdrv\.ko$/insmod aic8800_fdrv.ko he_on=0/' /oem/usr/ko/insmod_wifi.sh

# 验证改动
grep 'aic8800_fdrv' /oem/usr/ko/insmod_wifi.sh

# 重启生效
reboot

# 重启后验证
cat /sys/module/aic8800_fdrv/parameters/he_on   # 应输出 N
```

**注意**：
- 此修改仅作用于设备 `/oem` 分区，不涉及 SDK 工程代码
- 此为绕过方案，不是根本修复；若 `/oem` 分区被重新烧录则需重新执行
- `he_on=0` 时设备以 HT (802.11n) MCS7 关联，实测吞吐 ~36 Mbps（受 SDIO 总线限制），满足 RTSP 需求

---

## 相关文件

- 驱动 Makefile：`sysdrv/drv_ko/wifi/aic8800dc/Makefile`
  （已有 `MAKEFLAGS += CONFIG_SDIO_PWRCTRL=n` 修复）
- WiFi 加载脚本（SDK）：`sysdrv/drv_ko/wifi/insmod_wifi.sh`
- WiFi 加载脚本（设备）：`/oem/usr/ko/insmod_wifi.sh`
- 固件目录（设备）：`/oem/usr/ko/aic8800dc_fw/`
