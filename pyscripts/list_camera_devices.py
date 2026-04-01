import json
import subprocess
import os
import tempfile
from typing import Dict, Any

def list_camera_devices(
    include_virtual: bool = False,
    dry_run: bool = False,
    # 使用 r"" 原始字符串避免路径转义问题
    script_path: str = r"scripts\scripts\powershell\list_camera_devices.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本获取系统摄像头列表。
    
    该工具能区分物理摄像头和虚拟摄像头(如OBS)，并检查设备状态。
    用于诊断 "找不到相机"、"黑屏" 或 "相机被占用" 等问题。

    Args:
        include_virtual (bool): 是否包含虚拟摄像头 (如 OBS, ManyCam)。默认为 False。
        dry_run (bool): 仅模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含摄像头列表及健康状态统计的字典。
    """

    # 1. 构造参数负载
    payload = {
        "parameter": {
            "include_virtual": include_virtual,
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
    
    target_script = r"scripts\scripts\powershell\list_camera_devices.ps1"
    print("--- Test: List Cameras ---")
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    # 示例：仅列出物理摄像头
    res = list_camera_devices(include_virtual=False, script_path=target_script)
    
    if res.get("ok"):
        data = res['data']
        print(f"Status: {data.get('status').upper()}")
        print(f"Physical Cameras: {data.get('physical_count')}")
        print(f"Working Cameras:  {data.get('working_count')}")
        
        if data.get('issues'):
            print("\n⚠️ Issues Detected:")
            for issue in data['issues']:
                print(f"  - {issue}")
        
        print("\nDevice List:")
        for cam in data.get('cameras', []):
            icon = "📷" if not cam['is_virtual'] else "📹"
            state = "✅ OK" if cam['is_ok'] else f"❌ Error ({cam['status']})"
            print(f"{icon} {cam['friendly_name']} [{state}]")
            # print(f"   ID: {cam['instance_id']}") # 调试用
    else:
        print(json.dumps(res, indent=2, ensure_ascii=False))