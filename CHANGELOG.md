# Changelog

All notable changes to the VSM Event Bus will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial VSM Event Bus implementation
- Phoenix PubSub integration for scalable event distribution
- Event filtering and routing mechanisms
- Distributed coordination via libcluster
- VSM-aware message validation and transformation
- Comprehensive test coverage
- Performance monitoring and telemetry

### Features
- Central event bus GenServer for VSM subsystem coordination
- Support for all VSM communication channels (command, coordination, audit, algedonic)
- Event persistence and replay capabilities
- Real-time event streaming and subscription management
- Automatic failover and clustering support
- Integration with VSM Core message protocol

## [0.1.0] - 2025-07-21

### Added
- Initial project structure
- Core dependencies configuration
- Basic application supervision tree