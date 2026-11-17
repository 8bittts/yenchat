"use client";

import Link from "next/link";
import { PageShell } from "@/components/shared/page-shell";

export function NotFoundClient() {
	return (
		<PageShell currentPage="home" mainClassName="flex flex-1 items-center">
			<section
				className="section-padding w-full"
				aria-labelledby="not-found-heading"
			>
				<div className="container-page">
					<div className="container-centered">
						<h1
							id="not-found-heading"
							className="text-heading-lg heading-spacing"
						>
							404 — Page Not Found
						</h1>

						<p className="text-body mb-6 md:mb-8">
							The page you&apos;re looking for doesn&apos;t exist or has been
							moved. Let&apos;s get you back on track.
						</p>

						<div className="flex flex-col sm:flex-row gap-4 justify-center items-center">
							<Link href="/" className="btn-primary">
								Go Home
							</Link>
							<Link href="/docs" className="btn-secondary">
								View Docs
							</Link>
						</div>
					</div>
				</div>
			</section>
		</PageShell>
	);
}
