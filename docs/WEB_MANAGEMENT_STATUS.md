# Web management development status

This branch is **not a completed no-terminal release**. Do not install it over a production router. The last packaged version is not equivalent to this working tree.

Implemented: persisted maintenance task list, five allow-listed actions (doctor, backup, initialize, dependencies, hook repair), POST/CSRF checks, execution confirmation and shared configuration lock; legacy initialization now submits through the same task runner. Private command logs stay on the router. Hook integration supports marked blocks and refuses ambiguous legacy integrations.

Still required before release:
- Device edit/rebind/disable/delete with previews, references and rollback tests.
- Real UDP path tests and a diagnostic center, not merely configuration indicators.
- Per-group DNS cache management and validated settings application.
- Backup inventory/download with sensitive-data confirmation and a tested browser restore flow.
- Validated uploaded package upgrades and complete safe uninstall UI.
- First-run discovery wizard, complete progress reporting, crash/reboot task reconciliation.
- Router integration tests, UI tests and a freshly tested package.

Checks performed so far: pure import planner tests, task allow-list/serialization tests, JavaScript/Ruby/shell syntax and publication privacy checks. These do not establish real-router operation, complete rollback or security of unimplemented operations.

本分支为开发版本，不代表所有按钮已完成，不应替换生产安装。设备编辑删除、网页恢复、上传升级、卸载向导、实际UDP诊断以及实机测试仍未完成。严禁把本分支描述为完整免终端版。
