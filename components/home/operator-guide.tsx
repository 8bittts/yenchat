import { ManualChapters } from "@/app/docs/docs-client";
import { ManualAnchor } from "./manual-anchor";

export function OperatorGuide() {
	return (
		<section id="guide" className="ph-guide ph-section">
			<div className="ph-wrap ph-guide-grid">
				<div className="ph-guide-intro">
					<p className="ph-kicker">Operator’s guide</p>
					<h2>At the keyboard.</h2>
					<p className="ph-lede">
						Install YEN, put a dev server in its own pane, or look up the one
						shortcut you keep forgetting.
					</p>
				</div>
				<div className="ph-topics">
					<ManualAnchor />
					<ManualChapters />
				</div>
			</div>
		</section>
	);
}
