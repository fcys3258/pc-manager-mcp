import json
import subprocess
import os
import tempfile
from typing import Dict, Any, Optional

def clear_proxy_config(
    dry_run: bool = False,
    script_path: str = r"scripts\scripts\powershell\clear_proxy_config.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本清除 Windows 系统代理配置 (IE/Edge/Chrome 等使用的系统代理)。
    
    操作包括:
    1. 将 'ProxyEnable' 设置为 0。
    2. 删除 'ProxyServer' 注册表项。
    3. 删除 'AutoConfigURL' (PAC 脚本) 注册表项。
    4. 刷新 WinInet 设置以立即生效。

    Args:
        dry_run (bool): 如果为 True，仅模拟执行，不修改注册表。默认为 False。
        script_path (str): ps1 脚本的本地路径。

    Returns:
        Dict[str, Any]: 执行结果字典。
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

    # 2. 创建临时文件传递 JSON
    input_file_fd, input_file_path = tempfile.mkstemp(suffix=".json", text=True)

    try:
        with os.fdopen(input_file_fd, 'w', encoding='utf-8') as f:
            json.dump(payload, f, ensure_ascii=False)

        # 3. 构建 PowerShell 命令
        # 修改 HKCU 通常不需要管理员权限
        cmd = [
            "powershell",
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", script_path,
            "-InputFile", input_file_path
        ]

        # 4. 执行命令
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
    print("--- 1. Dry Run (模拟清除) ---")
    res_dry = clear_proxy_config(dry_run=True)
    print(json.dumps(res_dry, indent=2, ensure_ascii=False))

    print("\n--- 2. Actual Run (执行清除) ---")
    # 注意：这将真正清除你电脑的代理设置，请按需运行
    # res_real = clear_proxy_config(dry_run=False)
    # print(json.dumps(res_real, indent=2, ensure_ascii=False))