import json
import subprocess
import os
import tempfile
from typing import Dict, Any

def get_hosts_content(
    dry_run: bool = False,
    # 使用 r"" 原始字符串避免路径转义问题
    script_path: str = r"scripts\scripts\powershell\get_hosts_content.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本读取并解析 Windows Hosts 文件内容。
    
    该工具用于检查本地 DNS 映射，排查域名被劫持或开发环境配置错误的问题。
    它会自动忽略注释行 (#) 和空行。

    Args:
        dry_run (bool): 仅模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含解析后的 Hosts 条目列表。
    """

    # 1. 构造参数负载
    payload = {
        "parameter": {
            "dry_run": dry_run
        },
        "metadata": {
            "timeout_ms": 5000, # 读取文本文件非常快
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
    
    target_script = r"scripts\scripts\powershell\get_hosts_content.ps1"
    print("--- Test: Read Hosts File ---")
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    res = get_hosts_content(script_path=target_script)
    
    if res.get("ok"):
        entries = res['data']['entries']
        print(f"Total valid entries: {res['data']['entry_count']}")
        print("-" * 40)
        print(f"{'IP Address':<15} | {'Hostnames'}")
        print("-" * 40)
        
        for entry in entries:
            hosts = ", ".join(entry['hostnames'])
            print(f"{entry['ip_address']:<15} | {hosts}")
    else:
        print(json.dumps(res, indent=2, ensure_ascii=False))