import { DocSection } from "@/components/docs/doc-section";

export function LegalPrivacyContent() {
	return (
		<>
			<DesktopPrivacy />
			<WebsitePrivacy />
			<DataSharingPrivacy />
			<PrivacyRightsAndContact />
		</>
	);
}

function DesktopPrivacy() {
	return (
		<DocSection id="desktop" title="Desktop Application">
			<div>
				<h3 className="text-heading-sm mb-2">What we collect</h3>
				<p className="text-body-sm text-text-muted mb-3">
					YEN does not collect terminal content, shell history, files, settings,
					or desktop usage analytics. The desktop app only contacts external
					services for explicit product functions:
				</p>
				<ul className="list-disc pl-6 text-body-sm text-text-muted space-y-1 mb-4">
					<li>
						<strong className="text-text-primary">Update checks</strong> — when
						you manually check for updates or enable automatic Sparkle checks,
						YEN requests update metadata from yen.chat. Standard update requests
						can include app version and macOS version.
					</li>
					<li>
						<strong className="text-text-primary">Native browser</strong> — when
						you open a URL in YEN Browser, WebKit connects directly to the site
						you selected. YEN uses a non-persistent WebKit data store and does
						not receive your browsing activity.
					</li>
					<li>
						<strong className="text-text-primary">
							Experimental wallpaper.
						</strong>{" "}
						Choosing a YouTube link can download a verified helper from GitHub
						and contact YouTube and its media servers. Restoring a selected
						video can repeat the download if its cached file is missing. Apple’s
						Photos picker shares the video you select. Shuffle from Photos
						requests library permission. iCloud Photos can download media. YEN
						keeps selections and cached media on your Mac.
					</li>
				</ul>
				<p className="text-body-sm text-text-muted mb-4">
					If you enable Show Token Usage, YEN reads local tool records and keeps
					a daily index of counts, record identifiers, source paths and read
					positions in its cache. Its analytics view also keeps each tool’s
					token total for each of the last 90 days. Conversation text stays out
					of both. Claude, Codex, and Grok Build plan readings come from local
					tool records. When YEN reads Claude&apos;s own usage cache, it checks
					that the reading belongs to the signed-in account by matching the
					account ID in Claude&apos;s local settings. The OpenCode billing link
					uses the workspace ID in OpenCode&apos;s local log. If you also turn
					on Claude Plan Limits, YEN adds a marked block to your Claude Code
					statusline script that saves Claude’s plan limits to a file on your
					Mac; turning it off removes the block and the file. The token menu
					makes no network request, and YEN’s servers receive no usage data.
				</p>
			</div>

			<div>
				<h3 className="text-heading-sm mb-2">Speech-to-text</h3>
				<p className="text-body-sm text-text-muted mb-4">
					Voice dictation uses Apple&apos;s macOS Speech frameworks. YEN does
					not receive audio or transcripts and does not run a YEN speech
					service. YEN uses Apple&apos;s on-device SpeechAnalyzer when
					available. Its fallback uses the legacy recognizer, which requests
					on-device recognition when Apple reports support; otherwise
					Apple&apos;s Speech framework can use Apple&apos;s network service.
					Apple controls its processing and speech assets.
				</p>
			</div>

			<div>
				<h3 className="text-heading-sm mb-2">Configuration</h3>
				<p className="text-body-sm text-text-muted">
					Your settings are stored locally at{" "}
					<code className="inline-code-brand">
						~/Library/Application Support/com.yenchat.yen/config.yen
					</code>
					. This file never leaves your machine.
				</p>
			</div>
			<div>
				<h3 className="text-heading-sm mb-2">Crash records</h3>
				<p className="text-body-sm text-text-muted mb-4">
					If YEN crashes, it writes a crash record to{" "}
					<code className="inline-code-brand">~/.local/state/yen/crash</code> on
					your Mac. The record holds the app version, system details, and a
					snapshot of part of the app&apos;s memory, which can contain fragments
					of terminal text. It stays on your Mac: YEN does not upload crash
					reports, and you choose whether to send one. You can delete the folder
					at any time.
				</p>
			</div>
			<div>
				<h3 className="text-heading-sm mb-2">Persistent sessions</h3>
				<p className="text-body-sm text-text-muted">
					With Keep Sessions Running on, a persistent pane runs its shell in a
					local helper on your Mac. Its sockets and small session records live
					in <code className="inline-code-brand">~/.local/state/yen/zmx</code>.
					The helper also keeps local diagnostic logs with working directories
					and connection details. These logs can remain after a session ends.
					The screen and scrollback it restores stay in memory. The helper sends
					nothing over the network.
				</p>
			</div>
			<div>
				<h3 className="text-heading-sm mb-2">Remote sessions</h3>
				<p className="text-body-sm text-text-muted">
					Starting in YEN 1.285, you can attach to a session on another of your
					Macs. When you ask for hosts in the command palette or open Hosts in
					the tab sidebar, YEN reads the status of the Tailscale software on
					this Mac to find your other Macs. It then connects to them with the
					system <code className="inline-code-brand">ssh</code> over your
					Tailscale network, so the session&apos;s screen and your typing travel
					only between your Macs. Tailscale is software and a network you
					install and control under your own Tailscale account and its terms; it
					is not a YEN service provider. Sign-in uses your own SSH keys and
					settings, and YEN stores no passwords. To reattach after a restart, a
					remote pane keeps the other Mac&apos;s name and session ID in its
					saved window state on this Mac. None of this is sent to YEN.
				</p>
			</div>
		</DocSection>
	);
}

