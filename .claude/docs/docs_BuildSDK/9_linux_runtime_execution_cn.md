# Linux 运行机制详解：从启动到命令执行

## 第 1 章：概述 - 从静态文件到动态执行

### 1.1 回顾：Buildroot 生成的静态文件

在之前的文档《Buildroot 与根文件系统构建流程》中，我们详细了解了 Buildroot 如何生成根文件系统：

```
Buildroot 构建流程：
tar.gz → 解压 → 配置 → 下载 → 编译 → 安装 → 后处理 → 打包 → rootfs.ext4
```

最终生成的根文件系统包含：

```
/
├── bin/          # 基本命令（ls、cp、sh 等）
├── sbin/         # 系统命令（init、ifconfig 等）
├── lib/          # 共享库（libc.so、libssl.so 等）
├── etc/          # 配置文件（init.d、network 等）
├── usr/          # 用户程序（ssh、python、samba 等）
└── var/          # 可变数据（日志、缓存等）
```

这些都是**静态文件** - 它们在编译时生成，烧录到设备后就固定在存储介质中。

但是，当设备启动后，这些静态文件如何变成**运行中的程序**？为什么你能在终端输入命令并得到响应？这就是本文档要解答的核心问题。

### 1.2 本文档要解决的问题

当你第一次接触 Linux 系统时，可能会有以下困惑：

#### 问题 1：为什么登录后能运行 `ls` 命令？

```bash
# 你在终端输入
$ ls
bin  dev  etc  home  lib  mnt  proc  root  sbin  sys  tmp  usr  var

# 为什么会有输出？
# ls 是什么？在哪里？如何执行的？
```

#### 问题 2：为什么能执行 `.sh` 脚本？

```bash
# 你创建一个脚本
$ cat > test.sh << 'EOF'
#!/bin/sh
echo "Hello World"
EOF

$ chmod +x test.sh
$ ./test.sh
Hello World

# 为什么脚本能执行？
# #!/bin/sh 是什么意思？
# 与二进制程序有什么区别？
```

#### 问题 3：为什么服务会自动启动？

从启动日志中可以看到：

```
Starting syslogd: OK
Starting klogd: OK
Starting network: OK
Starting sshd: OK
Starting telnetd: OK
Starting SMB services: OK
```

这些服务是如何自动启动的？`/etc/init.d/rcS` 是如何被执行的？

#### 问题 4：Linux 与单片机的本质区别是什么？

**单片机编程模型**：
```c
int main() {
    init_hardware();
    while(1) {
        // 你的代码
        if (button_pressed) {
            do_something();
        }
    }
}
```
- 只运行一个程序（你的固件）
- 编译时确定所有功能
- 无法动态加载新程序

**Linux 使用体验**：
```bash
$ ls        # 运行 ls 程序
$ cat file  # 运行 cat 程序
$ ./myapp   # 运行你的程序
```
- 可以随时运行不同的程序
- 不需要重新编译系统
- 像一台可交互的小型电脑

**为什么会有这种区别？**

### 1.3 核心概念预览

要理解 Linux 的运行机制，需要掌握以下核心概念：

#### 1.3.1 进程（Process）vs 线程（Thread）

**进程**：
- Linux 的基本执行单元
- 每个进程有独立的内存空间
- 进程之间完全隔离
- 每个命令执行都会创建新进程

**线程**：
- 进程内的执行单元
- 同一进程的线程共享内存空间
- 用于并发处理，而非命令执行

**关键区别**：
```
进程 A (独立内存)          进程 B (独立内存)
├── 代码段                 ├── 代码段
├── 数据段                 ├── 数据段
├── 堆                     ├── 堆
└── 栈                     └── 栈

进程 C (共享内存)
├── 代码段 (共享)
├── 数据段 (共享)
├── 堆 (共享)
├── 线程 1 (独立栈)
├── 线程 2 (独立栈)
└── 线程 3 (独立栈)
```

**重要**：Linux 命令执行使用的是**进程**，不是线程。

#### 1.3.2 系统调用（System Call）

**什么是系统调用**：
- 用户程序请求内核服务的接口
- 从用户态切换到内核态
- 内核执行特权操作后返回用户态

**常用系统调用**：
- `fork()` - 创建子进程
- `exec()` - 用新程序替换当前进程
- `wait()` - 等待子进程结束
- `exit()` - 终止当前进程
- `open()` - 打开文件
- `read()` - 读取文件
- `write()` - 写入文件

**为什么需要系统调用**：
```
用户空间（应用程序）
    ↓ 系统调用
内核空间（操作系统）
    ↓ 硬件操作
硬件（CPU、内存、磁盘）
```

应用程序不能直接访问硬件，必须通过系统调用请求内核代为操作。

#### 1.3.3 可执行文件格式（ELF）

**ELF（Executable and Linkable Format）**：
- Linux 的标准可执行文件格式
- 包含程序代码、数据、符号表等
- 内核知道如何加载和执行 ELF 文件

**查看文件类型**：
```bash
$ file /bin/ls
/bin/ls: symbolic link to busybox

$ file /bin/busybox
/bin/busybox: ELF 32-bit LSB executable, ARM, version 1 (SYSV),
dynamically linked, interpreter /lib/ld-uClibc.so.0
```

**ELF 文件结构**：
```
ELF 文件
├── ELF 头部（文件类型、架构、入口点）
├── 程序头表（如何加载到内存）
├── .text 段（代码段 - 程序指令）
├── .data 段（数据段 - 已初始化数据）
├── .bss 段（未初始化数据）
├── .rodata 段（只读数据 - 字符串常量）
└── 节头表（调试和链接信息）
```

### 1.4 文档结构

本文档将按以下顺序展开：

1. **第 2-3 章**：介绍基础概念（可执行文件、进程、系统调用）
2. **第 4 章**：追踪从内核启动到 Shell 的完整链条
3. **第 5 章**：深入 `fork() + exec()` 机制，解释命令如何执行
4. **第 6 章**：解释脚本执行的 Shebang 机制
5. **第 7 章**：分析服务自动启动的 Init 系统
6. **第 8 章**：补充进程生命周期的完整知识
7. **第 9 章**：对比 Linux 与单片机的本质区别
8. **第 10 章**：提供实践验证方法
9. **第 11 章**：总结核心概念

### 1.5 与其他文档的关系

本文档是 Luckfox Pico SDK 文档系列的一部分：

```
文档体系：
├── 设备树与硬件初始化（7_uboot_kernel_driver_comparison_cn.md）
│   └── 解释：硬件如何被识别和初始化
├── Buildroot 与根文件系统构建（8_buildroot_rootfs_build_cn.md）
│   └── 解释：静态文件如何生成
└── Linux 运行机制（本文档）
    └── 解释：静态文件如何在运行时执行
```

**阅读建议**：
- 如果你不了解设备树，建议先阅读文档 7
- 如果你不了解 Buildroot，建议先阅读文档 8
- 本文档假设你已经理解静态文件的来源

### 1.6 学习目标

阅读完本文档后，你应该能够：

1. ✅ 理解进程和线程的区别
2. ✅ 解释 `fork() + exec()` 机制
3. ✅ 说明命令执行的完整流程
4. ✅ 理解脚本的 Shebang 机制
5. ✅ 解释服务如何自动启动
6. ✅ 对比 Linux 与单片机的本质区别
7. ✅ 能够使用 `ps`、`pstree` 等工具观察进程
8. ✅ 理解为什么 Linux 是"可交互的小型电脑"

让我们开始深入探索 Linux 的运行机制！

---

## 第 2 章：可执行文件 - 程序的存储形式

### 2.1 ELF 文件格式

#### 2.1.1 什么是 ELF

**ELF（Executable and Linkable Format）** 是 Linux 系统的标准可执行文件格式。

**为什么需要特定格式**：
- 内核需要知道如何加载程序到内存
- 需要指定程序的入口点（从哪里开始执行）
- 需要描述程序的内存布局
- 需要指定依赖的共享库

**ELF 文件类型**：
1. **可执行文件**（Executable）：可以直接运行的程序
2. **共享库**（Shared Object）：`.so` 文件，被多个程序共享
3. **可重定位文件**（Relocatable）：`.o` 文件，编译中间产物

#### 2.1.2 ELF 文件结构

```
ELF 文件布局：

+---------------------------+
| ELF Header                | ← 文件头（52 字节，32 位系统）
|  - 魔数: 0x7F 'E' 'L' 'F'|   标识这是 ELF 文件
|  - 类别: 32-bit / 64-bit |   指定架构
|  - 字节序: LSB / MSB      |   大小端
|  - 机器类型: ARM          |   目标 CPU 架构
|  - 入口点地址             |   程序开始执行的地址
+---------------------------+
| Program Header Table      | ← 程序头表
|  - LOAD 段 1 (代码)       |   告诉内核如何加载到内存
|  - LOAD 段 2 (数据)       |
|  - DYNAMIC (动态链接)     |
|  - INTERP (解释器)        |
+---------------------------+
| .text Section             | ← 代码段（可执行指令）
|  - 程序的机器码           |   只读、可执行
+---------------------------+
| .rodata Section           | ← 只读数据段
|  - 字符串常量             |   只读
|  - const 变量             |
+---------------------------+
| .data Section             | ← 数据段（已初始化）
|  - 全局变量               |   可读写
|  - 静态变量               |
+---------------------------+
| .bss Section              | ← BSS 段（未初始化）
|  - 未初始化的全局变量     |   运行时清零
+---------------------------+
| .dynamic Section          | ← 动态链接信息
|  - 依赖的共享库列表       |
|  - 符号表位置             |
+---------------------------+
| Section Header Table      | ← 节头表
|  - 各个 section 的描述    |   用于链接和调试
+---------------------------+
```

#### 2.1.3 查看 ELF 文件信息

**使用 `file` 命令**：
```bash
$ file /bin/busybox
/bin/busybox: ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV),
dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped
```

**解读**：
- `ELF 32-bit LSB`：32 位 ELF 文件，小端字节序
- `ARM`：目标架构是 ARM
- `EABI5`：ARM 嵌入式应用二进制接口版本 5
- `dynamically linked`：动态链接（需要共享库）
- `interpreter /lib/ld-uClibc.so.0`：动态链接器路径
- `stripped`：已去除调试符号（减小文件大小）

**使用 `readelf` 命令**（如果可用）：
```bash
$ readelf -h /bin/busybox
ELF Header:
  Magic:   7f 45 4c 46 01 01 01 00 00 00 00 00 00 00 00 00
  Class:                             ELF32
  Data:                              2's complement, little endian
  Version:                           1 (current)
  OS/ABI:                            UNIX - System V
  ABI Version:                       0
  Type:                              EXEC (Executable file)
  Machine:                           ARM
  Version:                           0x1
  Entry point address:               0x8400
  Start of program headers:          52 (bytes into file)
  Start of section headers:          512000 (bytes into file)
```

**关键字段**：
- `Entry point address: 0x8400`：程序入口点，内核加载后从这里开始执行
- `Type: EXEC`：可执行文件类型

### 2.2 BusyBox 的特殊性

#### 2.2.1 什么是 BusyBox

BusyBox 是一个集成了数百个 Unix 工具的单一可执行文件，专为嵌入式系统设计。

