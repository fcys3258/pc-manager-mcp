import json
import subprocess
import os
import tempfile
from typing import Dict, Any

def get_password_expiry(
    dry_run: bool = False,
    # 使用 r"" 原始字符串避免路径转义问题
    script_path: str = r"scripts\scripts\powershell\get_password_expiry.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本获取当前用户的密码过期信息。
    
    自动识别本地用户或域用户，返回过期时间、剩余天数及状态（如即将过期、永不过期）。

    Args:
        dry_run (bool): 仅模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含密码过期详情的字典。
    """

    # 1. 构造参数负载
    payload = {
        "parameter": {
            "dry_run": dry_run
        },
        "metadata": {
            "timeout_ms": 10000, # 域查询可能涉及网络，给足时间
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
        # 脚本内部处理了编码，Python 端直接读取 UTF-8
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
    
    target_script = r"scripts\scripts\powershell\get_password_expiry.ps1"
    print("--- Test: Check Password Expiry ---")
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    res = get_password_expiry(script_path=target_script)
    
    if res.get("ok"):
        data = res['data']
        print(f"User: {data['username']} (Domain: {data['domain']})")
        print(f"Is Domain User: {data['is_domain_user']}")
        
        status = data.get('status')
        status_map = {
            'ok': "✅ 正常",
            'expired': "🔴 已过期",
            'expiring_soon': "⚠️ 即将过期",
            'never_expires': "♾️ 永不过期",
            'detection_failed': "❓ 检测失败"
        }
        print(f"Status: {status_map.get(status, status)}")
        
        if data.get('password_never_expires'):
            print("Expiry Date: Never")
        else:
            print(f"Expiry Date: {data.get('password_expires')}")
            print(f"Days Remaining: {data.get('days_until_expiry')}")
            
    else:
        print(json.dumps(res, indent=2, ensure_ascii=False))