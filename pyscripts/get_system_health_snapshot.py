import json
import subprocess
import os
import tempfile
from typing import Dict, Any

def get_system_health_snapshot(
    sampling_ms: int = 1000,
    dry_run: bool = False,
    # 使用 r"" 原始字符串避免路径转义问题
    script_path: str = r"scripts\scripts\powershell\get_system_health_snapshot.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本获取系统健康状况的实时快照。
    
    通过采样 Windows 性能计数器，返回 CPU、内存和磁盘的实时负载指标。
    
    Args:
        sampling_ms (int): 采样持续时间 (毫秒)，默认 1000ms。时间越长数据越平滑。
        dry_run (bool): 仅模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含 CPU(%)、内存(%)、磁盘IO 等指标的字典。
    """

    # 1. 构造参数负载
    payload = {
        "parameter": {
            "sampling_ms": sampling_ms,
            "dry_run": dry_run
        },
        "metadata": {
            # 超时时间需要包含采样时间，所以要比 sampling_ms 多一些冗余
            "timeout_ms": sampling_ms + 10000, 
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
    
    target_script = r"scripts\scripts\powershell\get_system_health_snapshot.ps1"
    print("--- Test: System Health Snapshot ---")
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    # 采样 1 秒
    res = get_system_health_snapshot(sampling_ms=1000, script_path=target_script)
    
    if res.get("ok"):
        data = res['data']
        print(f"CPU Usage:    {data['cpu_usage_percent']}%")
        print(f"Memory Usage: {data['memory_usage_percent']}%")
        print(f"Disk Active:  {data['disk_active_time_percent']}%")
        
        # 转换字节为 MB/s
        read_mb = round(data['disk_read_bytes_per_sec'] / 1024 / 1024, 2)
        write_mb = round(data['disk_write_bytes_per_sec'] / 1024 / 1024, 2)
        print(f"Disk I/O:     Read {read_mb} MB/s | Write {write_mb} MB/s")
    else:
        print(json.dumps(res, indent=2, ensure_ascii=False))