import { test as bunTest, describe, expect } from "bun:test";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
	chmodSync,
	existsSync,
	mkdirSync,
	readdirSync,
	readFileSync,
	realpathSync,
	utimesSync,
	writeFileSync,
} from "node:fs";
import { join } from "node:path";
import { createIdeTemp } from "./fixtures/ide-temp";

const { ideTemp } = createIdeTemp();

const repoRoot = process.cwd();
const yenBinPath = join(repoRoot, "yen-cli/bin/yen");
const ONE_HOUR_MS = 60 * 60 * 1000;
const ONE_DAY_MS = 24 * ONE_HOUR_MS;

// Agent evidence cases launch multiple hermetic CLI subprocesses.
const test = (name: string, fn: () => void) =>
	bunTest(name, fn, { timeout: 15_000 });

// Generate a recent date string (1 hour ago) so timeline entries stay within
// the 72-hour staleness window regardless of when the test runs.
function recentDateBase(): string {
	const d = new Date(Date.now() - 3600_000);
	return d.toISOString().slice(0, 10); // "YYYY-MM-DD"
}

function isoTimestamp(date: Date): string {
	return date.toISOString().replace(/\.\d{3}Z$/, "Z");
}

const RECENT = recentDateBase();
const RECENT_COMPACT = RECENT.replace(/-/g, ""); // "YYYYMMDD" for filenames

function runYen(args: string[], envOverrides: Record<string, string> = {}) {
	return spawnSync(yenBinPath, args, {
		cwd: repoRoot,
		encoding: "utf8",
		env: {
			...process.env,
			...envOverrides,
		},
	});
}

function runGit(args: string[], cwd: string) {
	const res = spawnSync("git", args, {
		cwd,
		encoding: "utf8",
	});
	if (res.status !== 0) {
		throw new Error(
			`git ${args.join(" ")} failed: ${res.stderr ?? res.stdout ?? ""}`,
		);
	}
}

function createMockAgentsBin() {
	const root = ideTemp("yen-agents-");
	const binDir = join(root, "bin");
	mkdirSync(binDir, { recursive: true });

	const claudePath = join(binDir, "claude");
	writeFileSync(
		claudePath,
		`#!/bin/bash
if [[ "$1" == "--version" ]]; then
  echo "claude 1.2.3"
  exit 0
fi
echo "claude-launch"
`,
		"utf8",
	);
	chmodSync(claudePath, 0o755);

	const codexPath = join(binDir, "codex");
	writeFileSync(
		codexPath,
		`#!/bin/bash
if [[ "$1" == "--version" ]]; then
  echo "codex 4.5.6"
  exit 0
fi
echo "codex-launch"
`,
		"utf8",
	);
	chmodSync(codexPath, 0o755);

	return { root, binDir };
}

function createFailingCodexBin(exitCode: number) {
	const mock = createMockAgentsBin();
	const codexPath = join(mock.binDir, "codex");
	writeFileSync(
		codexPath,
		`#!/bin/bash
if [[ "$1" == "--version" ]]; then
  echo "codex 4.5.6"
  exit 0
fi
exit ${exitCode}
`,
		"utf8",
	);
	chmodSync(codexPath, 0o755);
	return mock;
}

function createProject(prefix: string) {
	const root = ideTemp(prefix);
	writeFileSync(
		join(root, "package.json"),
		'{"name":"agents-fixture"}\n',
		"utf8",
	);
	return realpathSync(root);
}

function createGitProject(prefix: string) {
	const root = createProject(prefix);
	runGit(["init", "-b", "main"], root);
	runGit(["config", "user.name", "YEN Test"], root);
	runGit(["config", "user.email", "yen@example.test"], root);
	runGit(["add", "package.json"], root);
	runGit(["commit", "-m", "init"], root);
	return root;
}

function ideStateHashForRoot(projectRoot: string) {
	return createHash("sha256").update(projectRoot).digest("hex");
}

function seedIdeEvidence(stateDir: string, projectRoot: string) {
	mkdirSync(stateDir, { recursive: true });

	const verifySummary = join(stateDir, "verify-summary.tsv");
	const testSummary = join(stateDir, "test-summary.tsv");
	writeFileSync(verifySummary, "target\tstatus\n", "utf8");
	writeFileSync(testSummary, "target\tstatus\n", "utf8");
	writeFileSync(
		join(stateDir, "timeline.log"),
		[
			`${RECENT}T10:00:00Z\tverify\t${projectRoot}\tfailures=0;warns=0\tsummary=${verifySummary};semantic=project-clean`,
			`${RECENT}T10:05:00Z\ttest\t${projectRoot}\tfailures=0;warns=0\tsummary=${testSummary};semantic=tests-green`,
		].join("\n"),
		"utf8",
	);
}

function seedLinkedIdeArtifacts(stateDir: string, projectRoot: string) {
	const hash = ideStateHashForRoot(projectRoot);
	const evidenceDir = join(stateDir, "evidence");
	const watchDir = join(stateDir, "watch");
	const qualitySummary = join(stateDir, "quality-lint-summary.tsv");
	const qualityDetails = join(stateDir, "quality-lint-summary.log");
	const qualitySemantic = join(stateDir, "quality-lint-summary.semantic.tsv");
	const workflowSummary = join(stateDir, "workflow-native-summary.tsv");
	const workflowDetails = join(stateDir, "workflow-native-summary.log");
	const workflowSemantic = join(
		stateDir,
		"workflow-native-summary.semantic.tsv",
	);
	const evidencePath = join(evidenceDir, `pr-123-${RECENT_COMPACT}T100701Z.md`);
	const decisionPath = join(
		evidenceDir,
		`pr-123-decision-comment-${RECENT_COMPACT}T100702Z.md`,
	);
	const inlinePath = join(
		evidenceDir,
		`pr-123-inline-${RECENT_COMPACT}T100703Z.md`,
	);
	const watchSummary = join(stateDir, "verify-watch-summary.tsv");
	const watchDetails = join(stateDir, "verify-watch-summary.log");
	const timelinePath = join(stateDir, "timeline.log");
	mkdirSync(evidenceDir, { recursive: true });
	mkdirSync(watchDir, { recursive: true });
	writeFileSync(evidencePath, "# PR evidence\n", "utf8");
	writeFileSync(decisionPath, "# PR decision\n", "utf8");
	writeFileSync(inlinePath, "# Inline review\n", "utf8");
	writeFileSync(qualitySummary, "time\tstatus\n", "utf8");
	writeFileSync(qualityDetails, "quality details\n", "utf8");
	writeFileSync(qualitySemantic, "semantic quality\n", "utf8");
	writeFileSync(workflowSummary, "time\tstep\tmode\tstatus\n", "utf8");
	writeFileSync(workflowDetails, "workflow details\n", "utf8");
	writeFileSync(workflowSemantic, "semantic workflow\n", "utf8");
	writeFileSync(watchSummary, "target\tstatus\n", "utf8");
	writeFileSync(watchDetails, "watch details\n", "utf8");
	writeFileSync(
		join(stateDir, `pr-ci-${hash}.env`),
		[
			"available=yes",
			"repo=octo/yen",
			"reason=Current branch pull request detected.",
			"pr_number=123",
			"title=Refine linked evidence",
			"url=https://example.test/pr/123",
			"branch=main",
			"is_draft=no",
			"checks_state=passing",
			"checks_total=5",
			"checks_passing=5",
			"checks_pending=0",
			"checks_failing=0",
			"completed=yes",
			"",
		].join("\n"),
		"utf8",
	);
	writeFileSync(
		join(watchDir, `${hash}-verify.env`),
		[
			"schema_version=1",
			"kind=verify",
			"label=verify",
			"branch=main",
			"active=no",
			"state=max-runs",
			"iteration=1",
			"interval_seconds=0.1",
			"max_runs=1",
			"scope=quick-no-security",
			"started_at=${RECENT}T10:07:30Z",
			"updated_at=${RECENT}T10:08:00Z",
			"stop_reason=max-runs",
			"last_outcome=passing",
			"last_exit_code=0",
			"last_failures=0",
			"last_warns=0",
			"last_executed=3",
			`summary=${watchSummary}`,
			`details=${watchDetails}`,
			"semantic=watch-green",
			"",
		].join("\n"),
		"utf8",
	);

	const existingTimeline = existsSync(timelinePath)
		? readFileSync(timelinePath, "utf8").trimEnd()
		: "";
	const linkedLines = [
		`${RECENT}T10:06:00Z\tmerge-readiness\t${projectRoot}\tstatus=ok;pending=0;risky=1\tpr=123;verify=passing;format=json`,
		`${RECENT}T10:06:10Z\tquality\t${projectRoot}\tsuccess\taction=lint;candidate=biome;scope=workspace;summary=${qualitySummary};semantic=${qualitySemantic}`,
		`${RECENT}T10:06:20Z\tworkflow\t${projectRoot}\tsuccess\tname=check;kind=native;source=package-json:test;location=local;summary=${workflowSummary};semantic=${workflowSemantic}`,
		`${RECENT}T10:07:00Z\tpr-review\t${projectRoot}\tpr=123\tfile=src/a.ts;target=src/a.ts:12;evidence=yes;post=no`,
		`${RECENT}T10:07:01Z\tpr-evidence\t${projectRoot}\tpr=123\tfile=src/a.ts;target=src/a.ts:12;path=${evidencePath}`,
		`${RECENT}T10:07:02Z\tpr-decision\t${projectRoot}\tpr=123;mode=comment\tfile=src/a.ts;target=src/a.ts:12;post=no;path=${decisionPath}`,
		`${RECENT}T10:07:03Z\tpr-inline-comment\t${projectRoot}\tpr=123;posted=no\tpath=src/a.ts;line=12;side=RIGHT;template=${inlinePath}`,
		`${RECENT}T10:08:00Z\tpr-ci\t${projectRoot}\tpassing\trepo=octo/yen;pr=123;url=https://example.test/pr/123;pass=5;pending=0;fail=0`,
	];
	writeFileSync(
		timelinePath,
		[existingTimeline, ...linkedLines].filter(Boolean).join("\n"),
		"utf8",
	);

	return {
		qualitySummary,
		qualityDetails,
		qualitySemantic,
		workflowSummary,
		workflowDetails,
		workflowSemantic,
		evidencePath,
		decisionPath,
		inlinePath,
	};
}

