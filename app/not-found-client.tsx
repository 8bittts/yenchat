import Link from "next/link";
import { PageShell } from "@/components/shared/page-shell";
export function NotFoundClient() {
	return (
		<PageShell mainClassName="ed-page">
			<section className="ph-wrap ed-story ed-story-head">
				<p className="ed-label">YEN / 404</p>
				<h1>Page not found.</h1>
				<div className="ph-actions">
					<Link href="/" className="ph-primary">
						Go home ↗
					</Link>
					<Link href="/#guide" className="ed-text-link">
						Open the field guide
					</Link>
				</div>
			</section>
		</PageShell>
	);
}
