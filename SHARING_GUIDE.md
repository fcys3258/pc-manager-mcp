# PC Manager MCP Server - 分享清单

## 必需文件

### 1. 核心代码
```
mcp_server/
├── __init__.py
├── server.py
├── tool_registry.py
├── executor.py
└── tool_metadata.yaml
```

### 2. 依赖的脚本（必须包含）
```
pyscripts/          # 所有82个.py文件
scripts/
└── scripts/
    └── powershell/ # 所有81个.ps1文件
```

### 3. 配置文件
```
pyproject.toml      # 项目依赖
README.md           # 使用说明
TOOL_CATALOG.md     # 工具清单
```

### 4. 示例配置（可选）
```
.kiro/settings/mcp.json  # MCP配置示例
```

## 不需要分享的文件

```
.venv/              # 虚拟环境（接收者自己创建）
__pycache__/        # Python缓存
*.pyc               # 编译文件
test_server.py      # 测试脚本（可选）
generate_tool_catalog.py  # 生成脚本（可选）
```

## 打包建议

### 方式1: ZIP压缩包
包含以上必需文件，排除虚拟环境和缓存文件

### 方式2: Git仓库
创建.gitignore文件，推送到GitHub/GitLab

## 接收者使用步骤

1. 解压文件到本地目录
2. 安装uv: `pip install uv`
3. 创建虚拟环境: `uv venv`
4. 安装依赖: `uv pip install mcp pyyaml`
5. 配置Claude Desktop的mcp.json
6. 重启Claude Desktop
