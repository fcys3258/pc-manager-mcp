import json
import subprocess
import os
import tempfile
from typing import Dict, Any

def get_top_window(
    dry_run: bool = False,
    # 使用 r"" 原始字符串避免路径转义问题
    script_path: str = r"scripts\scripts\powershell\get_top_window.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本获取当前前台(活动)窗口的信息。
    
    该工具通过调用 User32.dll 获取用户当前正在操作的窗口详情。
    返回数据包括：窗口标题、进程名、窗口位置以及是否处于 "未响应" 状态。

    Args:
        dry_run (bool): 仅模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含活动窗口详情的字典。
    """

    # 1. 构造参数负载
    payload = {
        "parameter": {
            "dry_run": dry_run
        },
        "metadata": {
            "timeout_ms": 5000, # API 调用极快
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
    
    target_script = r"scripts\scripts\powershell\get_top_window.ps1"
    print("--- Test: Get Foreground Window ---")
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    # 提示用户：运行此测试时，当前的终端窗口通常就是活动窗口
    print("Capturing current active window...")
    res = get_top_window(script_path=target_script)
    
    if res.get("ok"):
        data = res['data']
        if data.get('has_foreground_window'):
            print(f"Window Title: {data.get('window_title')}")
            print(f"Process:      {data.get('process_name')} (PID: {data.get('process_id')})")
            print(f"Path:         {data.get('process_path')}")
            
            # 状态标记
            states = []
            if data.get('is_hung'): states.append("🔴 NOT RESPONDING")
            if data.get('is_maximized'): states.append("Maximized")
            if data.get('is_minimized'): states.append("Minimized")
            if not states: states.append("Normal")
            
            print(f"Status:       {', '.join(states)}")
            
            # 几何信息
            rect = data.get('window_rect', {})
            print(f"Geometry:     {rect.get('width')}x{rect.get('height')} at ({rect.get('left')}, {rect.get('top')})")
        else:
            print("No foreground window detected (Desktop locked or background session).")
    else:
        print(json.dumps(res, indent=2, ensure_ascii=False))