import json
import subprocess
import os
import tempfile
from typing import Dict, Any

def set_default_printer(
    printer_name: str,
    dry_run: bool = False,
    # 使用 r"" 原始字符串避免路径转义问题
    script_path: str = r"scripts\scripts\powershell\set_default_printer.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本将指定打印机设置为系统默认打印机。
    
    用于解决 "打印时总选错打印机" 或 "默认打印机被意外更改" 的问题。
    此操作不需要管理员权限。

    Args:
        printer_name (str): 目标打印机名称 (例如 "HP LaserJet Pro M402n")。
        dry_run (bool): 仅模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含操作结果的字典。
    """

    # 1. 构造参数负载
    payload = {
        "parameter": {
            "printer_name": printer_name,
            "dry_run": dry_run
        },
        "metadata": {
            "timeout_ms": 10000,
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
    
    target_script = r"scripts\scripts\powershell\set_default_printer.ps1"
    print("--- Test: Set Default Printer (Dry Run) ---")
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    # 示例：尝试设置一个虚拟打印机为默认
    # 请确保该打印机名称在系统中真实存在，否则会报错
    target_printer = "Microsoft Print to PDF"
    
    print(f"Setting default to: {target_printer}")
    
    res = set_default_printer(
        printer_name=target_printer, 
        dry_run=True, # 建议先测试 dry_run
        script_path=target_script
    )
    
    if res.get("ok"):
        if res['data'].get('result') == 'dry_run':
            print(f"✅ Dry Run: {res['data']['would_perform_action']}")
        else:
            print(f"✅ Success: {res['data']['message']}")
    else:
        # 常见错误是打印机名称拼写错误
        print(f"Error: {res.get('error', {}).get('message')}")