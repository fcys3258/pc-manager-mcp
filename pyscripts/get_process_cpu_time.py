import json
import subprocess
import os
import tempfile
from typing import Dict, Any, Optional

def get_process_cpu_time(
    limit: int = 20,
    process_name: Optional[str] = None,
    dry_run: bool = False,
    # 使用 r"" 原始字符串
    script_path: str = r"scripts\scripts\powershell\get_process_cpu_time.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本获取进程的累计 CPU 占用时间。
    
    不同于瞬时 CPU 使用率(%)，此工具反映的是进程自启动以来消耗的处理器总时间。
    非常适合查找长期运行且耗资源的 "资源吸血鬼" 进程。

    Args:
        limit (int): 返回排名靠前的进程数量 (默认 20)。
        process_name (str, optional): 指定进程名称过滤 (例如 "chrome")。
        dry_run (bool): 仅模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含进程 CPU 时间统计列表的字典。
    """

    # 1. 构造参数负载
    params = {
        "limit": limit,
        "dry_run": dry_run
    }
    if process_name:
        params['process_name'] = process_name

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
    
    target_script = r"scripts\scripts\powershell\get_process_cpu_time.ps1"
    print("--- Test: Top CPU Time Consumers ---")
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    # 示例 1: 获取 CPU 时间最长的前 5 个进程
    res = get_process_cpu_time(limit=5, script_path=target_script)
    
    if res.get("ok"):
        procs = res['data']['processes']
        print(f"Top {len(procs)} Processes by Cumulative CPU Time:")
        print(f"{'PID':<6} | {'Name':<25} | {'CPU Time':<12} | {'Started'}")
        print("-" * 60)
        
        for p in procs:
            start = p.get('start_time', 'N/A')
            # 截断长名称
            name = p['name'][:23] + ".." if len(p['name']) > 23 else p['name']
            print(f"{p['pid']:<6} | {name:<25} | {p['cpu_time_formatted']:<12} | {start}")
            
    else:
        print(json.dumps(res, indent=2, ensure_ascii=False))