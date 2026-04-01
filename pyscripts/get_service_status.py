import json
import subprocess
import os
import tempfile
from typing import Dict, Any, List, Optional, Literal

def get_service_status(
    service_names: Optional[List[str]] = None,
    limit: int = 50,
    sort_by: Literal["name", "status", "display_name"] = "name",
    dry_run: bool = False,
    # 使用 r"" 原始字符串避免路径转义问题
    script_path: str = r"scripts\scripts\powershell\get_service_status.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本获取 Windows 服务状态。
    
    可以查询指定服务列表的状态，或者列出系统中的所有服务。
    返回信息包括：服务名、显示名称、当前状态(Running/Stopped)、启动类型(Auto/Manual/Disabled)。

    Args:
        service_names (List[str], optional): 要查询的服务名称列表。如果为空，则查询所有服务。
        limit (int): 返回的最大服务数量 (默认 50)。
        sort_by (str): 排序方式。
        dry_run (bool): 仅模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含服务状态列表的字典。
    """

    # 1. 构造参数负载
    params = {
        "limit": limit,
        "sort_by": sort_by,
        "dry_run": dry_run
    }
    if service_names:
        params['service_names'] = service_names

    payload = {
        "parameter": params,
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
    
    target_script = r"scripts\scripts\powershell\get_service_status.ps1"
    print("--- Test: Check Specific Services ---")
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    # 示例 1: 查询几个关键服务的状态
    target_services = ["wuauserv", "Spooler", "WinDefend"]
    print(f"Querying: {', '.join(target_services)}")
    
    res = get_service_status(service_names=target_services, script_path=target_script)
    
    if res.get("ok"):
        data = res['data']
        print(f"Found {data.get('returned_count')} services:")
        
        for svc in data.get('services', []):
            status_icon = "🟢" if svc['status'] == 'Running' else "🔴"
            print(f"{status_icon} {svc['name']:<15} | {svc['status']:<10} | {svc['start_type']}")
            print(f"   ({svc['display_name']})")
            
    else:
        print(json.dumps(res, indent=2, ensure_ascii=False))