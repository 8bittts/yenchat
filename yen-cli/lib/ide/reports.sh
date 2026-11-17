# shellcheck shell=bash
# Source-time pure shared helpers for yen ide report and snapshot parsing.

timeline_lookup_key_for_root() {
    local root="$1"
    if declare -F project_timeline_key_for_root >/dev/null 2>&1; then
        project_timeline_key_for_root "${root}"
        return 0
    fi
    printf "%s\n" "${root}"
}

reports_project_hash() {
    local root="$1"
    if command -v shasum >/dev/null 2>&1; then
        printf "%s" "${root}" | shasum -a 256 | awk '{print $1}'
        return 0
    fi
    if command -v openssl >/dev/null 2>&1; then
        printf "%s" "${root}" | openssl dgst -sha256 | awk '{print $2}'
        return 0
    fi
    if command -v md5 >/dev/null 2>&1; then
        md5 -q -s "${root}"
        return 0
    fi
    printf "%s\n" "${root}" | tr -cd '[:alnum:]' | cut -c1-32
}

reports_project_hash_seed_for_root() {
    local root="$1"
    if declare -F workspace_hash_seed_for_root >/dev/null 2>&1; then
        workspace_hash_seed_for_root "${root}"
        return 0
    fi
    printf "%s\n" "${root}"
}

reports_project_hash_for_root() {
    local root="$1"
    reports_project_hash "$(reports_project_hash_seed_for_root "${root}")"
}

reports_watch_state_file_for_root_kind() {
    local root="$1"
    local kind="$2"
    local hash=""
    local kind_slug=""

    hash=$(reports_project_hash_for_root "${root}")
    kind_slug=$(printf "%s" "${kind}" | tr -cs 'A-Za-z0-9._-' '-')
    printf "%s/watch/%s-%s.env\n" "${IDE_STATE_DIR}" "${hash}" "${kind_slug}"
}

reports_pr_ci_state_file_for_root() {
    local root="$1"
    local hash=""

    hash=$(reports_project_hash_for_root "${root}")
    printf "%s/pr-ci-%s.env\n" "${IDE_STATE_DIR}" "${hash}"
}

reports_watch_state_latest_snapshot_for_root() {
    local root="$1"
    local latest=""
    local candidate=""
    local kind=""

    for kind in verify workflow-native-build; do
        candidate=$(reports_watch_state_file_for_root_kind "${root}" "${kind}")
        if [[ ! -f "${candidate}" ]]; then
            continue
        fi
        if [[ -z "${latest}" || "${candidate}" -nt "${latest}" ]]; then
            latest="${candidate}"
        fi
    done

    if [[ -n "${latest}" ]]; then
        cat "${latest}"
    fi
}

latest_verify_summary_for_root() {
    local root="$1"
    local line=""
    root=$(timeline_lookup_key_for_root "${root}")
    line=$(tail -n 400 "${IDE_TIMELINE_FILE}" 2>/dev/null | awk -F'\t' -v root="${root}" '$2 == "verify" && $3 == root {print $5}' | tail -n 1)
    if [[ -z "${line}" ]]; then
        return 1
    fi
    printf "%s\n" "${line}" | sed -nE 's/.*summary=([^;[:space:]]+).*/\1/p'
}

latest_timeline_line_for_event_root() {
    local event="$1"
    local root="$2"
    root=$(timeline_lookup_key_for_root "${root}")
    tail -n 400 "${IDE_TIMELINE_FILE}" 2>/dev/null | awk -F'\t' -v event="${event}" -v root="${root}" '$2 == event && $3 == root { line = $0 } END { print line }'
}

recent_timeline_lines_for_root_events() {
    local root="$1"
    local event_regex="$2"
    root=$(timeline_lookup_key_for_root "${root}")
    tail -n 400 "${IDE_TIMELINE_FILE}" 2>/dev/null | awk -F'\t' -v root="${root}" -v event_regex="${event_regex}" '$3 == root && $2 ~ event_regex { print $0 }'
}

latest_verify_timeline_line_for_root() {
    local root="$1"
    latest_timeline_line_for_event_root "verify" "${root}"
}

latest_test_timeline_line_for_root() {
    local root="$1"
    latest_timeline_line_for_event_root "test" "${root}"
}

