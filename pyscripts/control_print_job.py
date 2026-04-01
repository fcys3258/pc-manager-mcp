import json
import subprocess
import os
import tempfile
from typing import Dict, Any, Union

def control_print_job(
    printer_name: str, 
    job_id: int, 
    action: str, 
    dry_run: bool = False, 
    script_path: str = r"scripts\scripts\powershell\control_print_job.ps1"
) -> Dict[str, Any]:
    """
    控制特定打印作业（暂停、继续或重启）。
    
    Args:
        printer_name (str): 打印机的准确名称（例如“HP LaserJet M102”）。
        job_id (int): 打印作业的 ID。
        action (str): 要执行的操作，选项: "pause", "resume", "restart".
        dry_run (bool): 仅模拟执行。
        script_path (str): ps1 脚本路径。

    Returns:
        Dict[str, Any]: 包含结果的字典。
    """
    
    # 1. Construct the JSON payload required by the PowerShell script
    payload = {
        "parameter": {
            "printer_name": printer_name,
            "job_id": job_id,
            "action": action,
            "dry_run": dry_run
        },
        "metadata": {
            "timeout_ms": 30000,
            "agent_invoker": "python-client"
        }
    }

    # 2. Use a temporary file to pass arguments safely
    # This avoids command-line escaping issues for complex printer names
    input_file_fd, input_file_path = tempfile.mkstemp(suffix=".json", text=True)
    
    try:
        with os.fdopen(input_file_fd, 'w', encoding='utf-8') as f:
            json.dump(payload, f, ensure_ascii=False)

        # 3. Build the subprocess command
        # -ExecutionPolicy Bypass: Required to run scripts on most systems
        cmd = [
            "powershell",
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", script_path,
            "-InputFile", input_file_path
        ]

        # 4. Execute and capture output
        # Using utf-8 encoding to match [Console]::OutputEncoding in the script
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            encoding='utf-8'
        )

        # 5. Process the result
        # Case A: Script crashed or wrote to stderr only
        if result.stderr and not result.stdout:
            return {
                "ok": False,
                "error": {
                    "code": "SUBPROCESS_ERROR",
                    "message": result.stderr.strip()
                }
            }

        # Case B: Standard execution (Success or Logic Error caught by script)
        try:
            return json.loads(result.stdout)
        except json.JSONDecodeError:
            return {
                "ok": False,
                "error": {
                    "code": "JSON_PARSE_ERROR",
                    "message": "Failed to parse script output",
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
        # 6. Cleanup temporary file
        if os.path.exists(input_file_path):
            try:
                os.remove(input_file_path)
            except:
                pass

# --- Usage Example ---
if __name__ == "__main__":
    # Example: Dry Run to pause a job
    print("--- Test: Dry Run (Pause) ---")
    result = control_print_job(
        printer_name="Microsoft Print to PDF",
        job_id=123,
        action="pause",
        dry_run=True
    )
    print(json.dumps(result, indent=2, ensure_ascii=False))