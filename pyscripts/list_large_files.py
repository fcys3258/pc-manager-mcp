import json
import subprocess
import os
import tempfile
from typing import Dict, Any

def list_large_files(
    path: str,
    limit: int = 20,
    max_depth: int = 3,
    dry_run: bool = False,
    # 使用 r"" 原始字符串避免路径转义问题
    script_path: str = r"scripts\scripts\powershell\list_large_files.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本列出指定目录下体积最大的文件。
    
    使用优化的 Top-N 算法，在扫描大量文件时保持低内存占用。
    支持自动提权扫描系统目录。

    Args:
        path (str): 要扫描的目录路径。
        limit (int): 返回前多少个大文件 (默认 20)。
        max_depth (int): 递归扫描的最大深度 (默认 3)。
        dry_run (bool): 仅模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含大文件列表的字典。
    """

    # 1. 构造参数负载
    payload = {
        "parameter": {
            "path": path,
            "limit": limit,
            "max_depth": max_depth,
            "dry_run": dry_run
        },
        "metadata": {
            # 扫描大目录需要足够的时间
            "timeout_ms": 30000,
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
        # 脚本内部处理编码，Python 端直接读取 UTF-8
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
    
    target_script = r"scripts\scripts\powershell\list_large_files.ps1"
    print("--- Test: Find Largest Files ---")
    
    if not os.path.exists(target_script):
        print(f"[Warning] Script not found: {target_script}")
    
    # 示例：扫描用户的下载文件夹
    target_dir = os.path.join(os.environ['USERPROFILE'], 'Downloads')
    
    print(f"Scanning: {target_dir}...")
    res = list_large_files(
        path=target_dir, 
        limit=5, 
        max_depth=2, 
        script_path=target_script
    )
    
    if res.get("ok"):
        files = res['data']['large_files']
        meta = res.get('metadata', {})
        
        print(f"\nScanned {meta.get('total_items')} items.")
        print(f"Top {len(files)} Largest Files:")
        print(f"{'Size (MB)':<12} | {'Filename'}")
        print("-" * 60)
        
        for f in files:
            # 截断过长的文件名以便显示
            fname = os.path.basename(f['path'])
            if len(fname) > 45: fname = fname[:42] + "..."
            
            print(f"{f['size_mb']:<12} | {fname}")
            
    else:
        print(json.dumps(res, indent=2, ensure_ascii=False))