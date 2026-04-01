# PC Manager 工具清单

**总计：** 81 个工具

---

## 网络管理 (14个)

### clear_proxy_config
**作用：** 清除Windows系统代理配置
**参数：** 无

### flush_dns
**作用：** 刷新DNS客户端缓存
**参数：** 无

### get_active_connections
**作用：** 获取活动网络连接列表
**参数：** limit, sort_by

### get_dns_config
**作用：** 获取DNS配置信息
**参数：** 无

### get_network_configuration_snapshot
**作用：** 获取完整网络配置快照（适配器、防火墙、代理等）
**参数：** 无

### get_route_table
**作用：** 获取路由表信息
**参数：** 无

### get_vpn_status
**作用：** 获取VPN连接状态
**参数：** 无

### get_wifi_details
**作用：** 获取WiFi详细信息
**参数：** 无

### release_renew_ipconfig
**作用：** 释放并重新获取IP地址
**参数：** 无

### reset_network_stack
**作用：** 重置网络栈（Winsock、TCP/IP）
**参数：** 无

### reset_winhttp_proxy
**作用：** 重置WinHTTP代理设置
**参数：** 无

### test_connectivity
**作用：** 测试网络连接（ping/端口测试）
**参数：** mode, target, port, dns_server

### test_secure_channel
**作用：** 测试域安全通道
**参数：** 无

### trace_network_route
**作用：** 追踪网络路由（traceroute）
**参数：** target, max_hops, timeout_ms

---

## 系统信息 (10个)

### get_battery_status
**作用：** 获取电池状态信息
**参数：** 无

### get_bitlocker_status
**作用：** 获取BitLocker加密状态
**参数：** 无

### get_device_status
**作用：** 获取设备状态
**参数：** name_pattern, class_name

### get_disk_info
**作用：** 获取磁盘空间信息
**参数：** drive_letter

### get_firewall_status
**作用：** 获取防火墙状态
**参数：** 无

### get_pnp_device_list
**作用：** 获取即插即用设备列表
**参数：** 无

### get_system_specs
**作用：** 获取系统规格（CPU、内存、OS等）
**参数：** 无

### get_temperature
**作用：** 获取系统温度信息
**参数：** 无

### get_tpm_status
**作用：** 获取TPM（可信平台模块）状态
**参数：** 无

### get_usb_info
**作用：** 获取USB设备信息
**参数：** 无

---

## 进程与服务管理 (8个)

### check_process_health
**作用：** 检查进程健康状态（崩溃、重启历史）
**参数：** process_name, time_range_hours, limit

### get_process_cpu_time
**作用：** 获取进程CPU使用时间
**参数：** process_name, top_n

### get_running_processes
**作用：** 获取运行中的进程列表
**参数：** limit, sort_by

### get_service_status
**作用：** 获取Windows服务状态
**参数：** service_name, filter_status, sort_by, limit

### kill_process
**作用：** 终止进程
**参数：** process_name, process_id, force, include_children

### restart_service
**作用：** 重启Windows服务
**参数：** service_name

### start_service
**作用：** 启动Windows服务
**参数：** service_name

### stop_service
**作用：** 停止Windows服务
**参数：** service_name

---

## 电源管理 (3个)

### get_active_power_plan
**作用：** 获取当前活动的电源计划
**参数：** 无

### get_power_requests
**作用：** 获取阻止系统睡眠的电源请求
**参数：** 无

### set_active_power_plan
**作用：** 设置活动电源计划
**参数：** plan_name

---

## 打印机管理 (9个)

### cancel_print_job
**作用：** 取消打印任务
**参数：** printer_name, job_id

### control_print_job
**作用：** 控制打印任务（暂停/恢复/重启）
**参数：** printer_name, job_id, action

### get_printer_config
**作用：** 获取打印机配置
**参数：** printer_name

### get_printer_queue
**作用：** 获取打印队列
**参数：** printer_name

### install_printer
**作用：** 安装打印机
**参数：** printer_name, port_name, driver_name

### list_printers
**作用：** 列出所有打印机
**参数：** 无