**传统 Linux 系统**：
```
/bin/
├── ls        (30 KB)
├── cat       (25 KB)
├── cp        (40 KB)
├── mv        (35 KB)
├── rm        (28 KB)
└── ... (数百个独立程序)
总计：数 MB
```

**BusyBox 系统**：
```
/bin/
├── busybox   (500 KB) ← 包含所有工具
├── ls -> busybox      ← 符号链接
├── cat -> busybox
├── cp -> busybox
├── mv -> busybox
└── rm -> busybox
总计：500 KB + 少量符号链接
```

**优势**：
- 大幅减小文件系统大小
- 共享代码，减少内存占用
- 统一的代码库，易于维护

#### 2.2.2 符号链接机制

**查看符号链接**：
```bash
$ ls -l /bin/ls
lrwxrwxrwx 1 root root 7 Jan 26 /bin/ls -> busybox
```

**符号链接的作用**：
- `ls` 不是独立程序，只是指向 `busybox` 的链接
- 当你执行 `/bin/ls` 时，实际执行的是 `/bin/busybox`

#### 2.2.3 BusyBox 如何识别功能

**关键机制：`argv[0]`**

当程序被执行时，内核会传递参数：
- `argv[0]`：程序名称（或调用路径）
- `argv[1]`, `argv[2]`, ...：命令行参数

**BusyBox 的判断逻辑**（简化版）：
```c
int main(int argc, char **argv) {
    char *applet_name = basename(argv[0]);

    if (strcmp(applet_name, "ls") == 0) {
        return ls_main(argc, argv);
    } else if (strcmp(applet_name, "cat") == 0) {
        return cat_main(argc, argv);
    } else if (strcmp(applet_name, "cp") == 0) {
        return cp_main(argc, argv);
    }
    // ... 数百个工具的判断

    return 0;
}
```

**执行流程**：
```
1. 你执行：/bin/ls -l
2. 内核加载：/bin/busybox（因为 ls 是符号链接）
3. argv[0] = "/bin/ls"
4. BusyBox 提取 "ls"
5. 调用 ls_main() 函数
6. 输出目录列表
```

**验证**：
```bash
# 直接调用 busybox，指定功能
$ busybox ls -l
# 等同于
$ ls -l

# 查看 BusyBox 支持的所有命令
$ busybox --list
ls
cat
cp
mv
rm
...
```

### 2.3 动态链接

#### 2.3.1 什么是动态链接

**静态链接 vs 动态链接**：

**静态链接**：
```
程序 A                程序 B
├── 代码              ├── 代码
└── libc 代码 (1MB)   └── libc 代码 (1MB)

磁盘占用：2MB
内存占用：2MB（两份 libc）
```

**动态链接**：
```
程序 A                程序 B
├── 代码              ├── 代码
└── 引用 libc         └── 引用 libc
         ↓                    ↓
         libc.so (1MB，共享)

磁盘占用：程序 A + 程序 B + 1MB
内存占用：程序 A + 程序 B + 1MB（一份 libc）
```

**优势**：
- 节省磁盘空间
- 节省内存（共享库只加载一次）
- 更新库文件后，所有程序自动受益

#### 2.3.2 共享库（.so 文件）

**查看程序依赖的共享库**：
```bash
$ ldd /bin/busybox
    libc.so.0 => /lib/libc.so.0 (0xb6e00000)
    ld-uClibc.so.0 => /lib/ld-uClibc.so.0 (0xb6f00000)
```

**共享库位置**：
```
/lib/
├── libc.so.0           # C 标准库
├── libm.so.0           # 数学库
├── libpthread.so.0     # 线程库
├── libssl.so.3         # OpenSSL 加密库
└── ld-uClibc.so.0      # 动态链接器
```

**共享库命名规范**：
```
libname.so.major.minor.patch
  ↑     ↑   ↑     ↑     ↑
  |     |   |     |     └─ 补丁版本
  |     |   |     └─────── 次版本
  |     |   └─────────── 主版本（不兼容时递增）
  |     └─────────────── 共享对象
  └───────────────────── 库名称

例如：libc.so.0 → C 库主版本 0
```

#### 2.3.3 动态链接器

**什么是动态链接器**：
- 负责在程序启动时加载共享库
- 解析符号引用（函数、变量）
- 重定位地址

**动态链接器路径**：
```bash
$ readelf -l /bin/busybox | grep interpreter
  [Requesting program interpreter: /lib/ld-uClibc.so.0]
```

**运行时库加载过程**：
```
1. 内核加载 ELF 文件
   ↓
2. 内核发现需要动态链接器
   ↓
3. 内核加载 /lib/ld-uClibc.so.0
   ↓
4. 动态链接器读取 ELF 的 DYNAMIC 段
   ↓
5. 加载所需的共享库（libc.so.0 等）
   ↓
6. 解析符号（printf、malloc 等函数地址）
   ↓
7. 重定位（修正地址引用）
   ↓
8. 跳转到程序入口点（main 函数）
```

**为什么需要动态链接器**：
- 共享库的加载地址在运行时才确定
- 需要解析符号引用（函数名 → 实际地址）
- 需要处理不同版本的库

### 2.4 本章总结

**关键概念**：
1. **ELF 格式**：Linux 的标准可执行文件格式，包含代码、数据和元信息
2. **BusyBox**：集成多个工具的单一可执行文件，通过 `argv[0]` 识别功能
3. **动态链接**：程序运行时加载共享库，节省空间和内存

**文件类型识别**：
```bash
$ file /bin/ls
/bin/ls: symbolic link to busybox  # 符号链接

$ file /bin/busybox
/bin/busybox: ELF 32-bit LSB executable, ARM  # ELF 可执行文件

$ file /lib/libc.so.0
/lib/libc.so.0: ELF 32-bit LSB shared object, ARM  # ELF 共享库

$ file /etc/init.d/rcS
/etc/init.d/rcS: POSIX shell script, ASCII text executable  # Shell 脚本
```

**下一章预告**：
现在我们知道了可执行文件的存储形式，下一章将介绍 Linux 如何使用**进程**来执行这些文件。

---

## 第 3 章：进程 - Linux 的执行单元

### 3.1 进程的概念

#### 3.1.1 什么是进程

**进程（Process）** 是 Linux 中程序的运行实例。

**程序 vs 进程**：
- **程序**：存储在磁盘上的静态文件（ELF 文件）
- **进程**：程序加载到内存后的动态执行实体

**类比**：
```
程序 = 菜谱（静态的文本）
进程 = 按照菜谱做菜的过程（动态的活动）
```

**同一个程序可以有多个进程**：
```bash
$ ls &        # 进程 1
[1] 100
$ ls &        # 进程 2
[2] 101
$ ls &        # 进程 3
[3] 102
```
三个进程都在执行 `/bin/ls` 程序，但它们是独立的执行实例。

#### 3.1.2 进程的内存空间

每个进程都有独立的虚拟内存空间：

```
进程的虚拟内存布局（32 位系统）：

0xFFFFFFFF  +------------------+
            | 内核空间          | ← 所有进程共享
            | (1GB)            |   只有内核态可访问
0xC0000000  +------------------+
            | 栈（Stack）       | ← 向下增长
            | - 局部变量        |   函数调用栈
            | - 函数参数        |
            | - 返回地址        |
            |       ↓          |
            |                  |
            |       ↑          |
            | 堆（Heap）        | ← 向上增长
            | - malloc 分配    |   动态内存
            | - new 分配       |
0x08048000  +------------------+
            | BSS 段           | ← 未初始化数据
            | - 未初始化全局变量|   运行时清零
            +------------------+
            | 数据段（Data）    | ← 已初始化数据
            | - 全局变量        |   可读写
            | - 静态变量        |
            +------------------+
            | 只读数据（RoData）| ← 只读数据
            | - 字符串常量      |   只读
            | - const 变量     |
            +------------------+
            | 代码段（Text）    | ← 程序代码
            | - 机器指令        |   只读、可执行
0x00000000  +------------------+
```

**关键特性**：
- **独立性**：每个进程看到的都是完整的 4GB 虚拟地址空间
- **隔离性**：进程 A 不能访问进程 B 的内存
- **保护性**：代码段只读，防止程序自我修改

#### 3.1.3 进程标识符（PID）

**PID（Process ID）**：
- 每个进程都有唯一的 PID
- PID 是正整数，从 1 开始
- PID 1 是 init 进程，系统启动后第一个用户空间进程

**查看进程 PID**：
```bash
$ ps
  PID USER       VSZ STAT COMMAND
    1 root      1640 S    init
  174 root      2104 S    /usr/bin/dbus-daemon --system
  180 root      3256 S    /usr/sbin/sshd
  530 root      1644 S    -sh
  540 root      1636 R    ps
```

**特殊 PID**：
- **PID 0**：内核调度器（不是真正的进程）
- **PID 1**：init 进程（所有用户进程的祖先）
- **PPID**：父进程 ID（Parent PID）

**查看父进程**：
```bash
$ ps -o pid,ppid,comm
  PID  PPID COMMAND
    1     0 init
  530     1 sh
  540   530 ps
```
- `ps` 的父进程是 `sh`（PID 530）
- `sh` 的父进程是 `init`（PID 1）

#### 3.1.4 进程状态

进程在生命周期中会经历不同的状态：

```
进程状态转换图：

    [新建]
      ↓
   [就绪] ←──────┐
      ↓          │
   [运行] ────→ [阻塞]
      ↓          ↑
   [终止]        │
                 └─ 等待 I/O
```

**主要状态**：

| 状态 | 符号 | 说明 | 示例 |
|------|------|------|------|
| 运行（Running） | R | 正在 CPU 上执行 | 计算密集型任务 |
| 就绪（Runnable） | R | 等待 CPU 调度 | 多个进程竞争 CPU |
| 睡眠（Sleeping） | S | 等待事件（可中断） | 等待键盘输入 |
| 不可中断睡眠 | D | 等待 I/O（不可中断） | 等待磁盘读写 |
| 停止（Stopped） | T | 被信号停止 | Ctrl+Z 暂停 |
| 僵尸（Zombie） | Z | 已终止但未回收 | 父进程未调用 wait() |

**查看进程状态**：
```bash
$ ps aux
USER       PID %CPU %MEM    VSZ   RSS STAT COMMAND
root         1  0.0  0.1   1640   532 S    init
root       180  0.0  0.3   3256  1024 S    /usr/sbin/sshd
root       530  0.0  0.1   1644   612 S    -sh
root       540  0.0  0.1   1636   584 R    ps aux
```

**STAT 列解释**：
- `S`：睡眠状态（Sleeping）
- `R`：运行状态（Running）
- `Z`：僵尸状态（Zombie）
- `T`：停止状态（Stopped）
- `<`：高优先级
- `N`：低优先级
- `+`：前台进程组

### 3.2 进程 vs 线程

#### 3.2.1 进程：独立内存空间

```
进程 A (PID 100)              进程 B (PID 200)
+------------------+          +------------------+
| 代码段            |          | 代码段            |
| 数据段            |          | 数据段            |
| 堆                |          | 堆                |
| 栈                |          | 栈                |
| 文件描述符表      |          | 文件描述符表      |
| 环境变量          |          | 环境变量          |
+------------------+          +------------------+
     ↑                              ↑
     └──── 完全隔离 ────────────────┘
```

