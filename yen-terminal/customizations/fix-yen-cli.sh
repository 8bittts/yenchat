#!/bin/bash
# Fix YEN CLI Issues
# Diagnoses common YEN CLI problems and only applies safe automatic fixes.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_DIR/../scripts/lib/yen-cli-resolve.sh"

has_issue=0
applied_fix=0
needs_reload=0

shell_type="$(detect_shell_type)"
shell_config="$(detect_shell_config)"
in_yen_shell=0
if is_yen_shell; then
    in_yen_shell=1
fi

cli_script="$(resolve_cli_script || true)"
runtime_yen_path="$(detect_runtime_command_path)"
config_file="$HOME/Library/Application Support/com.yenchat.yen/config.yen"
invalid_cli_entries="$(grep -n '^cli:' "$config_file" 2>/dev/null || true)"

echo "=========================================="
echo "YEN CLI Diagnostic and Fix Script"
echo "=========================================="
echo ""

echo "[1/5] Checking PATH and command resolution..."
if command -v yen >/dev/null 2>&1; then
    echo "  ✓ yen is callable in this shell"
    if [[ -n "$runtime_yen_path" ]]; then
        echo "  ✓ Executable path: $runtime_yen_path"
        if [[ "$runtime_yen_path" == *"/Contents/MacOS/yen" ]]; then
            echo "  ✗ ISSUE: yen resolves to the app executable instead of the CLI script"
            has_issue=1
        elif [[ "$runtime_yen_path" == *"/Contents/Resources/bin/yen" || "$runtime_yen_path" == */bin/yen ]]; then
            echo "  ✓ yen resolves to a CLI script"
        fi
    else
        echo "  i yen resolves through shell state only (no direct executable path visible)"
    fi
else
    echo "  ✗ yen is not callable in this shell"
    if [[ "$in_yen_shell" -eq 1 ]]; then
        echo "    ISSUE: bundled shell integration or the app bundle is stale inside a YEN-launched shell"
    else
        echo "    External-shell access is not configured in this shell session"
    fi
    has_issue=1
fi
echo ""

echo "[2/5] Checking shell configuration..."
if [[ -n "$shell_config" ]]; then
    echo "  Shell: $shell_type"
    if [[ -f "$shell_config" ]]; then
        if grep -q '^[[:space:]]*yen()' "$shell_config" 2>/dev/null; then
            echo "  ✓ Found manual yen() wrapper in $shell_config"
            if grep -q "command yen" "$shell_config" 2>/dev/null; then
                echo "  ✓ Wrapper uses 'command yen'"
            else
                echo "  ⚠ Wrapper in $shell_config does not use 'command yen'"
                has_issue=1
            fi
        else
            if [[ "$in_yen_shell" -eq 1 ]]; then
                echo "  i No manual yen() wrapper in $shell_config (expected inside YEN-launched shells)"
            else
                echo "  i No manual yen() wrapper in $shell_config"
            fi
        fi

        if grep -q "YEN.app/Contents/Resources/bin" "$shell_config" 2>/dev/null; then
            echo "  ✓ Shell config adds a YEN app bundle bin directory to PATH"
        else
            echo "  i Shell config does not add a YEN app bundle bin directory to PATH"
        fi
    else
        echo "  i Shell config not found at $shell_config"
    fi
else
    echo "  i Could not determine a zsh/bash shell config for SHELL=${SHELL:-unset}"
fi
echo ""

echo "[3/5] Checking config.yen for invalid entries..."
if [[ -f "$config_file" ]]; then
    if [[ -n "$invalid_cli_entries" ]]; then
        echo "  ✗ Found invalid 'cli:' entries in config.yen:"
        printf '%s\n' "$invalid_cli_entries" | head -5
        echo "    ISSUE: terminal config expects 'key = value' entries, not 'cli:' prefixes"
        has_issue=1
    else
        echo "  ✓ No invalid 'cli:' entries found"
    fi
else
    echo "  i config.yen not found (it is created on first launch)"
fi
echo ""

echo "[4/5] Locating a usable CLI script..."
if [[ -n "$cli_script" && -x "$cli_script" ]]; then
    echo "  ✓ CLI script found: $cli_script"
    if "$cli_script" --version >/dev/null 2>&1 || "$cli_script" version >/dev/null 2>&1; then
        echo "  ✓ CLI script executes correctly"
    else
        echo "  ✗ ISSUE: CLI script exists but failed to execute"
        has_issue=1
    fi
else
    echo "  ✗ ISSUE: Could not locate a working YEN CLI script"
    has_issue=1
fi
echo ""

echo "[5/5] Applying safe fixes..."
if [[ -n "$invalid_cli_entries" ]]; then
    backup_file="${config_file}.backup.$(date +%Y%m%d-%H%M%S)"
    cp "$config_file" "$backup_file"
    sed -i '' '/^cli:/d' "$config_file"
    echo "  ✓ Removed invalid 'cli:' entries from config.yen"
    echo "  ✓ Backup created: $backup_file"
    applied_fix=1
    needs_reload=1
else
    echo "  i No safe automatic file fixes were needed"
    echo "  i Shell wrapper/path changes remain opt-in because they depend on whether you want YEN in external shells"
fi
echo ""

echo "=========================================="
echo "Next Steps"
echo "=========================================="
if [[ "$has_issue" -eq 0 && "$applied_fix" -eq 0 ]]; then
    echo "✓ No issues found. YEN CLI resolution looks healthy."
    echo ""
    echo "1. Test: yen --version"
else
    if [[ "$in_yen_shell" -eq 1 ]]; then
        if [[ -n "$cli_script" ]]; then
            echo "1. Test the bundled CLI directly: \"$cli_script\" --version"
        else
            echo "1. Rebuild or reinstall YEN so the bundled CLI is present again."
        fi
        if [[ "$needs_reload" -eq 1 ]]; then
            echo "2. Restart YEN so the cleaned config.yen is reloaded."
            echo "3. If CLI access is still broken inside YEN, treat it as bundled integration/build drift rather than a missing manual wrapper."
        else
            echo "2. Reopen the YEN shell (or restart YEN.app) so bundled integration is reloaded."
            echo "3. If CLI access is still broken inside YEN, treat it as bundled integration/build drift rather than a missing manual wrapper."
        fi
    else
        if [[ -n "$cli_script" ]]; then
            case "$shell_type" in
                zsh|bash)
                    echo "1. Run: \"$cli_script\" init $shell_type"
                    if [[ -n "$shell_config" ]]; then
                        echo "2. Add the output to $shell_config only if you want CLI access in external shells."
                    else
                        echo "2. Add the output to your shell config only if you want CLI access in external shells."
                    fi
                    ;;
                *)
                    echo "1. Run the CLI directly: \"$cli_script\" --version"
                    echo "2. Add $(dirname "$cli_script") to PATH only if you want CLI access in external shells."
                    ;;
            esac
        else
            echo "1. Install YEN.app in /Applications or ~/Applications, or build a local YEN.app first."
            echo "2. Then rerun this script."
        fi
        if [[ "$needs_reload" -eq 1 ]]; then
            echo "3. Restart YEN so the cleaned config.yen is reloaded."
        else
            echo "3. Restart the external shell and test: yen --version"
        fi
    fi
fi
echo ""