function WebsitePrivacy() {
	return (
		<>
			<DocSection id="website" title="Website (yen.chat and blog.yen.chat)">
				<p className="text-body-sm text-text-muted mb-3">
					The YEN website uses:
				</p>
				<ul className="list-disc pl-6 text-body-sm text-text-muted space-y-1 mb-4">
					<li>
						<strong className="text-text-primary">Vercel Analytics</strong> —
						privacy-focused website analytics that do not use cookies. Vercel
						processes page, referrer, device, browser, operating-system, and
						country-level data for this service. The site also sends a few click
						events: which download button, header link, or footer link you used,
						and a theme change.
					</li>
					<li>
						<strong className="text-text-primary">Vercel Speed Insights</strong>{" "}
						— anonymous performance metrics such as route, web vitals, browser,
						device type, device OS, network class, and country.
					</li>
					<li>
						<strong className="text-text-primary">Downloads</strong> —{" "}
						<code className="inline-code-brand">/download</code> redirects you
						to the current release on GitHub. The redirect itself records
						nothing. When you click a download button on yen.chat, Vercel
						Analytics counts the click and the button’s place on the page.
						GitHub serves the file and processes the request under its own
						privacy terms.
					</li>
					<li>
						<strong className="text-text-primary">Embedded videos</strong> —
						pages with a video load YouTube&apos;s privacy-enhanced player from
						youtube-nocookie.com. YouTube receives your IP address and browser
						details when the player loads.
					</li>
				</ul>
				<p className="text-body-sm text-text-muted">
					We do not use advertising trackers, remarketing pixels, or any
					third-party analytics beyond the above.
				</p>
			</DocSection>

			<DocSection id="cookies" title="Cookies">
				<div>
					<h3 className="text-heading-sm mb-2">What we don't use</h3>
					<ul className="list-disc pl-6 text-body-sm text-text-muted space-y-1 mb-4">
						<li>No Google Analytics</li>
						<li>No Facebook Pixel or Meta tracking</li>
						<li>No advertising cookies or retargeting</li>
						<li>No cross-site tracking scripts</li>
						<li>
							No consent banner because YEN does not set non-essential cookies
						</li>
					</ul>
				</div>

				<div>
					<h3 className="text-heading-sm mb-2">Local storage</h3>
					<p className="text-body-sm text-text-muted mb-4">
						yen.chat saves your light or dark theme choice in your
						browser&apos;s local storage so the next page uses it. It stays in
						your browser, and you can clear it in your browser settings.
					</p>
				</div>

				<div>
					<h3 className="text-heading-sm mb-2">Desktop app</h3>
					<p className="text-body-sm text-text-muted mb-4">
						YEN does not use cookies or a web view for desktop analytics. Sites
						you open in browser preview may use cookies and other website data
						in WebKit&apos;s non-persistent, memory-only store. YEN does not
						import your regular browser profile or save that store to disk.
					</p>
				</div>

				<div>
					<h3 className="text-heading-sm mb-2">Managing cookies</h3>
					<p className="text-body-sm text-text-muted">
						You can clear or block cookies through your browser settings. Since
						we don't rely on cookies for functionality, this won't affect your
						experience on yen.chat.
					</p>
				</div>
			</DocSection>
		</>
	);
}

