import json
import subprocess
import os
import tempfile
from typing import Dict, Any

def get_wifi_details(
    dry_run: bool = False,
    # 使用 r"" 原始字符串避免路径转义问题
    script_path: str = r"scripts\scripts\powershell\get_wifi_details.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本获取 Wi-Fi 连接的详细信息。
    
    用于诊断 "网速慢"、"信号差" 或确认当前连接的频段(2.4G/5G)。
    返回数据包括 SSID, BSSID, 信道, 信号强度(%) 和 链路速率。

    Args:
        dry_run (bool): 仅模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含 Wi-Fi 详情的字典。
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
        # 脚本内部处理编码，Python 端直接读取 UTF-8
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
    
    target_script = r"scripts\scripts\powershell\get_wifi_details.ps1"
    print("--- Test: Check Wi-Fi Connection ---")
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    res = get_wifi_details(script_path=target_script)
    
    if res.get("ok"):
        data = res['data']
        
        if not data.get('wifi_available'):
            print("No Wi-Fi interface found.")
        elif not data.get('connected'):
            print(f"Wi-Fi Interface ({data.get('interface_name')}) is disconnected.")
        else:
            print(f"SSID: {data.get('ssid')} ({data.get('frequency_band')})")
            print(f"BSSID: {data.get('bssid')}")
            print(f"Channel: {data.get('channel')}")
            
            # 信号强度可视化
            sig = data.get('signal_percent', 0)
            bars = "▂▃▄▅▆▇"
            # 简单的映射逻辑
            idx = int(sig / 100 * (len(bars) - 1)) if sig > 0 else 0
            print(f"Signal: {bars[idx]} {sig}% ({data.get('signal_quality')})")
            
            print(f"Speed: Rx {data.get('receive_rate_mbps')} Mbps / Tx {data.get('transmit_rate_mbps')} Mbps")
            print(f"Diagnosis: {data.get('diagnosis')}")
            
            if data.get('issues'):
                print("\nIssues:")
                for issue in data['issues']:
                    print(f"⚠️ {issue}")
    else:
        print(json.dumps(res, indent=2, ensure_ascii=False))