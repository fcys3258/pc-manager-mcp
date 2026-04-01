import json
import subprocess
import os
import tempfile
from typing import Dict, Any, Optional, Literal

def get_installed_software(
    limit: int = 50,
    sort_by: Literal["name", "install_date", "publisher"] = "name",
    name_filter: Optional[str] = None,
    dry_run: bool = False,
    # 使用 r"" 原始字符串避免路径转义问题
    script_path: str = r"scripts\scripts\powershell\get_installed_software.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本获取已安装的软件列表。
    
    该工具扫描 Windows 注册表，自动过滤掉系统更新和组件，返回用户安装的应用程序。
    
    Args:
        limit (int): 返回的最大软件数量 (默认 50)。
        sort_by (str): 排序方式 ("name", "install_date", "publisher")。
        name_filter (str, optional): 按名称筛选 (例如 "Adobe*")。
        dry_run (bool): 仅模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含软件列表的字典。
    """

    # 1. 构造参数负载
    params = {
        "limit": limit,
        "sort_by": sort_by,
        "dry_run": dry_run
    }
    if name_filter:
        params['name_filter'] = name_filter

    payload = {
        "parameter": params,
        "metadata": {
            "timeout_ms": 20000, # 注册表扫描较快，但条目多时可能稍慢
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
    
    target_script = r"scripts\scripts\powershell\get_installed_software.ps1"
    print("--- Test: List Installed Software ---")
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    # 示例 1: 列出所有软件 (默认按名称排序)
    # res = get_installed_software(limit=10, script_path=target_script)
    
    # 示例 2: 搜索特定软件 (如 "Python" 或 "Google")
    print("Searching for 'Microsoft'...")
    res = get_installed_software(
        limit=100, 
        name_filter="Microsoft*", 
        script_path=target_script
    )
    
    if res.get("ok"):
        data = res['data']
        print(f"Total Found: {data.get('total_found')} (Returned: {data.get('returned_count')})")
        print("-" * 60)
        print(f"{'Name':<40} | {'Version':<15} | {'Date'}")
        print("-" * 60)
        
        for app in data.get('installed_software', []):
            name = app['name'][:38] + ".." if len(app['name']) > 38 else app['name']
            ver = str(app['version'])[:15]
            date = str(app['install_date'])
            print(f"{name:<40} | {ver:<15} | {date}")
    else:
        print(json.dumps(res, indent=2, ensure_ascii=False))