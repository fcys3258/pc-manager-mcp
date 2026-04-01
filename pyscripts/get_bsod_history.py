import json
import subprocess
import os
import tempfile
from typing import Dict, Any

def get_bsod_history(
    days: int = 30,
    max_events: int = 20,
    dry_run: bool = False,
    # 使用 r"" 原始字符串避免路径转义问题
    script_path: str = r"scripts\scripts\powershell\get_bsod_history.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本获取系统蓝屏(BSOD)和意外关机的历史记录。
    
    通过分析 Windows 系统事件日志 (Event ID 1001 和 41)，识别系统不稳定的原因。
    脚本会自动将常见的 BugCheck 代码 (如 0x000000D1) 翻译为可读名称。

    Args:
        days (int): 查询过去多少天的日志 (默认 30)。
        max_events (int): 返回的最大事件数量 (默认 20)。
        dry_run (bool): 仅模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含崩溃记录列表和意外关机列表的字典。
    """

    # 1. 构造参数负载
    payload = {
        "parameter": {
            "days": days,
            "max_events": max_events,
            "dry_run": dry_run
        },
        "metadata": {
            "timeout_ms": 30000, # 查询日志可能需要较长时间
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
    
    target_script = r"scripts\scripts\powershell\get_bsod_history.ps1"
    print("--- Test: BSOD History Analysis ---")
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    # 获取过去 30 天的崩溃记录
    res = get_bsod_history(days=30, script_path=target_script)
    
    if res.get("ok"):
        data = res['data']
        crash_count = data.get('crash_count', 0)
        shutdown_count = data.get('shutdown_count', 0)
        
        print(f"在过去 {data.get('query_days')} 天内发现:")
        print(f"- 蓝屏崩溃 (BSOD): {crash_count} 次")
        print(f"- 意外关机 (Power Loss): {shutdown_count} 次")
        
        if crash_count > 0:
            print("\n详细崩溃记录:")
            for crash in data.get('crashes', []):
                print(f"[{crash['time']}] {crash['bug_check_code']} ({crash['bug_check_name']})")
                print(f"  可能原因: {crash['probable_cause']}")
        elif shutdown_count == 0:
            print("\n系统运行非常稳定，未检测到异常。")
            
    else:
        print(json.dumps(res, indent=2, ensure_ascii=False))