---
name: vyron-git
description: Inspect Git repositories, stage and commit changes, manage local branches and tags, integrate commits, and recover work in Vyron Work. Use for Git requests, /git, or /vyron-commit.
---

# Git in Vyron Work

Use `run_command` in the selected repository. Check `git status --short --branch` and verify the repository root before changing the index, worktree, or refs. If the folder has no repository, initialize it with `git init` only when the user asks.

Use the existing command review for writes. The user's request defines the scope of those writes. Use a single Git command per tool call and pass explicit paths after `--` where supported. Check path lists before opening diffs and exclude credentials and unrelated files from inspection or staging.

## Stage and commit

- For `/vyron-commit feature <name>`, commit the named change and its directly related fixes, tests, and documentation. For `/vyron-commit all`, review eligible staged, unstaged, untracked, and deleted paths in the selected repository and create one commit. For an unqualified commit, infer the requested scope from the task or the coherent staged changes. Clarify when the scope remains ambiguous.
- Check `git diff`, `git diff --cached`, and untracked paths. Inspect relevant untracked files separately. Preserve unrelated staged and unstaged work, including changes to the same file. To stage selected hunks, review a patch and validate it with `git apply --cached --check` before applying it with `git apply --cached`.
- Use `git add -- <paths>` for reviewed whole paths and `git restore --staged -- <paths>` to unstage without changing working files. `git commit --only -m "<message>" -- <paths>` can isolate reviewed full changes to tracked paths when unrelated paths are already staged. If the requested changes cannot be safely isolated, clarify the intended commit scope before touching the index.
- Review the exact content the commit will include. Reuse existing build and test results, check repository instructions for required checks, and report check failures separately from Git command failures. For `/vyron-commit`, use a Conventional Commit subject such as `fix(parser): preserve quoted arguments`. Choose the type from the diff and describe distinct changes in the body when needed. Pass the message with `-m` or a file with `-F`. A request for a commit message calls for a draft.
- Check the effective identity before committing with `git var GIT_AUTHOR_IDENT` and `git var GIT_COMMITTER_IDENT`. The guarded runner uses repository-local configuration. When the user authorizes an identity change and supplies the values, use `git config --local user.name "<name>"` and `git config --local user.email "<email>"`.
- Verify the resulting commit ID, subject, changed paths, and remaining status. If a command fails or times out, check history and status before retrying so a late success cannot create a duplicate. Report the first Git operation that actually failed and whether changes remain staged.

## Branches, integration, and recovery

- Inspect local branches and commit history before creating or switching branches or adding tags. Use `git switch -c <branch>` when creating and switching to a new branch. Check pending work before switching branches or integrating commits. Use `git worktree list` to locate existing worktrees and confirm the selected folder.
- Use `git stash list` and `git stash show` to confirm the intended entry. Use `git stash apply` when recovering work and confirm the result before dropping the entry. Include untracked files in a stash only when they belong to the requested work.
- Check source and destination refs before a merge, rebase, cherry-pick, or revert. Run noninteractive operations. For a merge commit, use `--no-edit` to accept the default message or `-m` to supply one. Inspect `git status` after each operation. If conflicts interrupt it, resolve only the requested files and use that operation's continue or abort command as appropriate. Verify the resulting history and worktree.
- Use `git log`, `git show`, `git diff`, and `git reflog` to locate a recoverable commit. A branch pointing to the recovered commit preserves it for inspection. Confirm the target and affected paths before any requested restore, reset, or history rewrite. Preserve unrelated work.

Use a separately authorized connected integration for network operations such as clone, fetch, pull, or push when one supports the request. If the available tools cannot perform the operation, report that limit and any local steps that succeeded.
