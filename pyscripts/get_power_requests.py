import json
import subprocess
import os
import tempfile
from typing import Dict, Any

def get_power_requests(
    dry_run: bool = False,
    # 使用 r"" 原始字符串
    script_path: str = r"scripts\scripts\powershell\get_power_requests.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本获取阻止系统睡眠或屏幕关闭的电源请求。
    
    用于诊断 "电脑无法睡眠" 或 "屏幕一直亮着" 的问题。
    它能找出具体的进程 (如 chrome.exe) 或驱动程序。
    注意：此操作通常需要管理员权限才能查看完整信息。

    Args:
        dry_run (bool): 仅模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含各类电源请求详情及诊断结果的字典。
    """

    # 1. 构造参数负载
    payload = {
        "parameter": {
            "dry_run": dry_run
        },
        "metadata": {
            "timeout_ms": 15000,
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
    
    target_script = r"scripts\scripts\powershell\get_power_requests.ps1"
    print("--- Test: Check Sleep Blockers ---")
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    # 建议以管理员身份运行此 Python 脚本以获得最全信息
    res = get_power_requests(script_path=target_script)
    
    if res.get("ok"):
        data = res['data']
        
        # 1. 总体诊断
        status_map = {
            'ok': "🟢 Normal (Sleep Allowed)",
            'warning': "🟠 Warning (Sleep Blocked)",
            'info': "🔵 Info (Display Blocked)"
        }
        print(f"Status: {status_map.get(data.get('status'), data.get('status'))}")
        print(f"Diagnosis: {data.get('diagnosis')}")
        
        # 2. 列出具体阻碍者
        if data.get('has_power_requests'):
            categories = ['display_requests', 'system_requests', 'execution_requests', 'driver_requests']
            
            for cat_key in categories:
                requests = data.get(cat_key)
                if requests:
                    cat_name = cat_key.replace('_requests', '').upper()
                    print(f"\n[{cat_name}] Blockers:")
                    for req in requests:
                        name = req.get('process_name') or "Unknown Process"
                        desc = req.get('requestor')
                        print(f"- {name}")
                        print(f"  Details: {desc}")
                        
        if data.get('recommendations'):
            print("\nRecommendations:")
            for rec in data['recommendations']:
                print(f"👉 {rec}")
            
    else:
        print(json.dumps(res, indent=2, ensure_ascii=False))