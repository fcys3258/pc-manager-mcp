import json
import subprocess
import os
import tempfile
from typing import Dict, Any

def install_printer(
    name: str,
    ipp_url: str,
    driver_name: str = "Microsoft IPP Class Driver",
    dry_run: bool = False,
    # 使用 r"" 原始字符串避免路径转义问题
    script_path: str = r"scripts\scripts\powershell\install_printer.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本通过 IPP URL 安装网络打印机。
    
    支持使用通用 IPP 驱动程序快速添加打印机，无需手动下载驱动。
    常用于企业环境配置网络打印机。

    Args:
        name (str): 要创建的打印机名称 (例如 "Office_HP_Color")。
        ipp_url (str): 打印机的 IPP 地址 (例如 "http://192.168.1.100/ipp/print")。
        driver_name (str): 驱动程序名称，默认为 "Microsoft IPP Class Driver"。
        dry_run (bool): 仅模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含安装结果的字典。
    """

    # 1. 构造参数负载
    payload = {
        "parameter": {
            "name": name,
            "ipp_url": ipp_url,
            "driver_name": driver_name,
            "dry_run": dry_run
        },
        "metadata": {
            "timeout_ms": 60000, # 安装驱动可能需要较长时间
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
    
    target_script = r"scripts\scripts\powershell\install_printer.ps1"
    print("--- Test: Install IPP Printer ---")
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    # 示例：模拟安装一个虚拟打印机 (开启 dry_run 以避免真实修改系统)
    # 真实的 IPP URL 通常长这样: http://printer_ip:631/ipp/print
    printer_name = "Test_IPP_Printer"
    ipp_url = "http://192.168.1.200:631/ipp/print"
    
    print(f"Installing '{printer_name}' from {ipp_url}...")
    
    # 脚本内部有提权逻辑，可能会弹出 UAC
    res = install_printer(
        name=printer_name, 
        ipp_url=ipp_url, 
        dry_run=True, # 生产环境请设为 False
        script_path=target_script
    )
    
    if res.get("ok"):
        if res['data'].get('result') == 'dry_run':
            print(f"✅ Dry Run: {res['data']['would_perform_action']}")
        else:
            print(f"✅ Success: {res['data']['message']}")
            print(f"   Name: {res['data']['printer_name']}")
            print(f"   Driver: {res['data']['driver_name']}")
    else:
        print(json.dumps(res, indent=2, ensure_ascii=False))