**特点**：
- 每个进程有独立的内存空间
- 进程间不能直接访问对方的内存
- 需要通过 IPC（进程间通信）交换数据
- 创建开销大（需要复制内存空间）

#### 3.2.2 线程：共享内存空间

```
进程 C (PID 300)
+------------------+
| 代码段 (共享)     |
| 数据段 (共享)     |
| 堆 (共享)         |
+------------------+
| 线程 1           |
|  - 栈 (独立)     |
|  - 寄存器 (独立) |
+------------------+
| 线程 2           |
|  - 栈 (独立)     |
|  - 寄存器 (独立) |
+------------------+
| 线程 3           |
|  - 栈 (独立)     |
|  - 寄存器 (独立) |
+------------------+
```

**特点**：
- 同一进程的线程共享内存空间
- 线程间可以直接访问共享变量
- 创建开销小（不需要复制内存）
- 需要同步机制（互斥锁、信号量）

#### 3.2.3 对比表格

| 特性 | 进程 | 线程 |
|------|------|------|
| 内存空间 | 独立 | 共享 |
| 通信方式 | IPC（管道、消息队列、共享内存） | 直接访问共享变量 |
| 创建开销 | 大（~1-2ms） | 小（~10-100μs） |
| 切换开销 | 大（需要切换页表） | 小（同一地址空间） |
| 安全性 | 高（隔离） | 低（需要同步） |
| 稳定性 | 高（一个进程崩溃不影响其他） | 低（一个线程崩溃导致整个进程崩溃） |
| 资源占用 | 大（独立资源） | 小（共享资源） |

#### 3.2.4 使用场景

**使用进程的场景**：
- 执行独立的命令（`ls`、`cat`、`grep`）
- 运行不可信的代码（需要隔离）
- 需要独立的权限和资源限制
- 多个独立的服务（SSH、Samba、Web 服务器）

**使用线程的场景**：
- Web 服务器处理多个请求（共享连接池）
- 视频编码（共享视频帧数据）
- 并行计算（共享计算数据）
- GUI 应用（主线程处理界面，工作线程处理任务）

**Linux 命令执行为什么用进程而不是线程**：
1. **隔离性**：命令失败不影响 shell
2. **简单性**：不需要考虑同步问题
3. **安全性**：命令不能访问 shell 的内存
4. **Unix 哲学**：每个程序做好一件事

### 3.3 进程树

#### 3.3.1 init 进程（PID 1）

**init 是所有用户进程的祖先**：

```
内核启动后：
1. 内核初始化完成
2. 挂载根文件系统
3. 执行 /sbin/init（PID 1）
4. init 创建其他所有进程
```

**init 的特殊性**：
- PID 固定为 1
- 永远不会退出（除非系统关机）
- 负责回收孤儿进程
- 负责系统初始化

#### 3.3.2 父子进程关系

**进程创建关系**：
```
PID 1: init
├─ PID 174: dbus-daemon
├─ PID 180: sshd (SSH 服务器)
│  └─ PID 520: sshd (你的 SSH 连接)
│     └─ PID 530: sh (你的 shell)
│        └─ PID 540: ls (你运行的命令)
├─ PID 190: telnetd
└─ PID 200: getty (串口登录)
```

**父子进程的关系**：
- 子进程继承父进程的环境变量
- 子进程继承父进程的文件描述符
- 子进程继承父进程的工作目录
- 子进程有独立的 PID 和内存空间

#### 3.3.3 实际进程树示例

从 Luckfox Pico 启动日志可以看到实际的进程树：

```bash
$ pstree
init─┬─dbus-daemon
     ├─sshd───sshd───sh───pstree
     ├─getty
     ├─bluetoothd
     ├─ntpd
     ├─telnetd
     └─smbd
```

**详细进程信息**：
```bash
$ ps -ef
UID        PID  PPID  C STIME TTY          TIME CMD
root         1     0  0 00:00 ?        00:00:00 init
root       174     1  0 00:00 ?        00:00:00 /usr/bin/dbus-daemon --system
root       180     1  0 00:00 ?        00:00:00 /usr/sbin/sshd
root       200     1  0 00:00 ttyFIQ0  00:00:00 /sbin/getty -L console 0 vt100
root       520   180  0 10:30 ?        00:00:00 sshd: root@pts/0
root       530   520  0 10:30 pts/0    00:00:00 -sh
root       540   530  0 10:35 pts/0    00:00:00 ps -ef
```

**PPID 列**：
- `ps` (PID 540) 的父进程是 `sh` (PID 530)
- `sh` (PID 530) 的父进程是 `sshd` (PID 520)
- `sshd` (PID 520) 的父进程是 `sshd` (PID 180)
- `sshd` (PID 180) 的父进程是 `init` (PID 1)

#### 3.3.4 查看进程树

**使用 `pstree` 命令**：
```bash
$ pstree -p
init(1)─┬─dbus-daemon(174)
        ├─sshd(180)───sshd(520)───sh(530)───pstree(540)
        ├─getty(200)
        └─smbd(210)
```

**使用 `ps` 命令**：
```bash
$ ps -ejH
  PID  PGID   SID TTY          TIME CMD
    1     1     1 ?        00:00:00 init
  174   174   174 ?        00:00:00   dbus-daemon
  180   180   180 ?        00:00:00   sshd
  520   520   520 ?        00:00:00     sshd
  530   530   530 pts/0    00:00:00       sh
  540   540   530 pts/0    00:00:00         ps
```

### 3.4 系统调用

#### 3.4.1 什么是系统调用

**系统调用（System Call）** 是用户程序请求内核服务的接口。

**为什么需要系统调用**：
- 用户程序运行在用户态（User Mode），权限受限
- 硬件操作需要特权指令，只能在内核态（Kernel Mode）执行
- 系统调用是用户态和内核态之间的桥梁

**用户态 vs 内核态**：

```
用户态（User Mode）
- 权限受限
- 不能直接访问硬件
- 不能执行特权指令
- 应用程序运行在这里
        ↓ 系统调用
────────────────────────────
        ↑ 返回
内核态（Kernel Mode）
- 完全权限
- 可以访问所有硬件
- 可以执行特权指令
- 操作系统内核运行在这里
```

#### 3.4.2 系统调用的执行过程

**示例：`write()` 系统调用**

```c
// 用户程序
#include <unistd.h>

int main() {
    write(1, "Hello\n", 6);  // 系统调用
    return 0;
}
```

**执行流程**：
```
1. 用户程序调用 write()
   ↓
2. C 库（libc）包装函数
   ↓
3. 设置系统调用号（__NR_write = 4）
   ↓
4. 触发软中断（SWI 指令，ARM 架构）
   ↓
5. CPU 切换到内核态
   ↓
6. 内核根据系统调用号查找处理函数
   ↓
7. 执行 sys_write() 内核函数
   ↓
8. 写入数据到文件描述符 1（标准输出）
   ↓
9. 返回写入的字节数
   ↓
10. CPU 切换回用户态
   ↓
11. 返回到用户程序
```

#### 3.4.3 常用系统调用

**进程管理**：
- `fork()` - 创建子进程
- `exec()` - 用新程序替换当前进程
- `wait()` / `waitpid()` - 等待子进程结束
- `exit()` - 终止当前进程
- `getpid()` - 获取当前进程 PID
- `getppid()` - 获取父进程 PID

**文件操作**：
- `open()` - 打开文件
- `read()` - 读取文件
- `write()` - 写入文件
- `close()` - 关闭文件
- `lseek()` - 移动文件指针

**内存管理**：
- `brk()` / `sbrk()` - 调整堆大小
- `mmap()` - 内存映射
- `munmap()` - 取消内存映射

**信号处理**：
- `kill()` - 发送信号
- `signal()` - 设置信号处理函数
- `sigaction()` - 高级信号处理

#### 3.4.4 系统调用与库函数的区别

**系统调用**：
- 内核提供的接口
- 直接进入内核态
- 开销较大（上下文切换）
- 数量有限（几百个）

**库函数**：
- C 库提供的函数
- 可能调用系统调用，也可能不调用
- 开销较小（用户态执行）
- 数量众多（数千个）

**示例对比**：
```c
// 库函数（不涉及系统调用）
strlen("hello");  // 纯用户态计算

// 库函数（内部调用系统调用）
printf("hello");  // 内部调用 write() 系统调用

// 直接系统调用
write(1, "hello", 5);  // 直接进入内核
```

### 3.5 本章总结

**关键概念**：
1. **进程**：程序的运行实例，有独立的内存空间和 PID
2. **进程 vs 线程**：进程隔离，线程共享；Linux 命令执行使用进程
3. **进程树**：init（PID 1）是所有进程的祖先
4. **系统调用**：用户程序请求内核服务的接口

**进程的特性**：
- 独立的虚拟内存空间
- 唯一的 PID
- 父子进程关系
- 不同的状态（运行、睡眠、僵尸等）

**下一章预告**：
现在我们理解了进程的概念，下一章将追踪从内核启动到 Shell 的完整链条，看看进程是如何一步步创建的。

---

## 第 4 章：从启动到 Shell - 完整执行链

### 4.1 启动链条总览

从设备上电到你能输入命令，经历了以下完整链条：

```
启动链条：

硬件上电
    ↓
DDR 初始化（34ms）
    ↓
U-Boot SPL（383ms）
    ↓
U-Boot Proper（795ms）
    ↓
Linux 内核启动（484ms）
    ↓
内核挂载根文件系统
    ↓
内核执行 /sbin/init（PID 1）
    ↓
init 读取 /etc/inittab
    ↓
init 执行 /etc/init.d/rcS
    ↓
rcS 启动各种服务（S01*, S02*, ...）
    ↓
init 启动 getty（串口登录）
    ↓
getty 显示登录提示符
    ↓
用户输入用户名和密码
    ↓
login 验证身份
    ↓
login 启动 shell（/bin/sh）
    ↓
shell 显示提示符，等待命令
    ↓
你输入命令（如 ls）
```

**总时间**：约 11 秒（到服务启动完成）

本章将详细分析从内核启动 init 到 shell 就绪的过程。

### 4.2 内核启动 init（PID 1）

#### 4.2.1 内核挂载根文件系统

从启动日志（stage4_kernel_boot_cn.md）可以看到：

```
[    0.417791] EXT4-fs (mmcblk0p7): INFO: recovery required on readonly filesystem
[    0.479368] EXT4-fs (mmcblk0p7): recovery complete
[    0.479899] EXT4-fs (mmcblk0p7): mounted filesystem with ordered data mode
[    0.479971] VFS: Mounted root (ext4 filesystem) readonly on device 179:7.
```

**关键步骤**：
1. 内核识别根设备：`/dev/mmcblk0p7`（来自内核命令行 `root=/dev/mmcblk0p7`）
2. 执行文件系统检查和日志恢复（62ms）
3. 以只读模式挂载根文件系统
4. 根文件系统挂载到 `/`

#### 4.2.2 内核执行 /sbin/init

```
[    0.483988] Run /sbin/init as init process
```

