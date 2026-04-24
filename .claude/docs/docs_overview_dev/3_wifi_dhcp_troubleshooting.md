# WiFi DHCP 故障排查笔记

> 设备：Luckfox Pico Ultra W（RV1106G3）  
> 问题：wlan0 在运行约 1 小时后 IP 自动丢失  
> 时间：2026-04-09

---

## 1. 背景与网络结构

本设备同时拥有三个网络接口，各自独立工作，互不冲突：

| 接口 | 连接方式 | 正常 IP 示例 | 用途 |
|------|----------|-------------|------|
| `eth0` | 有线网线 | `192.168.0.108` | 主要开发调试接口，最稳定 |
| `wlan0` | WiFi（AIC8800DC，2.4GHz） | `192.168.63.196` | 无线访问，本次故障接口 |
| `usb0` | USB 数据线（RNDIS 虚拟网卡） | `172.32.0.93` | USB 直连 PC |

**同时使用三个接口是完全正常的**，这本身不是问题原因。

---

## 2. 问题现象

**复现条件**：设备开机约 1 小时后（手机热点默认租期为 3600 秒）。

**故障表现**：

- `wlan0` 的 IP 从正常的 `192.168.63.x` 变成 `169.254.x.x`
- 无法通过 WiFi ping 通设备
- `eth0` 和 `usb0` 不受影响，仍然正常

**`169.254.x.x` 是什么意思？**  
这是 IPv4 链路本地地址（Link-Local），当设备找不到 DHCP 服务器、无法获取正常 IP 时，系统会自动分配这个地址作为"兜底"。看到这个地址就意味着 DHCP 获取失败。

---

## 3. 关键概念

### DHCP 与租约

**DHCP**：设备连上网络后，向路由器/热点"要 IP 地址"的协议。DHCP 客户端发送请求，DHCP 服务器（路由器或手机热点）回应并分配 IP。

**租约（lease）**：分配的 IP 有有效期，称为租期。手机热点默认租期通常是 3600 秒（1 小时）。租期到期前，DHCP 客户端需要向服务器**续约**（renew），否则 IP 失效。

**续约失败的后果**：IP 失效，接口回落到 `169.254.x.x`。

---

### udhcpc 与 dhcpcd 的区别

本设备上同时存在两个 DHCP 客户端程序：

| 程序 | 特点 | 问题 |
|------|------|------|
| `udhcpc` | BusyBox 内置，轻量。不带 `-b` 参数时为**一次性运行**，获取到 IP 后立即退出 | 退出后无人续约，租期到了 IP 就丢失 |
| `dhcpcd` | 完整的 DHCP 守护进程，会在后台**持续运行**，在租期剩余约 50% 时自动续约 | 正确的选择 |

> **守护进程（daemon）**：在后台持续运行的程序，名称通常以 `d` 结尾（如 `dhcpcd`、`wpa_supplicant`d）。

---

### /etc/init.d/S??xxx 启动顺序

Linux 启动时，`/etc/init.d/` 目录下的脚本按文件名中的数字**从小到大依次执行**：

```
S41dhcpcd   ← 数字 41，先启动 dhcpcd
S99hciinit  ← 数字 99，后启动，在这里意外地启动了 udhcpc
```

数字越小越早执行。`S` 前缀表示 Start（启动时执行）。

---

## 4. 排查过程

> 前提：通过 `eth0`（`192.168.0.108`）SSH 连入设备，此时 wlan0 已故障。

### 步骤 1：确认各接口当前 IP

```bash
sshpass -p "luckfox" ssh root@192.168.0.108 "ip addr show"
```

- `ip addr show`：列出所有网络接口及其 IP 地址
- 看 `wlan0` 条目里的 `inet` 行，若显示 `169.254.x.x` 则确认 DHCP 已失效
- 正常应显示 `192.168.63.x/24` 并带有 `valid_lft xxxsec`（租约剩余时间）

---

### 步骤 2：检查 WiFi 是否仍然关联

```bash
sshpass -p "luckfox" ssh root@192.168.0.108 "wpa_cli -i wlan0 status"
```

