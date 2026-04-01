import json
import subprocess
import os
import tempfile
from typing import Union, Dict, Any, Optional

def cancel_print_job(
    printer_name: str, 
    job_id: Union[int, str], 
    dry_run: bool = False, 
    script_path: str = "scripts/scripts/powershell/cancel_print_job.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本取消指定的打印任务或清空打印队列。
    
    Args:
        printer_name (str): 目标打印机的名称 (例如 "HP LaserJet M1005").
        job_id (Union[int, str]): 要取消的任务 ID (整数)，或者传递字符串 "all" 以取消该打印机的所有任务。
        dry_run (bool): 如果为 True，仅模拟执行，不实际取消任务。默认为 False。
        script_path (str): cancel_print_job.ps1 脚本的本地文件路径。

    Returns:
        Dict[str, Any]: 包含执行结果的字典。
                        结构示例: {'ok': True, 'data': {...}, 'error': None}
    """
    
    # 1. 构造参数负载
    payload = {
        "parameter": {
            "printer_name": printer_name,
            "job_id": job_id,
            "dry_run": dry_run
        },
        "metadata": {
            "timeout_ms": 60000,  # 给脚本设置 60s 的内部超时预算
            "agent_invoker": "python-agent"
        }
    }

    # 2. 创建临时文件以传递 JSON 参数
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

        # 4. 执行命令并捕获输出
        # PowerShell 脚本会自动处理提权 (Auto-elevate)，可能会在屏幕上弹出 UAC 提示
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            encoding='utf-8' # 确保与脚本的 [Console]::OutputEncoding 匹配
        )

        # 5. 处理执行结果
        if result.stderr and not result.stdout:
            # 如果只有错误输出且没有标准输出，说明脚本崩溃或未按预期运行
            return {
                "ok": False,
                "error": {
                    "code": "SUBPROCESS_ERROR",
                    "message": result.stderr.strip()
                }
            }

        # 尝试解析 JSON 输出
        try:
            output_data = json.loads(result.stdout)
            return output_data
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
    # 示例 1: 取消特定 ID 的任务
    print("--- Test 1: Specific Job ---")
    res1 = cancel_print_job(
        printer_name="OneNote (Desktop)", 
        job_id=123, 
        dry_run=True # 开启 dry_run 用于测试
    )
    print(json.dumps(res1, indent=2, ensure_ascii=False))

    # 示例 2: 取消所有任务
    print("\n--- Test 2: All Jobs ---")
    res2 = cancel_print_job(
        printer_name="OneNote (Desktop)", 
        job_id="all", 
        dry_run=True
    )
    print(json.dumps(res2, indent=2, ensure_ascii=False))