report_snapshot_from_timeline_line() {
    local prefix="$1"
    local line="$2"
    local status_key="${prefix}_status"
    local last_run_key="${prefix}_last_run_at"
    local summary_key="${prefix}_summary"
    local details_key="${prefix}_details"
    local semantic_key="${prefix}_semantic"
    local failures_key="${prefix}_failures"
    local warns_key="${prefix}_warns"
    local executed_key="${prefix}_executed"

    local report_status="never-run"
    local report_last_run_at=""
    local report_summary=""
    local report_details=""
    local report_semantic=""
    local report_failures="0"
    local report_warns="0"
    local report_executed="0"

    if [[ -n "${line}" ]]; then
        local report_status_field=""
        local report_detail_field=""
        IFS=$'\t' read -r report_last_run_at _ _ report_status_field report_detail_field << EOF
${line}
EOF
        report_summary=$(printf "%s\n" "${report_detail_field}" | sed -nE 's/.*summary=([^;[:space:]]+).*/\1/p')
        report_semantic=$(printf "%s\n" "${report_detail_field}" | sed -nE 's/.*semantic=([^;[:space:]]+).*/\1/p')
        report_failures=$(printf "%s\n" "${report_status_field}" | sed -nE 's/.*failures=([0-9]+).*/\1/p')
        report_warns=$(printf "%s\n" "${report_status_field}" | sed -nE 's/.*warns=([0-9]+).*/\1/p')
        [[ -z "${report_failures}" ]] && report_failures="0"
        [[ -z "${report_warns}" ]] && report_warns="0"
        if [[ -n "${report_summary}" && "${report_summary}" == *.tsv ]]; then
            local derived_details="${report_summary%.tsv}.log"
            if [[ -f "${derived_details}" ]]; then
                report_details="${derived_details}"
            fi
        fi
        if [[ -f "${report_summary}" ]]; then
            report_executed=$(awk 'END { print NR + 0 }' "${report_summary}" 2>/dev/null)
        fi
        if [[ ! -f "${report_summary}" ]]; then
            report_status="report-missing"
        elif [[ "${report_failures}" -gt 0 ]]; then
            report_status="failing"
        elif [[ "${report_warns}" -gt 0 ]]; then
            report_status="warnings"
        else
            report_status="passing"
        fi
    fi

    cat << EOF
${status_key}=${report_status}
${last_run_key}=${report_last_run_at}
${summary_key}=${report_summary}
${details_key}=${report_details}
${semantic_key}=${report_semantic}
${failures_key}=${report_failures}
${warns_key}=${report_warns}
${executed_key}=${report_executed}
EOF
}

verify_snapshot_for_root() {
    local root="$1"
    report_snapshot_from_timeline_line "verify" "$(latest_verify_timeline_line_for_root "${root}" || true)"
}

test_snapshot_for_root() {
    local root="$1"
    report_snapshot_from_timeline_line "test" "$(latest_test_timeline_line_for_root "${root}" || true)"
}

