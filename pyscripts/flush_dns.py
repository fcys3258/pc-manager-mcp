import json
import subprocess
import os
import tempfile
from typing import Dict, Any

def flush_dns(
    dry_run: bool = False,
    script_path: str = r"scripts\scripts\powershell\flush_dns.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本刷新 Windows DNS 客户端缓存。
    
    此操作通常用于解决无法解析域名、解析旧 IP 或网络连接不稳定的问题。
    操作需要管理员权限。脚本内置了自动提权逻辑，如果 Python 非管理员运行，会弹出 UAC 提示。

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
            "timeout_ms": 20000, # DNS 刷新通常很快
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
        # 如果不是管理员，PowerShell 脚本会触发 UAC 弹窗
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
    
    # 场景: 模拟刷新 DNS (Dry Run)
    print("--- Test: Flush DNS (Dry Run) ---")
    res_dry = flush_dns(dry_run=True)
    print(json.dumps(res_dry, indent=2, ensure_ascii=False))

    # 场景: 真实刷新 (需要管理员权限)
    # res_real = flush_dns(dry_run=False)
    # print(json.dumps(res_real, indent=2, ensure_ascii=False))