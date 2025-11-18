# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-11-17

### Changed

- **BREAKING**: Now requires Charon 4.0 or later (previously compatible with Charon 3.x)
- **BREAKING**: Minimum Elixir version raised to 1.16 (previously 1.13)
- Removed direct dependency on Jason - now uses the JSON module configured for Charon instead
- Reduced (new) client secret size to 256 bits from 384

## [0.6.0] - 2025-11-13

### Added

- Support for OAuth2 Client Credentials grant type
