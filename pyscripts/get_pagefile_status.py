import json
import subprocess
import os
import tempfile
from typing import Dict, Any

def get_pagefile_status(
    dry_run: bool = False,
    # 使用 r"" 原始字符串避免路径转义问题
    script_path: str = r"scripts\scripts\powershell\get_pagefile_status.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本获取 Windows 页面文件(Pagefile)和虚拟内存状态。
    
    用于诊断 "内存不足"、"系统卡顿" 等问题。
    返回数据包括：页面文件是否自动管理、文件路径、当前使用量、峰值使用量等。

    Args:
        dry_run (bool): 仅模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含页面文件配置和使用情况的字典。
    """

    # 1. 构造参数负载
    payload = {
        "parameter": {
            "dry_run": dry_run
        },
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
    
    target_script = r"scripts\scripts\powershell\get_pagefile_status.ps1"
    print("--- Test: Pagefile Status ---")
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    res = get_pagefile_status(script_path=target_script)
    
    if res.get("ok"):
        data = res['data']
        auto_managed = "Yes" if data.get('automatic_managed') else "No"
        print(f"Auto Managed: {auto_managed}")
        
        print(f"\nUsage Stats:")
        print(f"  Current: {data.get('current_usage_mb')} MB")
        print(f"  Peak:    {data.get('peak_usage_mb')} MB")
        print(f"  Total Allocated: {data.get('allocated_size_mb')} MB")
        
        if data.get('page_files'):
            print(f"\nPage Files:")
            for pf in data['page_files']:
                path = pf.get('path')
                if pf.get('source') == 'setting':
                    # 手动设置时显示初始/最大值
                    print(f"- {path}: {pf.get('initial_size_mb')}-{pf.get('maximum_size_mb')} MB")
                else:
                    # 自动管理时通常只显示当前大小
                    print(f"- {path}: {pf.get('current_size_mb')} MB (System Managed)")
                    
        if data.get('total_virtual_memory_mb'):
            print(f"\nVirtual Memory: {data.get('free_virtual_memory_mb')} MB free / {data.get('total_virtual_memory_mb')} MB total")
            
    else:
        print(json.dumps(res, indent=2, ensure_ascii=False))