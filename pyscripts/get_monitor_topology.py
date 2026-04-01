import json
import subprocess
import os
import tempfile
from typing import Dict, Any

def get_monitor_topology(
    dry_run: bool = False,
    # 使用 r"" 原始字符串避免路径转义问题
    script_path: str = r"scripts\scripts\powershell\get_monitor_topology.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本获取显示器拓扑结构和显卡信息。
    
    该工具用于诊断 "分辨率不对"、"外接显示器不亮" 或 "屏幕模糊" 等问题。
    它能识别显示器的物理尺寸(英寸)、制造商、序列号以及当前的分辨率设置。

    Args:
        dry_run (bool): 仅模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含显示器、显卡和桌面设置的详细信息。
    """

    # 1. 构造参数负载
    payload = {
        "parameter": {
            "dry_run": dry_run
        },
        "metadata": {
            "timeout_ms": 10000, # WMI 查询通常较快
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
    
    target_script = r"scripts\scripts\powershell\get_monitor_topology.ps1"
    print("--- Test: Get Monitor Topology ---")
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    res = get_monitor_topology(script_path=target_script)
    
    if res.get("ok"):
        data = res['data']
        print(f"Multi-Monitor Setup: {data.get('is_multi_monitor')}")
        
        print(f"\n--- Monitors Found ({data.get('monitor_count')}) ---")
        for mon in data.get('monitors', []):
            name = mon.get('friendly_name') or mon.get('instance_name')
            size = f"{mon.get('diagonal_inch')} inch" if mon.get('diagonal_inch') else "Unknown size"
            active = "Active" if mon.get('active') else "Inactive"
            print(f"[{mon['index']}] {name} - {size} ({active})")
            if mon.get('manufacturer'):
                print(f"    Manufacturer: {mon['manufacturer']}")
        
        print(f"\n--- Video Controllers ({data.get('video_controller_count')}) ---")
        for vc in data.get('video_controllers', []):
            print(f"- {vc['name']}")
            print(f"  Resolution: {vc['current_horizontal_resolution']} x {vc['current_vertical_resolution']} @ {vc['current_refresh_rate']}Hz")
            print(f"  Driver: {vc['driver_version']} ({vc['driver_date']})")
            
    else:
        print(json.dumps(res, indent=2, ensure_ascii=False))