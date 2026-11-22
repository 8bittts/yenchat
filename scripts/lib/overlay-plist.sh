#!/bin/bash

# Add-or-set helper for Info.plist keys (PlistBuddy exits non-zero when Add key exists).
plist_escape_string() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '%s' "$value"
}

plist_upsert() {
    local plist="$1"
    local key="$2"
    local value_type="$3"
    local value="$4"

    if [ "$value_type" = "string" ]; then
        local escaped_value
        escaped_value="$(plist_escape_string "$value")"
        /usr/libexec/PlistBuddy -c "Add :$key string \"$escaped_value\"" "$plist" 2>/dev/null || \
            /usr/libexec/PlistBuddy -c "Set :$key \"$escaped_value\"" "$plist"
    else
        /usr/libexec/PlistBuddy -c "Add :$key $value_type $value" "$plist" 2>/dev/null || \
            /usr/libexec/PlistBuddy -c "Set :$key $value" "$plist"
    fi
}

plist_delete() {
    local plist="$1"
    local key="$2"
    /usr/libexec/PlistBuddy -c "Delete :$key" "$plist" 2>/dev/null || true
}

# Set a privacy usage string in the Info.plist and delete the project build
# setting for the same key. A build setting overrides the file, so the built
# app would show upstream's generic "A program running within YEN" text.
plist_set_usage_description() {
    local plist="$1"
    local pbxproj="$2"
    local key="$3"
    local value="$4"
    plist_upsert "$plist" "$key" "string" "$value"
    sed -i '' -e "/INFOPLIST_KEY_${key} = /d" "$pbxproj"
}
