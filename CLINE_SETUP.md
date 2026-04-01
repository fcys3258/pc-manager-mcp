# Cline MCP 配置指南

## 配置位置

Cline的MCP配置文件位于：
- **Windows**: `%APPDATA%\Code\User\globalStorage\saoudrizwan.claude-dev\settings\cline_mcp_settings.json`
- **macOS**: `~/Library/Application Support/Code/User/globalStorage/saoudrizwan.claude-dev/settings/cline_mcp_settings.json`
- **Linux**: `~/.config/Code/User/globalStorage/saoudrizwan.claude-dev/settings/cline_mcp_settings.json`

## 配置内容

在上述文件中添加以下配置：

```json
{
  "mcpServers": {
    "pc-manager": {
      "command": "python",
      "args": ["-m", "mcp_server.server"],
      "cwd": "D:\\MyProject\\PC Manager",
      "disabled": false
    }
  }
}
```

**注意：** 将 `cwd` 路径改为你的实际项目路径。

## 测试步骤

1. 确保虚拟环境已激活并安装依赖：
   ```bash
   cd "D:\MyProject\PC Manager"
   .venv\Scripts\activate
   ```

2. 在VS Code中打开Cline

3. 在Cline中输入测试命令：
   - "列出所有可用的工具"
   - "查看C盘空间"
   - "获取系统信息"

4. 检查Cline是否能成功调用MCP工具

## 故障排查

如果工具无法使用：
1. 检查路径是否正确
2. 确认虚拟环境中已安装mcp和pyyaml
3. 查看Cline的MCP日志
4. 重启VS Code
