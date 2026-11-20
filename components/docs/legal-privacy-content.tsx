import { DocSection } from "@/components/docs/doc-section";

export function LegalPrivacyContent() {
	return (
		<>
			<DocSection id="desktop" title="Desktop Application">
				<div>
					<h3 className="text-heading-sm mb-2">What we collect</h3>
					<p className="text-body-sm text-text-muted mb-3">
						YEN does not collect terminal content, shell history, files,
						settings, or desktop usage analytics. The desktop app only contacts
						external services for explicit product functions:
					</p>
					<ul className="list-disc pl-6 text-body-sm text-text-muted space-y-1 mb-4">
						<li>
							<strong className="text-text-primary">Update checks</strong> —
							when you manually check for updates or enable automatic Sparkle
							checks, YEN requests update metadata from yen.chat. Standard
							update requests can include app version and macOS version.
						</li>
						<li>
							<strong className="text-text-primary">Native browser</strong> —
							when you open a URL in YEN Browser, WebKit connects directly to
							the site you selected. YEN uses a non-persistent WebKit data store
							and does not receive your browsing activity.
						</li>
					</ul>
				</div>

				<div>
					<h3 className="text-heading-sm mb-2">Speech-to-text</h3>
					<p className="text-body-sm text-text-muted mb-4">
						Voice dictation uses Apple&apos;s macOS Speech frameworks. YEN does
						not receive audio or transcripts and does not run a YEN speech
						service. On macOS 26 or newer, YEN uses Apple&apos;s on-device
						SpeechAnalyzer when available. Older versions and runtime fallback
						use the legacy recognizer, which requests on-device recognition when
						Apple reports support; otherwise Apple&apos;s Speech framework can
						use Apple&apos;s network service. Apple controls its processing and
						speech assets.
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
					<h3 className="text-heading-sm mb-2">Persistent sessions</h3>
					<p className="text-body-sm text-text-muted">
						With Keep Sessions Running on, each pane&apos;s shell runs in a
						local helper on your Mac. Its sockets and small session records live
						in <code className="inline-code-brand">~/.local/state/yen/zmx</code>
						, the screen and scrollback it restores stay in its memory, and it
						sends nothing over the network.
					</p>
				</div>
			</DocSection>

			<DocSection id="website" title="Website (yen.chat and blog.yen.chat)">
				<p className="text-body-sm text-text-muted mb-3">
					The YEN website uses:
				</p>
				<ul className="list-disc pl-6 text-body-sm text-text-muted space-y-1 mb-4">
					<li>
						<strong className="text-text-primary">Vercel Analytics</strong> —
						privacy-focused website analytics that do not use cookies. Vercel
						processes page, referrer, device, browser, operating-system, and
						country-level data for this service.
					</li>
					<li>
						<strong className="text-text-primary">Vercel Speed Insights</strong>{" "}
						— anonymous performance metrics such as route, web vitals, browser,
						device type, device OS, network class, and country.
					</li>
					<li>
						<strong className="text-text-primary">Downloads</strong> —{" "}
						<code className="inline-code-brand">/download</code> redirects you
						to the current release on GitHub. YEN does not record the request.
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

			<DocSection id="third-parties" title="Third Parties">
				<p className="text-body-sm text-text-muted">
					YEN does not sell personal data, run ads, operate affiliate programs,
					or use your data to train AI models. Limited request data is shared
					only with the service providers needed to host the website, serve
					downloads and updates, and measure website performance.
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
						<code className="inline-code-brand">Cloudflare</code> — DNS and
						mail-forwarding routing.
					</li>
				</ul>
			</DocSection>

			<DocSection id="retention" title="Retention and Security">
				<p className="text-body-sm text-text-muted mb-3">
					YEN keeps no database of visitors or downloads. Provider logs and
					analytics follow each provider&apos;s retention terms.
				</p>
				<p className="text-body-sm text-text-muted">
					No security measure is perfect, but YEN uses data minimization and
					signed, notarized releases to reduce risk.
				</p>
			</DocSection>

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
					when law requires it.
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
