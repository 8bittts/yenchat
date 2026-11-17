const CSP_HASH_PATTERN = /^sha256-[A-Za-z0-9+/]{43}=$/;

export function buildCSP(
	nonce?: string,
	scriptHashes: readonly string[] = [],
	allowUnsafeEval = false,
): string {
	const normalizedScriptHashes = Array.from(new Set(scriptHashes)).sort();
	for (const hash of normalizedScriptHashes) {
		if (!CSP_HASH_PATTERN.test(hash)) {
			throw new Error(`invalid CSP script hash: ${hash}`);
		}
	}
	const scriptSources = [
		"'self'",
		...(nonce ? [`'nonce-${nonce}'`] : []),
		...normalizedScriptHashes.map((hash) => `'${hash}'`),
		...(allowUnsafeEval ? ["'unsafe-eval'"] : []),
	];

	return [
		"default-src 'self'",
		`script-src ${scriptSources.join(" ")}`,
		"script-src-attr 'none'",
		"worker-src 'self' blob:",
		"style-src 'self' 'unsafe-inline'",
		"font-src 'self'",
		"img-src 'self' data:",
		"connect-src 'self' https://vitals.vercel-insights.com https://*.vercel-insights.com",
		"frame-src https://www.youtube-nocookie.com https://www.youtube.com",
		"frame-ancestors 'none'",
		"object-src 'none'",
		"base-uri 'self'",
		"form-action 'self'",
		"upgrade-insecure-requests",
	].join("; ");
}
