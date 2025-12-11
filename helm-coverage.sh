#!/bin/bash
set -euo pipefail

# =============================================================================
# Helm Chart Coverage Tool
# Instruments Helm templates to track conditional branch execution
# =============================================================================

readonly SCRIPT_NAME="$(basename "$0")"
readonly HELPER_FILENAME="_coverage_helper.tpl"

# -----------------------------------------------------------------------------
# Colors
# -----------------------------------------------------------------------------
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# -----------------------------------------------------------------------------
# Usage
# -----------------------------------------------------------------------------
usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} [options] <chart-path> [values-file...]

Options:
    --instrument-only   Stop after instrumentation (no cleanup)
    -h, --help          Show this help message

Arguments:
    chart-path      Path to the Helm chart directory
    values-file     Optional values files for helm template

Examples:
    ${SCRIPT_NAME} ./my-chart
    ${SCRIPT_NAME} ./my-chart values.yaml
    ${SCRIPT_NAME} --instrument-only ./my-chart
EOF
    exit 1
}

# -----------------------------------------------------------------------------
# Logging (all to stderr to keep stdout clean for return values)
# -----------------------------------------------------------------------------
log_info()    { echo -e "${CYAN}[INFO]${NC} $*" >&2; }
log_success() { echo -e "${GREEN}[OK]${NC} $*" >&2; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# -----------------------------------------------------------------------------
# Validation
# -----------------------------------------------------------------------------
validate_chart_path() {
    local chart_path="$1"
    
    if [[ ! -d "$chart_path" ]]; then
        log_error "Chart directory not found: $chart_path"
        exit 1
    fi

    if [[ ! -d "$chart_path/templates" ]]; then
        log_error "No templates/ directory in: $chart_path"
        exit 1
    fi
    
    if [[ ! -f "$chart_path/Chart.yaml" ]]; then
        log_error "No Chart.yaml found in: $chart_path"
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# Create coverage helper template
# -----------------------------------------------------------------------------
create_helper_template() {
    local output_path="$1"
    
    cat > "$output_path" << 'HELPER_EOF'
{{- /*
Coverage Helper - Tracks executed template branches
Uses shared context ._cov to track across files and helpers
All tracking functions expect (list $context "marker")
*/ -}}

{{- define "coverage.init" -}}
{{- $_ := set . "_cov" (dict "files" (list) "helpers" (list)) -}}
{{- end -}}

{{- define "coverage.trackFile" -}}
{{- $ctx := index . 0 -}}
{{- $marker := index . 1 -}}
{{- $_ := set $ctx._cov "files" (append $ctx._cov.files $marker) -}}
{{- end -}}

{{- define "coverage.trackHelper" -}}
{{- $ctx := index . 0 -}}
{{- $marker := index . 1 -}}
{{- $_ := set $ctx._cov "helpers" (append $ctx._cov.helpers $marker) -}}
{{- end -}}

{{- define "coverage.printReport" -}}
{{- $ctx := index . 0 -}}
{{- $total := index . 1 -}}
{{- $fileCount := len $ctx._cov.files -}}
{{- $helperCount := len $ctx._cov.helpers -}}
{{- $totalCovered := add $fileCount $helperCount -}}
# COVERAGE_REPORT: {{ $totalCovered }}/{{ $total }}
# FILES_COVERED: {{ $fileCount }}
{{- range $ctx._cov.files }}
# COVERED_FILE: {{ . }}
{{- end }}
# HELPERS_COVERED: {{ $helperCount }}
{{- range $ctx._cov.helpers }}
# COVERED_HELPER: {{ . }}
{{- end }}
{{- end -}}
HELPER_EOF
}

# -----------------------------------------------------------------------------
# Instrument a single .yaml template file
# Returns the number of injected markers via stdout
# -----------------------------------------------------------------------------
instrument_yaml_template() {
    local template_file="$1"
    local relative_name="$2"
    
    local temp_file count_file
    temp_file=$(mktemp)
    count_file=$(mktemp)
    
    awk -v fname="$relative_name" -v countfile="$count_file" '
    BEGIN {
        marker_count = 0
        # Initialize shared coverage context
        print "{{- include \"coverage.init\" . -}}"
    }
    {
        # Check if standalone end/else (on its own line)
        if ($0 ~ /^[[:space:]]*\{\{-?[[:space:]]*(end|else)[[:space:]]*-?\}\}[[:space:]]*$/ ||
            $0 ~ /^[[:space:]]*\{\{-?[[:space:]]*else[[:space:]]+if[[:space:]]+/) {
            # Standalone - inject before line
            marker_count++
            marker_id = fname ":" marker_count
            print "{{- include \"coverage.trackFile\" (list $ \"" marker_id "\") -}}"
            print $0
        } else if ($0 ~ /\{\{-?[[:space:]]*(end|else)/) {
            # Inline end/else - inject before each occurrence within the line
            line = $0
            result = ""
            while (match(line, /\{\{-?[[:space:]]*(end|else)[[:space:]]*([^}]*-?\}\})?/)) {
                marker_count++
                marker = "{{- include \"coverage.trackFile\" (list $ \"" fname ":" marker_count "\") -}}"
                # Add everything before the match + marker + the matched pattern
                result = result substr(line, 1, RSTART-1) marker substr(line, RSTART, RLENGTH)
                line = substr(line, RSTART + RLENGTH)
            }
            result = result line
            print result
        } else {
            print $0
        }
    }
    END {
        print ""
        print "---"
        print "{{- include \"coverage.printReport\" (list $ " marker_count ") -}}"
        
        # Write marker count to separate file
        print marker_count > countfile
    }
    ' "$template_file" > "$temp_file"
    
    # Read marker count from file
    local marker_count
    marker_count=$(cat "$count_file")
    
    mv "$temp_file" "$template_file"
    rm -f "$count_file"
    
    echo "$marker_count"
}

# -----------------------------------------------------------------------------
# Instrument a single .tpl helper file
# Returns the number of injected markers via stdout
# -----------------------------------------------------------------------------
instrument_tpl_template() {
    local template_file="$1"
    local relative_name="$2"
    
    local temp_file count_file
    temp_file=$(mktemp)
    count_file=$(mktemp)
    
    awk -v fname="$relative_name" -v countfile="$count_file" '
    BEGIN {
        marker_count = 0
        in_define = 0
        current_define = ""
    }
    {
        # Track define blocks to get helper names
        if ($0 ~ /\{\{-?[[:space:]]*define[[:space:]]+"([^"]+)"/) {
            in_define = 1
            # Extract define name
            match($0, /define[[:space:]]+"([^"]+)"/)
            temp = substr($0, RSTART, RLENGTH)
            gsub(/define[[:space:]]+"/, "", temp)
            gsub(/"/, "", temp)
            current_define = temp
        }
        
        # Only instrument inside define blocks
        if (in_define) {
            # Check if standalone end/else (on its own line)
            if ($0 ~ /^[[:space:]]*\{\{-?[[:space:]]*(end|else)[[:space:]]*-?\}\}[[:space:]]*$/) {
                # Check if this is likely the define-closing end (simple heuristic: no else)
                if ($0 ~ /else/) {
                    marker_count++
                    marker_id = fname ":" current_define ":" marker_count
                    print "{{- include \"coverage.trackHelper\" (list $ \"" marker_id "\") -}}"
                    print $0
                } else {
                    # Could be define-closing or block-closing end
                    # We inject anyway, but it wont break if its the define end
                    marker_count++
                    marker_id = fname ":" current_define ":" marker_count
                    print "{{- include \"coverage.trackHelper\" (list $ \"" marker_id "\") -}}"
                    print $0
                    # Check if this closes the define
                    if ($0 ~ /end[[:space:]]*-?\}\}[[:space:]]*$/) {
                        # Might be closing define, reset
                        in_define = 0
                        current_define = ""
                    }
                }
            } else if ($0 ~ /^[[:space:]]*\{\{-?[[:space:]]*else[[:space:]]+if[[:space:]]+/) {
                marker_count++
                marker_id = fname ":" current_define ":" marker_count
                print "{{- include \"coverage.trackHelper\" (list $ \"" marker_id "\") -}}"
                print $0
            } else if ($0 ~ /\{\{-?[[:space:]]*(end|else)/) {
                # Inline end/else
                line = $0
                result = ""
                while (match(line, /\{\{-?[[:space:]]*(end|else)[[:space:]]*([^}]*-?\}\})?/)) {
                    marker_count++
                    marker = "{{- include \"coverage.trackHelper\" (list $ \"" fname ":" current_define ":" marker_count "\") -}}"
                    result = result substr(line, 1, RSTART-1) marker substr(line, RSTART, RLENGTH)
                    line = substr(line, RSTART + RLENGTH)
                }
                result = result line
                print result
            } else {
                print $0
            }
        } else {
            print $0
        }
    }
    END {
        # Write marker count to separate file
        print marker_count > countfile
    }
    ' "$template_file" > "$temp_file"
    
    # Read marker count from file
    local marker_count
    marker_count=$(cat "$count_file")
    
    mv "$temp_file" "$template_file"
    rm -f "$count_file"
    
    echo "$marker_count"
}

# -----------------------------------------------------------------------------
# Instrument all templates in chart
# -----------------------------------------------------------------------------
instrument_chart() {
    local instrumented_dir="$1"
    local total_file_markers=0
    local total_helper_markers=0
    
    # Create coverage helper template
    create_helper_template "${instrumented_dir}/templates/${HELPER_FILENAME}"
    log_info "Created helper: ${HELPER_FILENAME}"
    
    # Find and instrument all .yaml files
    while IFS= read -r -d '' template; do
        local relative_path="${template#${instrumented_dir}/templates/}"
        local filename
        filename=$(basename "$template")
        
        # Skip our coverage helper
        [[ "$filename" == "$HELPER_FILENAME" ]] && continue
        # Skip other helper files (start with _)
        [[ "$filename" == _* ]] && continue
        
        local markers
        markers=$(instrument_yaml_template "$template" "$relative_path")
        total_file_markers=$((total_file_markers + markers))
        
        log_info "Instrumented file: ${relative_path} (${markers} branches)"
    done < <(find "${instrumented_dir}/templates" -type f -name "*.yaml" -print0)
    
    # Find and instrument all .tpl files (except our coverage helper)
    while IFS= read -r -d '' template; do
        local relative_path="${template#${instrumented_dir}/templates/}"
        local filename
        filename=$(basename "$template")
        
        # Skip our coverage helper
        [[ "$filename" == "$HELPER_FILENAME" ]] && continue
        
        local markers
        markers=$(instrument_tpl_template "$template" "$relative_path")
        total_helper_markers=$((total_helper_markers + markers))
        
        if [[ "$markers" -gt 0 ]]; then
            log_info "Instrumented helper: ${relative_path} (${markers} branches)"
        fi
    done < <(find "${instrumented_dir}/templates" -type f -name "*.tpl" -print0)
    
    local total=$((total_file_markers + total_helper_markers))
    echo "$total"
}

# -----------------------------------------------------------------------------
# Run helm template and parse coverage
# -----------------------------------------------------------------------------
run_coverage() {
    local instrumented_dir="$1"
    local total_branches="$2"
    shift 2
    local values_files=("$@")
    
    local helm_args=("template" "coverage-test" "$instrumented_dir")
    
    # Add values files
    for vf in "${values_files[@]}"; do
        [[ -n "$vf" ]] && helm_args+=("-f" "$vf")
    done
    
    local output
    output=$(mktemp)
    
    if ! helm "${helm_args[@]}" > "$output" 2>&1; then
        log_error "Helm template failed:"
        cat "$output" >&2
        rm -f "$output"
        return 1
    fi
    
    # Parse coverage from output
    local covered_files=()
    local covered_helpers=()
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^#[[:space:]]*COVERED_FILE:[[:space:]]*(.+)$ ]]; then
            covered_files+=("${BASH_REMATCH[1]}")
        elif [[ "$line" =~ ^#[[:space:]]*COVERED_HELPER:[[:space:]]*(.+)$ ]]; then
            covered_helpers+=("${BASH_REMATCH[1]}")
        fi
    done < "$output"
    
    rm -f "$output"
    
    local file_count=${#covered_files[@]}
    local helper_count=${#covered_helpers[@]}
    local total_covered=$((file_count + helper_count))
    
    # Display results
    echo ""
    echo "========================================"
    echo "Coverage Report"
    echo "========================================"
    
    if [[ ${#covered_files[@]} -gt 0 ]]; then
        echo ""
        echo "📄 Covered file branches (${file_count}):"
        for line in "${covered_files[@]}"; do
            echo -e "  ${GREEN}✓${NC} $line"
        done
    fi
    
    if [[ ${#covered_helpers[@]} -gt 0 ]]; then
        echo ""
        echo "🔧 Covered helper branches (${helper_count}):"
        for line in "${covered_helpers[@]}"; do
            echo -e "  ${GREEN}✓${NC} $line"
        done
    fi
    
    echo ""
    
    # Calculate percentage
    local percent=0
    if [[ "$total_branches" -gt 0 ]]; then
        percent=$((total_covered * 100 / total_branches))
    fi
    
    # Color based on coverage
    local color icon
    if [[ "$percent" -eq 100 ]]; then
        color=$GREEN
        icon="✓"
    elif [[ "$percent" -ge 50 ]]; then
        color=$YELLOW
        icon="~"
    else
        color=$RED
        icon="✗"
    fi
    
    echo "----------------------------------------"
    printf "📄 Files:   %d branches covered\n" "$file_count"
    printf "🔧 Helpers: %d branches covered\n" "$helper_count"
    echo "----------------------------------------"
    printf "${color}${icon} Total: %d/%d branches (%d%%)${NC}\n" \
        "$total_covered" "$total_branches" "$percent"
    
    return 0
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    local instrument_only=false
    local chart_path=""
    local values_files=()
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --instrument-only)
                instrument_only=true
                shift
                ;;
            -h|--help)
                usage
                ;;
            -*)
                log_error "Unknown option: $1"
                usage
                ;;
            *)
                if [[ -z "$chart_path" ]]; then
                    chart_path="$1"
                else
                    values_files+=("$1")
                fi
                shift
                ;;
        esac
    done
    
    [[ -z "$chart_path" ]] && usage
    
    # Validate
    validate_chart_path "$chart_path"
    
    log_info "Helm Coverage Analysis"
    log_info "Chart: $chart_path"
    
    # Create instrumented copy in a readable location
    local instrumented_dir
    if [[ "$instrument_only" == true ]]; then
        instrumented_dir="${chart_path}-instrumented"
        rm -rf "$instrumented_dir"
        mkdir -p "$instrumented_dir"
    else
        instrumented_dir=$(mktemp -d)
    fi
    cp -r "$chart_path"/* "$instrumented_dir/"
    
    # Instrument
    log_info "Instrumenting templates..."
    local total_branches
    total_branches=$(instrument_chart "$instrumented_dir")
    
    if [[ "$total_branches" -eq 0 ]]; then
        log_warn "No conditional branches found"
        [[ "$instrument_only" == false ]] && rm -rf "$instrumented_dir"
        exit 0
    fi
    
    log_success "Found $total_branches total branches"
    
    # Stop here if instrument-only mode
    if [[ "$instrument_only" == true ]]; then
        echo "" >&2
        log_success "Instrumented chart saved to: $instrumented_dir"
        log_info "You can inspect the files or run manually:"
        log_info "  helm template $instrumented_dir -f <values>"
        exit 0
    fi
    
    # Run coverage for each values file or default
    if [[ ${#values_files[@]} -eq 0 ]]; then
        log_info "Running with default values..."
        run_coverage "$instrumented_dir" "$total_branches" ""
    else
        for vf in "${values_files[@]}"; do
            log_info "Running with: $(basename "$vf")"
            run_coverage "$instrumented_dir" "$total_branches" "$vf"
        done
    fi
    
    # Cleanup
    rm -rf "$instrumented_dir"
    
    echo "" >&2
    log_success "Done"
}

main "$@"
