import json
import subprocess
import os
import tempfile
from typing import Dict, Any, Literal

def enable_startup_item(
    item_type: Literal["REGISTRY", "TASK", "FOLDER"],
    item_path: str,
    item_name: str,
    dry_run: bool = False,
    script_path: str = r"scripts\scripts\powershell\enable_startup_item.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本启用（恢复）指定的 Windows 启动项。

    Args:
        item_type: 启动项类型 ("REGISTRY", "TASK", "FOLDER").
        item_path: 启动项的**原始路径**。
            - REGISTRY: 注册表键路径 (如 'HKCU:\\...\\Run')
            - TASK: 任务路径 (如 '\\')
            - FOLDER: 文件在**启动文件夹中**的完整路径 (不是在 disabled 文件夹中的路径)
        item_name: 名称。
            - REGISTRY: 注册表值名称
            - TASK: 任务名称
            - FOLDER: 文件名
        dry_run (bool): 模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 执行结果。
    """

    # 1. 构造 startup_id (TYPE::PATH::NAME)
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

    # 3. 创建临时文件
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

        # 5. 执行命令 (可能触发 UAC)
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            encoding='utf-8'
        )

        # 6. 错误处理
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
    
    # 场景 1: 恢复一个注册表启动项 (Dry Run)
    print("--- Test: Enable Registry Item (Dry Run) ---")
    res_reg = enable_startup_item(
        item_type="REGISTRY",
        item_path=r"HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
        item_name="OneDrive",
        dry_run=True
    )
    print(json.dumps(res_reg, indent=2, ensure_ascii=False))

    # 场景 2: 恢复一个文件启动项 (Dry Run)
    # 注意：path 填的是“原本应该在的位置”，脚本会自动去 disabled_startup 子目录找
    print("\n--- Test: Enable Folder Item (Dry Run) ---")
    res_folder = enable_startup_item(
        item_type="FOLDER",
        item_path=r"C:\Users\User\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\app.lnk",
        item_name="app.lnk",
        dry_run=True
    )
    print(json.dumps(res_folder, indent=2, ensure_ascii=False))