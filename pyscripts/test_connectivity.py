import json
import subprocess
import os
import tempfile
from typing import Dict, Any, Literal, Optional

def test_connectivity(
    mode: Literal["internet", "intranet", "custom"] = "internet",
    target: Optional[str] = None,
    port: Optional[int] = None,
    dns_server: Optional[str] = None,
    dry_run: bool = False,
    # 使用 r"" 原始字符串避免路径转义问题
    script_path: str = r"scripts\scripts\powershell\test_connectivity.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本测试网络连通性。
    
    支持多种模式：
    - internet: 测试外网连通性 (8.8.8.8, bing.com)
    - intranet: 测试本地网关连通性
    - custom: 测试指定目标 (支持 IP 或域名)
    
    同时支持 DNS 解析测试和 TCP 端口测试。

    Args:
        mode (str): 测试模式 ("internet", "intranet", "custom")。
        target (str, optional): 自定义目标地址 (当 mode="custom" 时必填)。
        port (int, optional): 要测试的 TCP 端口 (例如 443, 3389)。
        dns_server (str, optional): 指定用于测试的 DNS 服务器 IP。
        dry_run (bool): 仅模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含详细的连通性测试结果。
    """

    # 1. 构造参数负载
    params = {
        "mode": mode,
        "dry_run": dry_run
    }
    if target: params['target'] = target
    if port: params['port'] = port
    if dns_server: params['dns_server'] = dns_server

    payload = {
        "parameter": params,
        "metadata": {
            "timeout_ms": 20000, # 网络测试可能涉及超时等待
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
    
    target_script = r"scripts\scripts\powershell\test_connectivity.ps1"
    print("--- Test: Network Connectivity ---")
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    # 示例 1: 测试互联网连接 (默认)
    print("\n1. Testing Internet Connectivity...")
    res = test_connectivity(mode="internet", script_path=target_script)
    if res.get("ok"):
        for r in res['data']['connectivity_results']:
            status = "✅ UP" if r['ping_successful'] else "❌ DOWN"
            dns = "✅ Resolved" if r['dns_resolved'] else "❌ DNS Fail"
            print(f"Target: {r['target']:<15} | Ping: {status} ({r['ping_rtt_ms']}ms) | DNS: {dns}")
            
    # 示例 2: 测试特定端口 (如 Google 的 443 端口)
    print("\n2. Testing Custom Port (google.com:443)...")
    res_port = test_connectivity(mode="custom", target="google.com", port=443, script_path=target_script)
    if res_port.get("ok"):
        r = res_port['data']['connectivity_results'][0]
        port_status = "✅ OPEN" if r.get('port_test_successful') else "❌ CLOSED/BLOCKED"
        print(f"Target: {r['target']} | Port 443: {port_status}")
    else:
        print(json.dumps(res_port, indent=2, ensure_ascii=False))