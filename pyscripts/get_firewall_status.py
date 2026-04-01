import json
import subprocess
import os
import tempfile
from typing import Dict, Any

def get_firewall_status(
    dry_run: bool = False,
    # 使用 r"" 原始字符串避免路径转义问题
    script_path: str = r"scripts\scripts\powershell\get_firewall_status.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本获取 Windows 防火墙状态。
    
    检查 Domain, Private, Public 三种网络配置文件的防火墙是否开启，
    以及默认的入站/出站策略。

    Args:
        dry_run (bool): 仅模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含防火墙配置文件列表的字典。
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
    
    target_script = r"scripts\scripts\powershell\get_firewall_status.ps1"
    print("--- Test: Firewall Status ---")
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    res = get_firewall_status(script_path=target_script)
    
    if res.get("ok"):
        profiles = res['data']['firewall_profiles']
        print(f"Profiles Found: {len(profiles)}")
        for p in profiles:
            status_icon = "🛡️ ON" if p['enabled'] else "⚠️ OFF"
            print(f"\n{p['name']} Profile: {status_icon}")
            
            # 显示详细策略 (如果是新版 PowerShell)
            if 'default_inbound_action' in p:
                print(f"  Inbound: {p['default_inbound_action']}")
                print(f"  Outbound: {p['default_outbound_action']}")
    else:
        print(json.dumps(res, indent=2, ensure_ascii=False))