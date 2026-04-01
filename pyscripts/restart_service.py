import json
import subprocess
import os
import tempfile
from typing import Dict, Any

def restart_service(
    service_name: str,
    dry_run: bool = False,
    # 使用 r"" 原始字符串避免路径转义问题
    script_path: str = r"scripts\scripts\powershell\restart_service.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本重启指定的 Windows 服务。
    
    用于修复卡死的服务、应用配置更改或解决某些系统故障。
    注意：此操作需要管理员权限。

    Args:
        service_name (str): 服务名称 (例如 "Spooler", "wuauserv")。
        dry_run (bool): 仅模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含操作结果的字典。
    """

    # 1. 构造参数负载
    payload = {
        "parameter": {
            "service_name": service_name,
            "dry_run": dry_run
        },
        "metadata": {
            # 给足时间等待服务停止和启动
            "timeout_ms": 60000, 
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
    
    target_script = r"scripts\scripts\powershell\restart_service.ps1"
    print("--- Test: Restart Service (Dry Run) ---")
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    # 示例：重启打印后台处理程序 (Print Spooler)
    target_svc = "Spooler"
    
    print(f"Targeting service: {target_svc}")
    
    # 脚本内部有提权逻辑，可能会弹出 UAC
    res = restart_service(
        service_name=target_svc, 
        dry_run=True, # 建议先测试 dry_run
        script_path=target_script
    )
    
    if res.get("ok"):
        data = res['data']
        if data.get('result') == 'dry_run':
            print(f"✅ Dry Run: {data['would_perform_action']}")
            print(f"   Current Status: {data.get('current_status')}")
        else:
            print(f"✅ Success: {data.get('reason')}")
    else:
        print(json.dumps(res, indent=2, ensure_ascii=False))