import json
import subprocess
import os
import tempfile
from typing import Dict, Any

def get_app_last_used_time(
    limit: int = 30,
    dry_run: bool = False,
    # 使用 r"" 原始字符串避免路径转义问题
    script_path: str = r"scripts\scripts\powershell\get_app_last_used_time.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本从 Windows Prefetch 获取应用程序最后使用时间。
    
    此操作需要管理员权限。

    Args:
        limit (int): 返回最近使用的多少个应用 (默认 30)。
        dry_run (bool): 仅模拟执行 (此脚本为只读，效果与真实运行一致)。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含应用名称和最后运行时间的列表。
    """

    # 1. 构造参数负载
    payload = {
        "parameter": {
            "limit": limit,
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
        # 脚本内部已强制 UTF-8 输出，直接使用 utf-8 读取
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
    
    target_script = r"scripts\scripts\powershell\get_app_last_used_time.ps1"
    
    print("--- Test: Get Recently Used Apps ---")
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    # 获取最近运行的前 10 个程序
    res = get_app_last_used_time(limit=10, script_path=target_script)
    
    if res.get("ok"):
        print(f"Total found: {res['data']['total_count']}")
        for app in res['data']['apps']:
            print(f"[{app['last_used_friendly']}] {app['app_name']}")
    else:
        print(json.dumps(res, indent=2, ensure_ascii=False))