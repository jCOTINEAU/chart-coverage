# Helm Coverage

A code coverage tool for Helm charts. It instruments template files to track which conditional branches are executed when rendering with different values files.

**Zero changes required to your chart.** The tool works on a temporary copy, instruments it dynamically, runs the analysis, and cleans up. Your original templates are never modified.

## What are "branches"?

In Helm templates, **branches** are conditional code paths created by:

- `{{- if ... }}` / `{{- else }}` / `{{- else if ... }}` — conditional rendering
- `{{- with ... }}` — scoped blocks that only render when the value exists
- `{{- range ... }}` — loops that only execute when the list is non-empty

Each of these creates one or more branches. For example, an `if/else` block has two branches: one for when the condition is true, one for when it's false.

## Why track branch coverage?

Helm templates behave differently depending on the values provided. A template that works with one `values.yaml` may produce invalid YAML or missing resources with different values.

Branch coverage helps chart maintainers:

- **Identify untested code paths** — Find conditional blocks that are never exercised by your test values
- **Validate edge cases** — Ensure `enabled: false`, empty lists, and optional features are properly tested
- **Prevent regressions** — Catch template errors before they reach production environments
- **Improve test completeness** — Know exactly which values files are needed to cover all template logic

## How It Works

1. **Instrumentation** — Injects tracking markers before `{{ end }}` and `{{ else }}` statements
2. **Rendering** — Runs `helm template` with your values files
3. **Analysis** — Counts which markers appear in the output vs. total markers

## Installation

```bash
# Clone or copy the script
chmod +x helm-coverage.sh
```

Requirements: `bash`, `awk`, `helm`

## Usage

```bash
./helm-coverage.sh [options] <chart-path> [values-files-or-dirs...]
```

### Options

| Option | Description |
|--------|-------------|
| `-s, --select <path>` | Only instrument specific template(s). Can be used multiple times |
| `--instrument-only` | Stop after instrumentation (for debugging) |
| `--json` | Output results in JSON format |
| `-h, --help` | Show help |

### Examples

```bash
# Basic usage with default values
./helm-coverage.sh ./my-chart

# With specific values file
./helm-coverage.sh ./my-chart values-prod.yaml

# With multiple values files (cumulative coverage)
./helm-coverage.sh ./my-chart values-dev.yaml values-prod.yaml values-ha.yaml

# With a directory of values files
./helm-coverage.sh ./my-chart ./test-values/

# Filter to specific templates
./helm-coverage.sh -s templates/deployment.yaml ./my-chart values.yaml
./helm-coverage.sh -s workers/ ./my-chart values.yaml

# JSON output for CI/CD
./helm-coverage.sh --json ./my-chart ./test-values/ > coverage.json

# Debug instrumented templates
./helm-coverage.sh --instrument-only ./my-chart
```

## Output

```
[INFO] Helm Coverage Analysis
[INFO] Chart: my-chart
[INFO] Instrumenting templates...
[INFO] Instrumented file: deployment.yaml (5 branches)
[INFO] Instrumented file: service.yaml (2 branches)
[INFO] Instrumented helper: _helpers.tpl (3 branches)
[OK] Found 10 total branches

[INFO] Running with: values-prod.yaml
========================================
Coverage Report
========================================
📄 Covered file branches (4):
  ✓ deployment.yaml:1
  ✓ deployment.yaml:3
  ✓ deployment.yaml:5
  ✓ service.yaml:2

🔧 Covered helper branches (2):
  ✓ _helpers.tpl:myhelper:1
  ✓ _helpers.tpl:myhelper:2

----------------------------------------
📄 Files:   4 branches covered
🔧 Helpers: 2 branches covered
----------------------------------------
~ Total: 6/10 branches (60%)
```

### JSON Output

```json
{
  "version": "1.0",
  "chart": "my-chart",
  "timestamp": "2024-01-15T10:30:00Z",
  "summary": {
    "total_branches": 10,
    "covered_branches": 6,
    "coverage_percent": 60.00,
    "file_branches_covered": 4,
    "helper_branches_covered": 2
  },
  "covered": {
    "files": ["deployment.yaml:1", "deployment.yaml:3", ...],
    "helpers": ["_helpers.tpl:myhelper:1", ...]
  }
}
```

## What's Tracked

| Pattern | Tracked | Notes |
|---------|---------|-------|
| `{{- if ... }}` | ✅ | Tracks when condition is true |
| `{{- else }}` | ✅ | Tracks else branch |
| `{{- else if ... }}` | ✅ | Tracks each branch |
| `{{- with ... }}` | ✅ | Tracks when value exists |
| `{{- range ... }}` | ✅ | Tracks when list is non-empty |
| Inline conditions | ✅ | `{{ if .x }}a{{ else }}b{{ end }}` |
| Helper functions | ✅ | Tracks branches inside `_*.tpl` files |
| `tpl` string args | ⚠️ | Skipped (dynamic evaluation) |

## Limitations

- **Helpers with non-root context**: When a helper is called with a simple value (e.g., `{{ include "helper" 42 }}`), its branches cannot be tracked
- **Dynamic `tpl` calls**: Template code inside strings passed to `tpl` is not instrumented
- **Inline functions**: `{{ default }}`, `{{ coalesce }}`, etc. are not tracked as branches

## Test Strategy

1. Create values files for each configuration variant:
   ```
   test-values/
   ├── minimal.yaml        # Bare minimum
   ├── with-ingress.yaml   # Ingress enabled
   ├── with-resources.yaml # Resource limits set
   ├── ha-mode.yaml        # High availability
   └── full.yaml           # Everything enabled
   ```

2. Run coverage with all values:
   ```bash
   ./helm-coverage.sh ./my-chart ./test-values/
   ```

3. The cumulative report shows which branches are covered across all files

4. Add new values files to cover missing branches until you reach your target coverage

## License

Apache License 2.0 — See [LICENSE](LICENSE) for details.

