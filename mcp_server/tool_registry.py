"""工具注册与自动发现"""
import os
import re
import inspect
from pathlib import Path
from typing import Dict, Any, List
import yaml


class ToolRegistry:
    def __init__(self, pyscripts_dir: str = "pyscripts"):
        self.pyscripts_dir = Path(pyscripts_dir)
        self.tools: Dict[str, Dict[str, Any]] = {}
        self.metadata = self._load_metadata()

    def _load_metadata(self) -> Dict:
        """加载工具元数据"""
        metadata_file = Path("mcp_server/tool_metadata.yaml")
        if metadata_file.exists():
            with open(metadata_file, 'r', encoding='utf-8') as f:
                return yaml.safe_load(f) or {}
        return {}

    def discover_tools(self) -> Dict[str, Dict[str, Any]]:
        """自动发现所有工具"""
        for py_file in sorted(self.pyscripts_dir.glob("*.py")):
            tool_name = py_file.stem
            tool_info = self._extract_tool_info(py_file)
            self.tools[tool_name] = tool_info
        return self.tools

    def _extract_tool_info(self, py_file: Path) -> Dict[str, Any]:
        """从Python文件提取工具信息"""
        tool_name = py_file.stem

        with open(py_file, 'r', encoding='utf-8') as f:
            content = f.read()

        # 提取docstring
        description = self._extract_description(content, tool_name)

        # 提取参数
        params = self._extract_parameters(content, tool_name)

        # 生成JSON Schema
        input_schema = self._generate_schema(params)

        # 合并元数据
        meta = self.metadata.get(tool_name, {})

        return {
            "name": tool_name,
            "description": description,
            "inputSchema": input_schema,
            "category": meta.get("category", "other"),
            "tags": meta.get("tags", []),
        }

    def _extract_description(self, content: str, tool_name: str) -> str:
        """提取工具描述"""
        match = re.search(r'def\s+' + tool_name + r'\s*\([^)]*\):\s*"""(.*?)"""', content, re.DOTALL)
        if match:
            lines = [line.strip() for line in match.group(1).split('\n') if line.strip()]
            return lines[0] if lines else f"执行 {tool_name}"
        return f"执行 {tool_name}"

    def _extract_parameters(self, content: str, tool_name: str) -> List[Dict]:
        """提取参数信息"""
        params = []
        match = re.search(r'def\s+' + tool_name + r'\s*\((.*?)\):', content, re.DOTALL)
        if match:
            param_block = match.group(1)
            for line in param_block.split('\n'):
                line = line.strip()
                if ':' in line and not line.startswith('#'):
                    parts = line.split(':')
                    param_name = parts[0].strip()
                    if param_name not in ['dry_run', 'script_path']:
                        type_info = parts[1].split('=')[0].strip() if len(parts) > 1 else 'str'
                        params.append({"name": param_name, "type": type_info})
        return params

    def _generate_schema(self, params: List[Dict]) -> Dict:
        """生成JSON Schema"""
        properties = {}
        for param in params:
            param_type = "string"
            if "int" in param["type"].lower():
                param_type = "integer"
            elif "bool" in param["type"].lower():
                param_type = "boolean"
            properties[param["name"]] = {"type": param_type}

        return {
            "type": "object",
            "properties": properties
        }

    def get_tool(self, name: str) -> Dict[str, Any]:
        """获取工具信息"""
        return self.tools.get(name)
