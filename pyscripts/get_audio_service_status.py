import json
import subprocess
import os
import tempfile
from typing import Dict, Any

def get_audio_service_status(
    dry_run: bool = False,
    # 使用 r"" 原始字符串处理路径
    script_path: str = r"scripts\scripts\powershell\get_audio_service_status.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本获取 Windows 音频服务和设备的状态。
    
    用于诊断 "电脑没声音"、"麦克风无法使用" 等问题。
    检查项包括: Windows Audio 服务状态、音频端点设备(扬声器/麦克风)的 PnP 状态。

    Args:
        dry_run (bool): 仅模拟执行 (此脚本为只读，效果与真实运行一致)。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含服务状态列表、设备列表及综合健康状态的字典。
    """

    # 1. 构造参数负载
    payload = {
        "parameter": {
            "dry_run": dry_run
        },
        "metadata": {
            "timeout_ms": 15000, # 硬件枚举可能稍慢
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
    
    target_script = r"scripts\scripts\powershell\get_audio_service_status.ps1"
    
    print("--- Test: Audio Status Check ---")
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    res = get_audio_service_status(script_path=target_script)
    
    if res.get("ok"):
        # 打印精简版结果
        summary = {
            "status": res['data']['overall_status'],
            "issues": res['data']['issues'],
            "services_running": res['data']['all_services_running']
        }
        print(json.dumps(summary, indent=2, ensure_ascii=False))
    else:
        print(json.dumps(res, indent=2, ensure_ascii=False))