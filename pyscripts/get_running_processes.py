import json
import subprocess
import os
import tempfile
from typing import Dict, Any, Literal

def get_running_processes(
    limit: int = 20,
    sort_by: Literal["cpu", "memory", "io"] = "cpu",
    include_username: bool = False,  # <--- [新增] 1. 新增参数，默认关闭
    dry_run: bool = False,
    script_path: str = r"scripts\scripts\powershell\get_running_processes.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本获取当前资源占用最高的进程列表。
    
    Args:
        limit (int): 返回前多少个进程 (默认 20)。
        sort_by (str): 排序依据 ("cpu", "memory", "io")。
        include_username (bool): 是否解析进程的所有者用户名。
                                 注意：开启此项会显著增加耗时 (可能从 <1s 增加到 >10s)，
                                 仅在必须区分系统进程或多用户环境时开启。
        dry_run (bool): 仅模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含进程列表的字典。
    """

    # 1. 构造参数负载
    payload = {
        "parameter": {
            "limit": limit,
            "sort_by": sort_by,
            "include_username": include_username, # <--- [新增] 2. 传递给 PS 脚本
            "dry_run": dry_run
        },
        "metadata": {
            # 如果开启了用户名查询，建议适当增加超时时间，否则保持默认
            "timeout_ms": 20000 if include_username else 15000, 
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
    
    target_script = r"scripts\scripts\powershell\get_running_processes.ps1"
    print("--- Test: Top Resource Hogs ---")
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    # 示例 1: 按 CPU 排序
    print("Fetching Top 10 by CPU...")
    res = get_running_processes(limit=10, sort_by="cpu", script_path=target_script)
    
    if res.get("ok"):
        procs = res['data']['processes']
        print(f"{'PID':<6} | {'Name':<25} | {'CPU%':<6} | {'Mem(MB)':<8} | {'User'}")
        print("-" * 65)
        for p in procs:
            # CPU 可能超过 100% (多核)
            cpu = f"{p['cpu_percent']}%"
            # 截断长名字
            name = p['name'][:24]
            user = p.get('username', '') or 'N/A'
            print(f"{p['pid']:<6} | {name:<25} | {cpu:<6} | {p['memory_mb']:<8} | {user}")
            
    else:
        print(json.dumps(res, indent=2, ensure_ascii=False))

    # 示例 2: 按内存排序
    # print("\nFetching Top 5 by Memory...")
    # res_mem = get_running_processes(limit=5, sort_by="memory", script_path=target_script)
    # ... (类似打印逻辑)