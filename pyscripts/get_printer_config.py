import json
import subprocess
import os
import tempfile
from typing import Dict, Any, Optional

def get_printer_config(
    printer_name: Optional[str] = None,
    dry_run: bool = False,
    # 使用 r"" 原始字符串避免路径转义问题
    script_path: str = r"scripts\scripts\powershell\get_printer_config.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本获取打印机的当前配置。
    
    用于诊断 "打印出来是黑白的"、"双面打印没生效" 等问题。
    如果不指定 printer_name，默认获取系统默认打印机的配置。

    Args:
        printer_name (str, optional): 打印机名称。如果不传，自动查找默认打印机。
        dry_run (bool): 仅模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含打印机配置详情的字典。
    """

    # 1. 构造参数负载
    params = {
        "dry_run": dry_run
    }
    if printer_name:
        params['name'] = printer_name

    payload = {
        "parameter": params,
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
    
    target_script = r"scripts\scripts\powershell\get_printer_config.ps1"
    print("--- Test: Check Printer Config ---")
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    # 示例 1: 获取默认打印机配置
    res = get_printer_config(script_path=target_script)
    
    if res.get("ok"):
        data = res['data']
        print(f"Printer: {data['printer_name']}")
        print(f"Paper Size: {data.get('paper_size')}")
        
        color_mode = "Color" if data.get('color') else "Monochrome (Black & White)"
        print(f"Color Mode: {color_mode}")
        
        print(f"Duplex Mode: {data.get('duplex_mode')}")
    else:
        # 如果没有默认打印机或出错
        print(json.dumps(res, indent=2, ensure_ascii=False))