import json
import subprocess
import os
import tempfile
from typing import Dict, Any, Optional

def get_device_status(
    name_pattern: Optional[str] = None,
    class_name: Optional[str] = None,
    dry_run: bool = False,
    # 使用 r"" 原始字符串避免路径转义问题
    script_path: str = r"scripts\scripts\powershell\get_device_status.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本查询硬件设备状态。
    
    Args:
        name_pattern (str, optional): 设备名称通配符 (例如 "*Camera*", "*Audio*")。
        class_name (str, optional): 设备类别名称 (例如 "Net", "DiskDrive", "Camera")。
        dry_run (bool): 仅模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含匹配设备列表的字典。
    """

    # 1. 构造参数负载
    params = {}
    if name_pattern:
        params['name_pattern'] = name_pattern
    if class_name:
        params['class_name'] = class_name
    params['dry_run'] = dry_run

    payload = {
        "parameter": params,
        "metadata": {
            "timeout_ms": 15000,
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
        # 脚本内部已强制 UTF-8 输出，直接使用 utf-8 读取，不需要复杂的解码逻辑
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
    
    target_script = r"scripts\scripts\powershell\get_device_status.ps1"
    print("--- Test: Find Camera Devices ---")
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    # 示例：查找所有包含 "Camera" 的设备
    # 注意：如果不传参数，会列出系统几百个设备，建议加上筛选
    res = get_device_status(
        name_pattern="*Camera*", 
        script_path=target_script
    )
    
    if res.get("ok"):
        devices = res['data']['devices']
        print(f"Found {len(devices)} devices:")
        for dev in devices:
            status_icon = "✅" if dev['status'] == 'OK' else "❌"
            print(f"{status_icon} {dev['friendly_name']} (Class: {dev['class']})")
            print(f"   ID: {dev['pnp_device_id']}")
            if dev['problem_code'] != 0:
                print(f"   ⚠️ Problem Code: {dev['problem_code']}")
    else:
        print(json.dumps(res, indent=2, ensure_ascii=False))