import json
import subprocess
import os
import tempfile
from typing import Dict, Any

def get_local_admin_members(
    dry_run: bool = False,
    # 使用 r"" 原始字符串避免路径转义问题
    script_path: str = r"scripts\scripts\powershell\get_local_admin_members.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本获取本地管理员组(Administrators)的成员列表。
    
    该工具用于安全审计，检查哪些用户拥有这台电脑的最高权限。
    能够区分本地用户、域用户(Domain Users)和 Azure AD 用户。

    Args:
        dry_run (bool): 仅模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含管理员成员列表及统计信息的字典。
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
    
    target_script = r"scripts\scripts\powershell\get_local_admin_members.ps1"
    print("--- Test: Audit Local Admins ---")
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    res = get_local_admin_members(script_path=target_script)
    
    if res.get("ok"):
        data = res['data']
        print(f"Total Admins: {data.get('member_count')}")
        print(f"  - Local: {data.get('local_count')}")
        print(f"  - Domain: {data.get('domain_count')}")
        print(f"  - AzureAD: {data.get('azure_count')}")
        
        print("\nMembers List:")
        for member in data.get('members', []):
            source = member.get('principal_source', 'Unknown')
            # 区分图标
            icon = "🏠" if source == 'Local' else "🏢" if source == 'Domain' else "☁️"
            print(f"{icon} {member['name']} ({source})")
            
    else:
        print(json.dumps(res, indent=2, ensure_ascii=False))