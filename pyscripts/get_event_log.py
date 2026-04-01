import json
import subprocess
import os
import tempfile
from typing import Dict, Any, Optional, Literal

def get_event_log(
    log_name: Literal["System", "Application", "Security"] = "System",
    level: Optional[str] = None,
    event_id: Optional[int] = None,
    time_range_hours: int = 24,
    max_events: int = 50,
    dry_run: bool = False,
    # 使用 r"" 原始字符串避免路径转义问题
    script_path: str = r"scripts\scripts\powershell\get_event_log.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本查询 Windows 事件日志。
    
    用于诊断系统错误、应用程序崩溃或安全审计。
    注意：查询 'Security' 日志需要管理员权限。

    Args:
        log_name (str): 日志名称 (System, Application, Security)。
        level (str, optional): 日志级别 (Critical, Error, Warning, Information)。
        event_id (int, optional): 特定事件 ID (例如 4624)。
        time_range_hours (int): 查询过去多少小时 (默认 24)。
        max_events (int): 返回的最大日志条数 (默认 50)。
        dry_run (bool): 仅模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含日志条目的列表。
    """

    # 1. 构造参数负载
    params = {
        "log_name": log_name,
        "time_range_hours": time_range_hours,
        "max_events": max_events,
        "dry_run": dry_run
    }
    if level: params['level'] = level
    if event_id: params['event_id'] = event_id

    payload = {
        "parameter": params,
        "metadata": {
            "timeout_ms": 30000, # 日志查询较慢
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
    
    target_script = r"agent\scripts\scripts\powershell\get_event_log.ps1"
    print("--- Test: Check System Errors ---")
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    res = get_event_log(
        log_name="Application",
        level="Error",
        max_events=5,
        script_path=target_script
    )
    
    if res.get("ok"):
        logs = res['data']['events']
        print(f"Found {res['data']['total_found']} errors:")
        for log in logs:
            print(f"[{log['time_created']}] ID: {log['id']} Source: {log['provider_name']}")
            print(f"  Message: {log['message'][:100]}...") # 截断显示
    else:
        print(json.dumps(res, indent=2, ensure_ascii=False))