evidence_status_json_for_root() {
    local root="$1"
    local verify_snapshot=""
    local test_snapshot=""
    local quality_lines=""
    local workflow_lines=""
    local merge_readiness_line=""
    local pr_review_line=""
    local stale_hours="${YEN_IDE_EVIDENCE_STALE_HOURS:-72}"

    verify_snapshot=$(verify_snapshot_for_root "${root}" 2>/dev/null || report_snapshot_from_timeline_line "verify" "")
    test_snapshot=$(test_snapshot_for_root "${root}" 2>/dev/null || report_snapshot_from_timeline_line "test" "")
    quality_lines=$(recent_timeline_lines_for_root_events "${root}" '^(quality)$' || true)
    workflow_lines=$(recent_timeline_lines_for_root_events "${root}" '^(workflow)$' || true)
    merge_readiness_line=$(latest_timeline_line_for_event_root "merge-readiness" "${root}" || true)
    pr_review_line=$(latest_timeline_line_for_event_root "pr-review" "${root}" || true)

    EVIDENCE_STATUS_ROOT="${root}" \
    EVIDENCE_STATUS_VERIFY_SNAPSHOT="${verify_snapshot}" \
    EVIDENCE_STATUS_TEST_SNAPSHOT="${test_snapshot}" \
    EVIDENCE_STATUS_QUALITY_LINES="${quality_lines}" \
    EVIDENCE_STATUS_WORKFLOW_LINES="${workflow_lines}" \
    EVIDENCE_STATUS_MERGE_READINESS_LINE="${merge_readiness_line}" \
    EVIDENCE_STATUS_PR_REVIEW_LINE="${pr_review_line}" \
    EVIDENCE_STATUS_STALE_HOURS="${stale_hours}" \
    python3 - <<'PY'
import json
import os
import sys
from datetime import datetime, timedelta, timezone


def parse_env_lines(text):
    payload = {}
    for raw in (text or "").splitlines():
        if "=" not in raw:
            continue
        key, value = raw.split("=", 1)
        payload[key] = value
    return payload


def parse_snapshot(text, prefix):
    payload = parse_env_lines(text)
    return {
        "status": payload.get(f"{prefix}_status", "never-run"),
        "lastRunAt": payload.get(f"{prefix}_last_run_at", ""),
        "summary": payload.get(f"{prefix}_summary", ""),
        "details": payload.get(f"{prefix}_details", ""),
        "semantic": payload.get(f"{prefix}_semantic", ""),
        "failures": int(payload.get(f"{prefix}_failures", "0") or "0"),
        "warns": int(payload.get(f"{prefix}_warns", "0") or "0"),
        "executed": int(payload.get(f"{prefix}_executed", "0") or "0"),
    }


def parse_detail(detail_text):
    payload = {}
    for item in (detail_text or "").split(";"):
        item = item.strip()
        if not item or "=" not in item:
            continue
        key, value = item.split("=", 1)
        payload[key] = value
    return payload


def parse_timeline_line(line):
    raw = (line or "").strip()
    if not raw:
        return None
    parts = raw.split("\t", 4)
    if len(parts) < 5:
        return None
    timestamp, event, root, status_field, detail_text = parts
    return {
        "timestamp": timestamp,
        "event": event,
        "root": root,
        "statusField": status_field,
        "detailText": detail_text,
        "detail": parse_detail(detail_text),
    }


def parse_timeline_lines(text):
    return [entry for entry in (parse_timeline_line(line) for line in (text or "").splitlines()) if entry is not None]


def display_name(artifact):
    return {
        "verify": "Verify",
        "test": "Test",
        "quality": "Quality",
        "workflow": "Workflow",
        "merge-readiness": "Merge readiness",
        "pr-review": "PR review",
    }.get(artifact, artifact)


def parse_iso(value):
    text = str(value or "").strip()
    if not text:
        return None
    try:
        if text.endswith("Z"):
            return datetime.strptime(text, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
        return datetime.fromisoformat(text)
    except Exception:
        return None


try:
    stale_after_hours = max(1, int(os.environ.get("EVIDENCE_STATUS_STALE_HOURS", "72") or "72"))
except Exception:
    stale_after_hours = 72
now = datetime.now(timezone.utc)
stale_delta = timedelta(hours=stale_after_hours)


def is_stale(timestamp):
    parsed = parse_iso(timestamp)
    if parsed is None:
        return False
    return now - parsed > stale_delta


def report_artifact_state(artifact, snapshot):
    raw_status = str(snapshot.get("status") or "never-run")
    last_seen = str(snapshot.get("lastRunAt") or "")
    summary = str(snapshot.get("summary") or "")
    details = str(snapshot.get("details") or "")
    semantic = str(snapshot.get("semantic") or "")
    stale = is_stale(last_seen)
    label = "available"
    reason = f"Latest local {artifact} report is available."

    if raw_status == "never-run":
        label = "unverified"
        reason = f"No local {artifact} report has been recorded for this workspace."
    elif raw_status == "report-missing" or (summary and not os.path.exists(summary)):
        label = "missing-report"
        reason = f"Latest local {artifact} report is missing on disk."
    elif stale:
        label = "stale-report"
        reason = (
            f"Latest local {artifact} report is older than {stale_after_hours}h and may not match the current workspace."
        )

    return {
        "artifact": artifact,
        "displayName": display_name(artifact),
        "label": label,
        "rawStatus": raw_status,
        "reason": reason,
        "lastSeenAt": last_seen,
        "summary": summary,
        "details": details,
        "semantic": semantic,
        "statusField": raw_status,
        "linkTarget": summary,
        "linkType": "summary-report" if summary else "",
        "stale": stale,
        "failures": int(snapshot.get("failures") or 0),
        "warns": int(snapshot.get("warns") or 0),
        "executed": int(snapshot.get("executed") or 0),
        "detail": {},
    }


def event_artifact_state(artifact, line, summary_required):
    entry = parse_timeline_line(line)
    label = "available"
    reason = f"Latest local {artifact} artifact is available."
    last_seen = ""
    summary = ""
    semantic = ""
    status_field = ""
    detail = {}
    stale = False
    link_type = "timeline-event"
    link_target = ""

    if entry is None:
        label = "missing-report"
        reason = f"No local {artifact} artifact has been recorded for this workspace."
    else:
        last_seen = str(entry.get("timestamp") or "")
        status_field = str(entry.get("statusField") or "")
        detail = entry.get("detail") or {}
        summary = str(detail.get("summary") or "")
        semantic = str(detail.get("semantic") or "")
        stale = is_stale(last_seen)
        if summary_required:
            if not summary:
                label = "missing-report"
                reason = f"Latest local {artifact} run does not include a reusable report path."
            elif not os.path.exists(summary):
                label = "missing-report"
                reason = f"Latest local {artifact} report is missing on disk."
            elif stale:
                label = "stale-report"
                reason = (
                    f"Latest local {artifact} report is older than {stale_after_hours}h and may not match the current workspace."
                )
            link_type = "summary-report" if summary else "timeline-event"
            link_target = summary or last_seen
        else:
            if stale:
                label = "stale-report"
                reason = (
                    f"Latest local {artifact} artifact is older than {stale_after_hours}h and may not match the current workspace."
                )
            else:
                reason = f"Latest local {artifact} artifact is recorded in the workspace timeline."
            link_target = last_seen

    return {
        "artifact": artifact,
        "displayName": display_name(artifact),
        "label": label,
        "rawStatus": status_field,
        "reason": reason,
        "lastSeenAt": last_seen,
        "summary": summary,
        "details": "",
        "semantic": semantic,
        "statusField": status_field,
        "linkTarget": link_target,
        "linkType": link_type,
        "stale": stale,
        "detail": detail,
    }


def latest_report_preferred_entry(entries, event_name):
    rows = [entry for entry in entries if entry.get("event") == event_name]
    if not rows:
        return None
    report_rows = [entry for entry in rows if str((entry.get("detail") or {}).get("summary") or "").strip()]
    if report_rows:
        rows = report_rows
    rows.sort(key=lambda item: (item.get("timestamp") or "", item.get("event") or ""))
    return rows[-1]


quality_entry = latest_report_preferred_entry(
    parse_timeline_lines(os.environ.get("EVIDENCE_STATUS_QUALITY_LINES", "")),
    "quality",
)
workflow_entry = latest_report_preferred_entry(
    parse_timeline_lines(os.environ.get("EVIDENCE_STATUS_WORKFLOW_LINES", "")),
    "workflow",
)


artifacts = {
    "verify": report_artifact_state("verify", parse_snapshot(os.environ.get("EVIDENCE_STATUS_VERIFY_SNAPSHOT", ""), "verify")),
    "test": report_artifact_state("test", parse_snapshot(os.environ.get("EVIDENCE_STATUS_TEST_SNAPSHOT", ""), "test")),
    "quality": event_artifact_state("quality", "\t".join([
        str(quality_entry.get("timestamp", "")),
        str(quality_entry.get("event", "")),
        str(quality_entry.get("root", "")),
        str(quality_entry.get("statusField", "")),
        str(quality_entry.get("detailText", "")),
    ]) if quality_entry is not None else "", True),
    "workflow": event_artifact_state("workflow", "\t".join([
        str(workflow_entry.get("timestamp", "")),
        str(workflow_entry.get("event", "")),
        str(workflow_entry.get("root", "")),
        str(workflow_entry.get("statusField", "")),
        str(workflow_entry.get("detailText", "")),
    ]) if workflow_entry is not None else "", True),
    "merge-readiness": event_artifact_state(
        "merge-readiness",
        os.environ.get("EVIDENCE_STATUS_MERGE_READINESS_LINE", ""),
        False,
    ),
    "pr-review": event_artifact_state("pr-review", os.environ.get("EVIDENCE_STATUS_PR_REVIEW_LINE", ""), False),
}

gap_artifacts = [name for name, item in artifacts.items() if item.get("label") != "available"]
overall = {
    "label": "exported-with-gaps" if gap_artifacts else "available",
    "reason": (
        "Evidence output still has missing or stale local artifacts."
        if gap_artifacts
        else "All tracked local evidence artifacts are present."
    ),
    "gapArtifacts": gap_artifacts,
}

json.dump(
    {
        "schemaVersion": 1,
        "workspaceRoot": os.environ.get("EVIDENCE_STATUS_ROOT", ""),
        "staleAfterHours": stale_after_hours,
        "overall": overall,
        "artifacts": artifacts,
    },
    sys.stdout,
    indent=2,
)
sys.stdout.write("\n")
PY
}

linked_evidence_json_for_root() {
    local root="$1"
    local quality_lines=""
    local workflow_lines=""
    local merge_readiness_line=""
    local pr_review_lines=""
    local pr_ci_line=""
    local pr_ci_snapshot=""
    local watch_snapshot=""
    local pr_ci_state_file=""

    quality_lines=$(recent_timeline_lines_for_root_events "${root}" '^(quality)$' || true)
    workflow_lines=$(recent_timeline_lines_for_root_events "${root}" '^(workflow)$' || true)
    merge_readiness_line=$(latest_timeline_line_for_event_root "merge-readiness" "${root}" || true)
    pr_review_lines=$(recent_timeline_lines_for_root_events "${root}" '^(pr-review|pr-evidence|pr-decision|pr-inline-comment)$' || true)
    pr_ci_line=$(latest_timeline_line_for_event_root "pr-ci" "${root}" || true)

    pr_ci_state_file=$(reports_pr_ci_state_file_for_root "${root}")
    if [[ -f "${pr_ci_state_file}" ]]; then
        pr_ci_snapshot=$(cat "${pr_ci_state_file}" 2>/dev/null || true)
    fi
    watch_snapshot=$(reports_watch_state_latest_snapshot_for_root "${root}" || true)

    LINKED_EVIDENCE_QUALITY_LINES="${quality_lines}" \
    LINKED_EVIDENCE_WORKFLOW_LINES="${workflow_lines}" \
    LINKED_EVIDENCE_MERGE_READINESS_LINE="${merge_readiness_line}" \
    LINKED_EVIDENCE_PR_REVIEW_LINES="${pr_review_lines}" \
    LINKED_EVIDENCE_PR_CI_LINE="${pr_ci_line}" \
    LINKED_EVIDENCE_PR_CI_SNAPSHOT="${pr_ci_snapshot}" \
    LINKED_EVIDENCE_WATCH_SNAPSHOT="${watch_snapshot}" \
    python3 - <<'PY'
import json
import os
import sys


def parse_env_lines(text):
    payload = {}
    for raw in (text or "").splitlines():
        if "=" not in raw:
            continue
        key, value = raw.split("=", 1)
        payload[key] = value
    return payload


def parse_detail(text):
    payload = {}
    for item in (text or "").split(";"):
        item = item.strip()
        if not item or "=" not in item:
            continue
        key, value = item.split("=", 1)
        payload[key] = value
    return payload


def parse_timeline_line(text):
    raw = str(text or "").strip()
    if not raw:
        return None
    parts = raw.split("\t", 4)
    if len(parts) != 5:
        return None
    timestamp, event, root, status_field, detail_text = parts
    return {
        "timestamp": timestamp,
        "event": event,
        "root": root,
        "statusField": status_field,
        "detailText": detail_text,
        "status": parse_detail(status_field),
        "detail": parse_detail(detail_text),
    }


def parse_int(value):
    try:
        return int(str(value or "").strip() or "0")
    except Exception:
        return 0


def parse_bool(value):
    return str(value or "").strip().lower() in {"1", "true", "yes", "on"}


def semantic_location(file_path="", target="", line=0, column=0):
    raw_target = str(target or "").strip()
    path = str(file_path or "").strip()
    parsed_line = parse_int(line)
    parsed_column = parse_int(column)

    if raw_target:
        parts = raw_target.rsplit(":", 2)
        if len(parts) >= 2 and parts[-1].isdigit() and parts[-2].isdigit():
            path = parts[0]
            parsed_line = parse_int(parts[-2])
            parsed_column = parse_int(parts[-1])
        elif len(parts) >= 2 and parts[-1].isdigit():
            path = parts[0]
            parsed_line = parse_int(parts[-1])

    normalized = ""
    if path:
        normalized = path
        if parsed_line > 0:
            normalized = f"{normalized}:{parsed_line}"
            if parsed_column > 0:
                normalized = f"{normalized}:{parsed_column}"
    elif raw_target:
        normalized = raw_target

    return {
        "target": normalized,
        "path": path,
        "line": parsed_line,
        "column": parsed_column,
    }


def latest_entry(entries):
    rows = [entry for entry in entries if entry]
    if not rows:
        return None
    rows.sort(key=lambda item: (item.get("timestamp") or "", item.get("event") or ""))
    return rows[-1]


def detail_value(entry, key):
    return ((entry or {}).get("detail") or {}).get(key, "")


def detail_value_first(entry, *keys):
    detail = ((entry or {}).get("detail") or {})
    for key in keys:
        value = detail.get(key, "")
        if value:
            return value
    return ""


def status_value(entry, key):
    return ((entry or {}).get("status") or {}).get(key, "")


def derive_details_path(summary_path):
    summary = str(summary_path or "").strip()
    if not summary:
        return ""
    if summary.endswith(".tsv"):
        return summary[:-4] + ".log"
    return ""


quality_entries = [
    entry
    for entry in (
        parse_timeline_line(line)
        for line in (os.environ.get("LINKED_EVIDENCE_QUALITY_LINES", "") or "").splitlines()
    )
    if entry is not None
]
workflow_entries = [
    entry
    for entry in (
        parse_timeline_line(line)
        for line in (os.environ.get("LINKED_EVIDENCE_WORKFLOW_LINES", "") or "").splitlines()
    )
    if entry is not None
]
merge_entry = parse_timeline_line(os.environ.get("LINKED_EVIDENCE_MERGE_READINESS_LINE", ""))
review_entries = [
    entry
    for entry in (
        parse_timeline_line(line)
        for line in (os.environ.get("LINKED_EVIDENCE_PR_REVIEW_LINES", "") or "").splitlines()
    )
    if entry is not None
]
pr_ci_entry = parse_timeline_line(os.environ.get("LINKED_EVIDENCE_PR_CI_LINE", ""))
pr_ci_snapshot = parse_env_lines(os.environ.get("LINKED_EVIDENCE_PR_CI_SNAPSHOT", ""))
watch_snapshot = parse_env_lines(os.environ.get("LINKED_EVIDENCE_WATCH_SNAPSHOT", ""))


def latest_report_entry(entries, event_name):
    rows = [
        entry
        for entry in entries
        if entry.get("event") == event_name and detail_value(entry, "summary")
    ]
    return latest_entry(rows)


quality_entry = latest_report_entry(quality_entries, "quality")
workflow_entry = latest_report_entry(workflow_entries, "workflow")
review_latest = latest_entry(review_entries)
review_pr = parse_int(
    status_value(review_latest, "pr")
    if review_latest is not None
    else "0"
)


def latest_event_for_pr(event_name):
    rows = [entry for entry in review_entries if entry.get("event") == event_name]
    if review_pr:
        rows = [entry for entry in rows if parse_int(status_value(entry, "pr")) == review_pr]
    return latest_entry(rows)


review_entry = latest_event_for_pr("pr-review")
evidence_entry = latest_event_for_pr("pr-evidence")
decision_entry = latest_event_for_pr("pr-decision")
inline_entry = latest_event_for_pr("pr-inline-comment")


def report_artifact_payload(entry, label):
    if entry is None:
        return {
            "available": False,
            "lastSeenAt": "",
            "status": "",
            "summaryPath": "",
            "summaryPathExists": False,
            "detailsPath": "",
            "detailsPathExists": False,
            "semanticPath": "",
            "semanticPathExists": False,
            "reason": f"No reusable local {label} report artifacts have been recorded for this workspace.",
        }

    summary_path = detail_value(entry, "summary")
    details_path = derive_details_path(summary_path)
    semantic_path = detail_value(entry, "semantic")
    summary_exists = bool(summary_path) and os.path.exists(summary_path)
    details_exists = bool(details_path) and os.path.exists(details_path)
    semantic_exists = bool(semantic_path) and os.path.exists(semantic_path)
    available = summary_exists
    if not summary_path:
        reason = f"Latest reusable local {label} report is missing a summary path."
    elif not summary_exists:
        reason = f"Latest reusable local {label} summary report is missing on disk."
    else:
        reason = f"Latest reusable local {label} report artifacts are linked from IDE timeline state."

    return {
        "available": available,
        "lastSeenAt": entry.get("timestamp", ""),
        "status": entry.get("statusField", ""),
        "summaryPath": summary_path,
        "summaryPathExists": summary_exists,
        "detailsPath": details_path,
        "detailsPathExists": details_exists,
        "semanticPath": semantic_path,
        "semanticPathExists": semantic_exists,
        "reason": reason,
    }

payload = {
    "schemaVersion": 1,
    "quality": {
        **report_artifact_payload(quality_entry, "quality"),
        "action": detail_value(quality_entry, "action"),
        "candidate": detail_value(quality_entry, "candidate"),
        "scope": detail_value(quality_entry, "scope"),
    },
    "workflow": {
        **report_artifact_payload(workflow_entry, "workflow"),
        "name": detail_value(workflow_entry, "name"),
        "kind": detail_value(workflow_entry, "kind"),
        "source": detail_value(workflow_entry, "source"),
        "location": detail_value(workflow_entry, "location"),
    },
    "mergeReadiness": {
        "available": merge_entry is not None,
        "lastSeenAt": (merge_entry or {}).get("timestamp", ""),
        "status": (merge_entry or {}).get("statusField", ""),
        "prNumber": parse_int(detail_value(merge_entry, "pr")),
        "verifyStatus": detail_value(merge_entry, "verify"),
        "format": detail_value(merge_entry, "format"),
        "detail": (merge_entry or {}).get("detail") or {},
        "reason": (
            "Latest local merge-readiness snapshot is linked from the IDE timeline."
            if merge_entry is not None
            else "No local merge-readiness snapshot has been recorded for this workspace."
        ),
    },
    "prReview": {
        "available": review_latest is not None,
        "lastSeenAt": (review_latest or {}).get("timestamp", ""),
        "prNumber": parse_int(
            status_value(review_entry, "pr")
            or status_value(evidence_entry, "pr")
            or status_value(decision_entry, "pr")
            or status_value(inline_entry, "pr")
        ),
        "reason": (
            "Latest local PR review artifacts are linked from IDE evidence/timeline state."
            if review_latest is not None
            else "No local PR review artifacts have been recorded for this workspace."
        ),
        "lastReview": {
            "available": review_entry is not None,
            "lastSeenAt": (review_entry or {}).get("timestamp", ""),
            "prNumber": parse_int(status_value(review_entry, "pr")),
            "file": detail_value(review_entry, "file"),
            "target": detail_value(review_entry, "target"),
            "semanticLocation": semantic_location(
                detail_value(review_entry, "file"),
                detail_value(review_entry, "target"),
            ),
            "evidenceRequested": parse_bool(detail_value(review_entry, "evidence")),
            "posted": parse_bool(detail_value(review_entry, "post")),
        },
        "evidenceBundle": {
            "available": evidence_entry is not None,
            "lastSeenAt": (evidence_entry or {}).get("timestamp", ""),
            "prNumber": parse_int(status_value(evidence_entry, "pr")),
            "file": detail_value(evidence_entry, "file"),
            "target": detail_value(evidence_entry, "target"),
            "semanticLocation": semantic_location(
                detail_value(evidence_entry, "file"),
                detail_value(evidence_entry, "target"),
            ),
            "path": detail_value(evidence_entry, "path"),
            "pathExists": os.path.exists(detail_value(evidence_entry, "path")),
        },
        "decision": {
            "available": decision_entry is not None,
            "lastSeenAt": (decision_entry or {}).get("timestamp", ""),
            "prNumber": parse_int(status_value(decision_entry, "pr")),
            "mode": status_value(decision_entry, "mode"),
            "file": detail_value(decision_entry, "file"),
            "target": detail_value(decision_entry, "target"),
            "semanticLocation": semantic_location(
                detail_value(decision_entry, "file"),
                detail_value(decision_entry, "target"),
            ),
            "posted": parse_bool(detail_value(decision_entry, "post")),
            "artifactPath": detail_value_first(decision_entry, "artifact", "path"),
            "artifactPathExists": os.path.exists(detail_value_first(decision_entry, "artifact", "path")),
        },
        "inlineComment": {
            "available": inline_entry is not None,
            "lastSeenAt": (inline_entry or {}).get("timestamp", ""),
            "prNumber": parse_int(status_value(inline_entry, "pr")),
            "posted": parse_bool(status_value(inline_entry, "posted")),
            "path": detail_value(inline_entry, "path"),
            "line": parse_int(detail_value(inline_entry, "line")),
            "side": detail_value(inline_entry, "side"),
            "semanticLocation": semantic_location(
                detail_value(inline_entry, "path"),
                "",
                parse_int(detail_value(inline_entry, "line")),
            ),
            "artifactPath": detail_value_first(inline_entry, "artifact", "template"),
            "artifactPathExists": os.path.exists(detail_value_first(inline_entry, "artifact", "template")),
        },
    },
    "currentBranchCi": {
        "available": (pr_ci_snapshot.get("available") == "yes") or (pr_ci_entry is not None),
        "lastSeenAt": (pr_ci_entry or {}).get("timestamp", ""),
        "repo": pr_ci_snapshot.get("repo", detail_value(pr_ci_entry, "repo")),
        "reason": pr_ci_snapshot.get("reason", detail_value(pr_ci_entry, "reason")),
        "prNumber": parse_int(pr_ci_snapshot.get("pr_number") or detail_value(pr_ci_entry, "pr")),
        "title": pr_ci_snapshot.get("title", ""),
        "url": pr_ci_snapshot.get("url", detail_value(pr_ci_entry, "url")),
        "branch": pr_ci_snapshot.get("branch", ""),
        "isDraft": pr_ci_snapshot.get("is_draft") == "yes",
        "checksState": pr_ci_snapshot.get("checks_state", (pr_ci_entry or {}).get("statusField", "")),
        "checksTotal": parse_int(pr_ci_snapshot.get("checks_total")),
        "checksPassing": parse_int(pr_ci_snapshot.get("checks_passing") or detail_value(pr_ci_entry, "pass")),
        "checksPending": parse_int(pr_ci_snapshot.get("checks_pending") or detail_value(pr_ci_entry, "pending")),
        "checksFailing": parse_int(pr_ci_snapshot.get("checks_failing") or detail_value(pr_ci_entry, "fail")),
        "completed": pr_ci_snapshot.get("completed") == "yes",
    },
    "localBuildWatch": {
        "available": bool(watch_snapshot),
        "kind": watch_snapshot.get("kind", ""),
        "label": watch_snapshot.get("label", ""),
        "branch": watch_snapshot.get("branch", ""),
        "active": watch_snapshot.get("active", "").lower() == "yes",
        "state": watch_snapshot.get("state", ""),
        "iteration": parse_int(watch_snapshot.get("iteration")),
        "intervalSeconds": watch_snapshot.get("interval_seconds", ""),
        "maxRuns": watch_snapshot.get("max_runs", ""),
        "scope": watch_snapshot.get("scope", ""),
        "startedAt": watch_snapshot.get("started_at", ""),
        "updatedAt": watch_snapshot.get("updated_at", ""),
        "stopReason": watch_snapshot.get("stop_reason", ""),
        "lastOutcome": watch_snapshot.get("last_outcome", ""),
        "lastExitCode": parse_int(watch_snapshot.get("last_exit_code")),
        "lastFailures": parse_int(watch_snapshot.get("last_failures")),
        "lastWarnings": parse_int(watch_snapshot.get("last_warns")),
        "lastExecuted": parse_int(watch_snapshot.get("last_executed")),
        "summary": watch_snapshot.get("summary", ""),
        "details": watch_snapshot.get("details", ""),
        "semantic": watch_snapshot.get("semantic", ""),
        "reason": (
            "Latest local build-watch snapshot is linked from IDE watch state."
            if watch_snapshot
            else "No local build-watch snapshot has been recorded for this workspace."
        ),
    },
}

json.dump(payload, sys.stdout, indent=2)
sys.stdout.write("\n")
PY
}

render_evidence_status_markdown_section_for_root() {
    local root="$1"
    local payload=""
    payload=$(evidence_status_json_for_root "${root}")
    [[ -n "${payload}" ]] || return 0

    EVIDENCE_STATUS_PAYLOAD="${payload}" python3 - <<'PY'
import json
import os


def text(value, fallback):
    value = str(value or "").strip()
    return value if value else fallback


payload = os.environ.get("EVIDENCE_STATUS_PAYLOAD", "")
try:
    data = json.loads(payload)
except Exception:
    raise SystemExit(0)

overall = data.get("overall") or {}
artifacts = data.get("artifacts") or {}
order = ["verify", "test", "quality", "workflow", "merge-readiness", "pr-review"]

print("## Evidence Status")
print("")
print(f"- Bundle: {text(overall.get('label'), 'available')} | reason={text(overall.get('reason'), '-')}")
for name in order:
    item = artifacts.get(name) or {}
    extras = []
    raw_status = text(item.get("rawStatus"), "")
    if raw_status:
        extras.append(f"raw={raw_status}")
    last_seen = text(item.get("lastSeenAt"), "")
    if last_seen:
        extras.append(f"last={last_seen}")
    link_target = text(item.get("linkTarget"), "")
    if link_target:
        extras.append(f"artifact={link_target}")
    semantic = text(item.get("semantic"), "")
    if semantic:
        extras.append(f"semantic={semantic}")
    extras.append(f"reason={text(item.get('reason'), '-')}")
    print(f"- {text(item.get('displayName'), name)}: {text(item.get('label'), 'available')} | {' | '.join(extras)}")
PY
}

latest_test_failure_source_snapshot_for_root() {
    local root="$1"
    local verify_line=""
    local test_line=""
    local verify_time=""
    local test_time=""
    local source="none"
    local snapshot=""

    verify_line=$(latest_verify_timeline_line_for_root "${root}" || true)
    test_line=$(latest_test_timeline_line_for_root "${root}" || true)
    if [[ -n "${verify_line}" ]]; then
        verify_time=$(printf "%s\n" "${verify_line}" | awk -F'\t' '{print $1}')
    fi
    if [[ -n "${test_line}" ]]; then
        test_time=$(printf "%s\n" "${test_line}" | awk -F'\t' '{print $1}')
    fi

    if [[ -n "${test_line}" && ( -z "${verify_line}" || "${test_time}" > "${verify_time}" || "${test_time}" == "${verify_time}" ) ]]; then
        source="test"
        snapshot=$(report_snapshot_from_timeline_line "latest" "${test_line}")
    elif [[ -n "${verify_line}" ]]; then
        source="verify"
        snapshot=$(report_snapshot_from_timeline_line "latest" "${verify_line}")
    else
        snapshot=$(report_snapshot_from_timeline_line "latest" "")
    fi

    cat << EOF
latest_source=${source}
${snapshot}
EOF
}

doctor_clean_value() {
    printf "%s" "$1" | tr '\r\n' '  '
}

doctor_join_lines_with_pipe() {
    awk 'NF { gsub(/\r/, "", $0); if (out != "") out = out "|" $0; else out = $0 } END { print out }'
}

doctor_count_lines() {
    local text="$1"
    if [[ -z "${text}" ]]; then
        printf "0\n"
        return 0
    fi
    printf "%s\n" "${text}" | awk 'NF { count += 1 } END { print count + 0 }'
}

doctor_count_csv_items() {
    local csv="$1"
    if [[ -z "${csv}" ]]; then
        printf "0\n"
        return 0
    fi
    printf "%s\n" "${csv}" | awk -F',' '{ count = 0; for (i = 1; i <= NF; i++) if ($i != "") count += 1; print count }'
}

doctor_snapshot_value() {
    local snapshot="$1"
    local key="$2"
    printf "%s\n" "${snapshot}" | sed -nE "s/^${key}=(.*)$/\\1/p" | head -n 1
}
