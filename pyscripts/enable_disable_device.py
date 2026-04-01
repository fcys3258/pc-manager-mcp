import json
import subprocess
import os
import tempfile
from typing import Dict, Any, Literal

def enable_disable_device(
    pnp_device_id: str,
    action: Literal["enable", "disable"],
    dry_run: bool = False,
    script_path: str = r"scripts\scripts\powershell\enable_disable_device.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本启用或禁用指定的 Windows 硬件设备。
    
    注意：此操作需要管理员权限。

    Args:
        pnp_device_id (str): 设备的 PnP 实例 ID (例如 "USB\\VID_04F2&PID_B604\\...").
                             可以通过 get-pnp_device_list 获取。
        action (str): 执行的操作，必须是 "enable" 或 "disable"。
        dry_run (bool): 如果为 True，仅模拟执行。默认为 False。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 执行结果。
    """

    # 1. 校验参数
    if action not in ["enable", "disable"]:
        return {
            "ok": False,
            "error": {"code": "INVALID_ARGUMENT", "message": f"Invalid action: {action}"}
        }

    # 2. 构造参数负载
    payload = {
        "parameter": {
            "pnp_device_id": pnp_device_id,
            "action": action,
            "dry_run": dry_run
        },
        "metadata": {
            "timeout_ms": 30000,
            "agent_invoker": "python-client"
        }
    }

    # 3. 创建临时文件传递参数
    input_file_fd, input_file_path = tempfile.mkstemp(suffix=".json", text=True)

    try:
        with os.fdopen(input_file_fd, 'w', encoding='utf-8') as f:
            json.dump(payload, f, ensure_ascii=False)

        # 4. 构建 PowerShell 命令
        cmd = [
            "powershell",
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", script_path,
            "-InputFile", input_file_path
        ]

        # 5. 执行命令
        # 启用/禁用设备操作较慢，且可能涉及驱动加载，subprocess 需耐心等待
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            encoding='utf-8'
        )

        # 6. 错误处理与解析
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
    
    # 提示：如何获取 PnP Device ID？
    # 在 PowerShell 中运行: Get-PnpDevice -Class Camera | Select-Object FriendlyName, InstanceId
    # 或者 Get-PnpDevice | Where-Object { $_.FriendlyName -like "*Webcam*" }
    
    # 假设这里有一个摄像头的 ID (仅作示例，请替换为你电脑上的真实 ID)
    # 例如：Integrated Webcam
    sample_id = "USB\\VID_04F2&PID_B604\\6&1A62A0D6&0&2" 

    print("--- Test: Dry Run Disable ---")
    res_dry = enable_disable_device(
        pnp_device_id=sample_id,
        action="disable",
        dry_run=True
    )
    print(json.dumps(res_dry, indent=2, ensure_ascii=False))

    # 实际执行时，需要确保 ID 正确，否则会报 TARGET_NOT_FOUND
    if not res_dry.get("ok") and res_dry.get("error", {}).get("code") == "TARGET_NOT_FOUND":
        print("\n[注意] 测试ID在当前机器上未找到。请修改 sample_id 为你电脑上存在的设备ID进行测试。")