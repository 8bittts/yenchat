import { DocSection } from "@/components/docs/doc-section";
import { LegalPrivacyContent } from "@/components/docs/legal-privacy-content";
import { PageShell } from "@/components/shared/page-shell";
import type { PolicySection } from "@/lib/legal-nav";

interface TermsPageClientProps {
	navItems: PolicySection[];
	lastUpdated: string;
}

export function TermsPageClient({
	navItems,
	lastUpdated,
}: TermsPageClientProps) {
	return (
		<PageShell mainClassName="ed-page">
			<header className="ph-wrap ed-legal-head">
				<div>
					<p className="ed-label">YEN / Legal</p>
					<h1>
						Terms <em>&amp;</em>
						<br />
						privacy.
					</h1>
					<p className="ed-deck">
						Your terminal is personal. Here’s what stays on your Mac, what
						connects to a service, and the terms for using YEN.
					</p>
				</div>
				<aside className="ed-receipt" aria-label="Desktop privacy summary">
					<p className="ed-label">YEN · Desktop privacy receipt</p>
					<dl>
						<div>
							<dt>YEN account</dt>
							<dd>None required</dd>
						</div>
						<div>
							<dt>Shell history</dt>
							<dd>Stays local</dd>
						</div>
						<div>
							<dt>Usage analytics</dt>
							<dd>None sent to YEN</dd>
						</div>
						<div>
							<dt>License</dt>
							<dd>MIT</dd>
						</div>
					</dl>
					<p>Last updated: {lastUpdated}</p>
				</aside>
			</header>
			<nav className="ed-legal-nav" aria-label="Policy chapters">
				<div className="ph-wrap">
					<a href="#desktop">Desktop privacy ↓</a>
					<a href="#website">Web &amp; cookies ↓</a>
					<a href="#agreement">Terms of use ↓</a>
					<a href="#terms-contact">Contact ↓</a>
				</div>
			</nav>
			<div className="ph-wrap ed-legal-body">
				<aside>
					<details className="ed-index">
						<summary>All policy sections</summary>
						<nav aria-label="Policy sections">
							{navItems.map((item) => (
								<a key={item.id} href={`#${item.id}`}>
									{item.title}
								</a>
							))}
						</nav>
					</details>
				</aside>
				<div className="ed-policy">
					<LegalPrivacyContent />

					<DocSection id="agreement" title="Agreement">
						<p className="text-body-sm text-text-muted">
							By downloading, installing, or using YEN ("the Software"), you
							agree to these terms. If you don't agree, don't use YEN. Nothing
							in these terms limits the rights the MIT License gives you to
							YEN&apos;s source code.
						</p>
					</DocSection>

					<DocSection id="what-yen-is" title="What YEN Is">
						<p className="text-body-sm text-text-muted">
							YEN is a free, GPU-accelerated terminal emulator for macOS. It
							includes built-in speech-to-text, a file browser, native WebKit
							browser preview, and terminal-first IDE workflows. It is provided
							at no cost and does not require an account for local desktop
							terminal usage.
						</p>
					</DocSection>

					<DocSection id="license" title="License">
						<p className="text-body-sm text-text-muted">
							YEN is open source under the MIT License. You may use, copy,
							modify, and distribute it under that license; the full text is in
							the{" "}
							<a
								href="https://github.com/8bittts/yenchat/blob/main/LICENSE"
								className="link-brand"
								target="_blank"
								rel="noopener noreferrer"
							>
								LICENSE file
							</a>{" "}
							of the{" "}
							<a
								href="https://github.com/8bittts/yenchat"
								className="link-brand"
								target="_blank"
								rel="noopener noreferrer"
							>
								source repository
							</a>
							. YEN is built on Ghostty, which is also MIT licensed. Third-party
							components remain governed by their own licenses; the app lists
							them, with their license texts, in{" "}
							<code className="inline-code-brand">
								YEN.app/Contents/Resources/Notices
							</code>
							. The YEN name and logo are not licensed under the MIT License.
						</p>
					</DocSection>

					<DocSection id="responsibilities" title="Your Responsibilities">
						<ul className="list-disc pl-6 text-body-sm text-text-muted space-y-1">
							<li>
								Use YEN in compliance with all applicable laws and regulations.
							</li>
							<li>
								Do not attempt to disrupt, overload, or exploit YEN's services
								(update servers).
							</li>
							<li>
								You are responsible for your own data, files, and terminal
								commands. YEN executes what you tell it to.
							</li>
							<li>
								If you use remote sessions, you are responsible for the Macs,
								accounts, SSH access, and Tailscale network you connect, and for
								who else can reach them. Tailscale and SSH are third-party
								software under their own terms.
							</li>
							<li>
								Use only wallpaper media you have permission to display. If you
								choose a YouTube link, you are responsible for following
								YouTube&apos;s Terms of Service. YEN grants no rights to any
								video.
							</li>
						</ul>
					</DocSection>

					<DocSection id="ip" title="Intellectual Property">
						<p className="text-body-sm text-text-muted">
							8BIT owns the YEN name, logos, and branding, and the copyright in
							its own original code. Code derived from Ghostty belongs to the
							Ghostty contributors, and each outside contributor keeps the
							copyright in their contribution, all under the MIT License. These
							terms do not transfer any ownership rights. Do not use YEN&apos;s
							marks in a way that implies sponsorship, affiliation, or
							endorsement.
						</p>
					</DocSection>

					<DocSection id="warranty" title="No Warranty">
						<p className="text-body-sm text-text-muted">
							YEN is provided "as is" without warranty of any kind, express or
							implied. We do not guarantee that the Software will be error-free,
							uninterrupted, or compatible with all systems. Use it at your own
							risk.
						</p>
					</DocSection>

					<DocSection id="liability" title="Limitation of Liability">
						<p className="text-body-sm text-text-muted">
							To the maximum extent permitted by law, 8BIT, YEN&apos;s
							contributors, and its licensors shall not be liable for any
							indirect, incidental, special, consequential, or punitive damages
							arising from your use of the Software, including but not limited
							to data loss, system damage, or loss of profits. Because YEN is
							free, our total liability for any claim about the Software is
							limited to US$50. Some places do not allow these limits, so they
							apply to you only as far as your local law allows.
						</p>
					</DocSection>

					<DocSection id="updates" title="Updates">
						<p className="text-body-sm text-text-muted">
							YEN can check for updates through Sparkle when you manually
							request a check or enable automatic update checks. If automatic
							downloads or installs are enabled, Sparkle may download or install
							updates for you. We may change, suspend, or discontinue any part
							of the Software at any time. We'll do our best to communicate
							significant changes via our{" "}
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

					<DocSection id="terms-changes" title="Changes to These Terms">
						<p className="text-body-sm text-text-muted">
							We may update these terms as YEN evolves. Continued use of the
							Software after changes constitutes acceptance of the updated
							terms. We'll update the date at the top of this page when changes
							are made.
						</p>
					</DocSection>

					<DocSection id="terms-contact" title="Contact">
						<p className="text-body-sm text-text-muted">
							Questions about these terms? Email{" "}
							<a href="mailto:support@yen.chat" className="link-brand">
								support@yen.chat
							</a>
							.
						</p>
					</DocSection>
				</div>
			</div>
		</PageShell>
	);
}
