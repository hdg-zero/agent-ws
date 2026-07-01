# Documentation

English documentation for the isolated AI environment. The French version remains the primary reference and is available in [`docs/fr/`](../fr/README.md).

## Contents

- [Architecture](architecture.md)
- [Installation](installation.md)
- [Daily usage](usage.md)
- [Troubleshooting](troubleshooting.md)

## Goal

This documentation explains how to isolate an AI environment on a Linux workstation by combining:

- a dedicated host user for AI tools;
- rootless Podman;
- Distrobox;
- an explicit shared project directory;
- controlled Wayland access for GUI applications.

## Recommended stance

The recommended path is the manual one. The scripts in this repository are optional automation helpers, not the primary learning path.

Do not assume that shell scripts found in repositories should be executed as-is. Read them, audit them, verify their scope, and only run them if you accept exactly what they will change.

## Who this is for

This architecture is suitable if you want to:

- run an AI agent or a graphical IDE with network access;
- avoid directly exposing your real personal home directory;
- keep a disposable environment for tools and dependencies;
- maintain a clearly defined and recoverable project workspace.

## What you will find here

- `architecture.md`: mental model, flows, and security assumptions;
- `installation.md`: installation via script and manual summary;
- `usage.md`: daily usage, helpful commands, and best practices;
- `troubleshooting.md`: common errors and fixes.

## Core assumption

The main security boundary is the dedicated Linux user and standard Unix permissions. Distrobox is treated as a convenience layer, not as a strong security sandbox.