**内核的操作**：
```c
// 内核代码（简化版）
// init/main.c

static int run_init_process(const char *init_filename) {
    const char *argv[] = { init_filename, NULL };
    const char *envp[] = { "HOME=/", "TERM=linux", NULL };

    return do_execve(init_filename, argv, envp);
}

// 尝试执行 init 程序
if (!try_to_run_init_process("/sbin/init") ||
    !try_to_run_init_process("/etc/init") ||
    !try_to_run_init_process("/bin/init") ||
    !try_to_run_init_process("/bin/sh")) {
    return 0;
}

panic("No working init found.");
```

**查找顺序**：
1. `/sbin/init`（标准位置）
2. `/etc/init`（备用位置）
3. `/bin/init`（备用位置）
4. `/bin/sh`（最后的备用）

在 Luckfox Pico 上：
```bash
$ ls -l /sbin/init
lrwxrwxrwx 1 root root 14 Jan 26 /sbin/init -> ../bin/busybox
```

**init 是 busybox 的符号链接**。

#### 4.2.3 init 进程的特殊性

**PID 固定为 1**：
```bash
$ ps aux | grep init
root         1  0.0  0.1   1640   532 S    init
```

**init 的职责**：
1. 系统初始化（执行启动脚本）
2. 启动系统服务
3. 管理登录进程（getty）
4. 回收孤儿进程（父进程已退出的进程）
5. 处理系统关机

**为什么 init 永远不会退出**：
- 如果 init 退出，内核会 panic（系统崩溃）
- init 是所有进程的祖先，必须一直运行

### 4.3 init 读取配置

#### 4.3.1 /etc/inittab 文件

init 启动后，首先读取配置文件 `/etc/inittab`：

```bash
# /etc/inittab

# 系统初始化
::sysinit:/etc/init.d/rcS

# 在串口上启动 getty
console::respawn:/sbin/getty -L console 0 vt100

# Ctrl+Alt+Del 处理
::ctrlaltdel:/sbin/reboot

# 关机前的清理
::shutdown:/etc/init.d/rcK
::shutdown:/sbin/swapoff -a
::shutdown:/bin/umount -a -r
```

#### 4.3.2 inittab 语法

**格式**：
```
id:runlevels:action:process
```

**字段说明**：
- `id`：标识符（可以为空）
- `runlevels`：运行级别（BusyBox init 忽略此字段）
- `action`：动作类型
- `process`：要执行的命令

**常用 action 类型**：

| Action | 说明 | 执行时机 |
|--------|------|----------|
| `sysinit` | 系统初始化 | init 启动时执行一次 |
| `respawn` | 重生 | 进程退出后自动重启 |
| `askfirst` | 询问后启动 | 类似 respawn，但先询问 |
| `once` | 执行一次 | 执行一次，不重启 |
| `wait` | 等待完成 | 执行并等待完成 |
| `restart` | 重启 init | 重新读取 inittab |
| `ctrlaltdel` | Ctrl+Alt+Del | 按下 Ctrl+Alt+Del 时执行 |
| `shutdown` | 关机 | 系统关机时执行 |

#### 4.3.3 sysinit 触发 rcS

**关键配置**：
```
::sysinit:/etc/init.d/rcS
```

**含义**：
- `action` 是 `sysinit`：系统初始化时执行
- `process` 是 `/etc/init.d/rcS`：执行这个脚本

**init 的操作**：
```c
// BusyBox init 代码（简化版）

if (action == SYSINIT) {
    // 执行系统初始化脚本
    run_script("/etc/init.d/rcS");
    // 等待脚本完成
    wait_for_completion();
}
```

### 4.4 rcS 执行服务脚本

#### 4.4.1 rcS 脚本内容

```bash
#!/bin/sh
# /etc/init.d/rcS

# 启动 /etc/init.d 中的所有 init 脚本
# 按数字顺序执行

for i in /etc/init.d/S??* ;do
     # 检查文件是否存在
     [ ! -f "$i" ] && continue

     case "$i" in
        *.sh)
            # 为了速度，source shell 脚本
            (
                trap - INT QUIT TSTP
                set start
                . $i
            )
            ;;
        *)
            # 没有 sh 扩展名，所以 fork 子进程
            $i start
            ;;
    esac
done
```

**关键机制**：
1. **通配符匹配**：`S??*` 匹配所有 `S` 开头、后跟两位数字的文件
2. **按字母顺序执行**：shell 的通配符展开是按字母顺序的
3. **传递 start 参数**：每个脚本都接收 `start` 参数

#### 4.4.2 服务脚本命名规范

**命名格式**：`S##name`
- `S`：表示启动脚本（Start）
- `##`：两位数字，决定执行顺序（01-99）
- `name`：服务名称

**示例**：
```
/etc/init.d/
├── S01seedrng       # 01 - 最先执行
├── S01syslogd       # 01 - 同时执行
├── S02klogd         # 02 - 稍后执行
├── S10udev          # 10
├── S40network       # 40
├── S50sshd          # 50
└── S91smb           # 91 - 最后执行
```

**为什么用数字前缀**：
- 控制启动顺序
- 处理依赖关系（如网络服务依赖网络初始化）
- 简单直观

#### 4.4.3 服务启动顺序

从启动日志（stage5_init_services_cn.md）可以看到实际的启动顺序：

```
[    0.487194] process '/bin/busybox' started with executable stack
[    0.530970] EXT4-fs (mmcblk0p7): re-mounted. Opts: (null)
Seeding 256 bits and crediting                    ← S01seedrng
Saving 256 bits of creditable seed for next boot
Starting syslogd: OK                               ← S01syslogd
Starting klogd: OK                                 ← S02klogd
Running sysctl: OK                                 ← S02sysctl
Populating /dev using udev: done                   ← S10udev
Initializing random number generator... done.     ← S20urandom
Starting system message bus: done                  ← S30dbus
Starting bluetoothd: OK                            ← S40bluetoothd
Starting network: OK                               ← S40network
Starting ntpd: OK                                  ← S49ntp
Starting sshd: OK                                  ← S50sshd
Starting telnetd: OK                               ← S50telnet
Starting SMB services: OK                          ← S91smb
Starting NMB services: OK                          ← S91smb
```

**启动顺序表**：

| 顺序 | 脚本 | 服务 | 描述 | 为什么这个顺序 |
|------|------|------|------|----------------|
| 1 | S01seedrng | 随机种子 | 初始化随机数生成器 | 加密操作需要 |
| 2 | S01syslogd | 系统日志 | 系统日志守护进程 | 记录后续服务的日志 |
| 3 | S02klogd | 内核日志 | 内核日志守护进程 | 记录内核消息 |
| 4 | S02sysctl | Sysctl | 应用内核参数 | 调整内核行为 |
| 5 | S10udev | udev | 设备管理器 | 创建设备节点 |
| 6 | S20urandom | urandom | 随机数生成器 | 补充熵池 |
| 7 | S30dbus | D-Bus | 消息总线系统 | 进程间通信 |
| 8 | S40bluetoothd | 蓝牙 | 蓝牙守护进程 | 蓝牙功能 |
| 9 | S40network | 网络 | 网络初始化 | 配置网络接口 |
| 10 | S49ntp | NTP | 网络时间协议 | 依赖网络 |
| 11 | S50sshd | SSH | SSH 服务器 | 依赖网络 |
| 12 | S50telnet | Telnet | Telnet 服务器 | 依赖网络 |
| 13 | S91smb | Samba | 文件共享 | 依赖网络和 D-Bus |

#### 4.4.4 服务脚本结构

**标准服务脚本格式**（以 S50sshd 为例）：

```bash
#!/bin/sh
# /etc/init.d/S50sshd

DAEMON="sshd"
PIDFILE="/var/run/$DAEMON.pid"

start() {
    printf "Starting $DAEMON: "
    start-stop-daemon -S -q -p $PIDFILE --exec /usr/sbin/$DAEMON
    [ $? = 0 ] && echo "OK" || echo "FAIL"
}

stop() {
    printf "Stopping $DAEMON: "
    start-stop-daemon -K -q -p $PIDFILE
    [ $? = 0 ] && echo "OK" || echo "FAIL"
}

restart() {
    stop
    sleep 1
    start
}

case "$1" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart|reload)
        restart
        ;;
    *)
        echo "Usage: $0 {start|stop|restart}"
        exit 1
esac

exit $?
```

**关键要素**：
1. **Shebang**：`#!/bin/sh` 指定解释器
2. **start 函数**：启动服务
3. **stop 函数**：停止服务
4. **restart 函数**：重启服务
5. **case 语句**：根据参数执行不同操作

### 4.5 getty 等待登录

#### 4.5.1 init 启动 getty

在 `/etc/inittab` 中：
```
console::respawn:/sbin/getty -L console 0 vt100
```

**含义**：
- `action` 是 `respawn`：如果 getty 退出，自动重启
- `process` 是 `/sbin/getty -L console 0 vt100`

**getty 参数**：
- `-L`：本地行（不是调制解调器）
- `console`：终端设备（实际是 `/dev/console`）
- `0`：波特率（0 表示保持当前设置）
- `vt100`：终端类型

#### 4.5.2 getty 的作用

**getty（get tty）** 的职责：
1. 打开终端设备（`/dev/console`）
2. 设置终端参数（波特率、奇偶校验等）
3. 显示登录提示符
4. 读取用户名
5. 调用 `login` 程序验证身份

**getty 显示的提示符**：
```
Luckfox Pico login:
```

#### 4.5.3 终端设备

**什么是终端**：
- 终端是输入输出设备的抽象
- 在 Luckfox Pico 上，`console` 通常是串口

**查看终端设备**：
```bash
$ ls -l /dev/console
crw------- 1 root root 5, 1 Jan 26 00:00 /dev/console

$ ls -l /dev/ttyFIQ0
crw------- 1 root root 253, 0 Jan 26 00:00 /dev/ttyFIQ0
```

**设备号**：
- `5, 1`：主设备号 5，次设备号 1（console）
- `253, 0`：主设备号 253，次设备号 0（FIQ 调试器）

### 4.6 login 验证身份

#### 4.6.1 用户输入用户名

当你在 getty 提示符下输入用户名：
```
Luckfox Pico login: root
```

getty 读取用户名后，执行 `login` 程序：
```bash
/bin/login root
```

#### 4.6.2 login 验证密码

**login 的操作**：
1. 读取 `/etc/passwd` 获取用户信息
2. 读取 `/etc/shadow` 获取密码哈希
3. 提示输入密码
4. 验证密码是否正确
5. 如果正确，启动用户的 shell

**查看用户信息**：
```bash
$ cat /etc/passwd
root:x:0:0:root:/root:/bin/sh
```

**字段说明**：
- `root`：用户名
- `x`：密码占位符（实际密码在 `/etc/shadow`）
- `0`：用户 ID（UID）
- `0`：组 ID（GID）
- `root`：用户描述
- `/root`：主目录
- `/bin/sh`：登录 shell

**查看密码哈希**：
```bash
$ cat /etc/shadow
root:$1$xyz...:19000:0:99999:7:::
```

**字段说明**：
- `root`：用户名
- `$1$xyz...`：密码哈希（MD5）
- `19000`：上次修改密码的日期（从 1970-01-01 算起的天数）
- 其他字段：密码策略

#### 4.6.3 密码验证过程

