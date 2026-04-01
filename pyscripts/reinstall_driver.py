import json
import subprocess
import os
import tempfile
from typing import Dict, Any

def reinstall_driver(
    driver_name: str,
    dry_run: bool = False,
    # 使用 r"" 原始字符串避免路径转义问题
    script_path: str = r"scripts\scripts\powershell\reinstall_driver.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本重装（重置）指定设备的驱动程序。
    
    通过执行 "禁用 -> 启用" 循环来强制重新加载驱动。
    这是解决声卡无声、摄像头黑屏、网卡断流等硬件故障的常用方法。
    
    Args:
        driver_name (str): 设备管理器中显示的设备名称 (例如 "Intel(R) Wi-Fi 6 AX201")。
        dry_run (bool): 仅模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含操作结果的字典。
    """

    # 1. 构造参数负载
    payload = {
        "parameter": {
            "driver_name": driver_name,
            "dry_run": dry_run
        },
        "metadata": {
            "timeout_ms": 30000, # 硬件操作可能较慢
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
    
    target_script = r"scripts\scripts\powershell\reinstall_driver.ps1"
    print("--- Test: Reinstall Driver (Dry Run) ---")
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    # 示例：尝试重置一个不存在的设备以测试流程
    # 在真实场景中，你会传入如 "Realtek High Definition Audio"
    target_device = "Test Device Name"
    
    # 脚本内部有提权逻辑，可能会弹出 UAC
    res = reinstall_driver(
        driver_name=target_device, 
        dry_run=True, # 强烈建议先测试 dry_run
        script_path=target_script
    )
    
    if res.get("ok"):
        print(f"Result: {res['data'].get('result')}")
        if res['data'].get('would_perform_action'):
            print(f"Action: {res['data']['would_perform_action']}")
    else:
        # 预期会报错找不到设备
        print(f"Error: {res.get('error', {}).get('message')}")