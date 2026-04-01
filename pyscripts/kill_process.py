import json
import subprocess
import os
import tempfile
from typing import Dict, Any, Optional

def kill_process(
    pid: int = None,
    process_key: str = None,
    force: bool = False,
    kill_tree: bool = False,
    dry_run: bool = False,
    # 使用 r"" 原始字符串避免路径转义问题
    script_path: str = r"scripts\scripts\powershell\kill_process.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本终止指定进程。
    
    支持通过 PID 或 process_key (PID:StartTime) 终止进程。
    具备防止误杀重用 PID 进程的安全机制，并能递归终止进程树。

    Args:
        pid (int, optional): 进程 ID。
        process_key (str, optional): 进程唯一标识符 (格式 "PID:StartTime")，推荐使用以防止误杀。
        force (bool): 是否强制终止 (类似于 kill -9)。
        kill_tree (bool): 是否同时终止该进程启动的所有子进程。
        dry_run (bool): 仅模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含操作结果的字典。
    """

    # 1. 构造参数负载
    params = {
        "force": force,
        "kill_tree": kill_tree,
        "dry_run": dry_run
    }
    if process_key:
        params['process_key'] = process_key
    elif pid:
        params['pid'] = pid
    else:
        return {"ok": False, "error": {"code": "INVALID_ARGUMENT", "message": "Either pid or process_key is required"}}

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
    
    target_script = r"scripts\scripts\powershell\kill_process.ps1"
    print("--- Test: Kill Process (Dry Run) ---")
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    # 示例：尝试终止记事本 (Notepad)，仅模拟
    # 假设我们先找到了一个 Notepad 进程
    try:
        # 这里用 python 启动一个 notepad 作为靶子
        target_proc = subprocess.Popen("notepad.exe")
        print(f"Started Notepad with PID: {target_proc.pid}")
        
        # 模拟终止它
        res = kill_process(
            pid=target_proc.pid, 
            dry_run=True, # 仅模拟
            script_path=target_script
        )
        
        if res.get("ok"):
            print(f"Result: {res['data']['result']}")
            if res['data'].get('would_perform_action'):
                print(f"Action: {res['data']['would_perform_action']}")
                print(f"Targets: {json.dumps(res['data']['targets'], indent=2)}")
        else:
            print(json.dumps(res, indent=2, ensure_ascii=False))
            
        # 清理测试进程
        target_proc.kill()
        
    except Exception as e:
        print(f"Test setup failed: {e}")