import json
import subprocess
import os
import tempfile
from typing import Dict, Any

def get_battery_status(
    dry_run: bool = False,
    # 使用原始字符串处理路径
    script_path: str = r"scripts\scripts\powershell\get_battery_status.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本获取电池状态和健康信息。
    
    返回的关键数据包括：
    - 剩余电量百分比
    - 电池健康度 (根据设计容量和当前满充容量计算)
    - 充电循环次数 (如果硬件支持)
    - 充放电状态 (Charging/Discharging/AC Power)

    Args:
        dry_run (bool): 仅模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含电池详细信息的字典。
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
        # 脚本内部已强制 UTF-8 输出，直接使用 utf-8 读取
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
    
    target_script = r"scripts\scripts\powershell\get_battery_status.ps1"
    print("--- Test: Battery Status ---")
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    res = get_battery_status(script_path=target_script)
    
    if res.get("ok"):
        data = res['data']
        if not data.get('supported'):
            print("结果: 未检测到电池 (可能是台式机)")
        else:
            print(f"状态: {data.get('status_description')}")
            print(f"电量: {data.get('estimated_charge_remaining_percent')}%")
            
            # 只有当获取到了容量信息才显示健康度
            if data.get('health_percent'):
                print(f"健康度: {data.get('health_percent')}% (循环次数: {data.get('cycle_count', '未知')})")
                print(f"容量详情: {data.get('full_charge_capacity_mwh')} mWh / {data.get('design_capacity_mwh')} mWh")
    else:
        print(json.dumps(res, indent=2, ensure_ascii=False))