### remove_printer
**作用：** 删除打印机
**参数：** printer_name

### set_default_printer
**作用：** 设置默认打印机
**参数：** printer_name

### set_printer_config
**作用：** 设置打印机配置
**参数：** printer_name, config_options

---

## 软件与应用 (4个)

### get_app_last_used_time
**作用：** 获取应用最后使用时间
**参数：** app_name

### get_browser_extensions
**作用：** 获取浏览器扩展列表
**参数：** browser

### get_installed_software
**作用：** 获取已安装软件列表
**参数：** name_pattern, limit

### uninstall_software
**作用：** 卸载软件
**参数：** software_name, product_code

---

## 启动项管理 (3个)

### disable_startup_item
**作用：** 禁用启动项
**参数：** item_type, item_path, item_name

### enable_startup_item
**作用：** 启用启动项
**参数：** item_type, item_path, item_name

### get_startup_items
**作用：** 获取启动项列表
**参数：** 无

---

## 文件操作 (5个)

### execute_cleanup_items
**作用：** 执行清理操作
**参数：** cleanup_ids

### get_directory_size
**作用：** 获取目录大小
**参数：** path, include_subdirs

### list_large_files
**作用：** 列出大文件
**参数：** path, min_size_mb, limit

### move_file_to_recycle_bin
**作用：** 移动文件到回收站
**参数：** file_path

### scan_cleanup_items
**作用：** 扫描可清理项目
**参数：** 无

---

## 安全与更新 (5个)

### check_root_certificate
**作用：** 检查根证书
**参数：** common_name, thumbprint, store, location

### force_gpupdate
**作用：** 强制更新组策略
**参数：** 无

### get_antivirus_status
**作用：** 获取杀毒软件状态
**参数：** 无

### get_gpo_status
**作用：** 获取组策略对象状态
**参数：** 无

### get_os_update_status
**作用：** 获取操作系统更新状态
**参数：** 无

---

## 硬件与设备 (6个)

### enable_disable_device
**作用：** 启用或禁用设备
**参数：** pnp_device_id, action

### get_audio_service_status
**作用：** 获取音频服务状态
**参数：** 无

### get_monitor_topology
**作用：** 获取显示器拓扑结构
**参数：** 无

### list_camera_devices
**作用：** 列出摄像头设备
**参数：** 无

### reinstall_driver
**作用：** 重新安装驱动程序
**参数：** device_id

### reset_audio_service
**作用：** 重置音频服务
**参数：** 无

---

## 系统配置 (9个)

### delete_hosts_entry
**作用：** 删除hosts文件条目
**参数：** hostname

### get_hosts_content
**作用：** 获取hosts文件内容
**参数：** 无

### get_local_admin_members
**作用：** 获取本地管理员组成员
**参数：** 无

### get_mic_privacy_settings
**作用：** 获取麦克风隐私设置
**参数：** 无

### get_pagefile_status
**作用：** 获取页面文件状态
**参数：** 无

### get_password_expiry
**作用：** 获取密码过期信息
**参数：** username

### get_system_uptime
**作用：** 获取系统运行时间
**参数：** 无

### get_user_context
**作用：** 获取用户上下文信息
**参数：** 无

### get_usb_storage_devices
**作用：** 获取USB存储设备列表
**参数：** 无

---

## 诊断工具 (5个)

### check_time_synchronization
**作用：** 检查时间同步状态
**参数：** 无

### get_bsod_history
**作用：** 获取蓝屏死机历史
**参数：** days, limit

### get_event_log
**作用：** 获取事件日志
**参数：** log_name, level, max_events

### get_system_health_snapshot
**作用：** 获取系统健康快照
**参数：** 无

### get_top_window
**作用：** 获取顶层窗口信息
**参数：** 无

---

## 使用说明

所有工具都支持以下通用参数：
- `dry_run` (bool): 模拟执行，不实际修改系统
- `script_path` (str): PowerShell脚本路径（通常无需修改）

危险操作（如kill_process、uninstall_software等）会自动请求管理员权限。
