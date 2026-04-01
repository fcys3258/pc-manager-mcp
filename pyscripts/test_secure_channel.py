import json
import subprocess
import os
import tempfile
from typing import Dict, Any

def test_secure_channel(
    dry_run: bool = False,
    # 使用 r"" 原始字符串避免路径转义问题
    script_path: str = r"scripts\scripts\powershell\test_secure_channel.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本测试计算机与域控制器的安全通道状态。
    
    这是诊断企业环境登录失败、组策略不生效或 "信任关系失败" 错误的关键工具。
    注意：此操作需要管理员权限。

    Args:
        dry_run (bool): 仅模拟执行（虽然此脚本主要是读取，但保持一致性）。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含域连接状态和诊断信息的字典。
    """

    # 1. 构造参数负载
    payload = {
        "parameter": {
            "dry_run": dry_run
        },
        "metadata": {
            "timeout_ms": 30000, # 连接域控可能因网络问题超时
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
    
    target_script = r"scripts\scripts\powershell\test_secure_channel.ps1"
    print("--- Test: Domain Secure Channel ---")
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    # 脚本包含提权逻辑，可能会触发 UAC
    res = test_secure_channel(script_path=target_script)
    
    if res.get("ok"):
        data = res['data']
        if not data.get('is_domain_joined'):
            print("ℹ️  当前计算机未加入域 (Workgroup 模式)。")
        else:
            print(f"Domain: {data.get('domain_name')}")
            
            status_icon = "✅ Pass" if data.get('secure_channel_valid') else "❌ Fail"
            print(f"Secure Channel: {status_icon}")
            
            if data.get('dc_info'):
                dc = data['dc_info']
                print(f"Connected DC:   {dc.get('dc_name')} ({dc.get('dc_address')})")
            
            if not data.get('secure_channel_valid'):
                print(f"\n⚠️  建议: {data.get('recommendation')}")
                if data.get('verbose_messages'):
                    print("调试信息:")
                    for msg in data['verbose_messages']:
                        print(f"  - {msg}")
    else:
        print(json.dumps(res, indent=2, ensure_ascii=False))