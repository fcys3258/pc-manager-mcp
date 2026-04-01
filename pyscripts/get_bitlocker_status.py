import json
import subprocess
import os
import tempfile
from typing import Dict, Any

def get_bitlocker_status(
    dry_run: bool = False,
    # 使用 r"" 原始字符串，防止路径转义问题
    script_path: str = r"scripts\scripts\powershell\get_bitlocker_status.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本获取磁盘 BitLocker 加密状态。
    
    支持自动降级：如果 BitLocker 模块不可用，会自动解析 manage-bde.exe 输出。
    注意：此操作需要管理员权限。

    Args:
        dry_run (bool): 仅模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含所有卷的加密状态信息。
    """

    # 1. 构造参数负载
    payload = {
        "parameter": {
            "dry_run": dry_run
        },
        "metadata": {
            "timeout_ms": 20000, # 读取硬件状态可能稍慢
            "agent_invoker": "python-client"
        }
    }

    # 2. 创建临时文件传递参数
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
    
    target_script = r"scripts\scripts\powershell\get_bitlocker_status.ps1"
    print("--- Test: BitLocker Status ---")
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    # 建议以管理员身份运行此 Python 脚本，否则会弹出 UAC 框
    res = get_bitlocker_status(script_path=target_script)
    
    if res.get("ok"):
        data = res['data']
        print(f"Total Volumes: {data.get('volume_count')}")
        print(f"All Protected: {data.get('all_protected')}")
        
        # 检查是否有回退模式信息
        if res.get("metadata", {}).get("fallback_mode"):
            print("[Info] Running in Fallback Mode (manage-bde.exe)")

        for vol in data.get('volumes', []):
            status_icon = "🔒" if vol['protection_status'] in ['On', 'FullyEncrypted'] else "🔓"
            mount = vol.get('mount_point', 'Unknown')
            # 兼容两种模式的字段名差异 (脚本已尽量统一，但 fallback 模式可能少某些字段)
            percent = vol.get('encryption_percentage', 0)
            
            print(f"{status_icon} {mount} - {vol['protection_status']} ({percent}%)")
    else:
        print(json.dumps(res, indent=2, ensure_ascii=False))