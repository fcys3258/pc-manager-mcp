import json
import subprocess
import os
import tempfile
from typing import Dict, Any

def get_mic_privacy_settings(
    dry_run: bool = False,
    # 使用 r"" 原始字符串避免路径转义问题
    script_path: str = r"scripts\scripts\powershell\get_mic_privacy_settings.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本获取 Windows 麦克风隐私设置。
    
    用于诊断 "麦克风无法录音" 或 "会议软件没声音" 的问题。
    检查项包括: 全局开关、系统级开关、以及各应用的单独授权状态。

    Args:
        dry_run (bool): 仅模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含隐私设置详情的字典。
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
    
    target_script = r"scripts\scripts\powershell\get_mic_privacy_settings.ps1"
    print("--- Test: Check Mic Privacy ---")
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    res = get_mic_privacy_settings(script_path=target_script)
    
    if res.get("ok"):
        data = res['data']
        mic = data.get('microphone', {})
        
        status_icon = "🟢 Allowed" if mic.get('overall_allowed') else "🔴 Blocked"
        print(f"Overall Status: {status_icon}")
        
        if data.get('issues'):
            print("Issues Found:")
            for issue in data['issues']:
                print(f"- {issue}")
        
        print(f"\nApp Permissions ({data.get('app_count')} found):")
        # 列出前 5 个有明确权限设置的应用
        count = 0
        for app in data.get('app_permissions', []):
            if app.get('allowed') is not None:
                perm = "Allowed" if app['allowed'] else "Denied"
                used = f"(Last used: {app.get('last_used')})" if app.get('last_used') else ""
                print(f"- {app['app_id']}: {perm} {used}")
                count += 1
                if count >= 5: break
                
    else:
        print(json.dumps(res, indent=2, ensure_ascii=False))