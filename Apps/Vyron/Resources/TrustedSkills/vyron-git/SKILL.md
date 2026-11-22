---
name: vyron-git
description: Inspect Git repositories, stage and commit changes, manage branches and tags, integrate commits, recover work, and perform authorized remote Git operations in Vyron Work. Use for Git requests, /git, or /vyron-commit.
---

# Git in Vyron Work

Use `run_command` in the selected repository. Check `git status --short --branch` and verify the repository root before changing the index, worktree, or refs. If the folder has no repository, initialize it with `git init` only when the user asks.

The user's request defines the operation and scope. Follow the command access captured for this Work response:

- Restricted access keeps commands offline with writes inside the selected project and private command storage. Existing command reviews still apply; approving a command does not add network or outside-folder access.
- Full access runs installed Git with the user's normal filesystem access, configuration, hooks, signing, and existing credential helpers. Complete requested local and remote Git operations within that scope without another confirmation for the same authorization. For a named outside repository, verify its path before using an explicit `git -C` target. Native Mac and plugin reviews remain separate.
- Plan stays read-only and cannot run commands, regardless of the access selection.

Use a single Git command per tool call and pass explicit paths after `--` where supported. Check path lists before opening diffs and exclude credentials and unrelated files from inspection or staging. Preserve unrelated work and existing identity/authentication settings. Never read or print credential values, copy authentication files, or place secrets in arguments, reports, or commits.

## Stage and commit

- For `/vyron-commit feature <name>`, commit the named change and its directly related fixes, tests, and documentation. For `/vyron-commit all`, review eligible staged, unstaged, untracked, and deleted paths in the selected repository and create one commit. For an unqualified commit, infer the requested scope from the task or the coherent staged changes. Clarify when the scope remains ambiguous.
- Check `git diff`, `git diff --cached`, and untracked paths. Inspect relevant untracked files separately. Preserve unrelated staged and unstaged work, including changes to the same file. To stage selected hunks, review a patch and validate it with `git apply --cached --check` before applying it with `git apply --cached`.
- Use `git add -- <paths>` for reviewed whole paths and `git restore --staged -- <paths>` to unstage without changing working files. `git commit --only -m "<message>" -- <paths>` can isolate reviewed full changes to tracked paths when unrelated paths are already staged. If the requested changes cannot be safely isolated, clarify the intended commit scope before touching the index.
- Review the exact content the commit will include. Reuse existing build and test results, check repository instructions for required checks, and report check failures separately from Git command failures. For `/vyron-commit`, use a Conventional Commit subject such as `fix(parser): preserve quoted arguments`. Choose the type from the diff and describe distinct changes in the body when needed. Pass the message with `-m` or a file with `-F`. A request for a commit message calls for a draft.
- Check the effective identity before committing with `git var GIT_AUTHOR_IDENT` and `git var GIT_COMMITTER_IDENT`. Restricted execution uses repository-local configuration; Full access inherits normal Git configuration, signing, hooks, and authentication. Preserve existing settings. Change an identity only when the user requests it and supplies the intended values; use repository-local configuration for a scoped change.
- Verify the resulting commit ID, subject, changed paths, and remaining status. If a command fails or times out, check history and status before retrying so a late success cannot create a duplicate. Report the first Git operation that actually failed and whether changes remain staged.

## Branches, integration, and recovery

- Inspect local branches and commit history before creating or switching branches or adding tags. Use `git switch -c <branch>` when creating and switching to a new branch. Check pending work before switching branches or integrating commits. Use `git worktree list` to locate existing worktrees and confirm the selected folder.
- Use `git stash list` and `git stash show` to confirm the intended entry. Use `git stash apply` when recovering work and confirm the result before dropping the entry. Include untracked files in a stash only when they belong to the requested work.
- Check source and destination refs before a merge, rebase, cherry-pick, or revert. Run noninteractive operations. For a merge commit, use `--no-edit` to accept the default message or `-m` to supply one. Inspect `git status` after each operation. If conflicts interrupt it, resolve only the requested files and use that operation's continue or abort command as appropriate. Verify the resulting history and worktree.
- Use `git log`, `git show`, `git diff`, and `git reflog` to locate a recoverable commit. A branch pointing to the recovered commit preserves it for inspection. Confirm the target and affected paths before any requested restore, reset, or history rewrite. Preserve unrelated work.

## Remote operations

Use a sufficient available connected integration when appropriate. In Full access, `run_command` can also perform requested clone, fetch, pull, or push operations using existing Git/SSH authentication. Verify the repository, remote destination, branch/ref, and intended commit before a remote mutation; keep any credentials embedded in configuration out of context and logs. Do not force-push, rewrite unrelated history, or alter authentication settings without that requested scope.

Restricted commands remain offline. If a requested remote action has no suitable connected integration in that mode, explain that Full access in Work is needed rather than attempting a different launcher. If the actual host lacks access, complete useful local work and identify the missing capability. After a failure, timeout, or uncertain push result, inspect local and remote state before retrying to avoid duplicate or conflicting changes. Verify the observed remote result before reporting success.
