# Nasio（私有 NAS 智能中枢与资产管家）

<p align="center">
  <img src="client/assets/icons/app_icon.png" alt="Nasio Logo" width="128" height="128" onerror="this.style.display='none'"/>
</p>

<p align="center">
  <strong>专为私有 NAS（特别优化适配绿联 UGOS / UGOS Pro，兼容群晖 Synology、威联通 QNAP、Unraid 及通用 Linux）打造的 AI Agent 原生智能中枢平台 + 跨平台现代化管理控制台。</strong>
</p>

<p align="center">
  <a href="https://www.python.org/"><img src="https://img.shields.io/badge/Python-3.11+-blue.svg" alt="Python 3.11+"></a>
  <a href="https://fastapi.tiangolo.com/"><img src="https://img.shields.io/badge/FastAPI-0.115+-009688.svg" alt="FastAPI"></a>
  <a href="https://flutter.dev/"><img src="https://img.shields.io/badge/Flutter-3.x-02569B.svg" alt="Flutter 3.x"></a>
  <a href="https://modelcontextprotocol.io/"><img src="https://img.shields.io/badge/Model_Context_Protocol-1.2+-purple.svg" alt="MCP Ready"></a>
  <a href="https://www.docker.com/"><img src="https://img.shields.io/badge/Docker-Compose_Ready-2496ED.svg" alt="Docker"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-green.svg" alt="License MIT"></a>
</p>

---

## 📖 项目简介 (Introduction)

**Nasio** 是一套开箱即用的私有 NAS 智能数字化资产管理系统。项目采用**服务端（Server）与客户端（Client）一体化架构**：
- **服务端 (`server/`)**：基于 Python 3.11 与 FastAPI 构建，内嵌 Anthropic 推出的 **Model Context Protocol (MCP)** 原生服务通道（支持 SSE 与 Streamable HTTP），开放 26+ 高阶原子工具，赋予外部 AI 智能体（如 Antigravity、Claude Desktop、Cursor、Cherry Studio、Dify 等）直接、安全治理私有 NAS 的能力。
- **客户端 (`client/`)**：基于 Flutter 3.x 打造的现代化全平台管理控制台，支持 **Web、Android、iOS、Windows、macOS、Linux**。提供自适应响应式布局、实时下载监控、智能体任务协同大屏、防灾回收站与连接配置中心。

---

## 🌟 核心特性 (Features)

### 1. 🤖 AI 智能体协议原生赋能 (MCP over SSE & HTTP)
- **多通道协议兼容**：支持标准 SSE (`/sse`) 与 Streamable HTTP (`/mcp`) 传输通道。
- **26+ 原子级 MCP 工具覆盖**：
  - **系统运维**：磁盘健康、白名单路径、存储空间监测 (`get_system_status`, `get_mcp_config`)。
  - **下载治理**：支持 qBittorrent、内置引擎（yt-dlp、HTTP 多线程并发）、aria2 自动路由与管理 (`create_download_task`, `get_task_status`, `cancel_task`)。
  - **文件治理沙箱**：全盘查重扫描、目录树折叠、批量重命名、智能剧集归档季数识别、压缩包解压 (`search_files`, `find_duplicate_files`, `batch_organize_files`, `organize_series_seasons`, `extract_archive`)。
  - **防灾隔离回收站**：软删除至安全隔离区，支持审计日志元数据与一键还原 (`safe_delete_files`, `list_trash_files`, `restore_trash_file`)。
  - **智能体闭环生命周期**：任务建档、进度汇报、缺失工具提报与终态归档 (`start_agent_task`, `report_agent_task_step`, `complete_agent_task`, `report_missing_mcp_tool`)。
  - **工作流技能自举中心**：本地 Skills 动态解析、元数据同步与热加载。

### 2. 🛡️ 严格的路径沙箱与防灾回收站
- **白名单机制**：所有文件操作强制限定在 `allowed_paths` 白名单目录内，严防越权访问系统核心分区。
- **两阶段防灾回收**：删除动作默认移入 `.trash` 隔离目录，支持容量上限自动轮转与过期清理，杜绝误删导致的数据灾难。

