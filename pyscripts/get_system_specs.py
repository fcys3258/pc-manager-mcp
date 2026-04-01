import json
import subprocess
import os
import tempfile
from typing import Dict, Any

def get_system_specs(
    dry_run: bool = False,
    # 使用 r"" 原始字符串避免路径转义问题
    script_path: str = r"scripts\scripts\powershell\get_system_specs.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本获取计算机的静态硬件配置信息。
    
    返回数据包括：
    1. 操作系统版本、架构、主机名。
    2. CPU 型号、核心数、线程数。
    3. 内存总量 (GB)。
    4. 磁盘列表 (盘符、文件系统、总容量、剩余空间)。

    Args:
        dry_run (bool): 仅模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含系统规格详情的字典。
    """

    # 1. 构造参数负载
    payload = {
        "parameter": {
            "dry_run": dry_run
        },
        "metadata": {
            "timeout_ms": 15000,
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
    
    target_script = r"scripts\scripts\powershell\get_system_specs.ps1"
    print("--- Test: System Specifications ---")
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    res = get_system_specs(script_path=target_script)
    
    if res.get("ok"):
        data = res['data']
        
        print(f"Hostname: {data['hostname']}")
        print(f"OS:       {data['os_name']} ({data['os_version']}, Build {data['os_build']}) {data['os_architecture']}")
        print(f"CPU:      {data['cpu_name']}")
        print(f"          {data['cpu_cores']} Cores / {data['cpu_logical_processors']} Threads")
        print(f"Memory:   {data['total_memory_gb']} GB")
        
        print(f"\nDisks ({len(data.get('disks', []))}):")
        print(f"{'Drive':<6} | {'Size (GB)':<10} | {'Free (GB)':<10} | {'Type'}")
        print("-" * 45)
        for disk in data.get('disks', []):
            is_sys = "*" if disk.get('is_system_disk') else ""
            print(f"{disk['drive_letter']:<6} | {disk['size_gb']:<10} | {disk['size_remaining_gb']:<10} | {disk['file_system']} {is_sys}")
            
    else:
        print(json.dumps(res, indent=2, ensure_ascii=False))