- `wpa_cli`：wpa_supplicant 的命令行控制工具，用于查看/操作 WiFi 连接状态
- 关键字段：`wpa_state=COMPLETED` 表示 WiFi 关联正常，只是 DHCP 出了问题
- 若 `wpa_state=DISCONNECTED` 则是 WiFi 本身断开，需另行处理

---

### 步骤 3：查看哪些进程在运行 DHCP

```bash
sshpass -p "luckfox" ssh root@192.168.0.108 "ps aux | grep -E 'udhcpc|dhcpcd|wpa_supplicant'"
```

- `ps aux`：列出当前所有运行中的进程
- `grep -E 'pattern1|pattern2'`：过滤只显示含关键词的行（`-E` 支持多个关键词用 `|` 分隔）
- 本次发现同时存在 `dhcpcd`（多个 worker 进程）和 `udhcpc -i wlan0`（一次性进程）

---

### 步骤 4：定位 udhcpc 是从哪里被启动的

```bash
sshpass -p "luckfox" ssh root@192.168.0.108 "grep -rn 'udhcpc' /etc/init.d/"
```

- `grep -rn`：在目录中**递归搜索**（`-r`）并显示**行号**（`-n`）
- 结果：`/etc/init.d/S99hciinit:  ifconfig wlan0 up && udhcpc -i wlan0 > /dev/null 2>&1`
- 这就是根本原因所在

---

### 步骤 5：确认 dhcpcd 是否知道当前租约

```bash
sshpass -p "luckfox" ssh root@192.168.0.108 "dhcpcd -U wlan0"
```

- `dhcpcd -U <接口>`：以键值对形式打印 dhcpcd 对该接口的当前状态
- 输出 `reason=BOUND` + `ip_address=xxx` 表示 dhcpcd 正在正常管理该接口
- 没有输出或报错则说明 dhcpcd 未获得该接口的租约

---

### 步骤 6：手动触发 DHCP 验证网络可达

```bash
sshpass -p "luckfox" ssh root@192.168.0.108 "udhcpc -i wlan0 -t 5 -T 3 -n"
```

- `-t 5`：最多发送 5 次 DISCOVER 包
- `-T 3`：每次等待 3 秒
- `-n`：若失败立即退出（no-wait）
- 用于测试热点 DHCP 服务器是否响应。若一直显示 `broadcasting discover` 无响应，需先重新关联 WiFi

---

### 步骤 7：重新关联 WiFi 后再申请 IP

```bash
sshpass -p "luckfox" ssh root@192.168.0.108 "wpa_cli -i wlan0 disconnect && sleep 3 && wpa_cli -i wlan0 reconnect"
```

- `disconnect`：主动断开当前 WiFi 关联
- `reconnect`：重新发起关联（会触发完整的 WPA 握手）
- 重新关联后热点会刷新设备状态，随后 DHCP 请求才能成功

---

## 5. 根本原因

`/etc/init.d/S99hciinit` 在 AIC8800DC WiFi 初始化后，多余地调用了一次 `udhcpc -i wlan0`：

```sh
# 问题代码（S99hciinit 第13行）
ifconfig wlan0 up && udhcpc -i wlan0 > /dev/null 2>&1
```

这导致了以下连锁反应：

```
开机
 │
 ├─[数字41] S41dhcpcd 启动 → dhcpcd 开始管理 wlan0，等待 WiFi 关联
 │
 ├─[数字99] S99hciinit 启动 → AIC8800 驱动加载 → wpa_supplicant 关联 WiFi
 │   └─ 随后 udhcpc 插队申请 IP，拿到后立即退出
 │
 │   ※ udhcpc 抢先拿到 IP，dhcpcd 的内部状态被扰乱
 │
 ├─[约30分钟后] dhcpcd 尝试续约，但其状态混乱，续约失败
 │
 └─[约60分钟后] 租约到期，udhcpc 早已退出，dhcpcd 无法续约
      → wlan0 回落到 169.254.x.x ← 故障出现
```

**根本矛盾**：`S99hciinit` 是为蓝牙（`hciattach`）初始化写的脚本，`udhcpc -i wlan0` 是错误附加进去的，与已有的 `dhcpcd` 形成重复管理。

---

## 6. 修复内容

### 修改的文件（共 3 处，内容相同）

**SDK 源文件（重新编译后生效）：**

