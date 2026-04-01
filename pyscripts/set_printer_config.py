import json
import subprocess
import os
import tempfile
from typing import Dict, Any, Optional

def set_printer_config(
    printer_name: str,
    paper_size: Optional[str] = None,
    color: Optional[bool] = None,
    duplex: Optional[str] = None,
    dry_run: bool = False,
    # 使用 r"" 原始字符串避免路径转义问题
    script_path: str = r"scripts\scripts\powershell\set_printer_config.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本修改打印机的默认配置。
    
    用于纠正 "默认单面打印"、"默认黑白打印" 或 "纸张大小错误" 的问题。
    注意：此操作可能需要管理员权限。

    Args:
        printer_name (str): 打印机名称 (例如 "HP Color LaserJet").
        paper_size (str, optional): 纸张大小 (例如 "A4", "Letter").
        color (bool, optional): 是否彩色 (True=Color, False=Monochrome).
        duplex (str, optional): 双面模式 ("OneSided", "TwoSidedLongEdge", "TwoSidedShortEdge").
        dry_run (bool): 仅模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含操作结果的字典。
    """

    # 1. 构造参数负载
    params = {
        "printer_name": printer_name,
        "dry_run": dry_run
    }
    if paper_size: params['paper_size'] = paper_size
    if color is not None: params['color'] = color
    if duplex: params['duplex'] = duplex

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
    
    target_script = r"scripts\scripts\powershell\set_printer_config.ps1"
    print("--- Test: Configure Printer ---")
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    # 示例：将 "Microsoft Print to PDF" 设置为 A4 纸张
    target_printer = "OneNote (Desktop)"
    
    print(f"Configuring '{target_printer}'...")
    
    # 脚本内部有提权逻辑，可能会弹出 UAC
    res = set_printer_config(
        printer_name=target_printer,
        paper_size="A4",
        # duplex="OneSided", # PDF 打印机通常不支持双面设置，这里仅作演示
        dry_run=True, # 建议先测试 dry_run
        script_path=target_script
    )
    
    if res.get("ok"):
        if res['data'].get('result') == 'dry_run':
            print(f"✅ Dry Run: {res['data']['would_perform_action']}")
        else:
            print(f"✅ Success: {res['data']['message']}")
            print(f"   Applied: {res['data']['applied_settings']}")
    else:
        print(json.dumps(res, indent=2, ensure_ascii=False))