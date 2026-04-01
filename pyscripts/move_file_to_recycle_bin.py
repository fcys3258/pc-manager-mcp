import json
import subprocess
import os
import tempfile
from typing import Dict, Any, List, Union

def move_file_to_recycle_bin(
    paths: Union[str, List[str]],
    dry_run: bool = False,
    # 使用 r"" 原始字符串避免路径转义问题
    script_path: str = r"scripts\scripts\powershell\move_file_to_recycle_bin.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本将文件或文件夹移动到回收站。
    
    相比直接删除，此操作更安全，允许用户在误操作后恢复文件。
    支持批量删除多个路径。

    Args:
        paths (str or List[str]): 单个文件路径或路径列表。
        dry_run (bool): 仅模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含操作结果的字典。
    """

    # 1. 构造参数负载
    # 统一将输入转换为列表
    if isinstance(paths, str):
        paths = [paths]
        
    payload = {
        "parameter": {
            "paths": paths,
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
    
    target_script = r"scripts\scripts\powershell\move_file_to_recycle_bin.ps1"
    print("--- Test: Move to Recycle Bin (Dry Run) ---")
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    # 创建一个临时测试文件
    test_file = os.path.join(tempfile.gettempdir(), "test_delete_me.txt")
    with open(test_file, "w") as f:
        f.write("This file is for testing recycle bin move.")
    print(f"Created temporary file: {test_file}")
    
    # 执行删除 (dry_run=False 以验证真实效果，或者设为 True 仅测试流程)
    # 注意：为了演示效果，这里设为 False，实际运行会把文件移到回收站
    res = move_file_to_recycle_bin(
        paths=[test_file], 
        dry_run=False, 
        script_path=target_script
    )
    
    if res.get("ok"):
        print(f"Success Count: {res['data']['success_count']}")
        for item in res['data']['results']:
            print(f"✅ Moved {item['type']}: {item['path']}")
    else:
        print(json.dumps(res, indent=2, ensure_ascii=False))
        
    # 验证文件是否已消失
    if not os.path.exists(test_file):
        print("File successfully removed from original location.")
    else:
        print("File still exists (Dry run or failed).")