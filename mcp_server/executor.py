"""工具执行层"""
import sys
import importlib
from typing import Dict, Any
from pathlib import Path


class ToolExecutor:
    def __init__(self, pyscripts_dir: str = "pyscripts"):
        self.pyscripts_dir = Path(pyscripts_dir)
        # 添加pyscripts到Python路径
        if str(self.pyscripts_dir.absolute()) not in sys.path:
            sys.path.insert(0, str(self.pyscripts_dir.absolute().parent))

    def execute(self, tool_name: str, arguments: Dict[str, Any]) -> Dict[str, Any]:
        """执行工具"""
        try:
            # 动态导入模块
            module = importlib.import_module(f"pyscripts.{tool_name}")
            func = getattr(module, tool_name)

            # 调用函数
            result = func(**arguments)

            return result

        except Exception as e:
            return {
                "ok": False,
                "error": {
                    "code": "EXECUTION_ERROR",
                    "message": str(e)
                }
            }