function DataSharingPrivacy() {
	return (
		<>
			<DocSection id="third-parties" title="Third Parties">
				<p className="text-body-sm text-text-muted">
					YEN does not sell personal data, run ads, operate affiliate programs,
					or use your data to train AI models. Limited request data is shared
					only with the service providers needed to host the website, serve
					downloads and updates, measure website performance, and answer support
					email.
				</p>
			</DocSection>

			<DocSection
				id="sub-processors"
				title="Service Providers and External Services"
			>
				<p className="text-body-sm text-text-muted mb-3">
					YEN uses the following services for limited product functions:
				</p>
				<ul className="list-disc pl-6 text-body-sm text-text-muted space-y-1 mb-4">
					<li>
						<code className="inline-code-brand">Apple macOS Speech</code> —
						speech recognition and language-asset management by macOS, including
						Apple&apos;s service when the legacy recognizer cannot run
						on-device.
					</li>
					<li>
						<code className="inline-code-brand">Sparkle</code> — embedded macOS
						update framework that checks YEN appcast metadata.
					</li>
					<li>
						<code className="inline-code-brand">Vercel</code> — Next.js app
						hosting, edge delivery, Web Analytics, and Speed Insights for
						yen.chat and blog.yen.chat.
					</li>
					<li>
						<code className="inline-code-brand">GitHub</code> — hosts the YEN
						source code and the release downloads, including the files Sparkle
						fetches for updates.
					</li>
					<li>
						<code className="inline-code-brand">Cloudflare</code> — DNS, and
						email routing that forwards mail sent to yen.chat addresses.
					</li>
					<li>
						<code className="inline-code-brand">Google (Gmail)</code> — receives
						and stores the email you send to support@yen.chat.
					</li>
					<li>
						<code className="inline-code-brand">Resend</code> — delivers the
						email replies YEN sends from yen.chat addresses.
					</li>
				</ul>
			</DocSection>

			<DocSection id="retention" title="Retention and Security">
				<p className="text-body-sm text-text-muted mb-3">
					YEN keeps no database of visitors or downloads. Provider logs and
					analytics follow each provider&apos;s retention terms. Support email
					stays in the support mailbox until it is deleted; ask and YEN will
					delete your messages.
				</p>
				<p className="text-body-sm text-text-muted">
					No security measure is perfect, but YEN uses data minimization and
					signed, notarized releases to reduce risk.
				</p>
			</DocSection>

			<DocSection id="legal-basis" title="Legal Basis and Transfers">
				<p className="text-body-sm text-text-muted mb-3">
					Where data protection law such as the GDPR applies, YEN processes
					website request data, analytics, and support email on the basis of
					legitimate interests: running and securing the website, understanding
					which pages help people, and answering the messages you send. YEN
					processes a privacy request because the law requires it.
				</p>
				<p className="text-body-sm text-text-muted">
					YEN&apos;s service providers can process data in the United States and
					other countries. When data leaves the European Economic Area, the
					United Kingdom, or Switzerland, YEN relies on the transfer safeguards
					those providers offer, such as Standard Contractual Clauses.
				</p>
			</DocSection>
		</>
	);
}

function PrivacyRightsAndContact() {
	return (
		<>
			<DocSection id="rights" title="Your Privacy Rights">
				<p className="text-body-sm text-text-muted mb-3">
					Depending on where you live, you may have rights to request access,
					correction, deletion, restriction, or a copy of personal data, and to
					object to or appeal certain processing. YEN does not sell or share
					personal data for cross-context behavioral advertising.
				</p>
				<p className="text-body-sm text-text-muted">
					Email{" "}
					<a href="mailto:support@yen.chat" className="link-brand">
						support@yen.chat
					</a>{" "}
					to make a request. Include enough detail to locate the relevant
					record. YEN may need to verify your request and may retain information
					when law requires it. You can also complain to the data protection
					authority where you live.
				</p>
			</DocSection>

			<DocSection id="children" title="Children's Privacy">
				<p className="text-body-sm text-text-muted">
					YEN is not directed to children under 13 and does not knowingly
					collect their personal information. Contact YEN if you believe a child
					has provided personal information through the website.
				</p>
			</DocSection>

			<DocSection id="changes" title="Changes to This Policy">
				<p className="text-body-sm text-text-muted">
					We may update this policy as YEN evolves. Changes will be reflected on
					this page with an updated date. For significant changes, we'll note
					them in our{" "}
					<a
						href="https://blog.yen.chat/"
						className="link-brand"
						target="_blank"
						rel="noopener noreferrer"
					>
						blog
					</a>
					.
				</p>
			</DocSection>

			<DocSection id="contact" title="Contact">
				<p className="text-body-sm text-text-muted">
					YEN is operated by 8BIT, the repository copyright holder. Email{" "}
					<a href="mailto:support@yen.chat" className="link-brand">
						support@yen.chat
					</a>{" "}
					with privacy questions or requests.
				</p>
			</DocSection>
		</>
	);
}
