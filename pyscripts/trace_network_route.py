import json
import subprocess
import os
import tempfile
from typing import Dict, Any

def trace_network_route(
    target: str,
    max_hops: int = 15,
    timeout_ms: int = 500,
    dry_run: bool = False,
    # 使用 r"" 原始字符串避免路径转义问题
    script_path: str = r"scripts\scripts\powershell\trace_network_route.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本追踪网络路由路径 (tracert)。
    
    用于诊断 "网页打开慢"、"连接中断" 或定位网络延迟发生在哪一跳（本地网关、运营商、骨干网）。
    
    Args:
        target (str): 目标地址 (域名或 IP，例如 "8.8.8.8" 或 "www.baidu.com")。
        max_hops (int): 最大跳数 (默认 15，范围 1-30)。
        timeout_ms (int): 每跳超时时间 (毫秒，默认 500)。
        dry_run (bool): 仅模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含每一跳路由信息的字典。
    """

    # 1. 构造参数负载
    payload = {
        "parameter": {
            "target": target,
            "max_hops": max_hops,
            "timeout_ms": timeout_ms,
            "dry_run": dry_run
        },
        "metadata": {
            # 路由追踪可能很慢 ( hops * timeout * 3 )
            "timeout_ms": 60000, 
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
    
    target_script = r"scripts\scripts\powershell\trace_network_route.ps1"
    print("--- Test: Trace Route ---")
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    target_host = "8.8.8.8"
    print(f"Tracing route to {target_host}...")
    
    res = trace_network_route(target=target_host, max_hops=10, script_path=target_script)
    
    if res.get("ok"):
        hops = res['data']['hops']
        print(f"Total Hops: {res['data']['hop_count']}")
        print(f"\n{'Hop':<4} | {'RTT (ms)':<10} | {'Address'}")
        print("-" * 40)
        
        for hop in hops:
            rtt = f"{hop['rtt_ms']} ms" if hop['rtt_ms'] >= 0 else "*"
            addr = hop['address'] if hop['address'] else "Request Timed Out"
            print(f"{hop['hop']:<4} | {rtt:<10} | {addr}")
    else:
        print(json.dumps(res, indent=2, ensure_ascii=False))