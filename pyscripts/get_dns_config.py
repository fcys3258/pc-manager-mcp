import json
import subprocess
import os
import tempfile
from typing import Dict, Any

def get_dns_config(
    dry_run: bool = False,
    # 使用 r"" 原始字符串
    script_path: str = r"scripts\scripts\powershell\get_dns_config.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本获取系统当前的网络 DNS 配置。
    
    该工具用于诊断 "无法打开网页"、"解析错误" 或 "网速慢" 等问题。
    它会列出所有处于连接状态的网卡及其 DNS 服务器地址 (IPv4/IPv6)。

    Args:
        dry_run (bool): 仅模拟执行 (此脚本为只读，效果与真实运行一致)。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含各个网卡 DNS 配置的列表。
    """

    # 1. 构造参数负载
    # 此脚本无需额外输入参数
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
    
    target_script = r"scripts\scripts\powershell\get_dns_config.ps1"
    print("--- Test: Get DNS Config ---")
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    res = get_dns_config(script_path=target_script)
    
    if res.get("ok"):
        configs = res['data']['dns_configs']
        print(f"Active Adapters Found: {len(configs)}")
        
        for adapter in configs:
            print(f"\nAdapter: {adapter['interface_name']} ({adapter.get('interface_description', '')})")
            
            # 优先显示 IPv4 DNS
            ipv4 = adapter.get('ipv4_dns', [])
            if ipv4:
                print(f"  IPv4 DNS: {', '.join(ipv4)}")
            
            # 显示 IPv6 DNS (如果有)
            ipv6 = adapter.get('ipv6_dns', [])
            if ipv6:
                print(f"  IPv6 DNS: {', '.join(ipv6)}")
                
            # WMI 模式下的 fallback 字段
            if adapter.get('dns_servers'):
                print(f"  DNS Servers: {', '.join(adapter['dns_servers'])}")
                
            if not ipv4 and not ipv6 and not adapter.get('dns_servers'):
                print("  DNS: (Auto/DHCP or None)")
    else:
        print(json.dumps(res, indent=2, ensure_ascii=False))