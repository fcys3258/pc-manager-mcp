import json
import subprocess
import os
import tempfile
from typing import Dict, Any

def get_tpm_status(
    dry_run: bool = False,
    # 使用 r"" 原始字符串
    script_path: str = r"scripts\scripts\powershell\get_tpm_status.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本获取 TPM (可信平台模块) 的状态。
    
    用于诊断 BitLocker 无法开启、Windows Hello 不可用或系统安全性检查。
    注意：此操作需要管理员权限。

    Args:
        dry_run (bool): 仅模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含 TPM 状态详情的字典。
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
    
    target_script = r"scripts\scripts\powershell\get_tpm_status.ps1"
    print("--- Test: Check TPM Status ---")
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    # 脚本内部有提权逻辑，可能会弹出 UAC
    res = get_tpm_status(script_path=target_script)
    
    if res.get("ok"):
        data = res['data']
        ready_icon = "✅ YES" if data.get('overall_ready') else "❌ NO"
        print(f"TPM Ready: {ready_icon}")
        
        tpm = data.get('tpm', {})
        if tpm.get('tpm_present'):
            print(f"Manufacturer: {tpm.get('manufacturer_id_txt')} (v{tpm.get('manufacturer_version')})")
            print(f"Status Details:")
            print(f"  - Enabled: {tpm.get('tpm_enabled')}")
            print(f"  - Activated: {tpm.get('tpm_activated')}")
            print(f"  - Owned: {tpm.get('tpm_owned')}")
        else:
            print("TPM Chip not detected.")
    else:
        print(json.dumps(res, indent=2, ensure_ascii=False))