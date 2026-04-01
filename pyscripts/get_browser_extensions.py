import json
import subprocess
import os
import tempfile
from typing import Dict, Any, Literal

def get_browser_extensions(
    browser: Literal["chrome", "edge", "all"] = "all",
    dry_run: bool = False,
    # 使用 r"" 原始字符串
    script_path: str = r"scripts\scripts\powershell\get_browser_extensions.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本获取已安装的浏览器扩展列表 (Chrome/Edge)。
    
    该工具通过扫描本地磁盘上的 User Data 目录来发现扩展，因此无需打开浏览器即可运行。
    
    Args:
        browser (str): 目标浏览器，可选 "chrome", "edge" 或 "all" (默认)。
        dry_run (bool): 仅模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含扩展列表的字典。
    """

    # 1. 构造参数负载
    payload = {
        "parameter": {
            "browser": browser,
            "dry_run": dry_run
        },
        "metadata": {
            "timeout_ms": 15000, # 扫描大量小文件可能需要几秒
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
    
    target_script = r"agent\scripts\scripts\powershell\get_browser_extensions.ps1"
    print("--- Test: Get Browser Extensions ---")
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    # 扫描所有浏览器的扩展
    res = get_browser_extensions(browser="all", script_path=target_script)
    
    if res.get("ok"):
        data = res['data']
        print(f"Total Extensions: {data.get('total_count')} (Chrome: {data.get('chrome_count')}, Edge: {data.get('edge_count')})")
        
        # 打印前 5 个扩展
        print("\nExtensions List (First 5):")
        for ext in data.get('extensions', [])[:5]:
            print(f"- [{ext['browser']}] {ext['name']} (v{ext['version']})")
            if ext.get('permissions'):
                # 只显示前3个权限作为示例
                perms = ", ".join(ext['permissions'][:3])
                if len(ext['permissions']) > 3: perms += "..."
                print(f"  Permissions: {perms}")
    else:
        print(json.dumps(res, indent=2, ensure_ascii=False))