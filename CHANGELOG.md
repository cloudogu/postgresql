# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
