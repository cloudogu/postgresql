# PostgreSQL Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [v14.17-5] - 2025-07-25
### Fixed
- [#56] Fix permission denied error on minor upgrade

## [v14.17-4] - 2025-07-25
### Fixed
- [#54] Fix problem to chown files while post-upgrade script deletes the pgdata
- [#54] Upgrade makefiles to 10.2.0

## [v14.17-3] - 2025-07-24
### Fixed
- [#53] Fix race condition between startup script and post upgrade script

## [v14.17-2] - 2025-04-24
### Changed
- [#50] Set sensible resource requests and limits

## [v14.17-1] - 2025-03-04
### Changed
- [#44] Execute necessary migration for all databases in post-upgrade script

## [v14.15-2] - 2025-02-21
### Changed
- [#47] Do not restrict access via `pg_hba.conf` in multinode anymore because network policies do that.

## [v14.15-1] - 2025-01-23
### Changed 
- [#42] Update Makefiles to 9.5.0
- [#42] Update postgresql to 14.15
- [#42] Add migration checker to post-upgrade.sh
  - The migration checker fixes potentially corrupt data in postgres, due to bugfixes in postgres itself

## [v14.13-1] - 2024-11-13
### Changed
- [#40] Update postgresql to v14.13

## [v14.12-4] - 2024-10-11
### Added
- [#38] Extensions from `postgresql-contrib`

## [v14.12-3] - 2024-09-23
### Changed
- Relicense to AGPL-3.0-only

## [v14.12-2] - 2024-09-05
### Fixed
- [#34] Add missing local-config volume

## [v14.12-1] - 2024-08-28
### Changed
- [#32] Update postgresql to v14.12
- [#32] Update base image to 3.20.2-1
- [#32] Update gosu to 1.17

## [v12.19-1] - 2024-08-28
### Fixed
- Re-release of v12.18-3
  - v12.18-3 used postgres package 12.19-r0

## [v12.18-3] - 2024-08-07
### Changed
- [#30] Upgrade base image to 3.18.8-1

### Security
- [#30] close CVE-2024-41110

## [v12.18-2] - 2024-06-27
### Changed
- [#28] Update postgresql to v12.19
- [#28] Upgrade Base Image to 3.18.7-2

## [v12.18-1] - 2024-02-13
### Changed
- [#26] Update postgresql to v12.18
- Update Makefiles to 9.0.1

### Fixed
- [#26] Fix [CVE-2024-0985](https://www.postgresql.org/support/security/CVE-2024-0985/)

## [v12.15-2] - 2023-06-27
### Added
- [#24] Configuration options for resource requirements
- [#24] Defaults for CPU and memory requests

## [v12.15-1] - 2023-06-13
### Fixed
- [#22] Allow connections from all nodes of a cluster (cidr /16) in kubernetes environments.

## [v12.14-2] - 2023-04-21
### Changed
- [#20] Upgrade Base Image to 3.17.3-2

### Security
- [#20] Fixed CVE-2023-27536, CVE-2023-27536 and some others

## [v12.14-1] - 2023-03-14
### Changed
- Upgrade to PostgreSQL 12.14; #18
  - This update contains a security fix

## [v12.13-1] - 2023-02-06
### Changed
- Upgrades PostgreSQL to 12.13 (#15)
  - This update contains several security fixes
- Update base image to 3.17.1-1 (#15)
- Set healthcheck interval to 5 seconds

## [v12.10-1] - 2022-04-06
### Changed
- Upgrades PostgreSQL to 12.10
  - this upgrade is necessary to upgrade packages for security reasons
  - PostgreSQL 12.9 is no longer available in Alpine 3.12.4

### Fixed
- Upgrade zlib to fix [CVE-2018-25032](https://security.alpinelinux.org/vuln/CVE-2018-25032); #13
- Upgrade ssl libraries to 1.1.1n-r0 and fix [CVE-2022-0778](https://security.alpinelinux.org/vuln/CVE-2022-0778)

## [v12.9-1] - 2022-01-11
### Changed
- Upgrade to PostgreSQL 12.9; #11

### Added
- Option to change the dogu log level

## [v12.5-2] - 2020-12-16
### Added
- command to remove service accounts

## [v12.5-1] - 2020-12-10
### Changed
- Major upgrade to PostgreSQL 12; #7
- Upgrade base image to 3.12.1-1

### Added
- Add Jenkinsfile

## [9.6.13-1](https://github.com/cloudogu/postgresql/releases/tag/v9.6.13-1) - 2020-04-22
### Added
- `create-sa.sh` now accepts a second argument which represents the database collation

### Changed
- updated gosu to version from 1.2 to 1.10
- Recreate the pg_hba.conf file on each dogu start to keep up with network changes