### 3. 🖥️ 跨平台自适应客户端 (Flutter)
- **大屏模式 (PC / 平板 / Web，宽度 ≥ 720px)**：自适应展开侧边导航栏与多栏栅格大屏。
- **移动端 (Android / iOS)**：针对紧凑屏幕优化的底部导航与钻取式子页面，杜绝排版溢出。
- **WebSocket 实时通知**：下载进度、智能体步骤毫秒级推送到客户端界面，流畅无闪烁。

---

## 📂 项目工程结构 (Directory Structure)

```text
nasio/
├── server/                     # 服务端核心工程 (Python FastAPI + MCP)
│   ├── src/nasio/              # 服务端核心源码
│   │   ├── api/                # RESTful 路由定义 (任务/认证/配置/RSS/回收站等)
│   │   ├── core/               # 核心配置加载与 Bearer 安全认证
│   │   ├── mcp/                # Model Context Protocol 工具定义与实现
│   │   ├── services/           # 核心业务服务 (下载器、文件治理、长任务调度)
│   │   ├── cli.py              # 命令行管理入口
│   │   └── main.py             # FastAPI 服务主入口
│   ├── data/                   # 配置文件与数据模版
│   │   └── config.example.yaml # 业务主配置模板 (存储白名单、下载器、LLM)
│   ├── scripts/                # 测试与验证脚本
│   └── requirements.txt        # Python 依赖清单
├── client/                     # 客户端跨平台工程 (Flutter)
│   ├── lib/                    # Flutter Dart 源码 (Provider 状态管理 + 响应式 UI)
│   ├── assets/                 # 静态字体 (MiSans) 与品牌图标
│   ├── android/                # Android 原生配置 (com.nasio.client)
│   ├── ios/                    # iOS 原生工程
│   ├── web/                    # Web 原生工程
│   ├── windows/                # Windows 桌面原生工程
│   └── pubspec.yaml            # Flutter 包配置
├── docker/                     # 容器化部署支持
│   ├── Dockerfile              # Nasio 服务端 Docker 镜像构建脚本
│   ├── entrypoint.sh           # 权限自愈与启动脚本 (解决 UGOS 权限冲突)
│   ├── nginx/default.conf      # Web 控制台反向代理与 Gzip 缓存配置
│   └── web/                    # 预编译好的纯净版 Web 控制台静态资源
├── docs/                       # 架构设计与详细协议文档
│   └── nasio_design_doc.md
├── docker-compose.yml          # 根目录一键编排脚本 (服务端 + 下载引擎 + WebUI)
├── .env.example                # 环境变量配置模板
├── .gitignore                  # Git 忽略配置
├── LICENSE                     # MIT 开源协议
└── README.md                   # 项目自说明文档
```

---

## 🚀 部署指南 (Deployment Guide)

### 方案一：Docker Compose 一键部署（强烈推荐）

适用于**绿联 UGOS / UGOS Pro、群晖 Synology DSM、威联通 QTS、Unraid、TrueNAS 以及普通 Linux 服务器**。

#### 1. 克隆代码仓库
```bash
git clone https://github.com/spreadwing/nasio.git
cd nasio
```

#### 2. 配置环境变量
从模板文件复制生成 `.env` 配置文件：
```bash
cp .env.example .env
```
使用文本编辑器（如 `vim .env` 或 `nano .env`）修改关键参数：
```ini
# 1. 访问安全令牌 (Bearer Token，用于 MCP 接入与客户端连接鉴权)
MCP_AUTH_TOKEN=your_custom_high_strength_secret_key_here

# 2. 账号权限对齐 (设置为宿主机 NAS 真实用户的 UID 和 GID，默认通常为 1000)
PUID=1000
PGID=1000
TZ=Asia/Shanghai

# 3. 宿主机真实共享文件夹路径挂载 (对齐绿联/群晖存储卷路径)
DOWNLOAD_DIR=/volume1/Download
MEDIA_DIR=/volume1/Media
TRASH_DIR=/volume1/.trash

# 4. 端口映射 (按需调整)
NASIO_PORT=8000
QBITTORRENT_WEB_PORT=8085
QBITTORRENT_BT_PORT=6881
WEB_PORT=8086
```

