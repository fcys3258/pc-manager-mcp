import json
import subprocess
import os
import tempfile
from typing import Dict, Any

def delete_hosts_entry(
    hostname: str,
    dry_run: bool = False,
    script_path: str = r"scripts\scripts\powershell\delete_hosts_entry.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本从 Windows Hosts 文件中删除指定域名的条目。
    
    注意：此操作需要管理员权限。如果 Python 未以管理员身份运行，
    脚本会尝试弹窗请求提权 (UAC)。

    Args:
        hostname (str): 要删除的域名 (例如 "test.local" 或 "屏蔽的网站.com")。
        dry_run (bool): 如果为 True，仅模拟执行，不修改文件。默认为 False。
        script_path (str): ps1 脚本的本地路径。

    Returns:
        Dict[str, Any]: 执行结果字典，包含删除行数和备份路径等信息。
    """

    # 1. 构造参数负载
    payload = {
        "parameter": {
            "hostname": hostname,
            "dry_run": dry_run
        },
        "metadata": {
            "timeout_ms": 20000, # 给提权操作预留更多时间
            "agent_invoker": "python-client"
        }
    }

    # 2. 创建临时文件传递 JSON
    # 使用文件传递参数可以避免命令行中特殊字符（如空格、引号）的转义问题
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
        # 注意：如果触发了 UAC 提权，PowerShell 可能会在新窗口闪烁一下
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
        # 清理临时文件
        if os.path.exists(input_file_path):
            try:
                os.remove(input_file_path)
            except:
                pass


# --- 使用示例 ---
if __name__ == "__main__":
    
    # 场景 1: 模拟删除 (Dry Run)
    print("--- Test: Dry Run ---")
    target_host = "test.example.com"
    res_dry = delete_hosts_entry(target_host, dry_run=True)
    print(json.dumps(res_dry, indent=2, ensure_ascii=False))

    # 场景 2: 真实删除 (请谨慎运行)
    # 建议先在 hosts 文件里手动加一行 "127.0.0.1 test.example.com" 用于测试
    print("\n--- Test: Actual Delete ---")
    # res_real = delete_hosts_entry(target_host, dry_run=False)
    # print(json.dumps(res_real, indent=2, ensure_ascii=False))