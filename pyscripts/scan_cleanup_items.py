import json
import subprocess
import os
import tempfile
from typing import Dict, Any

def scan_cleanup_items(
    dry_run: bool = False,
    # 使用 r"" 原始字符串避免路径转义问题
    script_path: str = r"scripts\scripts\powershell\scan_cleanup_items.ps1"
) -> Dict[str, Any]:
    """
    调用 PowerShell 脚本扫描可清理的系统垃圾和应用缓存。
    
    扫描范围包括：临时文件、回收站、浏览器缓存、Windows 更新缓存，
    以及微信(WeChat)和企业微信(WXWork)的数据目录。
    
    注意：此工具仅进行"扫描"，不执行删除操作。删除需调用 execute_cleanup_items。

    Args:
        dry_run (bool): 仅模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含各类垃圾文件大小和路径的字典。
    """

    # 1. 构造参数负载
    payload = {
        "parameter": {
            "dry_run": dry_run
        },
        "metadata": {
            "timeout_ms": 60000, # 扫描大目录（特别是微信）可能非常慢
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
    
    target_script = r"scripts\scripts\powershell\scan_cleanup_items.ps1"
    print("--- Test: Scan Cleanup Items ---")
    
    if not os.path.exists(target_script):
        print(f"[警告] 找不到脚本: {target_script}")
    
    # 脚本内部有提权逻辑，可能会弹出 UAC
    print("Scanning... (This may take a while)")
    res = scan_cleanup_items(script_path=target_script)
    
    if res.get("ok"):
        items = res['data']['cleanup_items']
        total_size = sum(item['size_mb'] for item in items)
        
        print(f"Total Potentially Cleanable: {total_size:.2f} MB")
        print("-" * 60)
        print(f"{'ID':<20} | {'Size (MB)':<10} | {'Description'}")
        print("-" * 60)
        
        for item in items:
            size_str = f"{item['size_mb']:.2f}"
            desc = item['description'][:40] + ".." if len(item['description']) > 40 else item['description']
            
            # 高亮大文件或敏感项
            prefix = "⚠️ " if item.get('warning') else "  "
            if item['size_mb'] > 1000: prefix = "🔥 " # 超过 1GB
            
            print(f"{prefix}{item['cleanup_id']:<18} | {size_str:<10} | {desc}")
            
    else:
        print(json.dumps(res, indent=2, ensure_ascii=False))