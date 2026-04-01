import json
import subprocess
import os
import tempfile
from typing import Dict, Any, Literal

def disable_startup_item(
    item_type: Literal["REGISTRY", "TASK", "FOLDER"],
    item_path: str,
    item_name: str,
    dry_run: bool = False,
    script_path: str = r"scripts\scripts\powershell\disable_startup_item.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本禁用指定的 Windows 启动项。

    Args:
        item_type: 启动项类型。
            - "REGISTRY": 注册表启动项 (HKCU/HKLM...Run)
            - "TASK": 任务计划程序
            - "FOLDER": 启动文件夹中的文件 (shell:startup)
        item_path: 路径。
            - 对于 REGISTRY: 注册表键路径 (如 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Run')
            - 对于 TASK: 任务路径 (通常为 '\\' 或 '\\Microsoft\\Windows\\...')
            - 对于 FOLDER: 文件的完整路径
        item_name: 名称。
            - 对于 REGISTRY: 注册表值的名称
            - 对于 TASK: 任务名称
            - 对于 FOLDER: 文件名 (其实在 FOLDER 模式下 path 已经包含了文件名，但为了格式统一仍需传入，或者传 path 的最后一部分)
        dry_run (bool): 如果为 True，仅模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 执行结果。
    """

    # 1. 构造 startup_id
    # 格式要求: TYPE::PATH::NAME
    # 注意：如果 path 中包含空格，脚本通过 split('::') 处理，所以是安全的
    startup_id = f"{item_type}::{item_path}::{item_name}"

    # 2. 构造参数负载
    payload = {
        "parameter": {
            "startup_id": startup_id,
            "dry_run": dry_run
        },
        "metadata": {
            "timeout_ms": 20000,
            "agent_invoker": "python-client"
        }
    }

    # 3. 创建临时文件传递参数
    input_file_fd, input_file_path = tempfile.mkstemp(suffix=".json", text=True)

    try:
        with os.fdopen(input_file_fd, 'w', encoding='utf-8') as f:
            json.dump(payload, f, ensure_ascii=False)

        # 4. 构建 PowerShell 命令
        cmd = [
            "powershell",
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", script_path,
            "-InputFile", input_file_path
        ]

        # 5. 执行命令
        # 如果需要提权，PowerShell 脚本会触发 UAC 弹窗
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            encoding='utf-8'
        )

        # 6. 错误处理与解析
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
    
    # 场景 1: 禁用一个常见的注册表启动项 (Dry Run)
    # 比如禁用 OneDrive (仅作演示，实际路径请按需修改)
    print("--- Test: Registry Dry Run ---")
    res_reg = disable_startup_item(
        item_type="REGISTRY",
        item_path=r"HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
        item_name="OneDrive",
        dry_run=True
    )
    print(json.dumps(res_reg, indent=2, ensure_ascii=False))

    # 场景 2: 禁用一个计划任务 (Dry Run)
    print("\n--- Test: Task Dry Run ---")
    res_task = disable_startup_item(
        item_type="TASK",
        item_path="\\", # 根路径
        item_name="OneDrive Standalone Update Task-S-1-5-21...", # 示例任务名
        dry_run=True
    )
    print(json.dumps(res_task, indent=2, ensure_ascii=False))