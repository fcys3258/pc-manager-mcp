import json
import subprocess
import os
import tempfile
from typing import Dict, Any

def get_directory_size(
    path: str,
    max_depth: int = 3,
    dry_run: bool = False,
    # 使用 r"" 原始字符串避免路径转义问题
    script_path: str = r"scripts\scripts\powershell\get_directory_size.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本计算指定目录的大小。
    
    支持自动提权：如果目标是系统受保护目录 (如 C:\\Windows)，脚本会尝试提升权限。
    内置超时保护：防止分析大目录时脚本挂起。

    Args:
        path (str): 要分析的目标目录路径。
        max_depth (int): 递归最大深度 (默认 3，设为更大值可获得更精确结果但更慢)。
        dry_run (bool): 仅模拟执行 (此脚本为只读，效果与真实运行一致)。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含目录大小(MB)和扫描文件数的字典。
    """

    # 1. 构造参数负载
    payload = {
        "parameter": {
            "path": path,
            "max_depth": max_depth,
            "dry_run": dry_run
        },
        "metadata": {
            "timeout_ms": 30000, # 扫描大目录需要更多时间
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
    
    target_script = r"scripts\scripts\powershell\get_directory_size.ps1"
    print("--- Test: Calculate Directory Size ---")
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    # 示例 1: 分析用户临时文件夹 (无需提权)
    target_dir = os.environ.get("TEMP")
    res = get_directory_size(path=target_dir, script_path=target_script)
    
    if res.get("ok"):
        data = res['data']
        print(f"Path: {data['path']}")
        print(f"Size: {data['size_mb']} MB")
        
        meta = res.get('metadata', {})
        print(f"Scanned Items: {meta.get('scanned_items')} (Depth Limit: {meta.get('scan_depth_limit')})")
        print(f"Time Taken: {meta.get('exec_time_ms')} ms")
    else:
        print(json.dumps(res, indent=2, ensure_ascii=False))