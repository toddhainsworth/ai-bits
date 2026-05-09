# Global Claude Context

## About Me
- **Name**: Todd
- **Role**: Senior Software Engineer
- **Location**: Adelaide, Australia
- **Experience Level**: Senior
- **Development Environment**: NeoVim

## Communication Preferences
- **Response Style**: Concise and technical
- **Format Preferences**: Bullet points

## Output Preferences
- **Documentation**: Prefer markdown
- **Code Comments**: Minimal when required, explain the decision, avoid essentially copying the code (the code should be self-documenting)
- **Examples**: Real-world scenarios or abstract examples
- **Follow-ups**: Iterative refinement, avoid creating large tasks, split into smaller deliverables

## Coding Standards

### General

- Run the test suite after all changes
- Run a `yarn lint --fix` before committing in Typescript-based projects
- Keep code simple, avoid flourish.

### Commit Messages

- Commits should always use imperative form.
- When a relevant ticket is provided the commit message should follow the format: <TICKET>: <MESSAGE>
- When no ticket is provided the commit message should follow the format: <TYPE>: <MESSAGE>
    - **Types**: feat, fix, docs, style, refactor, perf, test, chore
    - If it's not obvious, ask the user

### Branching

For consistency we use the ticket number as part of our naming conventions so changes can be tracked in the branches and pull requests.

Branches should follow the following format:
feature/AAA-00_task_description
epic/AAA-00_epic_description
hotfix/AAA-00_hotfix_description

Again, when no ticket is provided the branch should follow the format (or the user should be prompted):
feature/task_description

## Workflow rules

- **Committing** Always ask the user before committing anything.
- **Pull Requests**: Always ask the user before creating a pull request.
- **Uncertainty**: If unsure about a solution, ask for clarification, refine until we agree on an approach.
- **Git Staging**: Ensure you check the git stage before committing, the user may have added something to it
    - Be specific about what you `git add`, never `git add .` or `git add -A`
- **Provide Explanations**: When suggesting code changes, always explain the reasoning behind them.

### Sins

These are things I _really_ dislike, avoid them at all costs.

- Never use `any` in Typescript projects.
- Avoid deeply nested code, prefer early returns.
- Avoid large functions, prefer smaller, single-responsibility, testable functions.
- Avoid unnecessary comments, prefer self-explanatory code.
- Avoid using `console.log` for debugging in projects where a logger is set up.