- `project/cfg/BoardConfig_IPC/overlay/overlay-luckfox-buildroot-init/etc/init.d/S99hciinit`
- `project/cfg/BoardConfig_IPC/overlay/overlay-luckfox-buildroot-tiny/etc/init.d/S99hciinit`

**设备上的运行文件（立即生效）：**

- `/etc/init.d/S99hciinit`（通过 SSH `sed` 命令直接修改）

### 修改内容

```diff
- ifconfig wlan0 up && udhcpc -i wlan0 > /dev/null 2>&1
+ ifconfig wlan0 up
```

只保留 `ifconfig wlan0 up`（确保接口启动），删除后面的 `udhcpc` 调用。`wlan0` 的 DHCP 完全交由 `dhcpcd` 负责。

### 修复后验证

```bash
# 重启 dhcpcd（可选，修复后首次需要手动触发）
sshpass -p "luckfox" ssh root@192.168.0.108 "/etc/init.d/S41dhcpcd restart"

# 确认 wlan0 已获取正常 IP
sshpass -p "luckfox" ssh root@192.168.0.108 "ip addr show wlan0 | grep 'inet '"
# 预期输出：inet 192.168.63.x/24 ... valid_lft 3xxxsec

# 确认 dhcpcd 有持久化租约文件
sshpass -p "luckfox" ssh root@192.168.0.108 "ls /var/db/dhcpcd/"
# 预期看到：wlan0-<SSID>.lease 文件
```

租约文件 `/var/db/dhcpcd/wlan0-<SSID>.lease` 存在，说明 `dhcpcd` 会在下次连接同一热点时优先请求同一 IP，并在租期剩余约 50% 时自动续约。

---

## 7. 后续须知

### 设备重启后是否需要重新操作？

不需要。设备上的 `/etc/init.d/S99hciinit` 已直接修改，重启后自动生效。

### SDK 重新编译

SDK 源文件已修复，下次 `./build.sh` 编译 rootfs 并烧录后，生成的固件中 `S99hciinit` 已是正确版本。**不需要为这个修复单独重新编译**，下次正常编译时自然包含。

### 如何验证下次重启后 wlan0 稳定

等待超过 1 小时（超过一个完整租期）后检查：

```bash
sshpass -p "luckfox" ssh root@192.168.0.108 "ip addr show wlan0 | grep 'inet '"
```

若仍显示 `192.168.63.x/24` 并带有 `valid_lft`（租约剩余时间 > 0），说明续约正常工作。

### 若以后再次出现 169.254.x.x

按第 4 章步骤 7 执行 `wpa_cli disconnect` + `reconnect`，然后等待 `dhcpcd` 自动申请 IP（约 10 秒）。无需重启设备。

---

## 附录：WiFi 网络诊断速查表

SSH 连入设备后可用的常用指令（设备 IP：`192.168.0.108`）：

```bash
# 1. 查看所有接口 IP（含租约剩余时间）
ip addr show

# 2. 查看单个接口 IP（只看 wlan0）
ip addr show wlan0

# 3. 查看路由表（确认默认网关走哪个接口）
ip route

# 4. 查看 WiFi 连接状态（关联、SSID、IP）
wpa_cli -i wlan0 status

# 5. 查看所有运行中的进程（常用于找"在跑什么程序"）
ps aux

# 6. 过滤进程列表（只看 DHCP 相关）
ps aux | grep -E 'udhcpc|dhcpcd'

# 7. 在目录中全文搜索关键词（找某个命令被哪个脚本调用）
grep -rn 'udhcpc' /etc/init.d/

# 8. 查看 dhcpcd 对某接口的详细状态（含 IP、租约时间）
dhcpcd -U wlan0

# 9. 手动重新申请 DHCP（测试用，获取后退出）
udhcpc -i wlan0 -t 5 -T 3 -n

# 10. WiFi 断开重连（触发重新关联 + DHCP）
wpa_cli -i wlan0 disconnect && sleep 3 && wpa_cli -i wlan0 reconnect

# 11. 重启 dhcpcd 服务
/etc/init.d/S41dhcpcd restart

# 12. 查看 dhcpcd 的租约文件列表
ls /var/db/dhcpcd/
```