```c
// login 程序（简化版）

char *username = read_username();  // 读取用户名
char *password = read_password();  // 读取密码（不回显）

// 从 /etc/shadow 读取密码哈希
char *hash = get_password_hash(username);

// 使用相同的算法计算输入密码的哈希
char *input_hash = crypt(password, hash);

// 比较哈希值
if (strcmp(hash, input_hash) == 0) {
    // 密码正确，启动 shell
    exec_shell(username);
} else {
    // 密码错误
    printf("Login incorrect\n");
    exit(1);
}
```

### 4.7 启动 Shell

#### 4.7.1 login 执行 shell

密码验证成功后，login 执行用户的 shell：

```c
// login 程序（简化版）

// 从 /etc/passwd 获取 shell 路径
char *shell = get_user_shell(username);  // "/bin/sh"

// 设置环境变量
setenv("HOME", "/root", 1);
setenv("USER", "root", 1);
setenv("SHELL", "/bin/sh", 1);
setenv("PATH", "/bin:/sbin:/usr/bin:/usr/sbin", 1);

// 切换到用户的主目录
chdir("/root");

// 执行 shell
execl("/bin/sh", "-sh", NULL);
```

**关键操作**：
1. 设置环境变量（HOME、USER、SHELL、PATH）
2. 切换到用户主目录
3. 使用 `execl()` 替换当前进程为 shell

**为什么 shell 名称是 `-sh`**：
- 第一个字符是 `-`，表示这是登录 shell
- 登录 shell 会读取配置文件（如 `.profile`）

#### 4.7.2 Shell 初始化

**shell 启动后的操作**：
1. 读取配置文件（如果是登录 shell）
   - `/etc/profile`（系统级配置）
   - `~/.profile`（用户级配置）
2. 设置提示符（PS1 环境变量）
3. 显示提示符
4. 等待用户输入

**查看 shell 进程**：
```bash
$ ps aux | grep sh
root       530  0.0  0.1   1644   612 S    -sh
```

**注意**：
- 命令显示为 `-sh`（登录 shell）
- PID 530
- 父进程是 getty 或 sshd

#### 4.7.3 Shell 提示符

**默认提示符**：
```bash
#
```

**提示符由 PS1 环境变量控制**：
```bash
$ echo $PS1
#

$ export PS1="[\u@\h \W]\$ "
[root@luckfox-pico ~]$
```

**PS1 转义序列**：
- `\u`：用户名
- `\h`：主机名
- `\W`：当前目录（basename）
- `\$`：`#`（root）或 `$`（普通用户）

#### 4.7.4 Shell 等待命令

**shell 的主循环**（简化版）：
```c
// shell 主循环

while (1) {
    // 显示提示符
    printf("# ");

    // 读取用户输入
    char *line = read_line();

    // 解析命令
    char **args = parse_line(line);

    // 执行命令
    execute_command(args);
}
```

**现在，你可以输入命令了**：
```bash
# ls
bin  dev  etc  home  lib  mnt  proc  root  sbin  sys  tmp  usr  var
```

### 4.8 完整流程图

```
时间轴：从内核启动到 shell 就绪

0.484s  内核挂载根文件系统
        ↓
0.484s  内核执行 /sbin/init (PID 1)
        ↓
0.487s  init 读取 /etc/inittab
        ↓
0.487s  init 执行 /etc/init.d/rcS (sysinit)
        ↓
        rcS 遍历 /etc/init.d/S??*
        ↓
0.531s  S01seedrng 启动
0.575s  S01syslogd 启动
0.625s  S02klogd 启动
        ...
9.448s  所有服务启动完成
        ↓
        init 启动 getty (respawn)
        ↓
        getty 打开 /dev/console
        ↓
        getty 显示登录提示符
        ↓
        用户输入用户名 "root"
        ↓
        getty 执行 /bin/login root
        ↓
        login 提示输入密码
        ↓
        用户输入密码
        ↓
        login 验证密码（读取 /etc/shadow）
        ↓
        密码正确
        ↓
        login 执行 /bin/sh (PID 530)
        ↓
        shell 读取配置文件
        ↓
        shell 显示提示符 "#"
        ↓
        等待用户输入命令
```

### 4.9 本章总结

**启动链条**：
```
内核 → init → rcS → 服务 → getty → login → shell
```

**关键进程**：
- **init (PID 1)**：所有进程的祖先，负责系统初始化
- **getty**：等待登录，显示提示符
- **login**：验证用户身份
- **shell**：命令解释器，等待用户输入

**关键配置文件**：
- `/etc/inittab`：init 配置
- `/etc/init.d/rcS`：启动脚本
- `/etc/init.d/S??*`：服务脚本
- `/etc/passwd`：用户信息
- `/etc/shadow`：密码哈希

**下一章预告**：
现在我们知道了如何到达 shell，下一章将详细解释当你在 shell 中输入 `ls` 命令时，系统如何使用 `fork() + exec()` 机制来执行它。

---

## 第 5 章：命令执行机制 - fork() + exec()

### 5.1 Shell 如何执行命令

当你在 shell 中输入命令时，shell 需要完成以下任务：

```bash
# ls -l /etc
```

**Shell 的处理流程**：
1. 读取用户输入：`ls -l /etc`
2. 解析命令行：提取命令名和参数
3. 在 PATH 中搜索可执行文件
4. 创建子进程执行命令
5. 等待命令完成
6. 显示新的提示符

#### 5.1.1 解析用户输入

**Shell 的解析步骤**：
```c
// Shell 解析命令（简化版）

char *line = "ls -l /etc";

// 1. 分词（按空格分割）
char *tokens[] = {"ls", "-l", "/etc", NULL};

// 2. 提取命令名
char *command = tokens[0];  // "ls"

// 3. 提取参数
char **args = tokens;  // {"ls", "-l", "/etc", NULL}
```

**为什么参数数组包含命令名**：
- `args[0]` 是命令名（`argv[0]`）
- `args[1]`, `args[2]`, ... 是实际参数
- 最后一个元素是 `NULL`（标记数组结束）

#### 5.1.2 在 PATH 中搜索

**PATH 环境变量**：
```bash
$ echo $PATH
/bin:/sbin:/usr/bin:/usr/sbin
```

**搜索过程**：
```c
// Shell 搜索可执行文件（简化版）

char *find_command(char *command) {
    // 如果命令包含 /，直接使用
    if (strchr(command, '/')) {
        return command;  // 如 "./myapp" 或 "/bin/ls"
    }

    // 获取 PATH 环境变量
    char *path = getenv("PATH");  // "/bin:/sbin:/usr/bin:/usr/sbin"

    // 分割 PATH
    char *dir = strtok(path, ":");
    while (dir != NULL) {
        // 构造完整路径
        char fullpath[256];
        snprintf(fullpath, sizeof(fullpath), "%s/%s", dir, command);

        // 检查文件是否存在且可执行
        if (access(fullpath, X_OK) == 0) {
            return strdup(fullpath);  // 找到了
        }

        dir = strtok(NULL, ":");
    }

    return NULL;  // 未找到
}
```

**搜索顺序**：
1. `/bin/ls` - 找到了！
2. 返回 `/bin/ls`

### 5.2 fork() 系统调用详解

#### 5.2.1 fork() 的作用

**fork()** 创建当前进程的完整副本。

**函数原型**：
```c
#include <unistd.h>

pid_t fork(void);
```

**返回值**：
- 在父进程中：返回子进程的 PID（正整数）
- 在子进程中：返回 0
- 失败：返回 -1

#### 5.2.2 fork() 的工作原理

**内核的操作**：
```
1. 分配新的 PID
   ↓
2. 创建新的进程控制块（PCB）
   ↓
3. 复制父进程的页表（写时复制 COW）
   ↓
4. 复制文件描述符表
   ↓
5. 复制环境变量
   ↓
6. 子进程继承父进程的代码位置
   ↓
7. 子进程进入就绪队列
   ↓
8. 返回到父进程和子进程
```

**写时复制（Copy-On-Write, COW）**：
- fork() 后，父子进程共享相同的物理内存页
- 页表标记为只读
- 当任一进程尝试写入时，触发页错误
- 内核复制该页，分配给写入的进程
- 这样避免了不必要的内存复制

#### 5.2.3 fork() 示例

```c
#include <stdio.h>
#include <unistd.h>

int main() {
    int x = 100;

    printf("Before fork: PID=%d, x=%d\n", getpid(), x);

    pid_t pid = fork();

    if (pid < 0) {
        // fork 失败
        perror("fork failed");
        return 1;
    } else if (pid == 0) {
        // 子进程
        x = 200;
        printf("Child: PID=%d, PPID=%d, x=%d\n", getpid(), getppid(), x);
    } else {
        // 父进程
        x = 300;
        printf("Parent: PID=%d, child_pid=%d, x=%d\n", getpid(), pid, x);
    }

    return 0;
}
```

**输出**：
```
Before fork: PID=530, x=100
Parent: PID=530, child_pid=540, x=300
Child: PID=540, PPID=530, x=200
```

**关键观察**：
- fork() 后，代码从同一位置继续执行
- 父子进程的 `x` 变量独立（写时复制）
- 子进程的 PPID 是父进程的 PID

#### 5.2.4 fork() 后的进程状态

```
fork() 之前：

父进程 (PID 530)
+------------------+
| 代码段            |
| 数据段: x=100    |
| 堆                |
| 栈                |
+------------------+

fork() 之后：

父进程 (PID 530)              子进程 (PID 540)
+------------------+          +------------------+
| 代码段 (共享)     |          | 代码段 (共享)     |
| 数据段: x=300    |          | 数据段: x=200    |
| 堆                |          | 堆 (复制)         |
| 栈                |          | 栈 (复制)         |
| 文件描述符 (复制) |          | 文件描述符 (复制) |
+------------------+          +------------------+
```

### 5.3 exec() 系统调用详解

#### 5.3.1 exec() 家族

**exec() 不是单一函数，而是一组函数**：

```c
int execl(const char *path, const char *arg, ...);
int execlp(const char *file, const char *arg, ...);
int execle(const char *path, const char *arg, ..., char *const envp[]);
int execv(const char *path, char *const argv[]);
int execvp(const char *file, char *const argv[]);
int execve(const char *path, char *const argv[], char *const envp[]);
```

**命名规则**：
- `l`（list）：参数以列表形式传递
- `v`（vector）：参数以数组形式传递
- `p`（path）：在 PATH 中搜索可执行文件
- `e`（environment）：指定环境变量

**最常用的**：
- `execl()`：参数列表，完整路径
- `execvp()`：参数数组，PATH 搜索

#### 5.3.2 exec() 的作用

**exec()** 用新程序替换当前进程的内存空间。

**关键特性**：
- PID 不变
- 进程的代码、数据、堆、栈全部被替换
- 如果成功，永远不会返回（因为原程序已被替换）
- 如果失败，返回 -1

#### 5.3.3 exec() 的工作原理

**内核的操作**：
```
1. 打开可执行文件
   ↓
2. 验证 ELF 格式
   ↓
3. 释放旧的内存映射
   ↓
4. 创建新的内存映射
   - 加载代码段（.text）
   - 加载数据段（.data）
   - 创建 BSS 段（清零）
   - 创建堆
   - 创建栈
   ↓
5. 如果是动态链接，加载动态链接器
   ↓
6. 设置 argv 和 envp
   ↓
7. 跳转到程序入口点
```