describe("IDE S2 agents adapter board", () => {
	test("yen help advertises agents command", () => {
		const res = runYen(["--help"]);
		const output = `${res.stdout ?? ""}\n${res.stderr ?? ""}`;
		expect(res.status).toBe(0);
		expect(output).toContain("agents  Adapter board");
	});

	test("agents list shows first-party adapters with version probes and capabilities", () => {
		const mock = createMockAgentsBin();
		const res = runYen(["agents", "list"], {
			PATH: `${mock.binDir}:${process.env.PATH ?? ""}`,
		});
		const output = `${res.stdout ?? ""}\n${res.stderr ?? ""}`;
		expect(res.status).toBe(0);
		expect(output).toContain("claude");
		expect(output).toContain("codex");
		expect(output).toContain("chat,edit,exec,review");
		expect(output).toContain("claude 1.2.3");
		expect(output).toContain("codex 4.5.6");
	});

	test("agents open dry-run degrades cleanly when adapter binary is unavailable", () => {
		const res = runYen(["agents", "open", "claude", "--dry-run"], {
			PATH: `/usr/bin:/bin`,
		});
		const output = `${res.stdout ?? ""}\n${res.stderr ?? ""}`;
		expect(res.status).toBe(0);
		expect(output).toContain("binary 'claude' not found");
		expect(output).toContain("would fall back to normal shell session");
	});

	test("agents open dry-run resolves known adapter command when available", () => {
		const mock = createMockAgentsBin();
		const res = runYen(["agents", "open", "--profile", "codex", "--dry-run"], {
			PATH: `${mock.binDir}:${process.env.PATH ?? ""}`,
		});
		const output = `${res.stdout ?? ""}\n${res.stderr ?? ""}`;
		expect(res.status).toBe(0);
		expect(output).toContain("would launch 'codex' via: codex");
	});

	test("agents open stays fail-open when capture state dir is unavailable", () => {
		const mock = createMockAgentsBin();
		const project = createProject("yen-agents-broken-state-");
		const badStateRoot = ideTemp("yen-agents-state-file-");
		const badStatePath = join(badStateRoot, "blocked");
		writeFileSync(badStatePath, "not-a-directory\n", "utf8");

		const res = runYen(["agents", "open", "codex", "--project", project], {
			PATH: `${mock.binDir}:${process.env.PATH ?? ""}`,
			YEN_AGENTS_STATE_DIR: badStatePath,
		});

		expect(res.status).toBe(0);
		expect(res.stdout).toContain("codex-launch");
	});

	test("agents open records session state and text timeline with linked IDE evidence", () => {
		const mock = createMockAgentsBin();
		const project = createProject("yen-agents-project-");
		const agentsStateDir = ideTemp("yen-agents-state-");
		const ideStateDir = ideTemp("yen-ide-state-");
		seedIdeEvidence(ideStateDir, project);

		const env = {
			PATH: `${mock.binDir}:${process.env.PATH ?? ""}`,
			YEN_AGENTS_STATE_DIR: agentsStateDir,
			YEN_IDE_STATE_DIR: ideStateDir,
		};

		const openRes = runYen(
			["agents", "open", "claude", "--project", project],
			env,
		);
		expect(openRes.status).toBe(0);
		expect(openRes.stdout).toContain("claude-launch");

		const sessionFiles = readdirSync(join(agentsStateDir, "sessions"));
		expect(sessionFiles.length).toBe(1);

		const sessionState = readFileSync(
			join(agentsStateDir, "sessions", sessionFiles[0] ?? ""),
			"utf8",
		);
		expect(sessionState).toContain("slot_id=claude");
		expect(sessionState).toContain("adapter=claude");
		expect(sessionState).toContain(`project_root=${project}`);
		expect(sessionState).toContain("branch=-");
		expect(sessionState).toContain("dirty_state=not-git");
		expect(sessionState).toContain("lifecycle_state=stopped");
		expect(sessionState).toContain("exit_code=0");
		expect(sessionState).toContain("binary_name=claude");
		expect(sessionState).toContain(
			`binary_path=${join(mock.binDir, "claude")}`,
		);
		expect(sessionState).toContain("probe_command=claude --version");
		expect(sessionState).toContain("probe_status=ready");
		expect(sessionState).toContain("probe_version=claude 1.2.3");
		expect(sessionState).toContain(
			"declared_capabilities=chat,edit,exec,review",
		);
		expect(sessionState).toContain("launch_result=launched");
		expect(sessionState).toContain("fallback_state=none");

		const timelineRes = runYen(
			["agents", "timeline", "--project", project],
			env,
		);
		const timelineOutput = `${timelineRes.stdout ?? ""}\n${timelineRes.stderr ?? ""}`;
		expect(timelineRes.status).toBe(0);
		expect(timelineOutput).toContain("Agent Timeline");
		expect(timelineOutput).toContain(`Project:      ${project}`);
		expect(timelineOutput).toContain("Evidence:     exported-with-gaps");
		expect(timelineOutput).toContain("Verify:       passing");
		expect(timelineOutput).toContain("Test:         passing");
		expect(timelineOutput).toContain("Quality:      missing-report");
		expect(timelineOutput).toContain("session-start");
		expect(timelineOutput).toContain("session-stop");
		expect(timelineOutput).toContain("slot=claude");
		expect(timelineOutput).toContain("workspace_identity=local://");
	});

	test("agents timeline json returns session metadata and evidence snapshot", () => {
		const mock = createMockAgentsBin();
		const project = createProject("yen-agents-json-");
		const agentsStateDir = ideTemp("yen-agents-state-");
		const ideStateDir = ideTemp("yen-ide-state-");
		seedIdeEvidence(ideStateDir, project);

		const env = {
			PATH: `${mock.binDir}:${process.env.PATH ?? ""}`,
			YEN_AGENTS_STATE_DIR: agentsStateDir,
			YEN_IDE_STATE_DIR: ideStateDir,
		};

		const openRes = runYen(
			["agents", "open", "codex", "--project", project],
			env,
		);
		expect(openRes.status).toBe(0);

		const timelineRes = runYen(
			["agents", "timeline", "--project", project, "--format", "json"],
			env,
		);
		expect(timelineRes.status).toBe(0);

		const payload = JSON.parse(timelineRes.stdout);
		expect(payload.schemaVersion).toBe(1);
		expect(payload.schemaKind).toBe("agents-timeline");
		expect(payload.schemas.event).toBe(1);
		expect(payload.schemas.evidenceStatus).toBe(1);
		expect(payload.schemas.linkedEvidence).toBe(1);
		expect(payload.eventTaxonomy.stableEventNames).toContain("export");
		expect(payload.projectRoot).toBe(project);
		expect(payload.workspaceIdentity).toContain("local://");
		expect(payload.repoSnapshot.contextKey).toBe(
			`${payload.workspaceIdentity}|${payload.repoSnapshot.branch || "-"}|${payload.repoSnapshot.shortHead || payload.repoSnapshot.head || "-"}`,
		);
		expect(payload.riskSummary.count).toBe(0);
		expect(payload.riskSummary.summaryText).toBe("none");
		expect(payload.riskFlags).toEqual([]);
		expect(payload.evidence.verify.status).toBe("passing");
		expect(payload.evidence.verify.details).toBe("");
		expect(payload.evidence.verify.semantic).toBe("project-clean");
		expect(payload.evidence.test.status).toBe("passing");
		expect(payload.evidence.test.details).toBe("");
		expect(payload.evidenceStatus.schemaVersion).toBe(1);
		expect(payload.evidenceStatus.overall.label).toBe("exported-with-gaps");
		expect(payload.evidenceStatus.artifacts.verify.label).toBe("available");
		expect(payload.evidenceStatus.artifacts.quality.label).toBe(
			"missing-report",
		);
		expect(payload.linkedEvidence.schemaVersion).toBe(1);
		expect(payload.linkedEvidence.mergeReadiness.available).toBe(false);
		expect(payload.linkedEvidence.currentBranchCi.available).toBe(false);
		expect(payload.events).toHaveLength(2);
		expect(payload.events[0].schemaVersion).toBe(1);
		expect(payload.events[0].event).toBe("session-start");
		expect(payload.events[0].eventFamily).toBe("session");
		expect(payload.events[0].eventAction).toBe("start");
		expect(payload.events[0].eventOutcome).toBe("launched");
		expect(payload.events[0].source.kind).toBe("agent");
		expect(payload.events[0].target.kind).toBe("slot");
		expect(payload.events[0].target.sessionId).toBeTruthy();
		expect(payload.events[0].slotId).toBe("codex");
		expect(payload.events[0].sessionState.schemaVersion).toBe(1);
		expect(payload.events[0].sessionState.lifecycleState).toBe("stopped");
		expect(payload.events[0].sessionState.binaryName).toBe("codex");
		expect(payload.events[0].sessionState.binaryPath).toBe(
			join(mock.binDir, "codex"),
		);
		expect(payload.events[0].sessionState.probeCommand).toBe("codex --version");
		expect(payload.events[0].sessionState.probeStatus).toBe("ready");
		expect(payload.events[0].sessionState.probeVersion).toBe("codex 4.5.6");
		expect(payload.events[0].sessionState.declaredCapabilities).toBe(
			"chat,edit,exec,review",
		);
		expect(payload.events[0].sessionState.launchResult).toBe("launched");
		expect(payload.events[0].sessionState.fallbackState).toBe("none");
		expect(payload.events[1].status).toBe("status=success;exit=0");
		expect(payload.events[1].statusFields.status).toBe("success");
		expect(payload.events[1].statusFields.exit).toBe("0");
		expect(payload.events[1].eventOutcome).toBe("success");
	});

	test("agents open preserves failing adapter exit status in state and timeline", () => {
		const mock = createFailingCodexBin(7);
		const project = createProject("yen-agents-failing-");
		const agentsStateDir = ideTemp("yen-agents-state-");

		const env = {
			PATH: `${mock.binDir}:${process.env.PATH ?? ""}`,
			YEN_AGENTS_STATE_DIR: agentsStateDir,
		};

		const openRes = runYen(
			["agents", "open", "codex", "--project", project],
			env,
		);
		expect(openRes.status).toBe(7);

		const sessionFiles = readdirSync(join(agentsStateDir, "sessions"));
		expect(sessionFiles.length).toBe(1);

		const sessionState = readFileSync(
			join(agentsStateDir, "sessions", sessionFiles[0] ?? ""),
			"utf8",
		);
		expect(sessionState).toContain("adapter=codex");
		expect(sessionState).toContain("lifecycle_state=stopped");
		expect(sessionState).toContain("exit_code=7");

		const timelineRes = runYen(
			["agents", "timeline", "--project", project, "--format", "json"],
			env,
		);
		expect(timelineRes.status).toBe(0);

		const payload = JSON.parse(timelineRes.stdout);
		expect(payload.events).toHaveLength(2);
		expect(payload.events[1].event).toBe("session-stop");
		expect(payload.events[1].status).toBe("status=failed;exit=7");
		expect(payload.events[1].sessionState.exitCode).toBe(7);
	});

	test("agents export writes a markdown evidence bundle with repo snapshot and risk flags", () => {
		const mock = createMockAgentsBin();
		const project = createGitProject("yen-agents-export-");
		const agentsStateDir = ideTemp("yen-agents-state-");
		const ideStateDir = ideTemp("yen-ide-state-");
		seedIdeEvidence(ideStateDir, project);

		writeFileSync(
			join(project, "package.json"),
			'{"name":"agents-fixture","dependencies":{"react":"19.0.0"}}\n',
			"utf8",
		);
		mkdirSync(join(project, "supabase", "migrations"), { recursive: true });
		writeFileSync(
			join(project, "supabase", "migrations", "20260328_init.sql"),
			"create table widgets(id int);\n",
			"utf8",
		);

		const env = {
			PATH: `${mock.binDir}:${process.env.PATH ?? ""}`,
			YEN_AGENTS_STATE_DIR: agentsStateDir,
			YEN_IDE_STATE_DIR: ideStateDir,
		};

		expect(
			runYen(["agents", "open", "codex", "--project", project], env).status,
		).toBe(0);

		const exportRes = runYen(["agents", "export", "--project", project], env);
		const exportOutput = `${exportRes.stdout ?? ""}\n${exportRes.stderr ?? ""}`;
		expect(exportRes.status).toBe(0);
		expect(exportOutput).toContain("Wrote agent export bundle:");

		const exportPath = exportOutput
			.trim()
			.split("Wrote agent export bundle: ")
			.pop();
		expect(exportPath).toBeTruthy();
		if (!exportPath) throw new Error("exportPath missing");

		const bundle = readFileSync(exportPath, "utf8");
		expect(bundle).toContain("# Agent Export Bundle");
		expect(bundle).toContain("## Repo Snapshot");
		expect(bundle).toContain("- Branch: main");
		expect(bundle).toContain("- Dirty state: dirty");
		expect(bundle).toContain("## Adapter Sessions");
		expect(bundle).toContain("Adapter: codex");
		expect(bundle).toContain("## Verification");
		expect(bundle).toContain("- Verify: passing");
		expect(bundle).toContain("- Test: passing");
		expect(bundle).not.toContain("verify-summary.log");
		expect(bundle).not.toContain("test-summary.log");
		expect(bundle).toContain("## Diff Summary");
		expect(bundle).toContain("package.json");
		expect(bundle).toContain("supabase/migrations/20260328_init.sql");
		expect(bundle).toContain("## Risk Flags");
		expect(bundle).toContain("dependency-change");
		expect(bundle).toContain("migration-touch");
		expect(bundle).toContain("## Evidence Status");
		expect(bundle).toContain("- Bundle: exported-with-gaps");
		expect(bundle).toContain("- Quality: missing-report");
		expect(bundle).toContain("## Evidence Gaps");
		expect(bundle).toContain("quality:missing-report");
	});

	test("agents export uses unique default filenames for repeated exports", () => {
		const mock = createMockAgentsBin();
		const project = createGitProject("yen-agents-export-repeat-");
		const agentsStateDir = ideTemp("yen-agents-state-");
		const ideStateDir = ideTemp("yen-ide-state-");
		seedIdeEvidence(ideStateDir, project);

		const env = {
			PATH: `${mock.binDir}:${process.env.PATH ?? ""}`,
			YEN_AGENTS_STATE_DIR: agentsStateDir,
			YEN_IDE_STATE_DIR: ideStateDir,
		};

		expect(
			runYen(["agents", "open", "claude", "--project", project], env).status,
		).toBe(0);

		const first = runYen(["agents", "export", "--project", project], env);
		const second = runYen(["agents", "export", "--project", project], env);
		expect(first.status).toBe(0);
		expect(second.status).toBe(0);

		const firstPath = `${first.stdout ?? ""}\n${first.stderr ?? ""}`
			.trim()
			.split("Wrote agent export bundle: ")
			.pop();
		const secondPath = `${second.stdout ?? ""}\n${second.stderr ?? ""}`
			.trim()
			.split("Wrote agent export bundle: ")
			.pop();

		expect(firstPath).toBeTruthy();
		expect(secondPath).toBeTruthy();
		if (!firstPath || !secondPath) throw new Error("export paths missing");
		expect(firstPath).not.toBe(secondPath);
		expect(readFileSync(firstPath, "utf8")).toContain("# Agent Export Bundle");
		expect(readFileSync(secondPath, "utf8")).toContain("# Agent Export Bundle");
	});

	test("agents note records approval context in timeline and export", () => {
		const project = createGitProject("yen-agents-note-");
		const agentsStateDir = ideTemp("yen-agents-state-");
		const ideStateDir = ideTemp("yen-ide-state-");
		seedIdeEvidence(ideStateDir, project);

		const env = {
			YEN_AGENTS_STATE_DIR: agentsStateDir,
			YEN_IDE_STATE_DIR: ideStateDir,
		};

		const noteRes = runYen(
			[
				"agents",
				"note",
				"--project",
				project,
				"--actor",
				"human",
				"--kind",
				"approval",
				"--decision",
				"approved",
				"--slot",
				"supervisor",
				"--message",
				"Reviewed manually before handoff",
			],
			env,
		);
		expect(noteRes.status).toBe(0);
		expect(`${noteRes.stdout ?? ""}\n${noteRes.stderr ?? ""}`).toContain(
			"Recorded agent note:",
		);

		const timelineRes = runYen(
			["agents", "timeline", "--project", project, "--format", "json"],
			env,
		);
		expect(timelineRes.status).toBe(0);
		const timelinePayload = JSON.parse(timelineRes.stdout);
		expect(timelinePayload.events).toHaveLength(1);
		expect(timelinePayload.events[0].event).toBe("note");
		expect(timelinePayload.events[0].eventFamily).toBe("note");
		expect(timelinePayload.events[0].eventAction).toBe("record");
		expect(timelinePayload.events[0].eventOutcome).toBe("approved");
		expect(timelinePayload.events[0].status).toBe("approval=approved");
		expect(timelinePayload.events[0].source.kind).toBe("human");
		expect(timelinePayload.events[0].target.kind).toBe("note");
		expect(timelinePayload.events[0].note.schemaVersion).toBe(1);
		expect(timelinePayload.events[0].note.actor).toBe("human");
		expect(timelinePayload.events[0].note.kind).toBe("approval");
		expect(timelinePayload.events[0].note.decision).toBe("approved");
		expect(timelinePayload.events[0].note.message).toBe(
			"Reviewed manually before handoff",
		);

		const exportRes = runYen(
			[
				"agents",
				"export",
				"--project",
				project,
				"--format",
				"json",
				"--output",
				"-",
			],
			env,
		);
		expect(exportRes.status).toBe(0);
		const payload = JSON.parse(exportRes.stdout);
		expect(payload.notes).toHaveLength(1);
		expect(payload.approvals).toHaveLength(1);
		expect(payload.approvals[0].decision).toBe("approved");
		expect(payload.approvals[0].message).toBe(
			"Reviewed manually before handoff",
		);
		expect(payload.evidenceGaps).not.toContain("missing-human-approvals");
	});

	test("agents note templates add structured metadata and validate linked sessions", () => {
		const mock = createMockAgentsBin();
		const project = createGitProject("yen-agents-note-template-");
		const agentsStateDir = ideTemp("yen-agents-state-");
		const ideStateDir = ideTemp("yen-ide-state-");
		seedIdeEvidence(ideStateDir, project);

		const env = {
			PATH: `${mock.binDir}:${process.env.PATH ?? ""}`,
			YEN_AGENTS_STATE_DIR: agentsStateDir,
			YEN_IDE_STATE_DIR: ideStateDir,
		};

		expect(
			runYen(["agents", "open", "codex", "--project", project], env).status,
		).toBe(0);

		const sessionFile = readdirSync(join(agentsStateDir, "sessions"))[0] ?? "";
		const sessionId = sessionFile.replace(/\.state$/, "");

		const noteRes = runYen(
			[
				"agents",
				"note",
				"--project",
				project,
				"--actor",
				"supervisor",
				"--template",
				"handoff-review",
				"--session",
				sessionId,
				"--validate-link",
			],
			env,
		);
		expect(noteRes.status).toBe(0);

		const timelineRes = runYen(
			[
				"agents",
				"timeline",
				"--project",
				project,
				"--event",
				"note",
				"--format",
				"json",
			],
			env,
		);
		expect(timelineRes.status).toBe(0);
		const timelinePayload = JSON.parse(timelineRes.stdout);
		expect(timelinePayload.events).toHaveLength(1);
		expect(timelinePayload.events[0].eventOutcome).toBe("handoff");
		expect(timelinePayload.events[0].source.kind).toBe("supervisor");
		expect(timelinePayload.events[0].target.kind).toBe("note");
		expect(timelinePayload.events[0].note.actor).toBe("supervisor");
		expect(timelinePayload.events[0].note.kind).toBe("handoff");
		expect(timelinePayload.events[0].note.template).toBe("handoff-review");
		expect(timelinePayload.events[0].note.title).toBe("Review handoff");
		expect(timelinePayload.events[0].note.linkValidated).toBe(true);
		expect(timelinePayload.events[0].note.slotId).toBe("codex");
		expect(timelinePayload.events[0].note.sessionId).toBe(sessionId);
		expect(timelinePayload.events[0].note.message).toContain(
			"Handing off the current workspace state for review.",
		);

		const exportRes = runYen(
			[
				"agents",
				"export",
				"--project",
				project,
				"--format",
				"json",
				"--output",
				"-",
			],
			env,
		);
		expect(exportRes.status).toBe(0);
		const payload = JSON.parse(exportRes.stdout);
		expect(payload.handoffs).toHaveLength(1);
		expect(payload.handoffs[0].template).toBe("handoff-review");
		expect(payload.handoffs[0].linkValidated).toBe(true);
		expect(payload.handoffs[0].slotId).toBe("codex");

		const mismatchRes = runYen(
			[
				"agents",
				"note",
				"--project",
				project,
				"--template",
				"handoff-review",
				"--session",
				sessionId,
				"--slot",
				"claude",
				"--validate-link",
			],
			env,
		);
		expect(mismatchRes.status).not.toBe(0);
		expect(
			`${mismatchRes.stdout ?? ""}\n${mismatchRes.stderr ?? ""}`,
		).toContain("is linked to slot 'codex', not 'claude'");
	});

	test("agents note slot-only validation prefers the newest matching session state", () => {
		const project = createProject("yen-agents-slot-link-order-");
		const agentsStateDir = ideTemp("yen-agents-state-");
		const env = {
			YEN_AGENTS_STATE_DIR: agentsStateDir,
		};

		const workspaceIdentityRes = runYen(
			["agents", "timeline", "--project", project, "--format", "json"],
			env,
		);
		expect(workspaceIdentityRes.status).toBe(0);
		const workspaceIdentity = JSON.parse(
			workspaceIdentityRes.stdout,
		).workspaceIdentity;

		const sessionsDir = join(agentsStateDir, "sessions");
		mkdirSync(sessionsDir, { recursive: true });

		const olderSessionId = "agt-20260328T120000Z-12345-999999";
		const newerSessionId = "agt-20260328T120000Z-12345-000001";
		const olderPath = join(sessionsDir, `${olderSessionId}.state`);
		const newerPath = join(sessionsDir, `${newerSessionId}.state`);
		const olderSessionTime = new Date(Date.now() - 2 * ONE_HOUR_MS);
		const newerSessionTime = new Date(Date.now() - ONE_HOUR_MS);
		const sessionState = (sessionId: string, timestamp: string) =>
			[
				`session_id=${sessionId}`,
				"slot_id=codex",
				"adapter=codex",
				`workspace_identity=${workspaceIdentity}`,
				`project_root=${project}`,
				"branch=-",
				"dirty_state=not-git",
				"launch_mode=adapter",
				"lifecycle_state=stopped",
				`started_at=${timestamp}`,
				`stopped_at=${timestamp}`,
				"exit_code=0",
			].join("\n");

		writeFileSync(
			olderPath,
			`${sessionState(olderSessionId, isoTimestamp(olderSessionTime))}\n`,
			"utf8",
		);
		writeFileSync(
			newerPath,
			`${sessionState(newerSessionId, isoTimestamp(newerSessionTime))}\n`,
			"utf8",
		);
		utimesSync(olderPath, olderSessionTime, olderSessionTime);
		utimesSync(newerPath, newerSessionTime, newerSessionTime);

		const noteRes = runYen(
			[
				"agents",
				"note",
				"--project",
				project,
				"--actor",
				"supervisor",
				"--template",
				"handoff-review",
				"--slot",
				"codex",
				"--validate-link",
			],
			env,
		);
		expect(noteRes.status).toBe(0);

		const timelineRes = runYen(
			[
				"agents",
				"timeline",
				"--project",
				project,
				"--event",
				"note",
				"--format",
				"json",
			],
			env,
		);
		expect(timelineRes.status).toBe(0);
		const timelinePayload = JSON.parse(timelineRes.stdout);
		expect(timelinePayload.events).toHaveLength(1);
		expect(timelinePayload.events[0].note.sessionId).toBe(newerSessionId);
		expect(timelinePayload.events[0].note.slotId).toBe("codex");
		expect(timelinePayload.events[0].note.linkValidated).toBe(true);
	});

	test("agents note slot-only validation accepts legacy project-root workspace session state", () => {
		const project = createProject("yen-agents-slot-link-legacy-root-");
		const agentsStateDir = ideTemp("yen-agents-state-");
		const env = {
			YEN_AGENTS_STATE_DIR: agentsStateDir,
		};

		const sessionsDir = join(agentsStateDir, "sessions");
		mkdirSync(sessionsDir, { recursive: true });

		const sessionId = "agt-20260328T120100Z-12345-000002";
		writeFileSync(
			join(sessionsDir, `${sessionId}.state`),
			[
				`session_id=${sessionId}`,
				"slot_id=codex",
				"adapter=codex",
				`workspace_identity=${project}`,
				`project_root=${project}`,
				"branch=-",
				"dirty_state=not-git",
				"launch_mode=adapter",
				"lifecycle_state=stopped",
				`started_at=${isoTimestamp(new Date(Date.now() - ONE_HOUR_MS))}`,
				`stopped_at=${isoTimestamp(new Date(Date.now() - ONE_HOUR_MS))}`,
				"exit_code=0",
			].join("\n"),
			"utf8",
		);

		const noteRes = runYen(
			[
				"agents",
				"note",
				"--project",
				project,
				"--actor",
				"supervisor",
				"--template",
				"handoff-review",
				"--slot",
				"codex",
				"--validate-link",
			],
			env,
		);
		expect(noteRes.status).toBe(0);

		const timelineRes = runYen(
			[
				"agents",
				"timeline",
				"--project",
				project,
				"--event",
				"note",
				"--format",
				"json",
			],
			env,
		);
		expect(timelineRes.status).toBe(0);
		const timelinePayload = JSON.parse(timelineRes.stdout);
		expect(timelinePayload.events).toHaveLength(1);
		expect(timelinePayload.events[0].note.sessionId).toBe(sessionId);
		expect(timelinePayload.events[0].note.linkValidated).toBe(true);
	});

	test("agents note slot-only validation falls back to retained timeline session metadata", () => {
		const project = createProject("yen-agents-slot-link-timeline-only-");
		const agentsStateDir = ideTemp("yen-agents-state-");
		const env = {
			YEN_AGENTS_STATE_DIR: agentsStateDir,
		};

		const timelineBootstrap = runYen(
			["agents", "timeline", "--project", project, "--format", "json"],
			env,
		);
		expect(timelineBootstrap.status).toBe(0);
		const workspaceIdentity = JSON.parse(
			timelineBootstrap.stdout,
		).workspaceIdentity;

		const sessionId = "agt-20260328T120200Z-12345-000003";
		const sessionStartedAt = isoTimestamp(
			new Date(Date.now() - 2 * ONE_HOUR_MS),
		);
		const sessionStoppedAt = isoTimestamp(new Date(Date.now() - ONE_HOUR_MS));
		writeFileSync(
			join(agentsStateDir, "timeline.log"),
			[
				`${sessionStartedAt}\tsession-start\t${project}\tlaunched\tsession=${sessionId};slot=codex;adapter=codex;branch=-;dirty=not-git;launch_mode=adapter;workspace_identity=${workspaceIdentity};started_at=${sessionStartedAt};binary_name=codex;binary_path=/tmp/mock-codex;probe_command=codex --version;probe_status=ready;probe_version=codex 4.5.6;declared_capabilities=chat,edit,exec,review;launch_result=launched;fallback_state=none`,
				`${sessionStoppedAt}\tsession-stop\t${project}\tstatus=success;exit=0\tsession=${sessionId};slot=codex;adapter=codex;branch=-;dirty=not-git;launch_mode=adapter;workspace_identity=${workspaceIdentity};started_at=${sessionStartedAt};stopped_at=${sessionStoppedAt};binary_name=codex;binary_path=/tmp/mock-codex;probe_command=codex --version;probe_status=ready;probe_version=codex 4.5.6;declared_capabilities=chat,edit,exec,review;launch_result=launched;fallback_state=none`,
			].join("\n"),
			"utf8",
		);

		const noteRes = runYen(
			[
				"agents",
				"note",
				"--project",
				project,
				"--actor",
				"supervisor",
				"--template",
				"handoff-review",
				"--slot",
				"codex",
				"--validate-link",
			],
			env,
		);
		expect(noteRes.status).toBe(0);

		const timelineRes = runYen(
			[
				"agents",
				"timeline",
				"--project",
				project,
				"--event",
				"note",
				"--format",
				"json",
			],
			env,
		);
		expect(timelineRes.status).toBe(0);
		const timelinePayload = JSON.parse(timelineRes.stdout);
		expect(timelinePayload.events).toHaveLength(1);
		expect(timelinePayload.events[0].note.sessionId).toBe(sessionId);
		expect(timelinePayload.events[0].note.slotId).toBe("codex");
		expect(timelinePayload.events[0].note.linkValidated).toBe(true);
	});

	test("agents note explicit-session validation falls back to retained timeline session metadata", () => {
		const project = createProject("yen-agents-session-link-timeline-only-");
		const agentsStateDir = ideTemp("yen-agents-state-");
		const env = {
			YEN_AGENTS_STATE_DIR: agentsStateDir,
		};

		const timelineBootstrap = runYen(
			["agents", "timeline", "--project", project, "--format", "json"],
			env,
		);
		expect(timelineBootstrap.status).toBe(0);
		const workspaceIdentity = JSON.parse(
			timelineBootstrap.stdout,
		).workspaceIdentity;

		const sessionId = "agt-20260328T120300Z-12345-000004";
		const sessionStartedAt = isoTimestamp(
			new Date(Date.now() - 2 * ONE_HOUR_MS),
		);
		const sessionStoppedAt = isoTimestamp(new Date(Date.now() - ONE_HOUR_MS));
		writeFileSync(
			join(agentsStateDir, "timeline.log"),
			[
				`${sessionStartedAt}\tsession-start\t${project}\tfallback\tsession=${sessionId};slot=claude;adapter=claude;branch=-;dirty=not-git;launch_mode=shell-fallback;workspace_identity=${workspaceIdentity};started_at=${sessionStartedAt};binary_name=claude;binary_path=;probe_command=claude --version;probe_status=missing;probe_version=-;declared_capabilities=chat,edit,exec,review;launch_result=fallback;fallback_state=binary-missing`,
				`${sessionStoppedAt}\tsession-stop\t${project}\tstatus=success;exit=0\tsession=${sessionId};slot=claude;adapter=claude;branch=-;dirty=not-git;launch_mode=shell-fallback;workspace_identity=${workspaceIdentity};started_at=${sessionStartedAt};stopped_at=${sessionStoppedAt};binary_name=claude;binary_path=;probe_command=claude --version;probe_status=missing;probe_version=-;declared_capabilities=chat,edit,exec,review;launch_result=fallback;fallback_state=binary-missing`,
			].join("\n"),
			"utf8",
		);

		const noteRes = runYen(
			[
				"agents",
				"note",
				"--project",
				project,
				"--actor",
				"supervisor",
				"--template",
				"handoff-review",
				"--session",
				sessionId,
				"--validate-link",
			],
			env,
		);
		expect(noteRes.status).toBe(0);

		const timelineRes = runYen(
			[
				"agents",
				"timeline",
				"--project",
				project,
				"--event",
				"note",
				"--format",
				"json",
			],
			env,
		);
		expect(timelineRes.status).toBe(0);
		const timelinePayload = JSON.parse(timelineRes.stdout);
		expect(timelinePayload.events).toHaveLength(1);
		expect(timelinePayload.events[0].note.sessionId).toBe(sessionId);
		expect(timelinePayload.events[0].note.slotId).toBe("claude");
		expect(timelinePayload.events[0].note.linkValidated).toBe(true);
	});

	test("agents timeline supports source-tag and note-kind filtering", () => {
		const mock = createMockAgentsBin();
		const project = createGitProject("yen-agents-timeline-filters-");
		const agentsStateDir = ideTemp("yen-agents-state-");
		const ideStateDir = ideTemp("yen-ide-state-");
		seedIdeEvidence(ideStateDir, project);

		const env = {
			PATH: `${mock.binDir}:${process.env.PATH ?? ""}`,
			YEN_AGENTS_STATE_DIR: agentsStateDir,
			YEN_IDE_STATE_DIR: ideStateDir,
		};

		expect(
			runYen(["agents", "open", "claude", "--project", project], env).status,
		).toBe(0);
		expect(
			runYen(
				[
					"agents",
					"note",
					"--project",
					project,
					"--actor",
					"human",
					"--kind",
					"approval",
					"--decision",
					"approved",
					"--slot",
					"supervisor",
					"--message",
					"Ship it",
				],
				env,
			).status,
		).toBe(0);

		const allRes = runYen(
			["agents", "timeline", "--project", project, "--format", "json"],
			env,
		);
		expect(allRes.status).toBe(0);
		const allPayload = JSON.parse(allRes.stdout);
		expect(allPayload.events).toHaveLength(3);
		expect(allPayload.events[0].sourceTag).toBe("agent:claude");
		expect(allPayload.events[1].sourceTag).toBe("agent:claude");
		expect(allPayload.events[2].sourceTag).toBe("human");

		const humanRes = runYen(
			[
				"agents",
				"timeline",
				"--project",
				project,
				"--format",
				"json",
				"--source",
				"human",
			],
			env,
		);
		expect(humanRes.status).toBe(0);
		const humanPayload = JSON.parse(humanRes.stdout);
		expect(humanPayload.events).toHaveLength(1);
		expect(humanPayload.events[0].event).toBe("note");
		expect(humanPayload.events[0].note.kind).toBe("approval");

		const agentRes = runYen(
			[
				"agents",
				"timeline",
				"--project",
				project,
				"--format",
				"json",
				"--source",
				"agent:claude",
			],
			env,
		);
		expect(agentRes.status).toBe(0);
		const agentPayload = JSON.parse(agentRes.stdout);
		expect(agentPayload.events).toHaveLength(2);
		expect(
			agentPayload.events.every(
				(event: { sourceTag: string }) => event.sourceTag === "agent:claude",
			),
		).toBe(true);

		const approvalRes = runYen(
			[
				"agents",
				"timeline",
				"--project",
				project,
				"--format",
				"json",
				"--event",
				"note",
				"--kind",
				"approval",
				"--tail",
				"1",
			],
			env,
		);
		expect(approvalRes.status).toBe(0);
		const approvalPayload = JSON.parse(approvalRes.stdout);
		expect(approvalPayload.events).toHaveLength(1);
		expect(approvalPayload.events[0].status).toBe("approval=approved");
		expect(approvalPayload.events[0].note.message).toBe("Ship it");
	});

	test("agents export captures a real multi-slot workspace with supervisor context", () => {
		const mock = createMockAgentsBin();
		const project = createGitProject("yen-agents-multi-slot-");
		const agentsStateDir = ideTemp("yen-agents-state-");
		const ideStateDir = ideTemp("yen-ide-state-");
		seedIdeEvidence(ideStateDir, project);
		seedLinkedIdeArtifacts(ideStateDir, project);

		const env = {
			PATH: `${mock.binDir}:${process.env.PATH ?? ""}`,
			YEN_AGENTS_STATE_DIR: agentsStateDir,
			YEN_IDE_STATE_DIR: ideStateDir,
		};

		expect(
			runYen(["agents", "open", "claude", "--project", project], env).status,
		).toBe(0);
		expect(
			runYen(["agents", "open", "codex", "--project", project], env).status,
		).toBe(0);
		expect(
			runYen(
				[
					"agents",
					"note",
					"--project",
					project,
					"--actor",
					"supervisor",
					"--kind",
					"approval",
					"--decision",
					"approved",
					"--slot",
					"supervisor",
					"--message",
					"Supervisor reviewed the pair-coding handoff.",
				],
				env,
			).status,
		).toBe(0);

		const exportRes = runYen(
			[
				"agents",
				"export",
				"--project",
				project,
				"--format",
				"json",
				"--output",
				"-",
			],
			env,
		);
		expect(exportRes.status).toBe(0);

		const payload = JSON.parse(exportRes.stdout);
		expect(payload.events).toHaveLength(5);
		expect(payload.adapters).toHaveLength(2);
		expect(
			payload.adapters.map((adapter: { name: string }) => adapter.name).sort(),
		).toEqual(["claude", "codex"]);
		expect(
			payload.adapters.every(
				(adapter: { sessionCount: number }) => adapter.sessionCount === 1,
			),
		).toBe(true);
		expect(payload.approvals).toHaveLength(1);
		expect(payload.approvals[0].actor).toBe("supervisor");
		expect(payload.approvals[0].slotId).toBe("supervisor");
		expect(payload.evidenceGaps).not.toContain(
			"human-approvals:missing-report",
		);
		expect(
			payload.events.some(
				(event: { sourceTag: string }) => event.sourceTag === "agent:claude",
			),
		).toBe(true);
		expect(
			payload.events.some(
				(event: { sourceTag: string }) => event.sourceTag === "agent:codex",
			),
		).toBe(true);
		expect(
			payload.events.some(
				(event: { sourceTag: string }) => event.sourceTag === "supervisor",
			),
		).toBe(true);
	});

	test("agents export json to stdout includes machine-readable repo snapshot and risks", () => {
		const mock = createMockAgentsBin();
		const project = createGitProject("yen-agents-export-json-");
		const agentsStateDir = ideTemp("yen-agents-state-");
		const ideStateDir = ideTemp("yen-ide-state-");
		seedIdeEvidence(ideStateDir, project);

		writeFileSync(
			join(project, "package.json"),
			'{"name":"agents-fixture","dependencies":{"zod":"4.0.0"}}\n',
			"utf8",
		);

		const env = {
			PATH: `${mock.binDir}:${process.env.PATH ?? ""}`,
			YEN_AGENTS_STATE_DIR: agentsStateDir,
			YEN_IDE_STATE_DIR: ideStateDir,
		};

		expect(
			runYen(["agents", "open", "claude", "--project", project], env).status,
		).toBe(0);

		const exportRes = runYen(
			[
				"agents",
				"export",
				"--project",
				project,
				"--format",
				"json",
				"--output",
				"-",
			],
			env,
		);
		expect(exportRes.status).toBe(0);

		const payload = JSON.parse(exportRes.stdout);
		expect(payload.schemaVersion).toBe(1);
		expect(payload.schemaKind).toBe("agents-export");
		expect(payload.schemas.adapter).toBe(1);
		expect(payload.schemas.event).toBe(1);
		expect(payload.schemas.linkedEvidence).toBe(1);
		expect(payload.schemas.note).toBe(1);
		expect(payload.eventTaxonomy.stableSourceKinds).toContain("supervisor");
		expect(payload.projectRoot).toBe(project);
		expect(payload.repoSnapshot.branch).toBe("main");
		expect(payload.repoSnapshot.dirtyState).toBe("dirty");
		expect(payload.repoSnapshot.contextKey).toBe(
			`${payload.workspaceIdentity}|${payload.repoSnapshot.branch}|${payload.repoSnapshot.shortHead}`,
		);
		expect(payload.repoSnapshot.changedFiles.length).toBeGreaterThan(0);
		expect(payload.adapters[0].name).toBe("claude");
		expect(payload.adapters[0].status).toBe("ready");
		expect(payload.adapters[0].version).toBe("claude 1.2.3");
		expect(payload.adapters[0].binaryPath).toBe(join(mock.binDir, "claude"));
		expect(payload.adapters[0].probeCommand).toBe("claude --version");
		expect(payload.adapters[0].probeStatus).toBe("ready");
		expect(payload.adapters[0].probeVersion).toBe("claude 1.2.3");
		expect(payload.adapters[0].declaredCapabilities).toBe(
			"chat,edit,exec,review",
		);
		expect(payload.adapters[0].capabilitiesList).toEqual([
			"chat",
			"edit",
			"exec",
			"review",
		]);
		expect(payload.adapters[0].sessionCount).toBe(1);
		expect(payload.adapters[0].latestSession.launchResult).toBe("launched");
		expect(payload.adapters[0].latestSession.fallbackState).toBe("none");
		expect(payload.adapters[0].latestSession.exitCode).toBe(0);
		expect(payload.verification.verify.status).toBe("passing");
		expect(payload.verification.test.status).toBe("passing");
		expect(payload.evidenceStatus.schemaVersion).toBe(1);
		expect(payload.evidenceStatus.overall.label).toBe("exported-with-gaps");
		expect(payload.evidenceStatus.artifacts["merge-readiness"].label).toBe(
			"missing-report",
		);
		expect(payload.linkedEvidence.schemaVersion).toBe(1);
		expect(payload.linkedEvidence.prReview.available).toBe(false);
		expect(
			payload.riskFlags.some(
				(flag: { id: string }) => flag.id === "dependency-change",
			),
		).toBe(true);
		expect(payload.riskSummary.ids).toContain("dirty-worktree");
		expect(payload.riskSummary.ids).toContain("dependency-change");
		expect(payload.evidenceGaps).toContain("human-approvals:missing-report");
		expect(payload.events).toHaveLength(2);
		expect(payload.events[0].eventFamily).toBe("session");
		expect(payload.events[0].source.kind).toBe("agent");
		expect(payload.events[0].target.kind).toBe("slot");

		const timelineRes = runYen(
			["agents", "timeline", "--project", project, "--format", "json"],
			env,
		);
		expect(timelineRes.status).toBe(0);
		const timelinePayload = JSON.parse(timelineRes.stdout);
		expect(timelinePayload.events).toHaveLength(3);
		expect(timelinePayload.events[2].event).toBe("export");
		expect(timelinePayload.events[2].status).toBe("format=json");
	});

	test("agents timeline and export link merge-readiness PR review and current-branch CI artifacts", () => {
		const mock = createMockAgentsBin();
		const project = createGitProject("yen-agents-linked-evidence-");
		const agentsStateDir = ideTemp("yen-agents-state-");
		const ideStateDir = ideTemp("yen-ide-state-");
		seedIdeEvidence(ideStateDir, project);
		const linkedArtifacts = seedLinkedIdeArtifacts(ideStateDir, project);

		const env = {
			PATH: `${mock.binDir}:${process.env.PATH ?? ""}`,
			YEN_AGENTS_STATE_DIR: agentsStateDir,
			YEN_IDE_STATE_DIR: ideStateDir,
		};

		expect(
			runYen(["agents", "open", "claude", "--project", project], env).status,
		).toBe(0);

		const timelineJson = runYen(
			["agents", "timeline", "--project", project, "--format", "json"],
			env,
		);
		expect(timelineJson.status).toBe(0);
		const timelinePayload = JSON.parse(timelineJson.stdout);
		expect(timelinePayload.evidenceStatus.artifacts.quality.label).toBe(
			"available",
		);
		expect(timelinePayload.evidenceStatus.artifacts.workflow.label).toBe(
			"available",
		);
		expect(
			timelinePayload.evidenceStatus.artifacts["merge-readiness"].label,
		).toBe("available");
		expect(timelinePayload.evidenceStatus.artifacts["pr-review"].label).toBe(
			"available",
		);
		expect(timelinePayload.linkedEvidence.mergeReadiness.available).toBe(true);
		expect(timelinePayload.linkedEvidence.mergeReadiness.prNumber).toBe(123);
		expect(timelinePayload.linkedEvidence.mergeReadiness.verifyStatus).toBe(
			"passing",
		);
		expect(timelinePayload.linkedEvidence.quality.available).toBe(true);
		expect(timelinePayload.linkedEvidence.quality.action).toBe("lint");
		expect(timelinePayload.linkedEvidence.quality.candidate).toBe("biome");
		expect(timelinePayload.linkedEvidence.quality.summaryPath).toBe(
			linkedArtifacts.qualitySummary,
		);
		expect(timelinePayload.linkedEvidence.quality.detailsPath).toBe(
			linkedArtifacts.qualityDetails,
		);
		expect(timelinePayload.linkedEvidence.quality.semanticPath).toBe(
			linkedArtifacts.qualitySemantic,
		);
		expect(timelinePayload.linkedEvidence.workflow.available).toBe(true);
		expect(timelinePayload.linkedEvidence.workflow.name).toBe("check");
		expect(timelinePayload.linkedEvidence.workflow.kind).toBe("native");
		expect(timelinePayload.linkedEvidence.workflow.summaryPath).toBe(
			linkedArtifacts.workflowSummary,
		);
		expect(timelinePayload.linkedEvidence.workflow.detailsPath).toBe(
			linkedArtifacts.workflowDetails,
		);
		expect(timelinePayload.linkedEvidence.workflow.semanticPath).toBe(
			linkedArtifacts.workflowSemantic,
		);
		expect(timelinePayload.linkedEvidence.prReview.available).toBe(true);
		expect(timelinePayload.linkedEvidence.prReview.evidenceBundle.path).toBe(
			linkedArtifacts.evidencePath,
		);
		expect(
			timelinePayload.linkedEvidence.prReview.evidenceBundle.semanticLocation
				.target,
		).toBe("src/a.ts:12");
		expect(
			timelinePayload.linkedEvidence.prReview.evidenceBundle.pathExists,
		).toBe(true);
		expect(timelinePayload.linkedEvidence.prReview.decision.artifactPath).toBe(
			linkedArtifacts.decisionPath,
		);
		expect(
			timelinePayload.linkedEvidence.prReview.decision.semanticLocation.target,
		).toBe("src/a.ts:12");
		expect(
			timelinePayload.linkedEvidence.prReview.decision.artifactPathExists,
		).toBe(true);
		expect(
			timelinePayload.linkedEvidence.prReview.inlineComment.artifactPath,
		).toBe(linkedArtifacts.inlinePath);
		expect(
			timelinePayload.linkedEvidence.prReview.inlineComment.semanticLocation
				.target,
		).toBe("src/a.ts:12");
		expect(
			timelinePayload.linkedEvidence.prReview.inlineComment.artifactPathExists,
		).toBe(true);
		expect(timelinePayload.linkedEvidence.currentBranchCi.available).toBe(true);
		expect(timelinePayload.linkedEvidence.currentBranchCi.checksState).toBe(
			"passing",
		);
		expect(timelinePayload.linkedEvidence.localBuildWatch.available).toBe(true);
		expect(timelinePayload.linkedEvidence.localBuildWatch.state).toBe(
			"max-runs",
		);
		expect(timelinePayload.linkedEvidence.localBuildWatch.kind).toBe("verify");
		expect(timelinePayload.repoSnapshot.contextKey).toBe(
			`${timelinePayload.workspaceIdentity}|${timelinePayload.repoSnapshot.branch}|${timelinePayload.repoSnapshot.shortHead}`,
		);
		expect(timelinePayload.riskSummary.count).toBe(0);
		expect(timelinePayload.riskSummary.summaryText).toBe("none");

		const timelineText = runYen(
			["agents", "timeline", "--project", project],
			env,
		);
		expect(timelineText.status).toBe(0);
		const timelineOutput = `${timelineText.stdout ?? ""}\n${timelineText.stderr ?? ""}`;
		expect(timelineOutput).toContain(
			`Context:      ${timelinePayload.repoSnapshot.contextKey}`,
		);
		expect(timelineOutput).toContain("Risks:        none");
		expect(timelineOutput).toContain(
			`Quality Link: yes | action=lint | candidate=biome | scope=workspace | summary=${linkedArtifacts.qualitySummary}`,
		);
		expect(timelineOutput).toContain(
			`Workflow Link: yes | name=check | kind=native | location=local | summary=${linkedArtifacts.workflowSummary}`,
		);
		expect(timelineOutput).toContain(
			"Merge Link:   yes | pr=123 | verify=passing",
		);
		expect(timelineOutput).toContain(
			"Review Link:  yes | pr=123 | file=src/a.ts | target=src/a.ts:12",
		);
		expect(timelineOutput).toContain(
			`Review Dec.:  yes | mode=comment | target=src/a.ts:12 | artifact=${linkedArtifacts.decisionPath}`,
		);
		expect(timelineOutput).toContain(
			`Review Inline: yes | target=src/a.ts:12 | path=src/a.ts | line=12 | side=RIGHT | artifact=${linkedArtifacts.inlinePath}`,
		);
		expect(timelineOutput).toContain(
			"Current CI:   yes | state=passing | pr=123",
		);
		expect(timelineOutput).toContain(
			"Build Watch:  yes | state=max-runs | kind=verify",
		);

		const exportJson = runYen(
			[
				"agents",
				"export",
				"--project",
				project,
				"--format",
				"json",
				"--output",
				"-",
			],
			env,
		);
		expect(exportJson.status).toBe(0);
		const exportPayload = JSON.parse(exportJson.stdout);
		expect(exportPayload.schemas.linkedEvidence).toBe(1);
		expect(exportPayload.linkedEvidence.quality.summaryPath).toBe(
			linkedArtifacts.qualitySummary,
		);
		expect(exportPayload.linkedEvidence.workflow.summaryPath).toBe(
			linkedArtifacts.workflowSummary,
		);
		expect(exportPayload.linkedEvidence.mergeReadiness.available).toBe(true);
		expect(exportPayload.linkedEvidence.prReview.available).toBe(true);
		expect(exportPayload.repoSnapshot.contextKey).toBe(
			`${exportPayload.workspaceIdentity}|${exportPayload.repoSnapshot.branch}|${exportPayload.repoSnapshot.shortHead}`,
		);
		expect(exportPayload.riskSummary.count).toBe(0);
		expect(exportPayload.riskSummary.summaryText).toBe("none");
		expect(exportPayload.linkedEvidence.prReview.decision.artifactPath).toBe(
			linkedArtifacts.decisionPath,
		);
		expect(
			exportPayload.linkedEvidence.prReview.decision.semanticLocation.target,
		).toBe("src/a.ts:12");
		expect(
			exportPayload.linkedEvidence.prReview.inlineComment.artifactPath,
		).toBe(linkedArtifacts.inlinePath);
		expect(
			exportPayload.linkedEvidence.prReview.inlineComment.semanticLocation
				.target,
		).toBe("src/a.ts:12");
		expect(exportPayload.linkedEvidence.currentBranchCi.prNumber).toBe(123);
		expect(exportPayload.linkedEvidence.localBuildWatch.lastOutcome).toBe(
			"passing",
		);

		const exportMarkdown = runYen(
			["agents", "export", "--project", project],
			env,
		);
		expect(exportMarkdown.status).toBe(0);
		const exportPath =
			`${exportMarkdown.stdout ?? ""}\n${exportMarkdown.stderr ?? ""}`
				.trim()
				.split("Wrote agent export bundle: ")
				.pop();
		expect(exportPath).toBeTruthy();
		if (!exportPath) throw new Error("exportPath missing");
		const bundle = readFileSync(exportPath, "utf8");
		expect(bundle).toContain("## Linked IDE Evidence");
		expect(bundle).toContain(
			`- Quality reports: available | last=${RECENT}T10:06:10Z | action=lint | candidate=biome | scope=workspace | summary=${linkedArtifacts.qualitySummary} | details=${linkedArtifacts.qualityDetails} | semantic=${linkedArtifacts.qualitySemantic}`,
		);
		expect(bundle).toContain(
			`- Workflow reports: available | last=${RECENT}T10:06:20Z | name=check | kind=native | location=local | summary=${linkedArtifacts.workflowSummary} | details=${linkedArtifacts.workflowDetails} | semantic=${linkedArtifacts.workflowSemantic}`,
		);
		expect(bundle).toContain(
			`- Context key: ${exportPayload.repoSnapshot.contextKey}`,
		);
		expect(bundle).toContain("- Merge readiness: available");
		expect(bundle).toContain("- PR review: available | ");
		expect(bundle).toContain("pr=123 | file=src/a.ts | target=src/a.ts:12");
		expect(bundle).toContain(`bundle=${linkedArtifacts.evidencePath}`);
		expect(bundle).toContain(
			`- PR review decision: available | mode=comment | target=src/a.ts:12 | artifact=${linkedArtifacts.decisionPath}`,
		);
		expect(bundle).toContain(
			`- PR review inline: available | target=src/a.ts:12 | path=src/a.ts | line=12 | side=RIGHT | artifact=${linkedArtifacts.inlinePath}`,
		);
		expect(bundle).toContain("- Summary: none | count=0");
		expect(bundle).toContain("- Current branch CI: available");
		expect(bundle).toContain("- Local build watch: available");
	});

	test("agents linked evidence keeps PR review artifacts scoped to the latest PR context", () => {
		const mock = createMockAgentsBin();
		const project = createGitProject("yen-agents-linked-evidence-scope-");
		const agentsStateDir = ideTemp("yen-agents-state-");
		const ideStateDir = ideTemp("yen-ide-state-");
		const evidenceDir = join(ideStateDir, "evidence");
		const timelinePath = join(ideStateDir, "timeline.log");
		const latestDecisionPath = join(
			evidenceDir,
			`pr-456-decision-comment-${RECENT_COMPACT}T101000Z.md`,
		);
		const latestInlinePath = join(
			evidenceDir,
			`pr-456-inline-${RECENT_COMPACT}T101001Z.md`,
		);

		seedIdeEvidence(ideStateDir, project);
		seedLinkedIdeArtifacts(ideStateDir, project);
		writeFileSync(latestDecisionPath, "# PR 456 decision\n", "utf8");
		writeFileSync(latestInlinePath, "# PR 456 inline\n", "utf8");
		writeFileSync(
			timelinePath,
			[
				readFileSync(timelinePath, "utf8").trimEnd(),
				`${RECENT}T10:10:00Z\tpr-decision\t${project}\tpr=456;mode=comment\tfile=src/b.ts;target=src/b.ts:42;post=no;artifact=${latestDecisionPath}`,
				`${RECENT}T10:10:01Z\tpr-inline-comment\t${project}\tpr=456;posted=no\tpath=src/b.ts;line=42;side=RIGHT;artifact=${latestInlinePath}`,
			]
				.filter(Boolean)
				.join("\n"),
			"utf8",
		);

		const env = {
			PATH: `${mock.binDir}:${process.env.PATH ?? ""}`,
			YEN_AGENTS_STATE_DIR: agentsStateDir,
			YEN_IDE_STATE_DIR: ideStateDir,
		};

		expect(
			runYen(["agents", "open", "claude", "--project", project], env).status,
		).toBe(0);

		const timelineJson = runYen(
			["agents", "timeline", "--project", project, "--format", "json"],
			env,
		);
		expect(timelineJson.status).toBe(0);
		const timelinePayload = JSON.parse(timelineJson.stdout);
		expect(timelinePayload.linkedEvidence.prReview.prNumber).toBe(456);
		expect(timelinePayload.linkedEvidence.prReview.lastReview.available).toBe(
			false,
		);
		expect(
			timelinePayload.linkedEvidence.prReview.evidenceBundle.available,
		).toBe(false);
		expect(timelinePayload.linkedEvidence.prReview.decision.artifactPath).toBe(
			latestDecisionPath,
		);
		expect(
			timelinePayload.linkedEvidence.prReview.inlineComment.artifactPath,
		).toBe(latestInlinePath);
	});

	test("agents linked evidence prefers the latest reusable quality and workflow reports", () => {
		const mock = createMockAgentsBin();
		const project = createGitProject("yen-agents-linked-report-preferred-");
		const agentsStateDir = ideTemp("yen-agents-state-");
		const ideStateDir = ideTemp("yen-ide-state-");
		const timelinePath = join(ideStateDir, "timeline.log");
		const linkedArtifacts = seedLinkedIdeArtifacts(ideStateDir, project);

		writeFileSync(
			timelinePath,
			[
				readFileSync(timelinePath, "utf8").trimEnd(),
				`${RECENT}T10:09:00Z\tquality\t${project}\tblocked\taction=lint;candidate=biome;scope=workspace;reason=approval-denied`,
				`${RECENT}T10:09:10Z\tworkflow\t${project}\tdry-run\tname=check;kind=native;location=local;mode=dry-run`,
			]
				.filter(Boolean)
				.join("\n"),
			"utf8",
		);

		const env = {
			PATH: `${mock.binDir}:${process.env.PATH ?? ""}`,
			YEN_AGENTS_STATE_DIR: agentsStateDir,
			YEN_IDE_STATE_DIR: ideStateDir,
		};

		expect(
			runYen(["agents", "open", "claude", "--project", project], env).status,
		).toBe(0);

		const timelineJson = runYen(
			["agents", "timeline", "--project", project, "--format", "json"],
			env,
		);
		expect(timelineJson.status).toBe(0);
		const timelinePayload = JSON.parse(timelineJson.stdout);
		expect(timelinePayload.evidenceStatus.artifacts.quality.label).toBe(
			"available",
		);
		expect(timelinePayload.evidenceStatus.artifacts.workflow.label).toBe(
			"available",
		);
		expect(timelinePayload.linkedEvidence.quality.summaryPath).toBe(
			linkedArtifacts.qualitySummary,
		);
		expect(timelinePayload.linkedEvidence.workflow.summaryPath).toBe(
			linkedArtifacts.workflowSummary,
		);
	});

	test("agents timeline and export stay honest when no prior local evidence exists", () => {
		const mock = createMockAgentsBin();
		const project = createGitProject("yen-agents-no-prior-evidence-");
		const agentsStateDir = ideTemp("yen-agents-state-");
		const ideStateDir = ideTemp("yen-ide-state-");

		const env = {
			PATH: `${mock.binDir}:${process.env.PATH ?? ""}`,
			YEN_AGENTS_STATE_DIR: agentsStateDir,
			YEN_IDE_STATE_DIR: ideStateDir,
		};

		expect(
			runYen(["agents", "open", "claude", "--project", project], env).status,
		).toBe(0);

		const timelineRes = runYen(
			["agents", "timeline", "--project", project, "--format", "json"],
			env,
		);
		expect(timelineRes.status).toBe(0);
		const timelinePayload = JSON.parse(timelineRes.stdout);
		expect(timelinePayload.evidence.verify.status).toBe("never-run");
		expect(timelinePayload.evidence.test.status).toBe("never-run");
		expect(timelinePayload.evidenceStatus.artifacts.verify.label).toBe(
			"unverified",
		);
		expect(timelinePayload.evidenceStatus.artifacts.test.label).toBe(
			"unverified",
		);
		expect(timelinePayload.evidenceStatus.artifacts.quality.label).toBe(
			"missing-report",
		);
		expect(timelinePayload.evidenceStatus.artifacts.workflow.label).toBe(
			"missing-report",
		);
		expect(timelinePayload.linkedEvidence.quality.available).toBe(false);
		expect(timelinePayload.linkedEvidence.workflow.available).toBe(false);
		expect(timelinePayload.linkedEvidence.mergeReadiness.available).toBe(false);
		expect(timelinePayload.linkedEvidence.prReview.available).toBe(false);
		expect(timelinePayload.linkedEvidence.currentBranchCi.available).toBe(
			false,
		);
		expect(timelinePayload.linkedEvidence.localBuildWatch.available).toBe(
			false,
		);

		const exportRes = runYen(
			[
				"agents",
				"export",
				"--project",
				project,
				"--format",
				"json",
				"--output",
				"-",
			],
			env,
		);
		expect(exportRes.status).toBe(0);
		const exportPayload = JSON.parse(exportRes.stdout);
		expect(exportPayload.evidenceGaps).toContain("verify:unverified");
		expect(exportPayload.evidenceGaps).toContain("test:unverified");
		expect(exportPayload.evidenceGaps).toContain("quality:missing-report");
		expect(exportPayload.evidenceGaps).toContain("workflow:missing-report");
		expect(exportPayload.linkedEvidence.quality.summaryPath).toBe("");
		expect(exportPayload.linkedEvidence.workflow.summaryPath).toBe("");
	});

	test("agents timeline marks stale local evidence explicitly", () => {
		const mock = createMockAgentsBin();
		const project = createProject("yen-agents-stale-evidence-");
		const agentsStateDir = ideTemp("yen-agents-state-");
		const ideStateDir = ideTemp("yen-ide-state-");
		mkdirSync(ideStateDir, { recursive: true });

		const verifySummary = join(ideStateDir, "verify-summary.tsv");
		const testSummary = join(ideStateDir, "test-summary.tsv");
		writeFileSync(verifySummary, "target\tstatus\n", "utf8");
		writeFileSync(testSummary, "target\tstatus\n", "utf8");
		writeFileSync(
			join(ideStateDir, "timeline.log"),
			[
				`2020-01-01T00:00:00Z\tverify\t${project}\tfailures=0;warns=0\tsummary=${verifySummary};semantic=old-verify`,
				`2020-01-01T00:05:00Z\ttest\t${project}\tfailures=0;warns=0\tsummary=${testSummary};semantic=old-test`,
			].join("\n"),
			"utf8",
		);

		const env = {
			PATH: `${mock.binDir}:${process.env.PATH ?? ""}`,
			YEN_AGENTS_STATE_DIR: agentsStateDir,
			YEN_IDE_STATE_DIR: ideStateDir,
		};

		expect(
			runYen(["agents", "open", "claude", "--project", project], env).status,
		).toBe(0);

		const timelineRes = runYen(
			["agents", "timeline", "--project", project, "--format", "json"],
			env,
		);
		expect(timelineRes.status).toBe(0);
		const payload = JSON.parse(timelineRes.stdout);
		expect(payload.evidenceStatus.artifacts.verify.label).toBe("stale-report");
		expect(payload.evidenceStatus.artifacts.test.label).toBe("stale-report");

		const exportRes = runYen(
			[
				"agents",
				"export",
				"--project",
				project,
				"--format",
				"json",
				"--output",
				"-",
			],
			env,
		);
		expect(exportRes.status).toBe(0);
		const exportPayload = JSON.parse(exportRes.stdout);
		expect(exportPayload.evidenceGaps).toContain("verify:stale-report");
		expect(exportPayload.evidenceGaps).toContain("test:stale-report");
	});

	test("agents export keeps explicit fail-open adapter metadata when only fallback session state exists", () => {
		const project = createProject("yen-agents-fallback-export-");
		const agentsStateDir = ideTemp("yen-agents-state-");
		const env = {
			YEN_AGENTS_STATE_DIR: agentsStateDir,
		};

		const timelineBootstrap = runYen(
			["agents", "timeline", "--project", project, "--format", "json"],
			env,
		);
		expect(timelineBootstrap.status).toBe(0);
		const workspaceIdentity = JSON.parse(
			timelineBootstrap.stdout,
		).workspaceIdentity;

		const sessionId = "agt-20260328T120500Z-12345-000123";
		const sessionStartedAt = isoTimestamp(
			new Date(Date.now() - 2 * ONE_HOUR_MS),
		);
		const sessionStoppedAt = isoTimestamp(new Date(Date.now() - ONE_HOUR_MS));
		const sessionsDir = join(agentsStateDir, "sessions");
		mkdirSync(sessionsDir, { recursive: true });
		writeFileSync(
			join(sessionsDir, `${sessionId}.state`),
			[
				`session_id=${sessionId}`,
				"slot_id=claude",
				"adapter=claude",
				`workspace_identity=${workspaceIdentity}`,
				`project_root=${project}`,
				"branch=-",
				"dirty_state=not-git",
				"launch_mode=shell-fallback",
				"lifecycle_state=stopped",
				`started_at=${sessionStartedAt}`,
				`stopped_at=${sessionStoppedAt}`,
				"exit_code=0",
				"binary_name=claude",
				"binary_path=",
				"probe_command=claude --version",
				"probe_status=missing",
				"probe_version=-",
				"declared_capabilities=chat,edit,exec,review",
				"launch_result=fallback",
				"fallback_state=binary-missing",
			].join("\n"),
			"utf8",
		);

		writeFileSync(
			join(agentsStateDir, "timeline.log"),
			[
				`${sessionStartedAt}\tsession-start\t${project}\tfallback\tsession=${sessionId};slot=claude;adapter=claude;branch=-;dirty=not-git;launch_mode=shell-fallback;workspace_identity=${workspaceIdentity}`,
				`${sessionStoppedAt}\tsession-stop\t${project}\tstatus=success;exit=0\tsession=${sessionId};slot=claude;adapter=claude;branch=-;dirty=not-git;launch_mode=shell-fallback;workspace_identity=${workspaceIdentity}`,
			].join("\n"),
			"utf8",
		);

		const exportRes = runYen(
			[
				"agents",
				"export",
				"--project",
				project,
				"--format",
				"json",
				"--output",
				"-",
			],
			env,
		);
		expect(exportRes.status).toBe(0);
		const payload = JSON.parse(exportRes.stdout);
		expect(payload.adapters).toHaveLength(1);
		expect(payload.adapters[0].name).toBe("claude");
		expect(payload.adapters[0].status).toBe("missing");
		expect(payload.adapters[0].version).toBe("-");
		expect(payload.adapters[0].probeStatus).toBe("missing");
		expect(payload.adapters[0].binaryPath).toBe("");
		expect(payload.adapters[0].latestSession.launchMode).toBe("shell-fallback");
		expect(payload.adapters[0].latestSession.launchResult).toBe("fallback");
		expect(payload.adapters[0].latestSession.fallbackState).toBe(
			"binary-missing",
		);
		expect(payload.events[0].sessionState.launchResult).toBe("fallback");
		expect(payload.events[0].sessionState.fallbackState).toBe("binary-missing");
	});

	test("agents export keeps adapter metadata when session state exists outside the default timeline tail", () => {
		const project = createProject("yen-agents-export-tail-metadata-");
		const agentsStateDir = ideTemp("yen-agents-state-");
		const env = {
			YEN_AGENTS_STATE_DIR: agentsStateDir,
		};

		const timelineBootstrap = runYen(
			["agents", "timeline", "--project", project, "--format", "json"],
			env,
		);
		expect(timelineBootstrap.status).toBe(0);
		const workspaceIdentity = JSON.parse(
			timelineBootstrap.stdout,
		).workspaceIdentity;

		const sessionId = "agt-20260328T121500Z-12345-000321";
		const sessionStartedAt = isoTimestamp(
			new Date(Date.now() - 3 * ONE_HOUR_MS),
		);
		const sessionStoppedAt = isoTimestamp(
			new Date(Date.now() - 2 * ONE_HOUR_MS),
		);
		const sessionsDir = join(agentsStateDir, "sessions");
		mkdirSync(sessionsDir, { recursive: true });
		writeFileSync(
			join(sessionsDir, `${sessionId}.state`),
			[
				`session_id=${sessionId}`,
				"slot_id=codex",
				"adapter=codex",
				`workspace_identity=${workspaceIdentity}`,
				`project_root=${project}`,
				"branch=-",
				"dirty_state=not-git",
				"launch_mode=adapter",
				"lifecycle_state=stopped",
				`started_at=${sessionStartedAt}`,
				`stopped_at=${sessionStoppedAt}`,
				"exit_code=0",
				"binary_name=codex",
				"binary_path=/tmp/mock-codex",
				"probe_command=codex --version",
				"probe_status=ready",
				"probe_version=codex 4.5.6",
				"declared_capabilities=chat,edit,exec,review",
				"launch_result=launched",
				"fallback_state=none",
			].join("\n"),
			"utf8",
		);

		const noteBaseTime = Date.now() - 90 * 60 * 1000;
		const noteLines = Array.from({ length: 45 }, (_, index) => {
			const noteTime = isoTimestamp(new Date(noteBaseTime + index * 60_000));
			return `${noteTime}\tnote\t${project}\tnote\tnote_id=agn-tail-${index};actor=human;kind=note;decision=;template=;link_validated=no;session=;slot=;workspace_identity=${workspaceIdentity}`;
		});

		writeFileSync(
			join(agentsStateDir, "timeline.log"),
			[
				`${sessionStartedAt}\tsession-start\t${project}\tlaunched\tsession=${sessionId};slot=codex;adapter=codex;branch=-;dirty=not-git;launch_mode=adapter;workspace_identity=${workspaceIdentity}`,
				`${sessionStoppedAt}\tsession-stop\t${project}\tstatus=success;exit=0\tsession=${sessionId};slot=codex;adapter=codex;branch=-;dirty=not-git;launch_mode=adapter;workspace_identity=${workspaceIdentity}`,
				...noteLines,
			].join("\n"),
			"utf8",
		);

		const exportRes = runYen(
			[
				"agents",
				"export",
				"--project",
				project,
				"--format",
				"json",
				"--output",
				"-",
			],
			env,
		);
		expect(exportRes.status).toBe(0);

		const payload = JSON.parse(exportRes.stdout);
		expect(payload.events).toHaveLength(40);
		expect(payload.events[0].event).toBe("note");
		expect(payload.adapters).toHaveLength(1);
		expect(payload.adapters[0].name).toBe("codex");
		expect(payload.adapters[0].status).toBe("ready");
		expect(payload.adapters[0].probeVersion).toBe("codex 4.5.6");
		expect(payload.adapters[0].binaryPath).toBe("/tmp/mock-codex");
		expect(payload.adapters[0].latestSession.sessionId).toBe(sessionId);
		expect(payload.adapters[0].latestSession.launchResult).toBe("launched");
	});

	test("agents export matches legacy project-root workspace session state outside the default timeline tail", () => {
		const project = createProject("yen-agents-export-tail-legacy-root-");
		const agentsStateDir = ideTemp("yen-agents-state-");
		const env = {
			YEN_AGENTS_STATE_DIR: agentsStateDir,
		};

		const sessionId = "agt-20260328T121600Z-12345-000654";
		const sessionStartedAt = isoTimestamp(
			new Date(Date.now() - 3 * ONE_HOUR_MS),
		);
		const sessionStoppedAt = isoTimestamp(
			new Date(Date.now() - 2 * ONE_HOUR_MS),
		);
		const sessionsDir = join(agentsStateDir, "sessions");
		mkdirSync(sessionsDir, { recursive: true });
		writeFileSync(
			join(sessionsDir, `${sessionId}.state`),
			[
				`session_id=${sessionId}`,
				"slot_id=claude",
				"adapter=claude",
				`workspace_identity=${project}`,
				`project_root=${project}`,
				"branch=-",
				"dirty_state=not-git",
				"launch_mode=shell-fallback",
				"lifecycle_state=stopped",
				`started_at=${sessionStartedAt}`,
				`stopped_at=${sessionStoppedAt}`,
				"exit_code=0",
				"binary_name=claude",
				"binary_path=",
				"probe_command=claude --version",
				"probe_status=missing",
				"probe_version=-",
				"declared_capabilities=chat,edit,exec,review",
				"launch_result=fallback",
				"fallback_state=binary-missing",
			].join("\n"),
			"utf8",
		);

		const noteBaseTime = Date.now() - 90 * 60 * 1000;
		const noteLines = Array.from({ length: 45 }, (_, index) => {
			const noteTime = isoTimestamp(new Date(noteBaseTime + index * 60_000));
			return `${noteTime}\tnote\t${project}\tnote\tnote_id=agn-legacy-tail-${index};actor=human;kind=note;decision=;template=;link_validated=no;session=;slot=;workspace_identity=${project}`;
		});

		writeFileSync(
			join(agentsStateDir, "timeline.log"),
			[
				`${sessionStartedAt}\tsession-start\t${project}\tfallback\tsession=${sessionId};slot=claude;adapter=claude;branch=-;dirty=not-git;launch_mode=shell-fallback;workspace_identity=${project}`,
				`${sessionStoppedAt}\tsession-stop\t${project}\tstatus=success;exit=0\tsession=${sessionId};slot=claude;adapter=claude;branch=-;dirty=not-git;launch_mode=shell-fallback;workspace_identity=${project}`,
				...noteLines,
			].join("\n"),
			"utf8",
		);

		const exportRes = runYen(
			[
				"agents",
				"export",
				"--project",
				project,
				"--format",
				"json",
				"--output",
				"-",
			],
			env,
		);
		expect(exportRes.status).toBe(0);

		const payload = JSON.parse(exportRes.stdout);
		expect(payload.adapters).toHaveLength(1);
		expect(payload.adapters[0].name).toBe("claude");
		expect(payload.adapters[0].status).toBe("missing");
		expect(payload.adapters[0].latestSession.sessionId).toBe(sessionId);
		expect(payload.adapters[0].latestSession.fallbackState).toBe(
			"binary-missing",
		);
	});

	test("agents export and timeline recover adapter metadata from retained lifecycle events when session files are missing", () => {
		const project = createProject("yen-agents-export-tail-timeline-only-");
		const agentsStateDir = ideTemp("yen-agents-state-");
		const env = {
			YEN_AGENTS_STATE_DIR: agentsStateDir,
		};

		const timelineBootstrap = runYen(
			["agents", "timeline", "--project", project, "--format", "json"],
			env,
		);
		expect(timelineBootstrap.status).toBe(0);
		const workspaceIdentity = JSON.parse(
			timelineBootstrap.stdout,
		).workspaceIdentity;

		const sessionId = "agt-20260328T121700Z-12345-000777";
		const sessionStartedAt = isoTimestamp(
			new Date(Date.now() - 3 * ONE_HOUR_MS),
		);
		const sessionStoppedAt = isoTimestamp(
			new Date(Date.now() - 2 * ONE_HOUR_MS),
		);
		const noteBaseTime = Date.now() - 90 * 60 * 1000;
		const noteLines = Array.from({ length: 45 }, (_, index) => {
			const noteTime = isoTimestamp(new Date(noteBaseTime + index * 60_000));
			return `${noteTime}\tnote\t${project}\tnote\tnote_id=agn-timeline-tail-${index};actor=human;kind=note;decision=;template=;link_validated=no;session=;slot=;workspace_identity=${workspaceIdentity}`;
		});

		writeFileSync(
			join(agentsStateDir, "timeline.log"),
			[
				`${sessionStartedAt}\tsession-start\t${project}\tfallback\tsession=${sessionId};slot=claude;adapter=claude;branch=-;dirty=not-git;launch_mode=shell-fallback;workspace_identity=${workspaceIdentity};started_at=${sessionStartedAt};binary_name=claude;binary_path=;probe_command=claude --version;probe_status=missing;probe_version=-;declared_capabilities=chat,edit,exec,review;launch_result=fallback;fallback_state=binary-missing`,
				`${sessionStoppedAt}\tsession-stop\t${project}\tstatus=success;exit=0\tsession=${sessionId};slot=claude;adapter=claude;branch=-;dirty=not-git;launch_mode=shell-fallback;workspace_identity=${workspaceIdentity};started_at=${sessionStartedAt};stopped_at=${sessionStoppedAt};binary_name=claude;binary_path=;probe_command=claude --version;probe_status=missing;probe_version=-;declared_capabilities=chat,edit,exec,review;launch_result=fallback;fallback_state=binary-missing`,
				...noteLines,
			].join("\n"),
			"utf8",
		);

		const sessionTimelineRes = runYen(
			[
				"agents",
				"timeline",
				"--project",
				project,
				"--event",
				"session-stop",
				"--format",
				"json",
			],
			env,
		);
		expect(sessionTimelineRes.status).toBe(0);
		const sessionTimelinePayload = JSON.parse(sessionTimelineRes.stdout);
		expect(sessionTimelinePayload.events).toHaveLength(1);
		expect(sessionTimelinePayload.events[0].sessionState.adapter).toBe(
			"claude",
		);
		expect(sessionTimelinePayload.events[0].sessionState.launchResult).toBe(
			"fallback",
		);
		expect(sessionTimelinePayload.events[0].sessionState.fallbackState).toBe(
			"binary-missing",
		);

		const exportRes = runYen(
			[
				"agents",
				"export",
				"--project",
				project,
				"--format",
				"json",
				"--output",
				"-",
			],
			env,
		);
		expect(exportRes.status).toBe(0);

		const payload = JSON.parse(exportRes.stdout);
		expect(payload.events).toHaveLength(40);
		expect(payload.events[0].event).toBe("note");
		expect(payload.adapters).toHaveLength(1);
		expect(payload.adapters[0].name).toBe("claude");
		expect(payload.adapters[0].status).toBe("missing");
		expect(payload.adapters[0].probeVersion).toBe("-");
		expect(payload.adapters[0].binaryPath).toBe("");
		expect(payload.adapters[0].latestSession.sessionId).toBe(sessionId);
		expect(payload.adapters[0].latestSession.launchMode).toBe("shell-fallback");
		expect(payload.adapters[0].latestSession.launchResult).toBe("fallback");
		expect(payload.adapters[0].latestSession.fallbackState).toBe(
			"binary-missing",
		);
	});

	test("agents note and export redact common secret patterns in saved artifacts", () => {
		const project = createGitProject("yen-agents-redaction-");
		const agentsStateDir = ideTemp("yen-agents-state-");
		const env = {
			YEN_AGENTS_STATE_DIR: agentsStateDir,
		};
		const rawSecretMessage = [
			"api_key=sk-proj-12345678901234567890ABCDEFGHIJK",
			"Authorization: Bearer ghp_1234567890abcdefghijklmnopqrstuvwxyz",
			"password=supersecret",
		].join("\n");

		const noteRes = runYen(
			[
				"agents",
				"note",
				"--project",
				project,
				"--actor",
				"human",
				"--kind",
				"note",
				"--message",
				rawSecretMessage,
			],
			env,
		);
		expect(noteRes.status).toBe(0);

		const noteStateFiles = readdirSync(join(agentsStateDir, "notes")).sort();
		const noteStatePath = join(
			agentsStateDir,
			"notes",
			noteStateFiles[0] ?? "",
		);
		const noteTextPath = join(agentsStateDir, "notes", noteStateFiles[1] ?? "");
		const noteState = readFileSync(noteStatePath, "utf8");
		const noteText = readFileSync(noteTextPath, "utf8");
		expect(noteState).not.toContain("sk-proj-12345678901234567890ABCDEFGHIJK");
		expect(noteText).not.toContain("sk-proj-12345678901234567890ABCDEFGHIJK");
		expect(noteText).not.toContain("ghp_1234567890abcdefghijklmnopqrstuvwxyz");
		expect(noteText).not.toContain("supersecret");
		expect(noteText).toContain("api_key=[REDACTED:secret]");
		expect(noteText).toContain("Authorization: Bearer [REDACTED:bearer-token]");
		expect(noteText).toContain("password=[REDACTED:secret]");

		const exportRes = runYen(
			[
				"agents",
				"export",
				"--project",
				project,
				"--format",
				"json",
				"--output",
				"-",
			],
			env,
		);
		expect(exportRes.status).toBe(0);
		expect(exportRes.stdout).not.toContain(
			"sk-proj-12345678901234567890ABCDEFGHIJK",
		);
		expect(exportRes.stdout).not.toContain(
			"ghp_1234567890abcdefghijklmnopqrstuvwxyz",
		);
		expect(exportRes.stdout).not.toContain("supersecret");

		const payload = JSON.parse(exportRes.stdout);
		expect(payload.notes).toHaveLength(1);
		expect(payload.notes[0].message).toContain("api_key=[REDACTED:secret]");
		expect(payload.notes[0].message).toContain(
			"Bearer [REDACTED:bearer-token]",
		);
		expect(payload.notes[0].message).toContain("password=[REDACTED:secret]");
	});

	test("agents retention prunes expired artifacts and archives them when configured", () => {
		const project = createProject("yen-agents-retention-");
		const agentsStateDir = ideTemp("yen-agents-state-");
		const archiveDir = ideTemp("yen-agents-archive-");
		const env = {
			YEN_AGENTS_STATE_DIR: agentsStateDir,
			YEN_AGENTS_ARCHIVE_DIR: archiveDir,
			YEN_AGENTS_RETENTION_DAYS: "7",
		};

		const sessionsDir = join(agentsStateDir, "sessions");
		const notesDir = join(agentsStateDir, "notes");
		const exportsDir = join(agentsStateDir, "exports");
		mkdirSync(sessionsDir, { recursive: true });
		mkdirSync(notesDir, { recursive: true });
		mkdirSync(exportsDir, { recursive: true });

		const expiredSessionPath = join(sessionsDir, "agt-expired.state");
		const expiredNoteStatePath = join(notesDir, "agn-expired.state");
		const expiredNoteTextPath = join(notesDir, "agn-expired.txt");
		const expiredExportPath = join(exportsDir, "agents-export-old.json");
		writeFileSync(expiredSessionPath, "session_id=agt-expired\n", "utf8");
		writeFileSync(expiredNoteStatePath, "note_id=agn-expired\n", "utf8");
		writeFileSync(expiredNoteTextPath, "old note\n", "utf8");
		writeFileSync(expiredExportPath, '{"old":true}\n', "utf8");

		const expiredTime = new Date(Date.now() - 30 * ONE_DAY_MS);
		const retainedTime = new Date(Date.now() - ONE_DAY_MS);
		const expiredTimestamp = isoTimestamp(expiredTime);
		const retainedTimestamp = isoTimestamp(retainedTime);
		const expiredTimelineEntry = `${expiredTimestamp}\tnote\t${project}\tnote\tnote_id=agn-expired;actor=human;kind=note;decision=;template=;link_validated=no;session=;slot=;workspace_identity=${project}`;
		const retainedTimelineEntry = `${retainedTimestamp}\texport\t${project}\tformat=json\tpath=-;workspace_identity=${project};limit=20`;
		utimesSync(expiredSessionPath, expiredTime, expiredTime);
		utimesSync(expiredNoteStatePath, expiredTime, expiredTime);
		utimesSync(expiredNoteTextPath, expiredTime, expiredTime);
		utimesSync(expiredExportPath, expiredTime, expiredTime);

		writeFileSync(
			join(agentsStateDir, "timeline.log"),
			[expiredTimelineEntry, retainedTimelineEntry].join("\n"),
			"utf8",
		);

		const timelineRes = runYen(
			["agents", "timeline", "--project", project, "--format", "json"],
			env,
		);
		expect(timelineRes.status).toBe(0);

		expect(existsSync(expiredSessionPath)).toBe(false);
		expect(existsSync(expiredNoteStatePath)).toBe(false);
		expect(existsSync(expiredNoteTextPath)).toBe(false);
		expect(existsSync(expiredExportPath)).toBe(false);
		expect(existsSync(join(archiveDir, "sessions", "agt-expired.state"))).toBe(
			true,
		);
		expect(existsSync(join(archiveDir, "notes", "agn-expired.state"))).toBe(
			true,
		);
		expect(existsSync(join(archiveDir, "notes", "agn-expired.txt"))).toBe(true);
		expect(
			existsSync(join(archiveDir, "exports", "agents-export-old.json")),
		).toBe(true);
		expect(
			readFileSync(join(archiveDir, "timeline", "timeline.log"), "utf8"),
		).toContain(expiredTimelineEntry);

		const retainedTimeline = readFileSync(
			join(agentsStateDir, "timeline.log"),
			"utf8",
		);
		expect(retainedTimeline).not.toContain(expiredTimelineEntry);
		expect(retainedTimeline).toContain(retainedTimelineEntry);
	});

	test("agents retention treats non-positive day overrides as the default window", () => {
		const project = createProject("yen-agents-retention-default-");
		const agentsStateDir = ideTemp("yen-agents-state-");
		const env = {
			YEN_AGENTS_STATE_DIR: agentsStateDir,
			YEN_AGENTS_RETENTION_DAYS: "0",
		};

		const notesDir = join(agentsStateDir, "notes");
		mkdirSync(notesDir, { recursive: true });

		const expiredNoteStatePath = join(notesDir, "agn-expired.state");
		const expiredNoteTextPath = join(notesDir, "agn-expired.txt");
		writeFileSync(expiredNoteStatePath, "note_id=agn-expired\n", "utf8");
		writeFileSync(expiredNoteTextPath, "old note\n", "utf8");

		const expiredTime = new Date(Date.now() - 30 * ONE_DAY_MS);
		utimesSync(expiredNoteStatePath, expiredTime, expiredTime);
		utimesSync(expiredNoteTextPath, expiredTime, expiredTime);

		const timelineRes = runYen(
			["agents", "timeline", "--project", project, "--format", "json"],
			env,
		);
		expect(timelineRes.status).toBe(0);
		expect(existsSync(expiredNoteStatePath)).toBe(false);
		expect(existsSync(expiredNoteTextPath)).toBe(false);
	});

	test("agents timeline preserves typed taxonomy for template-apply and export events", () => {
		const project = createProject("yen-agents-taxonomy-");
		const agentsStateDir = ideTemp("yen-agents-state-");
		const ideStateDir = ideTemp("yen-ide-state-");
		seedIdeEvidence(ideStateDir, project);

		const env = {
			YEN_AGENTS_STATE_DIR: agentsStateDir,
			YEN_IDE_STATE_DIR: ideStateDir,
		};

		expect(
			runYen(
				["agents", "templates", "apply", "pair-coding", "--project", project],
				env,
			).status,
		).toBe(0);
		expect(
			runYen(
				[
					"agents",
					"export",
					"--project",
					project,
					"--format",
					"json",
					"--output",
					"-",
				],
				env,
			).status,
		).toBe(0);

		const timelineRes = runYen(
			["agents", "timeline", "--project", project, "--format", "json"],
			env,
		);
		expect(timelineRes.status).toBe(0);
		const payload = JSON.parse(timelineRes.stdout);
		expect(payload.events).toHaveLength(2);
		expect(payload.events[0].event).toBe("template-apply");
		expect(payload.events[0].eventFamily).toBe("template");
		expect(payload.events[0].eventAction).toBe("apply");
		expect(payload.events[0].target.kind).toBe("template");
		expect(payload.events[0].source.kind).toBe("system");
		expect(payload.events[1].event).toBe("export");
		expect(payload.events[1].eventFamily).toBe("artifact");
		expect(payload.events[1].eventAction).toBe("export");
		expect(payload.events[1].eventOutcome).toBe("exported");
		expect(payload.events[1].source.kind).toBe("system");
	});
});
