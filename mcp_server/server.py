"""MCP Server主程序"""
import asyncio
import json
import sys
from typing import Any
from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import Tool, TextContent

from .tool_registry import ToolRegistry
from .executor import ToolExecutor


class PCManagerServer:
    def __init__(self):
        self.server = Server("pc-manager")
        self.registry = ToolRegistry()
        self.executor = ToolExecutor()
        self.tools = {}

        # 注册处理器
        self.server.list_tools()(self.handle_list_tools)
        self.server.call_tool()(self.handle_call_tool)

    async def handle_list_tools(self) -> list[Tool]:
        """返回可用工具列表"""
        if not self.tools:
            self.tools = self.registry.discover_tools()

        return [
            Tool(
                name=tool["name"],
                description=tool["description"],
                inputSchema=tool["inputSchema"]
            )
            for tool in self.tools.values()
        ]

    async def handle_call_tool(self, name: str, arguments: dict) -> list[TextContent]:
        """执行工具调用"""
        result = self.executor.execute(name, arguments)

        return [TextContent(
            type="text",
            text=json.dumps(result, ensure_ascii=False, indent=2)
        )]


async def main():
    server = PCManagerServer()
    async with stdio_server() as (read_stream, write_stream):
        await server.server.run(read_stream, write_stream, server.server.create_initialization_options())


if __name__ == "__main__":
    asyncio.run(main())
