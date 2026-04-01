import json
import subprocess
import os
import tempfile
from datetime import timedelta
from typing import Dict, Any

def get_system_uptime(
    dry_run: bool = False,
    # 使用 r"" 原始字符串避免路径转义问题
    script_path: str = r"scripts\scripts\powershell\get_system_uptime.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本获取系统运行时间。
    
    返回系统已连续运行的秒数和上次启动时间。
    有助于判断用户是否真的很久没有重启电脑（很多故障只需重启即可解决）。

    Args:
        dry_run (bool): 仅模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含运行时间和启动时间的字典。
    """

    # 1. 构造参数负载
    payload = {
        "parameter": {
            "dry_run": dry_run
        },
        "metadata": {
            "timeout_ms": 5000, # 获取时间非常快
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
    
    target_script = r"scripts\scripts\powershell\get_system_uptime.ps1"
    print("--- Test: System Uptime ---")
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    res = get_system_uptime(script_path=target_script)
    
    if res.get("ok"):
        data = res['data']
        seconds = data['uptime_seconds']
        uptime_str = str(timedelta(seconds=seconds))
        
        print(f"Uptime: {uptime_str}")
        print(f"Last Boot: {data['last_boot_time']}")
        
        # 检查是否为快速启动导致的长时间未重置
        meta = res.get('metadata', {})
        if meta.get('is_hybrid_boot'):
            print("Note: Hybrid Boot detected. Uptime may include hibernation time.")
            
    else:
        print(json.dumps(res, indent=2, ensure_ascii=False))