import json
import subprocess
import os
import tempfile
from typing import Dict, Any, Optional

def uninstall_software(
    name: Optional[str] = None,
    uninstall_string: Optional[str] = None,
    force_quiet: bool = False,
    dry_run: bool = False,
    # 使用 r"" 原始字符串避免路径转义问题
    script_path: str = r"scripts\scripts\powershell\uninstall_software.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本卸载指定的软件。
    
    支持通过软件名称自动查找注册表中的卸载命令，或者直接执行给定的卸载字符串。
    
    Args:
        name (str, optional): 软件名称 (支持模糊匹配，如 "Chrome")。
        uninstall_string (str, optional): 直接指定卸载命令 (如果已知)。
        force_quiet (bool): 尝试强制静默卸载 (仅对 MSI 有效，其他类型取决于安装包)。
        dry_run (bool): 仅模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含操作启动结果的字典。
    """

    # 1. 构造参数负载
    params = {
        "force_quiet": force_quiet,
        "dry_run": dry_run
    }
    if name: params['name'] = name
    if uninstall_string: params['uninstall_string'] = uninstall_string
    
    if not name and not uninstall_string:
        return {"ok": False, "error": {"code": "INVALID_ARGUMENT", "message": "Either name or uninstall_string must be provided"}}

    payload = {
        "parameter": params,
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
    
    target_script = r"scripts\scripts\powershell\uninstall_software.ps1"
    print("--- Test: Uninstall Software (Dry Run) ---")
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    # 示例：模拟卸载 7-Zip
    target_app = "7-Zip"
    
    print(f"Searching for uninstaller: {target_app}")
    
    # 脚本内部有提权逻辑，可能会弹出 UAC
    res = uninstall_software(
        name=target_app, 
        dry_run=True, # 强烈建议先测试 dry_run
        script_path=target_script
    )
    
    if res.get("ok"):
        if res['data'].get('result') == 'dry_run':
            print(f"✅ Found: {res['data']['software_name']}")
            print(f"   Command: {res['data']['would_perform_action']}")
            print(f"   Type: {res['data']['command_type']}")
            
            if res['data'].get('user_interaction_required'):
                print("ℹ️  Note: This uninstaller may pop up a GUI and require user clicks.")
            else:
                print("⚡ Silent uninstallation likely possible.")
    else:
        # 常见错误是找不到软件
        print(f"Error: {res.get('error', {}).get('message')}")