#### 5.3.4 exec() 示例

```c
#include <stdio.h>
#include <unistd.h>

int main() {
    printf("Before exec: PID=%d\n", getpid());

    // 执行 ls 命令
    execl("/bin/ls", "ls", "-l", "/etc", NULL);

    // 如果 exec 成功，下面的代码永远不会执行
    perror("exec failed");
    return 1;
}
```

**输出**：
```
Before exec: PID=540
total 48
drwxr-xr-x  2 root root 4096 Jan 26 /etc/init.d
-rw-r--r--  1 root root  123 Jan 26 /etc/inittab
...
```

**关键观察**：
- PID 不变（540）
- 程序被完全替换为 `ls`
- `perror()` 永远不会执行（除非 exec 失败）

#### 5.3.5 exec() 前后的进程状态

```
exec() 之前：

进程 (PID 540)
+------------------+
| 代码段: main()   |
| 数据段: 变量     |
| 堆                |
| 栈                |
+------------------+

execl("/bin/ls", "ls", "-l", "/etc", NULL)

exec() 之后：

进程 (PID 540) - 相同的 PID
+------------------+
| 代码段: ls 程序  |
| 数据段: ls 数据  |
| 堆: ls 使用      |
| 栈: ls 使用      |
+------------------+
```

### 5.4 wait() 系统调用

#### 5.4.1 wait() 的作用

**wait()** 让父进程等待子进程结束。

**函数原型**：
```c
#include <sys/wait.h>

pid_t wait(int *status);
pid_t waitpid(pid_t pid, int *status, int options);
```

**返回值**：
- 成功：返回终止的子进程 PID
- 失败：返回 -1

#### 5.4.2 为什么需要 wait()

**问题 1：僵尸进程**

如果父进程不调用 wait()，子进程终止后会变成僵尸进程：
```bash
$ ps aux | grep Z
root       540  0.0  0.0      0     0 ?        Z    10:30   0:00 [ls] <defunct>
```

**僵尸进程的特征**：
- 进程已终止，但 PCB 仍然存在
- 占用 PID，但不占用内存
- 状态显示为 `Z`（Zombie）
- 需要父进程调用 wait() 回收

**问题 2：父进程需要知道子进程的退出状态**

```c
int status;
pid_t pid = wait(&status);

if (WIFEXITED(status)) {
    printf("Child exited with code %d\n", WEXITSTATUS(status));
}
```

#### 5.4.3 wait() 示例

```c
#include <stdio.h>
#include <unistd.h>
#include <sys/wait.h>

int main() {
    pid_t pid = fork();

    if (pid == 0) {
        // 子进程
        printf("Child: PID=%d, sleeping 2 seconds\n", getpid());
        sleep(2);
        printf("Child: exiting\n");
        return 42;  // 退出码
    } else {
        // 父进程
        printf("Parent: waiting for child %d\n", pid);

        int status;
        pid_t terminated_pid = wait(&status);

        printf("Parent: child %d terminated\n", terminated_pid);

        if (WIFEXITED(status)) {
            printf("Parent: child exit code = %d\n", WEXITSTATUS(status));
        }
    }

    return 0;
}
```

**输出**：
```
Parent: waiting for child 540
Child: PID=540, sleeping 2 seconds
Child: exiting
Parent: child 540 terminated
Parent: child exit code = 42
```

### 5.5 完整示例：执行 ls 命令

#### 5.5.1 Shell 执行命令的完整代码

```c
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/wait.h>
#include <string.h>

void execute_command(char **args) {
    pid_t pid = fork();

    if (pid < 0) {
        // fork 失败
        perror("fork failed");
        return;
    } else if (pid == 0) {
        // 子进程：执行命令
        execvp(args[0], args);

        // 如果 exec 失败
        perror("exec failed");
        exit(1);
    } else {
        // 父进程：等待子进程
        int status;
        waitpid(pid, &status, 0);

        if (WIFEXITED(status) && WEXITSTATUS(status) != 0) {
            printf("Command failed with exit code %d\n", WEXITSTATUS(status));
        }
    }
}

int main() {
    // 模拟执行 "ls -l /etc"
    char *args[] = {"ls", "-l", "/etc", NULL};

    printf("Shell: executing command\n");
    execute_command(args);
    printf("Shell: command completed\n");

    return 0;
}
```

#### 5.5.2 执行流程图

```
时间轴：执行 "ls -l /etc" 命令

父进程 (shell, PID 530)
    |
    | 1. 解析命令 "ls -l /etc"
    |    args = {"ls", "-l", "/etc", NULL}
    |
    | 2. 调用 fork()
    |
    +------------------+
    |                  |
父进程 (PID 530)    子进程 (PID 540)
    |                  |
    | fork() 返回 540  | fork() 返回 0
    |                  |
    | 3. 调用 wait()   | 3. 调用 execvp("ls", args)
    |    (阻塞等待)    |
    |                  | 4. 内核加载 /bin/ls
    |                  |    - 释放旧内存
    |                  |    - 加载 ls 程序
    |                  |    - 跳转到 ls 的 main()
    |                  |
    |                  | 5. ls 程序执行
    |                  |    - 打开 /etc 目录
    |                  |    - 读取目录项
    |                  |    - 输出到标准输出
    |                  |
    |                  | 6. ls 调用 exit(0)
    |                  |    - 进程终止
    |                  |    - 变成僵尸进程
    |                  |    - 向父进程发送 SIGCHLD
    |                  X
    |
    | 7. wait() 返回
    |    - 回收子进程
    |    - 获取退出状态
    |
    | 8. 显示新的提示符
    |
    V
```

#### 5.5.3 进程状态变化

```
1. 初始状态：
   父进程 (shell, PID 530) - 运行中

2. fork() 后：
   父进程 (shell, PID 530) - 运行中
   子进程 (shell 副本, PID 540) - 就绪

3. 父进程调用 wait()：
   父进程 (shell, PID 530) - 睡眠（等待子进程）
   子进程 (shell 副本, PID 540) - 运行中

4. 子进程调用 exec()：
   父进程 (shell, PID 530) - 睡眠
   子进程 (ls 程序, PID 540) - 运行中

5. 子进程执行完毕：
   父进程 (shell, PID 530) - 睡眠
   子进程 (ls 程序, PID 540) - 僵尸

6. 父进程回收子进程：
   父进程 (shell, PID 530) - 运行中
   子进程 - 已回收（不存在）
```

### 5.6 为什么使用 fork + exec 而不是直接创建

#### 5.6.1 设计哲学

**Unix 的设计哲学**：
- 每个系统调用做好一件事
- fork() 负责创建进程
- exec() 负责加载程序
- 两者组合提供最大灵活性

#### 5.6.2 fork + exec 的优势

**优势 1：在 exec 之前可以做准备工作**

```c
pid_t pid = fork();

if (pid == 0) {
    // 子进程：在 exec 之前做准备

    // 1. 重定向标准输出到文件
    int fd = open("output.txt", O_WRONLY | O_CREAT, 0644);
    dup2(fd, STDOUT_FILENO);
    close(fd);

    // 2. 改变工作目录
    chdir("/tmp");

    // 3. 设置环境变量
    setenv("MY_VAR", "value", 1);

    // 4. 关闭不需要的文件描述符
    close(3);
    close(4);

    // 5. 现在执行程序
    execl("/bin/ls", "ls", "-l", NULL);
}
```

**优势 2：实现管道**

```bash
# ls | grep txt
```

```c
int pipefd[2];
pipe(pipefd);  // 创建管道

pid_t pid1 = fork();
if (pid1 == 0) {
    // 子进程 1：ls
    close(pipefd[0]);  // 关闭读端
    dup2(pipefd[1], STDOUT_FILENO);  // 重定向标准输出到管道
    close(pipefd[1]);
    execl("/bin/ls", "ls", NULL);
}

pid_t pid2 = fork();
if (pid2 == 0) {
    // 子进程 2：grep
    close(pipefd[1]);  // 关闭写端
    dup2(pipefd[0], STDIN_FILENO);  // 重定向标准输入从管道
    close(pipefd[0]);
    execl("/bin/grep", "grep", "txt", NULL);
}

// 父进程
close(pipefd[0]);
close(pipefd[1]);
wait(NULL);
wait(NULL);
```

**优势 3：实现后台执行**

```bash
# ls &
```

```c
pid_t pid = fork();

if (pid == 0) {
    // 子进程
    execl("/bin/ls", "ls", NULL);
} else {
    // 父进程：不调用 wait()，立即返回
    printf("[1] %d\n", pid);
    // 继续显示提示符
}
```

#### 5.6.3 如果只有一个 spawn() 系统调用

假设有一个 `spawn()` 系统调用直接创建并执行程序：

```c
// 假设的 spawn() 函数
pid_t spawn(const char *path, char *const argv[]);
```

**问题**：
- 无法在执行前重定向 I/O
- 无法在执行前改变工作目录
- 无法实现管道
- 无法实现后台执行
- 灵活性大大降低

**fork + exec 的灵活性**：
```
fork() → 准备环境 → exec()
         ↑
         可以做任何事：
         - 重定向 I/O
         - 改变目录
         - 设置环境变量
         - 创建管道
         - 等等
```

### 5.7 本章总结

**核心机制**：
1. **fork()**：创建子进程（复制父进程）
2. **exec()**：用新程序替换当前进程
3. **wait()**：等待子进程结束并回收资源

**命令执行流程**：
```
shell 解析命令 → fork() 创建子进程 → 子进程 exec() 加载程序 → 父进程 wait() 等待 → 回收子进程
```

**关键概念**：
- fork() 后父子进程从同一位置继续执行
- exec() 成功后永远不会返回
- wait() 防止僵尸进程
- fork + exec 提供最大灵活性

**为什么这样设计**：
- 符合 Unix 哲学（每个系统调用做好一件事）
- 在 exec 之前可以准备环境
- 可以实现管道、重定向、后台执行等高级功能

**下一章预告**：
现在我们理解了二进制程序的执行机制，下一章将解释脚本文件（如 `.sh` 文件）是如何通过 Shebang 机制执行的。

---

## 第 6 章：脚本执行机制 - Shebang

### 6.1 什么是脚本

#### 6.1.1 脚本 vs 二进制程序

**二进制程序**：
- 包含机器码（CPU 可以直接执行的指令）
- 编译后的可执行文件（ELF 格式）
- 例如：`/bin/ls`、`/bin/cat`

**脚本**：
- 包含文本指令（需要解释器执行）
- 纯文本文件
- 例如：Shell 脚本、Python 脚本

**对比**：
```bash
# 二进制程序
$ file /bin/ls
/bin/ls: ELF 32-bit LSB executable, ARM

# 脚本文件
$ file /etc/init.d/rcS
/etc/init.d/rcS: POSIX shell script, ASCII text executable
```

#### 6.1.2 脚本需要解释器

**解释器**：读取脚本内容并执行的程序

**常见解释器**：
- `/bin/sh`：Shell 脚本解释器
- `/usr/bin/python3`：Python 解释器
- `/usr/bin/perl`：Perl 解释器
- `/usr/bin/env`：环境变量查找解释器

