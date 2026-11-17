import { describe, expect, test } from "bun:test";
import { resolveRequestHostSignals } from "@/lib/http/request-host";

describe("request host signal resolution", () => {
	test("uses nextUrl host as primary authority", () => {
		const resolved = resolveRequestHostSignals({
			nextUrlHost: "DOCS.YEN.CHAT:443",
			hostHeader: "docs.yen.chat",
			forwardedHostHeader: "docs.yen.chat",
		});
		expect(resolved.host).toBe("docs.yen.chat");
		expect(resolved.hasConflict).toBe(false);
	});

	test("rejects conflicting forwarded-host signal when authority is present", () => {
		const resolved = resolveRequestHostSignals({
			nextUrlHost: "docs.yen.chat",
			hostHeader: "docs.yen.chat",
			forwardedHostHeader: "yen.chat",
		});
		expect(resolved.host).toBe("docs.yen.chat");
		expect(resolved.hasConflict).toBe(true);
	});

	test("falls back to request URL host if nextUrl host is unavailable", () => {
		const resolved = resolveRequestHostSignals({
			requestUrl: "https://localhost:8987/stable/example.png",
			hostHeader: "localhost:8987",
		});
		expect(resolved.host).toBe("localhost");
		expect(resolved.hasConflict).toBe(false);
	});

	test("uses compatibility hints when authority is missing", () => {
		const resolved = resolveRequestHostSignals({
			hostHeader: "docs.yen.chat",
			forwardedHostHeader: "docs.yen.chat",
		});
		expect(resolved.host).toBe("docs.yen.chat");
		expect(resolved.hasConflict).toBe(false);
	});
});
