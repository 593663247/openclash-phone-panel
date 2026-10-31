# Versioning

- Application version: `VERSION`, semantic version `1.0.0`.
- Git tag and GitHub Release: `v1.0.0`.
- opkg packaging revision: `1.0.0-1`; increment suffix for package-only fixes.
- Every release tag is immutable and points to its tested source commit. Release assets must be built from that commit. SHA256 is provided alongside assets.
- Patch versions fix bugs, minor versions add compatible capabilities, major versions introduce incompatible changes. Document changes in CHANGELOG.md before tagging.
- The panel shows application version plus installed commit; upgrading main may include unreleased changes, so a version string alone is not a source identity.
- A numbered release does not imply unsupported firmware or destructive recovery has been certified.
