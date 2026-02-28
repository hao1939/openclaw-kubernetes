# OpenClaw Skills

Skills are structured instruction sets that teach the OpenClaw agent how to operate external tools as managed sub-agents. They are baked into the container image and synced to the persistent volume (`~/.openclaw/skills/`) on every pod start, so image upgrades automatically update built-in skills.

## Included Skills

| Directory | Skill | Description |
|-----------|-------|-------------|
| `claude-skill/` | Claude Code Agent | Operate Claude Code as a managed coding agent -- worktree isolation, tmux sessions, adaptive polling, smart retries, and multi-model code review |
| `codex-skill/` | Codex Agent | Operate Codex CLI as a managed coding agent -- same workflow patterns with Codex-specific flags and sandbox modes |

## Skill Structure

Each skill is a directory containing a `SKILL.md` file with YAML frontmatter and markdown content:

```
skills/
  my-skill/
    SKILL.md              # Required: skill definition (frontmatter + instructions)
    references/           # Optional: supporting docs, examples, schemas
      examples.md
```

### SKILL.md Format

```markdown
---
name: my-skill
description: 'Short description of when this skill should be triggered.'
---

# Skill Title

Instructions, CLI references, workflows, and examples.
```

**Frontmatter fields:**

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Unique skill identifier (lowercase, hyphenated) |
| `description` | Yes | When the agent should activate this skill (used for matching user intent) |

### References Directory

Place supporting materials in `references/` within the skill directory. These can include usage examples, API schemas, or other context the agent may need during execution.

## Adding a New Skill

1. Create a directory under `skills/` with a descriptive name
2. Add a `SKILL.md` with frontmatter and instructions
3. Optionally add a `references/` directory for supporting docs
4. The skill will be included in the next container image build

## How Skills Work

When a user's request matches a skill's `description`, the OpenClaw agent loads the skill's instructions and follows the defined workflow. Skills enable the agent to:

- Launch and manage external coding tools (Claude Code, Codex, etc.)
- Isolate work in git worktrees with dedicated branches
- Monitor long-running tasks via tmux sessions and log files
- Apply quality gates (CI checks, cross-model code review)
- Retry failed tasks with enriched context
