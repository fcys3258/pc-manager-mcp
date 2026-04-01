import json
import subprocess
import os
import tempfile
from typing import Dict, Any, Optional

def get_disk_info(
    drive_letter: Optional[str] = None,
    dry_run: bool = False,
    # 使用 r"" 原始字符串避免路径转义问题
    script_path: str = r"scripts\scripts\powershell\get_disk_info.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本获取磁盘空间信息。
    
    支持获取所有磁盘或指定盘符的信息。
    数据包括：盘符、文件系统类型、总容量(GB)、剩余空间(GB)。

    Args:
        drive_letter (str, optional): 指定盘符 (例如 "C")。如果为 None，则返回所有磁盘。
        dry_run (bool): 仅模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含磁盘列表的字典。
    """

    # 1. 构造参数负载
    params = {"dry_run": dry_run}
    if drive_letter:
        # 确保只传递单个字母，去掉冒号
        params['drive_letter'] = drive_letter.upper().replace(":", "")

    payload = {
        "parameter": params,
        "metadata": {
            "timeout_ms": 10000, # 磁盘查询很快
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
    
    target_script = r"scripts\scripts\powershell\get_disk_info.ps1"
    print("--- Test: Get Disk Info ---")
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    # 示例 1: 获取所有磁盘
    res = get_disk_info(script_path=target_script)
    
    if res.get("ok"):
        disks = res['data']['disks']
        print(f"Found {len(disks)} volume(s):")
        for disk in disks:
            usage = disk['size_gb'] - disk['size_remaining_gb']
            percent = (usage / disk['size_gb']) * 100 if disk['size_gb'] > 0 else 0
            
            # 使用进度条展示
            bar_len = 20
            filled = int(percent / 100 * bar_len)
            bar = "█" * filled + "░" * (bar_len - filled)
            
            print(f"{disk['drive_letter']}: [{bar}] {percent:.1f}% Used ({disk['size_remaining_gb']}GB free / {disk['size_gb']}GB total)")
    else:
        print(json.dumps(res, indent=2, ensure_ascii=False))