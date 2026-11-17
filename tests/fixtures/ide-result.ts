import type { SpawnSyncReturns } from "node:child_process";

export function ideCommandDiagnostics(
	result: SpawnSyncReturns<string>,
): string {
	return JSON.stringify(
		{
			status: result.status,
			signal: result.signal,
			error: result.error?.message,
			stdout: result.stdout,
			stderr: result.stderr,
		},
		null,
		2,
	);
}
