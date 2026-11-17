#!/bin/bash
# YEN CLI Diagnostic Script
# Diagnoses why 'yen' may not resolve to the bundled CLI.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_DIR/../scripts/lib/yen-cli-resolve.sh"

has_issue=0

shell_type="$(detect_shell_type)"
shell_config="$(detect_shell_config)"
in_yen_shell=0
if is_yen_shell; then
    in_yen_shell=1
fi

cli_script="$(resolve_cli_script || true)"
runtime_yen_path="$(detect_runtime_command_path)"

echo "YEN CLI Diagnostic"
echo "=================="
echo ""

echo "[1/6] Checking PATH and command resolution..."
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

echo "[2/6] Checking shell configuration..."
if [[ -n "$shell_config" ]]; then
    echo "  Shell: $shell_type"
    if [[ -f "$shell_config" ]]; then
        if grep -q '^[[:space:]]*yen()' "$shell_config" 2>/dev/null; then
            echo "  ✓ Found manual yen() wrapper in $shell_config"
            if grep -q "command yen" "$shell_config" 2>/dev/null; then
                echo "  ✓ Wrapper uses 'command yen'"
            else
                echo "  ⚠ Wrapper in $shell_config does not use 'command yen'"
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

echo "[3/6] Checking LaunchServices entries..."
ls_entries=$(/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -dump 2>/dev/null | grep -i "yen.app" | wc -l | tr -d ' ')
if [[ "$ls_entries" -gt 0 ]]; then
    echo "  ⚠ Found $ls_entries YEN.app entries in LaunchServices"
    echo "  → Run: ./customizations/clear-app-cache.sh if app registration looks stale"
else
    echo "  ✓ No YEN.app entries in LaunchServices (or database not readable)"
fi
echo ""

echo "[4/6] Locating a usable CLI script..."
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

echo "[5/6] Inspecting command metadata..."
echo "  type -a yen:"
type -a yen 2>&1 || echo "  (not found)"
echo ""
echo "  command -v yen:"
command -v yen 2>&1 || echo "  (not found)"
echo ""

echo "[6/6] Context summary..."
if [[ "$in_yen_shell" -eq 1 ]]; then
    echo "  Shell was launched inside YEN: yes"
else
    echo "  Shell was launched inside YEN: no"
fi
if [[ -n "${YEN_BIN_DIR:-}" ]]; then
    echo "  YEN_BIN_DIR=${YEN_BIN_DIR}"
fi
if [[ -n "${YEN_RESOURCES_DIR:-}" ]]; then
    echo "  YEN_RESOURCES_DIR=${YEN_RESOURCES_DIR}"
fi
echo ""

echo "=================="
echo "Recommendations:"
echo ""
if [[ "$has_issue" -eq 0 ]]; then
    echo "1. Current CLI resolution looks healthy."
    echo "2. Test with: yen --version"
else
    if [[ "$in_yen_shell" -eq 1 ]]; then
        if [[ -n "$cli_script" ]]; then
            echo "1. Test the bundled CLI directly: \"$cli_script\" --version"
        else
            echo "1. Rebuild or reinstall YEN so the bundled CLI is present again."
        fi
        echo "2. Reopen the YEN shell (or restart YEN.app) so bundled shell integration is reloaded."
        echo "3. If yen still fails inside YEN, treat it as bundled integration/build drift rather than a dotfile-wrapper issue."
    else
        if [[ -n "$cli_script" ]]; then
            case "$shell_type" in
                zsh|bash)
                    echo "1. Run: \"$cli_script\" init $shell_type"
                    echo "2. Add the output to $shell_config only if you want external-shell access."
                    ;;
                *)
                    echo "1. Run the CLI directly: \"$cli_script\" --version"
                    echo "2. Add $(dirname "$cli_script") to PATH if you want external-shell access."
                    ;;
            esac
        else
            echo "1. Install YEN.app in /Applications or ~/Applications, or build a local YEN.app first."
            echo "2. Then rerun this diagnostic."
        fi
        echo "3. Restart the external shell and test: yen --version"
    fi
fi
echo ""
