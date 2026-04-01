import json
import subprocess
import os
import tempfile
from typing import Dict, Any

def get_temperature(
    dry_run: bool = False,
    # 使用 r"" 原始字符串避免路径转义问题
    script_path: str = r"scripts\scripts\powershell\get_temperature.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本获取硬件温度读数。
    
    通过查询 ACPI 热区传感器获取温度。
    用于诊断 "电脑自动关机"、"风扇狂转" 或 "系统过热" 等问题。
    注意：此操作需要管理员权限。

    Args:
        dry_run (bool): 仅模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含温度读数和统计信息的字典。
    """

    # 1. 构造参数负载
    payload = {
        "parameter": {
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
    
    target_script = r"scripts\scripts\powershell\get_temperature.ps1"
    print("--- Test: Check System Temperature ---")
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    # 该脚本如果不是以管理员身份运行，会触发 UAC 弹窗
    res = get_temperature(script_path=target_script)
    
    if res.get("ok"):
        data = res['data']
        if data.get('supported'):
            print(f"Max Temperature: {data.get('max_celsius')} °C")
            print(f"Avg Temperature: {data.get('average_celsius')} °C")
            print(f"\nSensors Found ({data.get('zone_count')}):")
            for sensor in data.get('temperatures', []):
                # 简化名称显示
                name = sensor.get('instance_name').split('\\')[-1]
                print(f"- {name}: {sensor['temperature_celsius']} °C")
        else:
            print(f"Not Supported: {data.get('reason')}")
            
    else:
        print(json.dumps(res, indent=2, ensure_ascii=False))