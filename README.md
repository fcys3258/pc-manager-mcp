# PC Manager MCP Server

将81个Windows系统管理工具通过MCP协议暴露给Claude Desktop和其他AI助手。

## 快速开始

### 1. 安装依赖

```bash
pip install mcp pyyaml
```

### 2. 配置Claude Desktop

MCP配置文件已创建在 `.kiro/settings/mcp.json`

### 3. 启动测试

```bash
python -m mcp_server.server
```

## 工具清单

共81个工具，分为10个类别：
- 网络管理 (14个)
- 系统信息 (10个)
- 进程与服务管理 (8个)
- 电源管理 (3个)
- 打印机管理 (9个)
- 软件与应用 (4个)
- 启动项管理 (3个)
- 文件操作 (5个)
- 安全与更新 (5个)
- 硬件与设备 (6个)
- 系统配置 (9个)
- 诊断工具 (5个)

详见 `TOOL_CATALOG.md`

## 项目结构

```
mcp_server/
├── server.py           # MCP协议主程序
├── tool_registry.py    # 工具自动发现
├── executor.py         # 工具执行层
└── tool_metadata.yaml  # 工具元数据
```

## 使用示例

在Claude Desktop中：
- "查看C盘空间" → 调用 get_disk_info
- "刷新DNS缓存" → 调用 flush_dns
- "列出运行中的进程" → 调用 get_running_processes
