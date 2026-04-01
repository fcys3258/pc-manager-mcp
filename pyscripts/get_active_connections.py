import json
import subprocess
import os
import tempfile
from typing import Dict, Any, Literal

def get_active_connections(
    limit: int = 50,
    sort_by: Literal["local_port", "remote_port", "state", "none"] = "state",
    # 使用原始字符串处理路径
    script_path: str = r"scripts\scripts\powershell\get_active_connections.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本获取当前系统的活动 TCP 连接。
    
    支持自动降级：如果 Get-NetTCPConnection 不可用，会自动解析 netstat 输出。

    Args:
        limit (int): 返回的最大连接数。默认为 50。
        sort_by (str): 排序依据。可选值:
                       - "state" (默认): 按连接状态排序 (LISTEN, ESTABLISHED...)
                       - "local_port": 按本地端口号排序
                       - "remote_port": 按远程端口号排序
                       - "none": 不排序
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含连接列表的字典。
    """

    # 1. 构造参数负载
    payload = {
        "parameter": {
            "limit": limit,
            "sort_by": sort_by
        },
        "metadata": {
            "timeout_ms": 10000, # 网络状态查询通常较快
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
        # 脚本内部已强制 UTF-8 输出，直接使用 utf-8 读取
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
    
    # 路径检查
    target_script = r"scripts\scripts\powershell\get_active_connections.ps1"
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本文件: {target_script}")
    
    print(f"--- Test: Get Top 10 Connections (Sorted by State) ---")
    res = get_active_connections(
        limit=10, 
        sort_by="state",
        script_path=target_script
    )
    
    if res.get("ok"):
        # 简单打印一下结果
        print(json.dumps(res['data']['connections'], indent=2))
        print(f"\n元数据: {res['metadata']}")
    else:
        print(json.dumps(res, indent=2))