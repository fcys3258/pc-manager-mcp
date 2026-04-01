import json
import subprocess
import os
import tempfile
from typing import Dict, Any

def reset_winhttp_proxy(
    dry_run: bool = False,
    # 使用 r"" 原始字符串避免路径转义问题
    script_path: str = r"scripts\scripts\powershell\reset_winhttp_proxy.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本重置 WinHTTP 系统代理设置。
    
    该工具用于修复 Windows Update、Microsoft Store 或系统激活无法连接网络的问题。
    它不会影响浏览器（Chrome/Edge）的代理设置，专门针对底层系统服务。

    Args:
        dry_run (bool): 仅模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含操作结果及重置前的代理状态。
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
    
    target_script = r"scripts\scripts\powershell\reset_winhttp_proxy.ps1"
    print("--- Test: Reset WinHTTP Proxy ---")
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    # 脚本内部包含提权逻辑，可能会弹出 UAC
    res = reset_winhttp_proxy(dry_run=True, script_path=target_script)
    
    if res.get("ok"):
        data = res['data']
        if data.get('result') == 'dry_run':
            print(f"✅ Dry Run: {data['would_perform_action']}")
        else:
            print(f"Result: {data['result']}")
            
            if data.get('had_proxy_before'):
                print(f"⚠️  发现并清理了残留代理: {data['previous_proxy']}")
            else:
                print("ℹ️  之前未设置 WinHTTP 代理 (Direct Access)。")
                
            print("\n当前设置:")
            for line in data.get('current_settings', []):
                if line.strip(): print(f"  {line.strip()}")
    else:
        print(json.dumps(res, indent=2, ensure_ascii=False))