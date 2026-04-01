import json
import subprocess
import os
import tempfile
from typing import Dict, Any

def get_user_context(
    dry_run: bool = False,
    # 使用 r"" 原始字符串避免路径转义问题
    script_path: str = r"scripts\scripts\powershell\get_user_context.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本获取当前用户的上下文信息。
    
    该工具用于识别 "我是谁"，包括用户名、是否拥有管理员权限以及是否为域用户。
    这对于判断后续操作是否有权限执行至关重要。

    Args:
        dry_run (bool): 仅模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含用户上下文详情的字典。
    """

    # 1. 构造参数负载
    payload = {
        "parameter": {
            "dry_run": dry_run
        },
        "metadata": {
            "timeout_ms": 5000, # 执行非常快
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
    
    target_script = r"scripts\scripts\powershell\get_user_context.ps1"
    print("--- Test: Get User Context ---")
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    res = get_user_context(script_path=target_script)
    
    if res.get("ok"):
        data = res['data']
        print(f"User: {data['user_name']}")
        
        # 使用图标显示管理员状态
        admin_status = "🛡️ Administrator" if data['is_admin'] else "👤 Standard User"
        print(f"Privileges: {admin_status}")
        
        # 显示域状态
        domain_status = f"Domain User ({data['user_domain']})" if data['is_domain_user'] else "Local User"
        print(f"Account Type: {domain_status}")
    else:
        print(json.dumps(res, indent=2, ensure_ascii=False))