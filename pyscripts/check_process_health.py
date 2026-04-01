import json
import subprocess
import os
import tempfile
from typing import Dict, Any, Optional

def check_process_health(
    process_name: str,
    time_range_hours: int = 24,
    limit: int = 100,
    script_path: str = "scripts\scripts\powershell\check_process_health.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本检查指定进程的健康状况（崩溃/挂起事件）。

    Args:
        process_name (str): 目标进程名称 (例如 "chrome" 或 "notepad").
        time_range_hours (int): 向前追溯的小时数 (默认 24).
        limit (int): 获取的最大日志条数 (默认 100).
        script_path (str): ps1 脚本的路径.

    Returns:
        Dict[str, Any]: 包含执行结果的字典。
    """

    # 1. 构造符合脚本要求的 JSON 结构 (SkillArgs)
    payload = {
        "parameter": {
            "process_name": process_name,
            "time_range": time_range_hours,
            "limit": limit
        },
        "metadata": {
            "timeout_ms": 30000,  # 30秒超时预算
            "agent_invoker": "python-client"
        }
    }

    # 2. 创建临时文件保存 JSON 参数
    # 使用文件传递比命令行字符串传递更稳定，特别是处理包含空格或特殊字符的参数时
    input_file_fd, input_file_path = tempfile.mkstemp(suffix=".json", text=True)

    try:
        # 写入 JSON 数据
        with os.fdopen(input_file_fd, 'w', encoding='utf-8') as f:
            json.dump(payload, f, ensure_ascii=False)

        # 3. 构建 PowerShell 调用命令
        # -ExecutionPolicy Bypass: 允许运行脚本
        cmd = [
            "powershell",
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", script_path,
            "-InputFile", input_file_path
        ]

        # 4. 执行并捕获输出
        # check_process_health.ps1 通常不需要管理员权限即可读取 Application Log，
        # 但如果遇到权限问题，请尝试以管理员身份运行 Python。
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            encoding='utf-8' # 对应脚本中的 [Console]::OutputEncoding
        )

        # 5. 错误处理与解析
        if result.stderr and not result.stdout:
            return {
                "ok": False,
                "error": {
                    "code": "SUBPROCESS_ERROR",
                    "message": result.stderr.strip()
                }
            }

        try:
            # 解析 PowerShell 返回的 JSON
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
        # 清理临时文件
        if os.path.exists(input_file_path):
            try:
                os.remove(input_file_path)
            except:
                pass

# --- 使用示例 ---
if __name__ == "__main__":
    # 确保当前目录下有 check_process_health.ps1 文件
    
    # 示例 1: 检查 explorer (资源管理器)
    print("--- 正在检查 explorer 进程健康状况 ---")
    result = check_process_health("explorer", time_range_hours=48)
    
    if result.get("ok"):
        data = result["data"]
        print(f"进程: {data['process_name']}")
        print(f"过去 {data['time_range_hours']} 小时内:")
        print(f"  - 崩溃次数: {data['total_crashes']}")
        print(f"  - 挂起次数: {data['total_hangs']}")
        
        if data['live_status']:
            print("当前运行实例:")
            for p in data['live_status']:
                print(f"  [ID: {p['id']}] CPU: {p['cpu_seconds']}s, Mem: {p['memory_mb']}MB")
        else:
            print("当前未运行。")
    else:
        print("执行失败:", json.dumps(result, indent=2, ensure_ascii=False))

    print("\n" + "="*30 + "\n")

    # 示例 2: 检查一个不存在或不稳定的应用
    print("--- 正在检查 testapp ---")
    print(json.dumps(check_process_health("testapp"), indent=2, ensure_ascii=False))