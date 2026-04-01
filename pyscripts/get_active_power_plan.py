import json
import subprocess
import os
import tempfile
from typing import Dict, Any

def get_active_power_plan(
    dry_run: bool = False,
    # 使用 r"" 原始字符串，保持路径安全的好习惯
    script_path: str = r"scripts\scripts\powershell\get_active_power_plan.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本获取当前活动的 Windows 电源计划及电池状态。

    Args:
        dry_run (bool): 仅模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含当前计划、可用计划列表及电源来源信息的字典。
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
        # 直接使用 text=True 和 encoding='utf-8'，信任脚本的输出设置
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
            # 6. 解析 JSON
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

# --- 测试代码 ---
if __name__ == "__main__":
    print("--- Test: Get Power Plan Info ---")
    target_script = r"scripts\scripts\powershell\get_active_power_plan.ps1"
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    # 即使是 dry_run，此脚本也会返回真实信息（因为它是只读的）
    res = get_active_power_plan(dry_run=True, script_path=target_script)
    
    print(json.dumps(res, indent=2, ensure_ascii=False))