> [!TIP]
> **权限自愈说明**：绿联 UGOS 等 NAS 系统在用户修改共享权限后经常会重置文件夹属主，导致 Docker 容器报权限不足或 qBittorrent 报 `missingFiles`。Nasio 镜像内嵌了 `entrypoint.sh` 权限自愈机制，会在启动时自动打通顶层共享目录穿透权限 (`a+rwx`)，并在运行时自动对齐属主，彻底免除权限烦恼。

#### 3. 初始化业务配置文件
```bash
mkdir -p ./data/server ./data/qbittorrent
cp server/data/config.example.yaml ./data/server/config.yaml
```
根据需要调整 `data/server/config.yaml` 中的下载器、路径白名单及 AI 模型配置。

#### 4. 一键启动容器集群
```bash
docker compose up -d --build
```

#### 5. 访问与服务验证
- **Web 管理控制台**：浏览器访问 `http://<NAS_IP>:8086`
- **服务端 API 与文档**：浏览器访问 `http://<NAS_IP>:8000/docs`
- **MCP SSE 协议端点**：`http://<NAS_IP>:8000/sse`
- **qBittorrent WebUI**：浏览器访问 `http://<NAS_IP>:8085`（默认账号：`admin`，默认密码：`adminadmin`）

---

### 方案二：服务端原生 Python 本地开发与运行

适用于本地调试、Python 二次开发或无需 Docker 的环境。

#### 1. 依赖与环境要求
- Python 3.11 或更高版本
- 系统多媒体与解压依赖（用于元数据分析与压缩包操作）：
  - **Debian / Ubuntu**：`sudo apt-get install -y ffmpeg p7zip-full unrar-free`
  - **macOS**：`brew install ffmpeg p7zip unrar`
  - **Windows**：通过 winget 或 Chocolatey 安装 ffmpeg 和 7-Zip 并加入 PATH。

#### 2. 安装 Python 依赖
```bash
cd nasio/server
python -m venv .venv

# Linux / macOS 激活虚拟环境
source .venv/bin/activate
# Windows 激活虚拟环境
# .venv\Scripts\activate

pip install -r requirements.txt
```

#### 3. 配置与启动
```bash
# 准备配置文件
mkdir -p data
cp data/config.example.yaml data/config.yaml

# 设置环境变量并启动服务
export MCP_AUTH_TOKEN="your_secure_random_token_here"
export PYTHONPATH=src
python -m nasio.main
```
服务默认监听在 `http://0.0.0.0:8000`。

---

### 方案三：客户端（Flutter）构建与运行

