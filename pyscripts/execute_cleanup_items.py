import json
import subprocess
import os
import tempfile
from typing import List, Dict, Any, Literal

# 定义允许的清理项 ID 类型，方便代码提示
CleanupID = Literal[
    "SYSTEM_TEMP", 
    "USER_TEMP", 
    "RECYCLE_BIN", 
    "CRASH_DUMPS", 
    "WECHAT_CACHE", 
    "WXWORK_CACHE", 
    "BROWSER_CACHE", 
    "WINDOWS_UPDATE_CACHE"
]

def execute_cleanup_items(
    cleanup_ids: List[CleanupID],
    dry_run: bool = False,
    script_path: str = r"scripts\scripts\powershell\execute_cleanup_items.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本执行磁盘清理任务。

    Args:
        cleanup_ids (List[str]): 要清理的项目 ID 列表。
            可选值:
            - "SYSTEM_TEMP": Windows 系统临时文件 (需要管理员权限)
            - "USER_TEMP": 当前用户临时文件
            - "RECYCLE_BIN": 清空回收站
            - "CRASH_DUMPS": 系统及应用崩溃转储文件 (部分需要管理员权限)
            - "WECHAT_CACHE": 微信缓存 (会强制关闭微信)
            - "WXWORK_CACHE": 企业微信缓存 (会强制关闭企业微信)
            - "BROWSER_CACHE": 浏览器缓存 (Chrome/Edge, 会强制关闭浏览器)
            - "WINDOWS_UPDATE_CACHE": Windows 更新缓存 (需要管理员权限)
        dry_run (bool): 模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 执行结果，包含每个项目的清理状态。
    """

    # 1. 校验参数
    if not cleanup_ids:
        return {
            "ok": False,
            "error": {"code": "INVALID_ARGUMENT", "message": "cleanup_ids list cannot be empty"}
        }

    # 2. 构造参数负载
    payload = {
        "parameter": {
            "cleanup_ids": cleanup_ids,
            "dry_run": dry_run
        },
        "metadata": {
            "timeout_ms": 60000, # 清理可能耗时较长，给 60s
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

        # 5. 执行命令 (如果清理 SYSTEM_TEMP 等项目，会触发 UAC)
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
    
    # 场景 1: 模拟清理用户临时文件和回收站 (Dry Run)
    # 不需要管理员权限
    print("--- Test 1: User Cleanup (Dry Run) ---")
    res_user = execute_cleanup_items(
        cleanup_ids=["USER_TEMP", "RECYCLE_BIN"],
        dry_run=True
    )
    print(json.dumps(res_user, indent=2, ensure_ascii=False))

    # 场景 2: 模拟清理系统垃圾 (Dry Run)
    # 涉及 SYSTEM_TEMP 和 WINDOWS_UPDATE_CACHE，如果不以管理员运行，会弹 UAC 框
    print("\n--- Test 2: System Cleanup (Dry Run) ---")
    res_sys = execute_cleanup_items(
        cleanup_ids=["SYSTEM_TEMP", "WINDOWS_UPDATE_CACHE"],
        dry_run=True
    )
    print(json.dumps(res_sys, indent=2, ensure_ascii=False))