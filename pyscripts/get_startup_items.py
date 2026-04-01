import json
import subprocess
import os
import tempfile
from typing import Dict, Any, Literal

def get_startup_items(
    limit: int = 50,
    sort_by: Literal["name", "publisher", "source"] = "name",
    dry_run: bool = False,
    # 使用 r"" 原始字符串避免路径转义问题
    script_path: str = r"scripts\scripts\powershell\get_startup_items.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本获取系统开机启动项列表。
    
    该工具扫描注册表、启动文件夹和计划任务，找出所有随系统启动运行的程序。
    常用于排查 "开机慢" 或 "未知弹窗" 问题。

    Args:
        limit (int): 返回的最大启动项数量 (默认 50)。
        sort_by (str): 排序方式 ("name", "publisher", "source")。
        dry_run (bool): 仅模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含启动项列表的字典。
    """

    # 1. 构造参数负载
    payload = {
        "parameter": {
            "limit": limit,
            "sort_by": sort_by,
            "dry_run": dry_run
        },
        "metadata": {
            "timeout_ms": 15000, # 签名验证可能稍慢
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
    
    target_script = r"scripts\scripts\powershell\get_startup_items.ps1"
    print("--- Test: List Startup Items ---")
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    res = get_startup_items(script_path=target_script)
    
    if res.get("ok"):
        items = res['data']['startup_items']
        print(f"Total Found: {res['data']['total_found']}")
        print(f"{'Name':<25} | {'Publisher':<20} | {'Source'} | {'Command'}")
        print("-" * 100)
        
        for item in items:
            name = item['name'][:23] + ".." if len(item['name']) > 23 else item['name']
            pub = item['publisher'][:18] + ".." if len(item['publisher']) > 18 else item['publisher']
            cmd = item['command'][:30] + ".." if len(item['command']) > 30 else item['command']
            
            # 使用图标区分状态
            state_icon = "🟢" if item['is_enabled'] else "🔴"
            
            print(f"{state_icon} {name:<23} | {pub:<20} | {item['source']:<15} | {cmd}")
            # print(f"   ID: {item['startup_id']}") # 调试用
            
    else:
        print(json.dumps(res, indent=2, ensure_ascii=False))