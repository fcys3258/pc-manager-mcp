import json
import subprocess
import os
import tempfile
from typing import Dict, Any

def check_time_synchronization(
    script_path: str = r"scripts\scripts\powershell\check_time_synchronization.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本检查 Windows 时间同步状态 (w32tm)。

    Args:
        script_path (str): ps1 脚本的本地路径.

    Returns:
        Dict[str, Any]: 包含执行结果的字典。
        关键字段:
          - is_synchronized (bool): 是否已同步
          - phase_offset_seconds (float): 时间偏差(秒)
          - source (str): 时间源 (如 time.windows.com 或 Local CMOS Clock)
    """

    # 1. 构造参数负载
    # 此脚本不需要复杂的输入参数，只需标准的元数据结构
    payload = {
        "parameter": {}, 
        "metadata": {
            "timeout_ms": 10000,
            "agent_invoker": "python-client"
        }
    }

    # 2. 创建临时文件
    input_file_fd, input_file_path = tempfile.mkstemp(suffix=".json", text=True)

    try:
        # 写入 JSON 数据
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
        # w32tm /query /status 通常不需要管理员权限即可读取
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
        # 清理临时文件
        if os.path.exists(input_file_path):
            try:
                os.remove(input_file_path)
            except:
                pass

# --- 使用示例 ---
if __name__ == "__main__":
    print("--- 正在检查时间同步状态 ---")
    result = check_time_synchronization()
    
    if result.get("ok"):
        data = result["data"]
        
        # 打印摘要
        status_icon = "✅" if data['is_synchronized'] else "❌"
        print(f"状态: {status_icon} {data['status'].upper()}")
        print(f"时间源: {data['source']}")
        print(f"时间偏差: {data['phase_offset_readable']}")
        print(f"层级 (Stratum): {data['stratum']}")
        print(f"最后同步: {data['last_sync_time']}")
        
        if data['issues']:
            print("\n发现问题:")
            for issue in data['issues']:
                print(f"  - {issue}")
                
        if data['recommendation']:
            print(f"\n建议操作: {data['recommendation']}")
            
    else:
        print("执行失败:", json.dumps(result, indent=2, ensure_ascii=False))