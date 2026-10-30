# Changes

## Unreleased — reliability and maintenance

- Invalidate device previews after edits and catalog changes; ignore obsolete responses.
- Refresh available nodes without losing a valid selection. Clear obsolete probe results.
- Bound status requests to 15 seconds. Distinguish controller failure from zero connections.
- Resume pending device jobs after tab reload; offer another polling cycle after timeout and prevent new submissions while unresolved.
- Ignore expired/malformed DHCP leases, reject duplicate static assignments and shadowed source rules.
- Use full IPv4 addresses in generated DHCP section names, avoiding collisions across wider LAN subnets.
- Include effective settings and saved UCI settings in preview revisions; reject pending settings edits.
- Show only allowlisted warning summaries instead of raw proxy log text.
- Regenerate fail-closed guards for the configured bridge; remove newly generated DNS files on rollback.
- Back up active source YAML, custom hooks and routing integration. Preserve the chosen restore target when taking a pre-restore snapshot; validate restore paths.
- Upgrade init/routing code, retain existing settings/hooks, and reload firewall rules during explicit initialization.
- Refuse staging over existing settings/model files. Accept the configured high-port range in probes.
- Extend UI, backend planning, settings, lease and isolated maintenance regression tests; reconcile bilingual setup/operation documentation.

Validation covers source syntax and isolated behavior. No production router deployment, provider UDP test or complete runtime rollback guarantee is included.
