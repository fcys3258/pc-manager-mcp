import json
import subprocess
import os
import tempfile
from typing import Dict, Any

def reset_network_stack(
    dry_run: bool = False,
    # 使用 r"" 原始字符串避免路径转义问题
    script_path: str = r"scripts\scripts\powershell\reset_network_stack.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本重置 Windows 网络协议栈 (Winsock 和 TCP/IP)。
    
    这是解决顽固网络故障的终极手段。
    注意：执行后通常需要重启计算机才能生效。
    
    Args:
        dry_run (bool): 仅模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含操作结果的字典。
    """

    # 1. 构造参数负载
    payload = {
        "parameter": {
            "dry_run": dry_run
        },
        "metadata": {
            "timeout_ms": 30000,
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
    
    target_script = r"scripts\scripts\powershell\reset_network_stack.ps1"
    print("--- Test: Reset Network Stack ---")
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    # 强烈建议先使用 dry_run 测试
    print("Simulating network reset (Dry Run)...")
    res = reset_network_stack(dry_run=True, script_path=target_script)
    
    if res.get("ok"):
        if res['data'].get('result') == 'dry_run':
            print(f"✅ Dry Run: {res['data']['would_perform_action']}")
        else:
            print("✅ Network Reset Completed.")
            if res.get('metadata', {}).get('reboot_required'):
                print("⚠️  A system reboot is required to complete the operation.")
    else:
        print(json.dumps(res, indent=2, ensure_ascii=False))