import json
import subprocess
import os
import tempfile
from typing import Dict, Any

def force_gpupdate(
    dry_run: bool = False,
    # 使用 r"" (原始字符串) 避免 \f (force) 被识别为换页符
    script_path: str = r"scripts\scripts\powershell\force_gpupdate.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本强制刷新组策略 (gpupdate /force)。

    Args:
        dry_run (bool): 如果为 True，仅模拟执行。默认为 False。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 执行结果。
    """

    # 1. 构造参数负载
    payload = {
        "parameter": {
            "dry_run": dry_run
        },
        "metadata": {
            "timeout_ms": 60000, # GPUpdate 可能需要较长时间
            "agent_invoker": "python-client"
        }
    }

    # 2. 创建临时文件传递参数
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
        # 脚本内部已设置 [Console]::OutputEncoding = UTF8，直接使用 utf-8 读取
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            encoding='utf-8'
        )

        # 5. 错误处理与解析
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
    
    print("--- Test: Force GPUpdate (Dry Run) ---")
    
    # 路径检查
    target_script = r"scripts\scripts\powershell\force_gpupdate.ps1"
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本文件: {target_script}")
    
    res_dry = force_gpupdate(dry_run=True, script_path=target_script)
    print(json.dumps(res_dry, indent=2, ensure_ascii=False))