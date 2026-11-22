import type { DocNavItem } from "@/components/docs/doc-nav";
import { DocPageShell } from "@/components/docs/doc-page-shell";
import { DocSection } from "@/components/docs/doc-section";
import { LegalPageHeader } from "@/components/docs/legal-page-header";
import { LegalPrivacyContent } from "@/components/docs/legal-privacy-content";

interface TermsPageClientProps {
	navItems: DocNavItem[];
	lastUpdated: string;
}

export function TermsPageClient({
	navItems,
	lastUpdated,
}: TermsPageClientProps) {
	return (
		<div className="ph-site ph-terms">
			<DocPageShell
				navItems={navItems}
				hero={
					<LegalPageHeader
						title="Terms & Privacy"
						description="Privacy policy, cookie policy, and terms of service for YEN. The desktop app sends no terminal content or desktop usage telemetry to YEN, requires no account for local terminal usage, and is free to use under the license below."
						lastUpdated={lastUpdated}
					/>
				}
			>
				<LegalPrivacyContent />

				<DocSection id="agreement" title="Agreement">
					<p className="text-body-sm text-text-muted">
						By downloading, installing, or using YEN ("the Software"), you agree
						to these terms. If you don't agree, don't use YEN. It's that simple.
					</p>
				</DocSection>

				<DocSection id="what-yen-is" title="What YEN Is">
					<p className="text-body-sm text-text-muted">
						YEN is a free, GPU-accelerated terminal emulator for macOS. It
						includes built-in speech-to-text, a file browser, native WebKit
						browser preview, and terminal-first IDE workflows. It is provided at
						no cost and does not require an account for local desktop terminal
						usage.
					</p>
				</DocSection>

				<DocSection id="license" title="License">
					<p className="text-body-sm text-text-muted">
						YEN is open source under the MIT License. You may use, copy, modify,
						and distribute it under that license; the full text is in the{" "}
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
						. YEN is built on Ghostty, which is also MIT licensed. Bundled Use
						wallpaper media you have permission to display. Third-party
						components remain governed by their own licenses. The YEN name and
						logo are not licensed under the MIT License.
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
					</ul>
				</DocSection>

				<DocSection id="ip" title="Intellectual Property">
					<p className="text-body-sm text-text-muted">
						8BIT owns YEN&apos;s source code, names, logos, and original
						branding. These terms do not transfer any ownership rights. Do not
						use YEN&apos;s marks in a way that implies sponsorship, affiliation,
						or endorsement.
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
						To the maximum extent permitted by law, YEN and its licensors shall
						not be liable for any indirect, incidental, special, consequential,
						or punitive damages arising from your use of the Software, including
						but not limited to data loss, system damage, or loss of profits.
					</p>
				</DocSection>

				<DocSection id="updates" title="Updates">
					<p className="text-body-sm text-text-muted">
						YEN can check for updates through Sparkle when you manually request
						a check or enable automatic update checks. If automatic downloads or
						installs are enabled, Sparkle may download or install updates for
						you. We may change, suspend, or discontinue any part of the Software
						at any time. We'll do our best to communicate significant changes
						via our{" "}
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
						Software after changes constitutes acceptance of the updated terms.
						We'll update the date at the top of this page when changes are made.
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
			</DocPageShell>
		</div>
	);
}
