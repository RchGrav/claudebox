# commands/ Directory Documentation

This directory contains command definitions for Claude Code, including both built-in ClaudeBox commands and specialized agent/workflow definitions.

## Directory Structure

### Subdirectories
- `BMad/` - Business Modeling and Design framework with specialized agents and tasks
  - `agents/` - Role-based agents (analyst, architect, dev, pm, etc.)
  - `tasks/` - Workflow tasks for story creation, documentation, etc.
- `cbox/` - ClaudeBox-specific commands
- `tmux/` - Terminal multiplexer integration commands

### Root Command Files
- `adaptive.md` - Adaptive problem-solving framework
- `agentflow.md` - Agent orchestration and flow control
- `context_pipeline.md` - Context management pipeline
- `controlflow.md` - Control flow management
- `devops.md` - DevOps automation commands
- `pr-draft.md` - Pull request draft creation
- `pr-review.md` - Pull request review automation
- `refactor.md` - Code refactoring assistant
- `taskengine.md` - Task management engine
- `taskflow.md` - Task flow orchestration
- `tdd.md` - Test-driven development workflow

## Command File Format

Commands follow a Markdown format with optional frontmatter:
```markdown
---
name: command-name
description: Brief description
tools: tool1, tool2, tool3
---

Command content and instructions...
```

## Syncing Mechanism

Commands are synced to projects via `sync_commands_to_project()` in lib/project.sh:
- ClaudeBox bundled commands from this directory
- User commands from ~/.claude/commands
- Synced to project's commands/ directory before container launch

## Key Design Decisions & Notes

### Command Organization
- Commands are organized by functionality and complexity
- Simple single-purpose commands at root level
- Complex frameworks (like BMad) in subdirectories
- Agents and tasks separated for clarity

### Tool Permissions
Commands can specify required tools in frontmatter. If omitted, they inherit all available tools. Best practice is to specify minimal required tools.

### Proactive Triggering
Commands with "Use proactively" in their description can be automatically invoked by Claude when appropriate conditions are met.

## Recent Additions

- BMad framework for comprehensive business modeling
- Tmux integration for multi-pane development
- Context pipeline for better context management
- TDD workflow for test-driven development

## Areas for Expansion

- More language-specific development workflows
- Additional DevOps automation commands
- Security audit workflows
- Performance optimization commands