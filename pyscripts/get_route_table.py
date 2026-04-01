import json
import subprocess
import os
import tempfile
from typing import Dict, Any

def get_route_table(
    dry_run: bool = False,
    # 使用 r"" 原始字符串避免路径转义问题
    script_path: str = r"scripts\scripts\powershell\get_route_table.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本获取系统路由表。
    
    用于诊断网络路由问题，例如 VPN 路由冲突、默认网关错误或多网卡优先级问题。
    返回 IPv4 和 IPv6 路由条目。

    Args:
        dry_run (bool): 仅模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含路由表条目的字典。
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
        # 脚本内部处理了 GBK 兼容性并强制 UTF-8 输出，Python 端直接读取 UTF-8
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
    
    target_script = r"scripts\scripts\powershell\get_route_table.ps1"
    print("--- Test: Get Route Table ---")
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    res = get_route_table(script_path=target_script)
    
    if res.get("ok"):
        routes = res['data']['routes']
        print(f"Total Routes: {res['data']['route_count']}")
        
        # 筛选并打印 IPv4 默认路由 (0.0.0.0/0)
        default_routes = [r for r in routes if r['destination'] == '0.0.0.0/0']
        if default_routes:
            print("\nDefault Gateway(s):")
            for r in default_routes:
                metric = r.get('metric', 'N/A')
                print(f"- Gateway: {r['gateway']} (Metric: {metric}) - {r.get('interface_alias', 'Unknown')}")
        
        # 打印其他路由的前几条
        print("\nOther Routes (Top 5):")
        other_routes = [r for r in routes if r['destination'] != '0.0.0.0/0'][:5]
        for r in other_routes:
            print(f"  {r['destination']} -> {r['gateway']}")
    else:
        print(json.dumps(res, indent=2, ensure_ascii=False))