import json
import subprocess
import os
import tempfile
from typing import Dict, Any

def set_active_power_plan(
    plan_guid: str,
    dry_run: bool = False,
    # 使用 r"" 原始字符串避免路径转义问题
    script_path: str = r"scripts\scripts\powershell\set_active_power_plan.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本设置当前活动的电源计划。
    
    用于在 "高性能"、"平衡" 和 "省电" 模式之间切换。
    请先使用 get_active_power_plan 获取可用的 plan_guid。

    Args:
        plan_guid (str): 目标电源计划的 GUID (例如 "381b4222-f694-41f0-9685-ff5bb260df2e")。
        dry_run (bool): 仅模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含操作结果的字典。
    """

    # 1. 构造参数负载
    payload = {
        "parameter": {
            "plan_guid": plan_guid,
            "dry_run": dry_run
        },
        "metadata": {
            "timeout_ms": 5000, # 命令执行非常快
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
    
    target_script = r"scripts\scripts\powershell\set_active_power_plan.ps1"
    print("--- Test: Set Power Plan ---")
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    # 常用 GUID (Windows 默认):
    # 平衡: 381b4222-f694-41f0-9685-ff5bb260df2e
    # 高性能: 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
    # 省电: a1841308-3541-4fab-bc81-f71556f20b4a
    
    # 建议先调用 get_active_power_plan 确认 GUID 是否存在
    target_guid = "381b4222-f694-41f0-9685-ff5bb260df2e" # 平衡
    
    print(f"Switching to Plan: {target_guid}")
    
    res = set_active_power_plan(
        plan_guid=target_guid, 
        dry_run=True, # 建议先测试 dry_run
        script_path=target_script
    )
    
    if res.get("ok"):
        data = res['data']
        if data.get('result') == 'dry_run':
            print(f"✅ Dry Run: {data['would_perform_action']}")
            print(f"   Current: {data.get('current_plan_guid')}")
        else:
            print(f"✅ Success: {data.get('message')}")
            print(f"   Active: {data.get('active_plan_guid')}")
    else:
        print(json.dumps(res, indent=2, ensure_ascii=False))