#### 1. 前置环境
- 安装 [Flutter SDK](https://docs.flutter.dev/get-started/install)（建议 3.24+ 或 3.27+）
- 执行 `flutter doctor` 确认环境无异常。

#### 2. 安装客户端依赖
```bash
cd nasio/client
flutter pub get
```

#### 3. 各平台编译与构建

- **运行与调试桌面端（Windows / macOS / Linux）**：
  ```bash
  flutter run -d windows    # Windows 平台
  flutter run -d macos      # macOS 平台
  flutter run -d linux      # Linux 平台
  ```

- **打包 Web 控制台静态资源**：
  ```bash
  flutter build web --release
  # 编译产物位于 client/build/web 目录
  ```

- **打包 Android APK**：
  ```bash
  flutter build apk --release
  # 编译生成的安装包位于 client/build/app/outputs/flutter-apk/app-release.apk
  ```

- **打包 Windows 可执行安装包**：
  ```bash
  flutter build windows --release
  # 产物位于 client/build/windows/x64/runner/Release/
  ```

---

## 🤖 接入 AI 智能体 (MCP Configuration)

Nasio 采用开源的 **Model Context Protocol (MCP)** 标准，可零门槛接入各类主流 AI 桌面端与 Agent 系统。

### 1. Antigravity / Claude Desktop 接入
打开您的 `mcp_config.json` 或 Claude 桌面端的 `claude_desktop_config.json`，在 `mcpServers` 下添加配置：

```json
{
  "mcpServers": {
    "nasio": {
      "serverUrl": "http://<NAS_IP>:8000/sse",
      "headers": {
        "Authorization": "Bearer your_secure_random_token_here"
      }
    }
  }
}
```

### 2. Cursor / Windsurf 接入
在设置面板中添加 MCP Server：
- **Type**: `SSE`
- **Name**: `nasio`
- **URL**: `http://<NAS_IP>:8000/sse`
- **Headers**:
  - `Authorization`: `Bearer your_secure_random_token_here`

### 3. Cherry Studio / Dify 接入
- **协议类型**：SSE
- **服务端点**：`http://<NAS_IP>:8000/sse`
- **鉴权方式**：HTTP Header `Authorization: Bearer <TOKEN>`

---

## 🛠️ MCP 核心工具速查 (Tools Reference)

| 分类 | 工具名称 | 功能描述 |
| :--- | :--- | :--- |
| **系统监控** | `get_system_status` | 查询 NAS 存储池容量、CPU、内存及各挂载点剩余空间 |
| | `get_mcp_config` | 查询当前服务器生效的安全白名单配置与参数 |
| **下载中枢** | `create_download_task` | 创建离线下载（支持 Magnet 磁力、BT 种子、HTTP 直链、YouTube 视频等） |
| | `get_task_status` | 轮询/查询当前下载引擎的任务列表与实时传输速度 |
| | `cancel_task` | 取消、暂停或删除指定的下载任务 |
| | `test_downloader_connection` | 测试外部 qBittorrent 或 aria2 下载器的网络连接连通性 |
| **文件治理** | `search_files` | 在白名单安全沙箱目录内根据关键词或正则检索文件 |
| | `find_duplicate_files` | 通过 SHA256 哈希值全盘扫描重复冗余文件 |
| | `batch_organize_files` | 批量整理归类杂乱文件至规范目录结构 |
| | `organize_series_seasons` | 智能识别剧集季数（Season/Episode）并自动重命名归档 |
| | `extract_archive` | 解压 zip、rar、7z 等压缩包，支持多卷解压 |
| | `safe_delete_files` | 两阶段软删除文件至防灾隔离回收站 (`.trash`) |
| | `restore_trash_file` | 将回收站中的已隔离文件原路无损还原恢复 |
| **智能体协同** | `start_agent_task` | 初始化长任务监控卡片并获取全局追踪 ID |
| | `report_agent_task_step` | 实时向大屏与监控台汇报任务执行进度与里程碑 |
| | `complete_agent_task` | 标记长任务圆满达成并归档最佳实践 Prompt 模版 |
| | `report_missing_mcp_tool` | 智能体自主上报缺少的底层原子工具需求 |

---

## ❓ 常见问题排查 (FAQ)

### Q1: qBittorrent 无法连接或提示密码错误？
> **检查点**：
> 1. 查看 `docker compose logs qbittorrent` 确认容器日志中打印的随机初始密码，或在配置文件中配置预设密码。
> 2. 确认 `config.yaml` 中的 `qbittorrent.url` 与 Docker 内部网络服务名一致（默认为 `http://qbittorrent:8080`）。

### Q2: 提示 `Path not allowed: /xxx`？
> **检查点**：
> Nasio 具备严格的路径白名单机制。所有操作路径必须在 `config.yaml` 的 `storage.allowed_paths` 列表中明确声明，否则将被安全引擎拦截。

### Q3: 客户端连接服务端时报 401 Unauthorized？
> **检查点**：
> 检查客户端设置页中的 **安全令牌 (Token)** 是否与服务端 `.env` 文件中的 `MCP_AUTH_TOKEN` 完全一致。

---

## 📄 开源许可证 (License)

本项目采用 [MIT License](LICENSE) 开源许可证。欢迎提交 Issue 与 Pull Request 共同建设私有 NAS 智能生态！
