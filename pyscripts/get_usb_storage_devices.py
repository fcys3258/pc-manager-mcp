import json
import subprocess
import os
import tempfile
from typing import Dict, Any

def get_usb_storage_devices(
    dry_run: bool = False,
    # 使用 r"" 原始字符串避免路径转义问题
    script_path: str = r"scripts\scripts\powershell\get_usb_storage_devices.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本获取当前连接的 USB 存储设备信息。
    
    该工具会自动过滤掉鼠标、键盘等非存储设备，仅返回 U 盘、移动硬盘等使用 USBSTOR 服务的大容量存储设备。
    返回信息包括厂商 ID (VID)、产品 ID (PID) 和设备名称。

    Args:
        dry_run (bool): 仅模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含 USB 存储设备列表的字典。
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
    
    target_script = r"scripts\scripts\powershell\get_usb_storage_devices.ps1"
    print("--- Test: Check USB Storage Devices ---")
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    res = get_usb_storage_devices(script_path=target_script)
    
    if res.get("ok"):
        devices = res['data']['devices']
        print(f"Connected Storage Devices: {len(devices)}")
        
        if len(devices) == 0:
            print("No USB drives found.")
        else:
            print(f"\n{'Name':<30} | {'Manufacturer':<15} | {'VID/PID'}")
            print("-" * 60)
            for dev in devices:
                # 截断过长的名称
                name = dev['friendly_name'][:28] + ".." if len(dev['friendly_name']) > 28 else dev['friendly_name']
                vid = dev.get('vid', '????')
                pid = dev.get('pid', '????')
                print(f"{name:<30} | {dev['manufacturer']:<15} | {vid}:{pid}")
                # print(f"   ID: {dev['pnp_device_id']}") # 调试用
            
    else:
        print(json.dumps(res, indent=2, ensure_ascii=False))