**手动执行脚本**：
```bash
# 方式 1：显式指定解释器
$ /bin/sh /etc/init.d/rcS

# 方式 2：使用 Shebang 直接执行
$ /etc/init.d/rcS
```

### 6.2 Shebang（#!）机制

#### 6.2.1 什么是 Shebang

**Shebang** 是脚本文件第一行的特殊标记：

```bash
#!/bin/sh
```

**组成**：
- `#!`：魔数（Magic Number），固定的两个字节（0x23 0x21）
- `/bin/sh`：解释器的完整路径

**作用**：
- 告诉内核使用哪个解释器执行脚本
- 使脚本可以像二进制程序一样直接执行

#### 6.2.2 Shebang 的工作原理

**内核识别 Shebang**：

```c
// 内核代码（简化版）
// fs/binfmt_script.c

static int load_script(struct linux_binprm *bprm) {
    char *cp;
    char *i_name, *i_arg;

    // 检查文件头是否是 #!
    if ((bprm->buf[0] != '#') || (bprm->buf[1] != '!'))
        return -ENOEXEC;

    // 提取解释器路径
    i_name = bprm->buf + 2;  // 跳过 #!

    // 提取解释器参数（如果有）
    i_arg = strchr(i_name, ' ');

    // 重新执行：解释器 脚本路径
    return exec_interpreter(i_name, i_arg, bprm->filename);
}
```

**执行流程**：
```
1. 用户执行：./script.sh
   ↓
2. 内核读取文件头（前 128 字节）
   ↓
3. 发现 #! 魔数
   ↓
4. 提取解释器路径：/bin/sh
   ↓
5. 重新执行：/bin/sh ./script.sh
   ↓
6. Shell 解释器读取脚本内容
   ↓
7. 逐行解释执行
```

#### 6.2.3 Shebang 示例

**示例脚本**：
```bash
#!/bin/sh
# /tmp/test.sh

echo "Hello from shell script"
echo "PID: $$"
echo "Script: $0"
```

**执行过程**：
```bash
$ chmod +x /tmp/test.sh
$ /tmp/test.sh
Hello from shell script
PID: 540
Script: /tmp/test.sh
```

**实际发生的事情**：
```
1. 用户执行：/tmp/test.sh
2. 内核读取文件头，发现 #!/bin/sh
3. 内核重新执行：/bin/sh /tmp/test.sh
4. Shell 读取脚本内容并执行
```

**验证**：
```bash
# 手动执行（等同于 Shebang 的效果）
$ /bin/sh /tmp/test.sh
Hello from shell script
PID: 541
Script: /tmp/test.sh
```

### 6.3 两种脚本执行方式

#### 6.3.1 Fork 方式：创建子进程

**标准执行方式**（rcS 中的默认方式）：

```bash
#!/bin/sh
# /etc/init.d/rcS

for i in /etc/init.d/S??* ;do
    [ ! -f "$i" ] && continue

    # Fork 方式：创建子进程执行
    $i start
done
```

**特点**：
- 创建新的子进程
- 脚本在独立的环境中执行
- 脚本中的变量不影响父进程
- 脚本退出后，子进程终止

**示例**：
```bash
# 父进程
VAR="parent"
echo "Before: VAR=$VAR"

# Fork 方式执行脚本
./script.sh

echo "After: VAR=$VAR"  # 仍然是 "parent"
```

#### 6.3.2 Source 方式：在当前 Shell 执行

**Source 方式**（rcS 中对 .sh 文件的处理）：

```bash
#!/bin/sh
# /etc/init.d/rcS

for i in /etc/init.d/S??* ;do
    [ ! -f "$i" ] && continue

    case "$i" in
        *.sh)
            # Source 方式：在当前 shell 执行
            . $i
            ;;
        *)
            # Fork 方式
            $i start
            ;;
    esac
done
```

**特点**：
- 不创建子进程
- 脚本在当前 shell 环境中执行
- 脚本中的变量会影响当前 shell
- 执行速度更快（无进程创建开销）

**示例**：
```bash
# 父进程
VAR="parent"
echo "Before: VAR=$VAR"

# Source 方式执行脚本
. ./script.sh  # 或 source ./script.sh

echo "After: VAR=$VAR"  # 可能被脚本修改
```

#### 6.3.3 对比

| 特性 | Fork 方式 | Source 方式 |
|------|----------|-------------|
| 命令 | `./script.sh` 或 `script.sh` | `. script.sh` 或 `source script.sh` |
| 子进程 | 创建 | 不创建 |
| 变量作用域 | 独立 | 共享 |
| 环境变量 | 继承但不影响父进程 | 可以修改父进程环境 |
| 执行速度 | 慢（创建进程） | 快（无进程创建） |
| 退出影响 | 只终止子进程 | 可能终止当前 shell |
| 使用场景 | 独立脚本 | 配置文件、函数库 |

### 6.4 脚本执行流程

#### 6.4.1 完整执行流程

**用户执行脚本**：
```bash
$ ./myscript.sh arg1 arg2
```

**详细步骤**：
```
1. Shell 解析命令
   - 命令：./myscript.sh
   - 参数：arg1, arg2
   ↓
2. Shell 调用 fork()
   - 创建子进程
   ↓
3. 子进程调用 execve("./myscript.sh", ["./myscript.sh", "arg1", "arg2"], envp)
   ↓
4. 内核读取文件头
   - 读取前 128 字节
   - 发现 #! 魔数
   ↓
5. 内核提取解释器路径
   - 解析 #!/bin/sh
   - 提取 /bin/sh
   ↓
6. 内核重新执行
   - execve("/bin/sh", ["/bin/sh", "./myscript.sh", "arg1", "arg2"], envp)
   ↓
7. Shell 解释器启动
   - 打开 ./myscript.sh
   - 读取脚本内容
   ↓
8. Shell 逐行执行
   - 解析每一行
   - 执行命令
   ↓
9. 脚本执行完毕
   - Shell 调用 exit()
   - 子进程终止
   ↓
10. 父进程回收子进程
    - wait() 返回
    - 显示新提示符
```

#### 6.4.2 与二进制执行的对比

**二进制程序执行**：
```
fork() → exec("/bin/ls") → 内核加载 ELF → 跳转到程序入口 → 执行机器码
```

**脚本执行**：
```
fork() → exec("./script.sh") → 内核发现 #! → exec("/bin/sh") → Shell 读取脚本 → 解释执行
```

**关键区别**：
- 二进制：内核直接加载并执行
- 脚本：内核启动解释器，解释器读取并执行脚本

### 6.5 常见解释器

#### 6.5.1 Shell 脚本

```bash
#!/bin/sh
echo "This is a shell script"
```

**解释器**：`/bin/sh`（通常是 busybox）

**用途**：
- 系统启动脚本
- 自动化任务
- 简单的文本处理

#### 6.5.2 Python 脚本

```python
#!/usr/bin/python3
print("This is a Python script")
```

**解释器**：`/usr/bin/python3`

**用途**：
- 复杂的数据处理
- Web 应用
- 科学计算

#### 6.5.3 使用 env 查找解释器

```bash
#!/usr/bin/env python3
print("This is a Python script")
```

**解释器**：`/usr/bin/env`

**优势**：
- 不需要硬编码解释器路径
- `env` 在 PATH 中查找 `python3`
- 提高脚本的可移植性

**工作原理**：
```
1. 内核执行：/usr/bin/env python3 script.py
2. env 在 PATH 中搜索 python3
3. env 找到 /usr/bin/python3
4. env 执行：/usr/bin/python3 script.py
```

### 6.6 服务脚本执行示例

#### 6.6.1 S50sshd 脚本

```bash
#!/bin/sh
# /etc/init.d/S50sshd

case "$1" in
    start)
        echo "Starting sshd: "
        /usr/sbin/sshd
        echo "OK"
        ;;
    stop)
        echo "Stopping sshd: "
        killall sshd
        echo "OK"
        ;;
    *)
        echo "Usage: $0 {start|stop}"
        exit 1
esac
```

#### 6.6.2 rcS 如何执行服务脚本

**rcS 执行**：
```bash
for i in /etc/init.d/S??* ;do
    $i start  # Fork 方式执行
done
```

**实际发生的事情**：
```
1. rcS 执行：/etc/init.d/S50sshd start
   ↓
2. rcS 调用 fork()
   ↓
3. 子进程调用 exec("/etc/init.d/S50sshd", ["S50sshd", "start"])
   ↓
4. 内核发现 #!/bin/sh
   ↓
5. 内核重新执行：/bin/sh /etc/init.d/S50sshd start
   ↓
6. Shell 读取脚本
   ↓
7. Shell 执行 case 语句
   ↓
8. 匹配 "start" 分支
   ↓
9. 执行 /usr/sbin/sshd
   ↓
10. sshd 启动（守护进程）
   ↓
11. 脚本退出
```

### 6.7 本章总结

**核心概念**：
1. **Shebang（#!）**：脚本第一行的魔数，指定解释器
2. **内核识别**：内核读取文件头，发现 #! 后重新执行解释器
3. **两种方式**：Fork（独立进程）和 Source（当前 shell）

**脚本执行流程**：
```
用户执行脚本 → 内核发现 #! → 提取解释器路径 → 执行解释器 → 解释器读取脚本 → 逐行执行
```

**与二进制的区别**：
- 二进制：内核直接加载 ELF 并执行机器码
- 脚本：内核启动解释器，解释器读取并解释执行

**实际应用**：
- 系统启动脚本（`/etc/init.d/S*`）使用 Shebang
- rcS 使用 Fork 方式执行服务脚本
- 配置文件使用 Source 方式加载

**下一章预告**：
现在我们理解了脚本执行机制，下一章将总结服务自动启动的完整机制，并补充进程生命周期的知识。

---

## 第 7 章：服务自动启动与进程生命周期

### 7.1 服务自动启动机制总结

#### 7.1.1 完整启动链

```
内核启动 init (PID 1)
    ↓
init 读取 /etc/inittab
    ↓
::sysinit:/etc/init.d/rcS
    ↓
rcS 遍历 /etc/init.d/S??*
    ↓
按数字顺序执行服务脚本
    ↓
每个服务脚本接收 "start" 参数
    ↓
服务启动（守护进程）
```

#### 7.1.2 为什么服务会自动启动

**关键机制**：
1. **inittab 配置**：`::sysinit:/etc/init.d/rcS` 告诉 init 执行 rcS
2. **rcS 脚本**：遍历所有 `S??*` 脚本并执行
3. **数字前缀**：控制启动顺序（S01、S02、...、S91）
4. **start 参数**：每个脚本接收 `start` 参数
5. **守护进程**：服务以守护进程方式在后台运行

#### 7.1.3 守护进程（Daemon）

**什么是守护进程**：
- 在后台运行的进程
- 不与终端关联
- 通常在系统启动时启动
- 持续运行直到系统关机

**守护进程的特征**：
```bash
$ ps aux | grep sshd
root       180  0.0  0.3   3256  1024 ?        Ss   00:00   0:00 /usr/sbin/sshd
```
- TTY 列显示 `?`（无终端）
- STAT 列包含 `s`（会话领导者）

