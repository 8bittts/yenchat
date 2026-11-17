export function isValidReleaseVersion(version: string): boolean {
	return /^(0|[1-9]\d*)\.\d{3}$/.test(version);
}

export function assertValidReleaseVersion(version: string): void {
	if (!isValidReleaseVersion(version)) {
		throw new Error(`Invalid release version: ${version}`);
	}
}

export function getVersionFilename(version: string): string {
	assertValidReleaseVersion(version);

	const [majorText = "0", trackText = "0"] = version.split(".");
	const major = Number.parseInt(majorText, 10);
	const track = Number.parseInt(trackText, 10);
	return String(major * 1000 + track).padStart(4, "0");
}

/**
 * Inverse of {@link getVersionFilename}: decode the numeric filename token
 * (e.g. "1117" -> "1.117", "017" -> "0.017") back into a release version.
 * Returns "unknown" for non-numeric input.
 */
export function getVersionFromFilename(filenameNumber: string): string {
	if (!/^\d+$/.test(filenameNumber)) {
		return "unknown";
	}
	const numeric = Number.parseInt(filenameNumber, 10);
	const major = Math.floor(numeric / 1000);
	const track = numeric % 1000;
	return `${major}.${String(track).padStart(3, "0")}`;
}
