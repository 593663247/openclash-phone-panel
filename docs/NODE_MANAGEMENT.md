# 落地节点管理 / Landing-node management

入口：手机出口与 DNS → 设备与节点（主页右侧）→ SOCKS5 落地节点管理。

1. 节点名称使用设置中的手机节点前缀（默认 `手机-`）。
2. 填服务器 IP/域名、端口；账号密码同时填写或同时留空。
3. 选择直连落地，或选择已有的具体代理节点作为前置代理（`dialer-proxy`）；暂不支持把策略组作为前置。
4. UDP 默认打开；关闭时尊重显式选择，不会被自动监听器生成脚本重新打开。开启不代表服务器或链式路径支持 UDP。
5. 点击检查并预览，核对脱敏摘要，再确认新增。确认会短暂重载 OpenClash。
6. 节点自动出现在添加/改绑设备的下拉列表。不会自动改绑现有设备。绑定后使用主页“检测 DNS / 出口”。

支持新增、编辑和删除 SOCKS5 节点；删除前检查引用。面板节点独立保存，切换配置时合并，同名不同参数会拒绝覆盖。编辑时留空认证字段可保留原认证；不会替代订阅管理。

账号密码通过已登录的 LuCI POST+CSRF 接口提交，写入本机源 YAML；不回显到预览、目录或前端持久存储，不发送到 GitHub。路由器备份含节点凭据，只保存在 root 私密目录；请自行保护备份。当前路由器使用 HTTP 管理，仅在可信管理网络操作，推荐配置 HTTPS。

应用前进行源版本校验、共享锁、核心配置检查；应用后核对实际运行节点。失败会恢复配置并尝试恢复服务，返回恢复状态与本地日志路径。配置检查及模拟测试不等于真实服务端的连通性或 UDP 测试。本功能未用真实新增付费节点完成端到端验收。

## English

Open **Devices & Nodes (to the right of Home) → SOCKS5 landing-node management**. Enter a prefixed node name, server, port, optional paired credentials, UDP preference and an optional existing concrete proxy as the dialer. Preview is read-only and redacts credentials. Confirmation backs up configuration, updates the OpenClash source, invalidates quick-start cache, restarts the core and checks the generated runtime node. Existing devices are not rebound.

The node appears in device-binding selectors. Bind explicitly, then use DNS/egress diagnostics. Explicit UDP settings are preserved; enabled does not mean the provider or full chain supports UDP. SOCKS5 nodes support creation, editing and reference-checked deletion; managed nodes are privately persisted and merged into source configurations, rejecting conflicts. Backups and diagnostics stay private on the router. Use a trusted LAN / HTTPS administration connection. Real paid-node connectivity and UDP have not been validated by fixture tests.

## Update: editing, deletion and private persistence

The Devices & Nodes page supports editing/deleting SOCKS5 nodes and direct per-node diagnostics. Blank passwords retain old authentication; advanced fields are preserved. Referenced nodes cannot be deleted. Nodes explicitly created/edited in this panel are privately persisted and merged, with conflict rejection. See [OPERATIONS.md](OPERATIONS.md) for current behavior; its node lifecycle description supersedes the initial create-only limitation above.
