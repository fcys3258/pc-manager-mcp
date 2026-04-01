import json
import subprocess
import os
import tempfile
from typing import Dict, Any, Literal

def get_pnp_device_list(
    problem_only: bool = False,
    limit: int = 50,
    sort_by: Literal["friendly_name", "class", "status", "problem_code"] = "friendly_name",
    dry_run: bool = False,
    # 使用 r"" 原始字符串
    script_path: str = r"scripts\scripts\powershell\get_pnp_device_list.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本获取即插即用(PnP)设备列表。
    
    特别适用于查找有驱动问题的设备 (Error Code 10, 28, 43 等)。
    
    Args:
        problem_only (bool): 如果为 True，仅返回有故障的设备 (排除正常的和手动禁用的)。
        limit (int): 返回的最大设备数量 (默认 50)。
        sort_by (str): 排序方式。
        dry_run (bool): 仅模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含设备列表的字典。
    """

    # 1. 构造参数负载
    payload = {
        "parameter": {
            "problem_only": problem_only,
            "limit": limit,
            "sort_by": sort_by,
            "dry_run": dry_run
        },
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
    
    target_script = r"scripts\scripts\powershell\get_pnp_device_list.ps1"
    print("--- Test: Check for Broken Devices ---")
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    # 示例：仅查找有问题的设备
    res = get_pnp_device_list(problem_only=True, script_path=target_script)
    
    if res.get("ok"):
        data = res['data']
        count = data.get('returned_count', 0)
        print(f"Broken Devices Found: {count}")
        
        if count > 0:
            for dev in data.get('devices', []):
                print(f"❌ {dev['friendly_name']} (Class: {dev['class']})")
                print(f"   Code {dev['problem_code']} - Status: {dev['status']}")
        else:
            print("✅ No hardware issues detected.")
            
    else:
        print(json.dumps(res, indent=2, ensure_ascii=False))