**如何创建守护进程**（简化版）：
```c
// 1. fork 并让父进程退出
pid_t pid = fork();
if (pid > 0) exit(0);  // 父进程退出

// 2. 创建新会话
setsid();

// 3. 改变工作目录
chdir("/");

// 4. 关闭标准输入输出
close(STDIN_FILENO);
close(STDOUT_FILENO);
close(STDERR_FILENO);

// 5. 执行守护进程的主循环
while (1) {
    // 守护进程的工作
}
```

### 7.2 进程生命周期

#### 7.2.1 进程创建

**创建步骤**：
```
1. fork() 系统调用
   - 内核分配新 PID
   - 复制父进程的 PCB
   - 复制页表（写时复制）
   - 复制文件描述符表
   ↓
2. 子进程进入就绪队列
   ↓
3. 调度器选择进程执行
   ↓
4. 子进程开始运行
```

#### 7.2.2 进程执行

**进程状态转换**：
```
[新建] → [就绪] ⇄ [运行] → [终止]
           ↑       ↓
           └─ [阻塞]
```

**状态说明**：
- **就绪**：等待 CPU 调度
- **运行**：正在 CPU 上执行
- **阻塞**：等待 I/O 或事件
- **终止**：进程结束

#### 7.2.3 进程终止

**正常终止**：
```c
// 方式 1：main 函数返回
int main() {
    return 0;  // 退出码 0
}

// 方式 2：调用 exit()
exit(0);

// 方式 3：调用 _exit()
_exit(0);
```

**异常终止**：
- 收到信号（SIGKILL、SIGSEGV 等）
- 程序崩溃（段错误、除零等）

#### 7.2.4 僵尸进程与孤儿进程

**僵尸进程（Zombie）**：
- 进程已终止，但父进程未调用 wait()
- PCB 仍然存在，占用 PID
- 状态显示为 `Z`

**如何避免**：
```c
// 父进程必须调用 wait()
pid_t pid = fork();
if (pid == 0) {
    // 子进程
    exit(0);
} else {
    // 父进程
    wait(NULL);  // 回收子进程
}
```

**孤儿进程（Orphan）**：
- 父进程已终止，子进程仍在运行
- init 进程（PID 1）自动收养孤儿进程
- init 会调用 wait() 回收孤儿进程

### 7.3 Linux vs 单片机对比

#### 7.3.1 单片机模型

```c
// 单片机程序
int main() {
    // 初始化硬件
    init_gpio();
    init_uart();
    init_timer();

    // 主循环
    while(1) {
        if (button_pressed()) {
            led_on();
        } else {
            led_off();
        }
    }
}
```

**特点**：
- 单一程序（固件）
- 编译时确定所有功能
- 直接访问硬件寄存器
- 无操作系统
- 无进程概念

#### 7.3.2 Linux 模型

```bash
# Linux 系统
$ ls        # 运行 ls 程序
$ cat file  # 运行 cat 程序
$ ./myapp   # 运行自定义程序
```

**特点**：
- 多进程并发
- 动态加载程序
- 硬件抽象层（驱动）
- 操作系统管理
- 可交互

#### 7.3.3 关键区别

| 特性 | 单片机 | Linux |
|------|--------|-------|
| 程序数量 | 1 个（固件） | 多个（动态加载） |
| 内存管理 | 无（直接访问） | 虚拟内存（隔离） |
| 硬件访问 | 直接访问寄存器 | 通过驱动和系统调用 |
| 多任务 | 无或简单调度 | 完整的进程调度 |
| 交互性 | 固定功能 | 命令行交互 |
| 更新方式 | 重新烧录固件 | 安装新程序 |
| 开发方式 | 编译整个固件 | 独立编译程序 |

#### 7.3.4 为什么 Linux 是"可交互的小型电脑"

**动态加载程序**：
```bash
# 不需要重新编译系统
$ ./new_program  # 直接运行新程序
```

**Shell 提供交互界面**：
```bash
# 可以随时输入命令
$ ls
$ cat file
$ ./myapp
```

**进程隔离**：
```
进程 A 崩溃 → 不影响进程 B
命令失败 → shell 继续运行
```

**文件系统**：
```
程序存储在文件系统中
可以随时添加、删除、修改
```

### 7.4 实践验证

#### 7.4.1 查看进程信息

```bash
# 查看所有进程
$ ps aux

# 查看进程树
$ pstree

# 查看特定进程
$ ps -p 1  # 查看 init 进程
```

#### 7.4.2 查看进程状态

```bash
# 查看进程详细信息
$ cat /proc/1/status

# 查看进程命令行
$ cat /proc/1/cmdline

# 查看进程环境变量
$ cat /proc/1/environ
```

#### 7.4.3 手动执行服务脚本

```bash
# 启动服务
$ /etc/init.d/S50sshd start

# 停止服务
$ /etc/init.d/S50sshd stop

# 重启服务
$ /etc/init.d/S50sshd restart
```

### 7.5 本章总结

**服务自动启动**：
```
init → inittab → rcS → S??* 脚本 → 服务启动
```

**进程生命周期**：
```
创建（fork） → 执行（运行/阻塞） → 终止（exit） → 回收（wait）
```

**Linux vs 单片机**：
- 单片机：单一固件，固定功能
- Linux：多进程，动态加载，可交互

**核心优势**：
- 进程隔离（安全）
- 动态加载（灵活）
- Shell 交互（易用）
- 文件系统（可扩展）

---

## 第 8 章：总结

### 8.1 核心概念回顾

**1. 可执行文件（ELF）**：
- Linux 的标准可执行文件格式
- 包含代码、数据、符号表
- 内核知道如何加载和执行

**2. 进程（Process）**：
- 程序的运行实例
- 独立的内存空间和 PID
- Linux 命令执行的基本单元

**3. 系统调用**：
- fork()：创建子进程
- exec()：用新程序替换当前进程
- wait()：等待子进程结束

**4. Shebang（#!）**：
- 脚本第一行的魔数
- 指定解释器路径
- 使脚本可以直接执行

### 8.2 完整执行流程

**从开机到执行命令**：

```
1. 硬件上电
   ↓
2. U-Boot 加载内核
   ↓
3. 内核初始化
   ↓
4. 内核挂载根文件系统
   ↓
5. 内核执行 /sbin/init (PID 1)
   ↓
6. init 读取 /etc/inittab
   ↓
7. init 执行 /etc/init.d/rcS
   ↓
8. rcS 启动所有服务（S01*, S02*, ...）
   ↓
9. init 启动 getty
   ↓
10. getty 显示登录提示符
   ↓
11. 用户登录
   ↓
12. login 启动 shell
   ↓
13. shell 等待命令
   ↓
14. 用户输入命令（如 ls）
   ↓
15. shell 调用 fork()
   ↓
16. 子进程调用 exec()
   ↓
17. 内核加载程序
   ↓
18. 程序执行
   ↓
19. 程序退出
   ↓
20. shell 回收子进程
   ↓
21. shell 显示新提示符
```

### 8.3 四个核心问题的答案

**问题 1：为什么登录后能运行 ls 命令？**

**答案**：
1. Shell 解析命令 `ls`
2. 在 PATH 中找到 `/bin/ls`
3. 调用 fork() 创建子进程
4. 子进程调用 exec() 加载 ls 程序
5. ls 执行并输出结果
6. Shell 调用 wait() 回收子进程

**问题 2：为什么能执行 .sh 脚本？**

**答案**：
1. 脚本第一行有 Shebang（`#!/bin/sh`）
2. 内核读取文件头，发现 `#!` 魔数
3. 内核提取解释器路径 `/bin/sh`
4. 内核重新执行：`/bin/sh script.sh`
5. Shell 解释器读取脚本并逐行执行

**问题 3：为什么服务会自动启动？**

**答案**：
1. init 读取 `/etc/inittab`
2. inittab 指定执行 `/etc/init.d/rcS`
3. rcS 遍历所有 `S??*` 脚本
4. 按数字顺序执行每个脚本
5. 每个脚本启动对应的服务

**问题 4：Linux 与单片机的本质区别？**

**答案**：
- **单片机**：单一固件，编译时确定功能，无进程概念
- **Linux**：多进程系统，动态加载程序，进程隔离，可交互

### 8.4 关键技术点

**fork() + exec() 机制**：
- Unix 的核心设计
- fork() 创建进程，exec() 加载程序
- 提供最大灵活性（重定向、管道、后台执行）

**进程隔离**：
- 每个进程有独立的内存空间
- 进程崩溃不影响其他进程
- 提供安全性和稳定性

**Shebang 机制**：
- 使脚本可以像二进制程序一样执行
- 内核自动识别并启动解释器
- 提高脚本的易用性

**Init 系统**：
- PID 1，所有进程的祖先
- 负责系统初始化和服务管理
- 回收孤儿进程

### 8.5 与其他文档的关联

```
文档体系：

1. 设备树与硬件初始化
   └→ 解释：硬件如何被识别和初始化

2. Buildroot 与根文件系统构建
   └→ 解释：静态文件如何生成

3. Linux 运行机制（本文档）
   └→ 解释：静态文件如何在运行时执行

完整链条：
硬件 → 设备树 → 驱动 → 内核 → 根文件系统 → 进程执行
```

### 8.6 进一步学习

**推荐阅读**：
1. 《Unix 环境高级编程》（APUE）- 系统调用和进程管理
2. 《深入理解 Linux 内核》- 内核机制
3. 《Linux 命令行与 Shell 脚本编程大全》- Shell 编程

**实践建议**：
1. 编写简单的 C 程序，使用 fork() 和 exec()
2. 编写 Shell 脚本，理解 Shebang 机制
3. 修改 init 脚本，添加自定义服务
4. 使用 strace 追踪系统调用

### 8.7 最终总结

**Linux 运行机制的本质**：

1. **静态层**（Buildroot 生成）：
   - 可执行文件（ELF 格式）
   - 脚本文件（带 Shebang）
   - 配置文件（inittab、rcS）

2. **动态层**（运行时执行）：
   - 进程（fork + exec）
   - 系统调用（内核服务）
   - 进程调度（CPU 分配）

3. **交互层**（用户界面）：
   - Shell（命令解释器）
   - 终端（输入输出）
   - 文件系统（程序存储）

**为什么 Linux 是"可交互的小型电脑"**：

- **动态性**：可以随时运行新程序
- **隔离性**：进程之间互不干扰
- **灵活性**：fork + exec 提供强大功能
- **交互性**：Shell 提供命令行界面
- **可扩展性**：文件系统存储程序

**从单片机到 Linux 的思维转变**：

```
单片机思维：
编写固件 → 编译 → 烧录 → 运行固定功能

Linux 思维：
系统启动 → Shell 就绪 → 动态执行程序 → 进程管理
```

现在你应该理解了：
- ✅ 为什么能运行 `ls` 命令
- ✅ 为什么能执行 `.sh` 脚本
- ✅ 为什么服务会自动启动
- ✅ Linux 与单片机的本质区别

**Linux 不是一个固定的程序，而是一个可以动态加载和执行程序的操作系统平台。**

---

## 文档完成

本文档详细介绍了 Linux 运行机制，从可执行文件格式到进程执行，从启动流程到命令执行，从脚本机制到服务管理，帮助你理解 Linux 如何从静态文件变成动态运行的系统。

希望这份文档能帮助你建立对 Linux 运行机制的完整认知！
