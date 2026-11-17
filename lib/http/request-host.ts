type HostResolutionInput = {
	forwardedHostHeader?: string | null;
	hostHeader?: string | null;
	nextUrlHost?: string | null;
	requestUrl?: string | null;
};

export type RequestHostResolution = {
	authoritativeHost: string | null;
	compatibilityForwardedHost: string | null;
	compatibilityHostHeader: string | null;
	hasConflict: boolean;
	host: string;
};

function normalizeHostSignal(raw: string | null | undefined): string | null {
	if (!raw) {
		return null;
	}
	const firstToken = raw.split(",")[0]?.trim().toLowerCase();
	if (!firstToken) {
		return null;
	}
	try {
		const candidate = firstToken.includes("://")
			? firstToken
			: `http://${firstToken}`;
		return new URL(candidate).hostname.toLowerCase();
	} catch {
		return null;
	}
}

function normalizeHostFromUrl(
	rawUrl: string | null | undefined,
): string | null {
	if (!rawUrl) {
		return null;
	}
	try {
		return new URL(rawUrl).hostname.toLowerCase();
	} catch {
		return null;
	}
}

export function resolveRequestHostSignals(
	input: HostResolutionInput,
): RequestHostResolution {
	const authoritativeHost =
		normalizeHostSignal(input.nextUrlHost) ||
		normalizeHostFromUrl(input.requestUrl);
	const compatibilityHostHeader = normalizeHostSignal(input.hostHeader);
	const compatibilityForwardedHost = normalizeHostSignal(
		input.forwardedHostHeader,
	);

	const hints = [compatibilityHostHeader, compatibilityForwardedHost].filter(
		(value): value is string => Boolean(value),
	);
	// Conflict is only asserted when we HAVE an authoritative host (nextUrl/
	// requestUrl) that a client hint disagrees with. When authority is absent we
	// fall back to the hints (see `host` below) rather than 400 — an intentional
	// contract (tests/71 "uses compatibility hints when authority is missing").
	// This fail-open is safe because every real caller (proxy.ts) always supplies
	// nextUrlHost + requestUrl, so `authoritativeHost` is never null in practice;
	// the hint-only branch exists solely for non-request unit/tool callers.
	const hasConflict = Boolean(
		authoritativeHost && hints.some((value) => value !== authoritativeHost),
	);

	return {
		authoritativeHost,
		compatibilityForwardedHost,
		compatibilityHostHeader,
		hasConflict,
		host:
			authoritativeHost ||
			compatibilityHostHeader ||
			compatibilityForwardedHost ||
			"",
	};
}
