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
        # 匹配三引号docstring
        match = re.search(r'"""(.*?)"""', content[content.find(f'def {tool_name}'):], re.DOTALL)
        if match:
            docstring = match.group(1).strip()
            # 提取第一行非空内容作为描述
            for line in docstring.split('\n'):
                line = line.strip()
                if line and not line.startswith('Args:') and not line.startswith('Returns:'):
                    return line
        return f"执行 {tool_name}"

    def _extract_parameters(self, content: str, tool_name: str) -> List[Dict]:
        """提取参数信息"""
        params = []

        # 提取docstring中的参数描述
        param_descriptions = {}
        doc_match = re.search(r'Args:(.*?)(?:Returns:|""")', content, re.DOTALL)
        if doc_match:
            args_section = doc_match.group(1)
            for line in args_section.split('\n'):
                line = line.strip()
                # 匹配格式: param_name (type): description
                param_match = re.match(r'(\w+)\s*\([^)]+\):\s*(.+)', line)
                if param_match:
                    param_descriptions[param_match.group(1)] = param_match.group(2).strip()

        # 提取函数签名中的参数
        match = re.search(r'def\s+' + tool_name + r'\s*\((.*?)\)\s*->', content, re.DOTALL)
        if not match:
            return params

        param_block = match.group(1)

        # 逐行解析参数
        current_param = None
        for line in param_block.split(','):
            line = line.strip()
            if not line or line.startswith('#'):
                continue

            # 提取参数名和类型
            if ':' in line:
                parts = line.split(':')
                param_name = parts[0].strip()

                # 跳过dry_run和script_path
                if param_name in ['dry_run', 'script_path']:
                    continue

                type_part = parts[1].split('=')[0].strip() if len(parts) > 1 else 'str'
                description = param_descriptions.get(param_name, '')

                params.append({
                    "name": param_name,
                    "type": type_part,
                    "description": description
                })

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

            prop = {"type": param_type}
            if param.get("description"):
                prop["description"] = param["description"]

            properties[param["name"]] = prop

        return {
            "type": "object",
            "properties": properties
        }

    def get_tool(self, name: str) -> Dict[str, Any]:
        """获取工具信息"""
        return self.tools.get(name)
