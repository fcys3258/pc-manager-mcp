import json
import subprocess
import os
import tempfile
from typing import Dict, Any, Literal

def list_printers(
    limit: int = 50,
    sort_by: Literal["name", "status", "driver_name"] = "name",
    dry_run: bool = False,
    # 使用 r"" 原始字符串避免路径转义问题
    script_path: str = r"scripts\scripts\powershell\list_printers.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本获取已安装的打印机列表。
    
    用于查找 "我的打印机在哪"、"哪台是默认打印机" 或 "打印机是否离线"。
    
    Args:
        limit (int): 返回的最大打印机数量 (默认 50)。
        sort_by (str): 排序方式。
        dry_run (bool): 仅模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含打印机列表的字典。
    """

    # 1. 构造参数负载
    payload = {
        "parameter": {
            "limit": limit,
            "sort_by": sort_by,
            "dry_run": dry_run
        },
        "metadata": {
            "timeout_ms": 10000,
            "agent_invoker": "python-client"
        }
    }

    # 2. 创建临时文件
    input_file_fd, input_file_path = tempfile.mkstemp(suffix=".json", text=True)

    try:
        with os.fdopen(input_file_fd, 'w', encoding='utf-8') as f:
            json.dump(payload, f, ensure_ascii=False)

        # 3. 构建 PowerShell 命令
        cmd = [
            "powershell",
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", script_path,
            "-InputFile", input_file_path
        ]

        # 4. 执行命令
        # 脚本内部强制 UTF-8 输出，直接使用 utf-8 读取
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            encoding='utf-8'
        )

        # 5. 错误处理
        if result.stderr and not result.stdout:
            return {
                "ok": False,
                "error": {
                    "code": "SUBPROCESS_ERROR",
                    "message": result.stderr.strip()
                }
            }

        try:
            return json.loads(result.stdout)
        except json.JSONDecodeError:
            return {
                "ok": False,
                "error": {
                    "code": "JSON_PARSE_ERROR",
                    "message": "无法解析脚本输出",
                    "raw_output": result.stdout
                }
            }

    except Exception as e:
        return {
            "ok": False,
            "error": {
                "code": "PYTHON_EXECUTION_ERROR",
                "message": str(e)
            }
        }
    finally:
        if os.path.exists(input_file_path):
            try: os.remove(input_file_path)
            except: pass

# --- 使用示例 ---
if __name__ == "__main__":
    
    target_script = r"scripts\scripts\powershell\list_printers.ps1"
    print("--- Test: List Printers ---")
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    res = list_printers(script_path=target_script)
    
    if res.get("ok"):
        printers = res['data']['printers']
        print(f"Total Printers: {res['data']['total_found']}")
        
        print(f"\n{'Name':<30} | {'Status':<10} | {'Port'}")
        print("-" * 60)
        
        for p in printers:
            # 标记默认打印机
            name = p['name']
            if p['is_default']:
                name = f"* {name}"
            
            # 截断过长的名称
            if len(name) > 28: name = name[:25] + "..."
            
            print(f"{name:<30} | {p['status']:<10} | {p['port_name']}")
            
    else:
        print(json.dumps(res, indent=2, ensure_ascii=False))