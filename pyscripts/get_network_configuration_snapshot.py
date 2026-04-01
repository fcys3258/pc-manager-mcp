import json
import subprocess
import os
import tempfile
from typing import Dict, Any

def get_network_configuration_snapshot(
    dry_run: bool = False,
    # 使用 r"" 原始字符串避免路径转义问题
    script_path: str = r"scripts\scripts\powershell\get_network_configuration_snapshot.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本获取系统网络配置的全景快照。
    
    返回数据包括：
    1. 所有活动网卡的详细信息 (IP, DNS, Gateway, MAC, Wi-Fi SSID)。
    2. Windows 防火墙的开启状态。
    3. 系统代理 (Proxy) 的开启状态和服务器地址。

    Args:
        dry_run (bool): 仅模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含网络配置快照的字典。
    """

    # 1. 构造参数负载
    payload = {
        "parameter": {
            "dry_run": dry_run
        },
        "metadata": {
            "timeout_ms": 15000, # 涉及 WMI 和网络查询
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
    
    target_script = r"scripts\scripts\powershell\get_network_configuration_snapshot.ps1"
    print("--- Test: Network Snapshot ---")
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    res = get_network_configuration_snapshot(script_path=target_script)
    
    if res.get("ok"):
        data = res['data']
        
        # 1. 打印代理状态
        proxy_status = "Enabled" if data.get('is_proxy_enabled') else "Disabled"
        proxy_server = f" ({data.get('proxy_server')})" if data.get('proxy_server') else ""
        print(f"System Proxy: {proxy_status}{proxy_server}")
        
        # 2. 打印网卡信息
        print(f"\nActive Adapters ({len(data.get('adapters', []))}):")
        for adapter in data.get('adapters', []):
            name = adapter['interface_name']
            # 安全获取 SSID
            ssid_info = adapter.get('wifi_ssid')
            if ssid_info: 
                name += f" (Wi-Fi: {ssid_info})"
            
            print(f"- {name}")
            
            # 安全打印 IP (过滤空值)
            ips = [str(i) for i in adapter.get('ip_addresses', []) if i]
            if ips:
                print(f"  IP: {', '.join(ips)}")
            
            # [修复点] 安全打印 Gateway (过滤 None)
            gws = [str(g) for g in adapter.get('default_gateways', []) if g]
            if gws:
                print(f"  GW: {', '.join(gws)}")
            
            # 安全打印 DNS
            dns = [str(d) for d in adapter.get('dns_servers', []) if d]
            if dns:
                print(f"  DNS: {', '.join(dns)}")

        # 3. 打印防火墙状态
        print("\nFirewall Profiles:")
        for fw in data.get('firewall_profiles', []):
            state = "ON" if fw['is_enabled'] else "OFF"
            print(f"  {fw['name']}: {state}")
            
    else:
        print(json.dumps(res, indent=2, ensure_ascii=False))