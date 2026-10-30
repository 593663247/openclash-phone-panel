# Security / 安全

This experimental software can modify privileged router configuration. Keep LuCI authentication, ACL and CSRF protections enabled, use only a trusted LAN, and review the reference topology before installing.

Do not submit real proxy YAML, keys, passwords, tokens, cookies, DHCP leases, real MAC/IP inventories, packet captures, screenshots containing private data, recovery snapshots or full runtime logs in public issues. Use synthetic reproductions and minimal redacted excerpts. Never paste a credential to demonstrate a bug.

本项目运行权限高，请勿暴露管理页。报告问题前用合成配置复现，移除账号密码、密钥、设备清单、日志和截图中的隐私。文件恢复不保证运行态完整恢复，部署前保留本地恢复通道。

If private vulnerability reporting is available on GitHub, prefer that mechanism for security-sensitive reports. Otherwise open a minimal issue asking for a private contact route without disclosing exploit details or secrets. No dedicated security support SLA is offered.
