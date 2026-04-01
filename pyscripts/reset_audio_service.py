import json
import subprocess
import os
import tempfile
from typing import Dict, Any

def reset_audio_service(
    dry_run: bool = False,
    # 使用 r"" 原始字符串避免路径转义问题
    script_path: str = r"scripts\scripts\powershell\reset_audio_service.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本重置 Windows 音频服务。
    
    通过重启 'Windows Audio Endpoint Builder' 和 'Windows Audio' 服务，
    解决 "电脑没声音"、"音频服务未运行" 或 "小喇叭红叉" 等问题。
    注意：此操作会暂时中断所有正在播放的声音。

    Args:
        dry_run (bool): 仅模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含服务重启结果的字典。
    """

    # 1. 构造参数负载
    payload = {
        "parameter": {
            "dry_run": dry_run
        },
        "metadata": {
            "timeout_ms": 30000, # 服务重启可能需要几秒到十几秒
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
    
    target_script = r"scripts\scripts\powershell\reset_audio_service.ps1"
    print("--- Test: Reset Audio Services (Dry Run) ---")
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    # 脚本内部有提权逻辑，可能会弹出 UAC
    # 建议先用 dry_run=True 测试流程
    res = reset_audio_service(dry_run=True, script_path=target_script)
    
    if res.get("ok"):
        if res['data'].get('result') == 'dry_run':
            print(f"✅ Dry Run: {res['data']['would_perform_action']}")
        else:
            print(f"Result: {res['data']['result']}")
            print("Services Status:")
            for svc in res['data']['final_status']:
                icon = "🟢" if svc['is_running'] else "🔴"
                print(f"{icon} {svc['name']}: {svc['status']}")
    else:
        print(json.dumps(res, indent=2, ensure_ascii=False))