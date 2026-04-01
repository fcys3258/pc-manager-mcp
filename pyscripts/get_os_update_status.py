import json
import subprocess
import os
import tempfile
from typing import Dict, Any

def get_os_update_status(
    dry_run: bool = False,
    # 使用 r"" 原始字符串避免路径转义问题
    script_path: str = r"scripts\scripts\powershell\get_os_update_status.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本获取 Windows 更新状态。
    
    诊断维度包括：
    1. 是否有挂起的重启请求 (Pending Reboot)。
    2. Windows Update 服务健康状况。
    3. 待安装的更新列表 (通过 COM 接口实时查询)。
    4. 最近的更新历史记录。

    Args:
        dry_run (bool): 仅模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含更新状态、服务状态及历史记录的字典。
    """

    # 1. 构造参数负载
    payload = {
        "parameter": {
            "dry_run": dry_run
        },
        "metadata": {
            # Windows Update 搜索可能非常慢（取决于网络和系统卡顿程度），建议给足时间
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
    
    target_script = r"scripts\scripts\powershell\get_os_update_status.ps1"
    print("--- Test: Windows Update Status ---")
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    # 注意：此操作可能需要几十秒时间来搜索更新
    print("正在查询 Windows Update (可能需要几十秒)...")
    res = get_os_update_status(script_path=target_script)
    
    if res.get("ok"):
        data = res['data']
        
        # 1. 关键状态
        reboot_icon = "🔴 YES" if data.get('reboot_required') else "🟢 No"
        print(f"Pending Reboot: {reboot_icon}")
        print(f"Service Status: {data.get('wu_service_status')}")
        print(f"Disabled by Policy: {data.get('is_disabled_by_policy')}")
        
        # 2. 时间戳
        print(f"Last Check: {data.get('last_check_time', 'Never')}")
        print(f"Last Install: {data.get('last_install_time', 'Never')}")
        
        # 3. 待安装更新
        pending = data.get('pending_updates', [])
        print(f"\nAvailable Updates: {data.get('available_updates_count')}")
        for update in pending:
            severity = f"[{update.get('severity')}] " if update.get('severity') else ""
            print(f"- {severity}{update['title']}")
            
        # 4. 最近历史
        history = data.get('recent_history', [])
        if history:
            print(f"\nRecent History (Top {len(history)}):")
            for h in history:
                print(f"[{h['date']}] {h['result_code']} - {h['title']}")
                
    else:
        print(json.dumps(res, indent=2, ensure_ascii=False))