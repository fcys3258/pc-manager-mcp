import json
import subprocess
import os
import tempfile
from typing import Dict, Any

def get_antivirus_status(
    dry_run: bool = False,
    # 使用 r"" 原始字符串处理路径
    script_path: str = r"scripts\scripts\powershell\get_antivirus_status.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本获取当前系统的杀毒软件状态。
    
    检测范围：
    1. 第三方杀毒软件 (通过 WMI SecurityCenter2)
    2. Windows Defender 详细状态 (通过 Get-MpComputerStatus)
    
    Args:
        dry_run (bool): 仅模拟执行 (此脚本为只读，dry_run 返回结果与真实运行一致)。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含杀软列表、启用状态及更新状态的字典。
    """

    # 1. 构造参数负载
    payload = {
        "parameter": {
            "dry_run": dry_run
        },
        "metadata": {
            "timeout_ms": 15000, # WMI 查询通常较快
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
        # 脚本内部已强制 UTF-8 输出，直接使用 utf-8 读取
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
    
    target_script = r"scripts\scripts\powershell\get_antivirus_status.ps1"
    print("--- Test: Get Antivirus Status ---")
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    res = get_antivirus_status(script_path=target_script)
    
    if res.get("ok"):
        print(json.dumps(res['data'], indent=2, ensure_ascii=False))
    else:
        print(json.dumps(res, indent=2, ensure_ascii=False))