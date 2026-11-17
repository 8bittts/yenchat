/**
 * GitHub Releases location of the desktop DMGs, mirrored from the shell source of
 * truth `scripts/lib/release-constants.sh`. Used by the `/download` route's
 * redirect allowlist and its tests. The site never fetches this host from the
 * browser (downloads are a 302 navigation), so it is intentionally NOT in the
 * CSP connect-src.
 */
export const RELEASE_HOSTNAME = "github.com";
export const RELEASES_PATH_PREFIX = "/8bittts/yenchat/releases/download/";
