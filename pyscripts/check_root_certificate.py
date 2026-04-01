import json
import subprocess
import os
import tempfile
from typing import Optional, Dict, Any

def check_root_certificate(
    common_name: Optional[str] = None,
    thumbprint: Optional[str] = None,
    store: str = "Root",
    location: str = "LocalMachine",
    script_path: str = r"scripts\scripts\powershell\check_root_certificate.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本查询或列出 Windows 证书存储中的证书。

    Args:
        common_name (str, optional): 证书通用名称 (CN) 的一部分，用于模糊搜索。
        thumbprint (str, optional): 证书指纹 (Hash)，用于精确搜索。
        store (str): 证书存储名称，默认为 "Root"。常见值: "Root", "CA", "My", "TrustedPublisher".
        location (str): 存储位置，默认为 "LocalMachine"。可选: "LocalMachine", "CurrentUser".
        script_path (str): ps1 脚本路径.

    Returns:
        Dict[str, Any]: 执行结果字典。
    """

    # 1. 构造参数负载
    # 如果 common_name 或 thumbprint 存在，脚本将进入"搜索模式"
    # 如果两者都不存在，脚本将进入"列表模式" (默认列出前50个)
    payload = {
        "parameter": {
            "store": store,
            "location": location
        },
        "metadata": {
            "timeout_ms": 10000,
            "agent_invoker": "python-client"
        }
    }

    if common_name:
        payload["parameter"]["common_name"] = common_name
    if thumbprint:
        payload["parameter"]["thumbprint"] = thumbprint

    # 2. 创建临时文件传递 JSON
    # 使用 InputFile 模式可以避免命令行参数转义问题
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
        # 读取证书通常不需要管理员权限，但如果要读 LocalMachine 的某些受保护区域可能需要
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            encoding='utf-8' # 对应脚本中的 [Console]::OutputEncoding
        )

        # 5. 处理结果
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
        # 清理临时文件
        if os.path.exists(input_file_path):
            try:
                os.remove(input_file_path)
            except:
                pass

# --- 使用示例 ---
if __name__ == "__main__":
    
    # 场景 1: 搜索包含 "Microsoft" 的根证书
    print("--- 搜索 'Microsoft' 证书 ---")
    result_search = check_root_certificate(
        common_name="Microsoft",
        store="Root",
        location="LocalMachine"
    )
    
    if result_search.get("ok"):
        data = result_search["data"]
        print(f"找到 {data['match_count']} 个匹配证书:")
        for cert in data.get('matched_certificates', [])[:3]: # 只打印前3个示例
            print(f"  - CN: {cert['common_name']}")
            print(f"    有效期至: {cert['not_after']}")
            print(f"    指纹: {cert['thumbprint']}")
    else:
        print("搜索失败:", result_search)

    print("\n" + "="*30 + "\n")

    # 场景 2: 列出当前用户 "个人 (My)" 存储区的所有证书
    # 不传 common_name 和 thumbprint 即可触发列表模式
    print("--- 列出当前用户个人证书 (前50个) ---")
    result_list = check_root_certificate(
        store="My",
        location="CurrentUser"
    )
    
    if result_list.get("ok"):
        data = result_list["data"]
        print(f"总数: {data['total_count']}")
        print(f"已过期: {data['expired_count']}")
        print("列表 (部分):")
        for cert in data.get('certificates', []):
            status = "[过期]" if cert['is_expired'] else "[有效]"
            print(f"  {status} {cert['common_name']} ({cert['thumbprint']})")
    else:
        # 如果是空的或者是新电脑，这里可能是0
        print("列出失败或无数据:", result_list)