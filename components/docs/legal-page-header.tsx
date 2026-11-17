interface LegalPageHeaderProps {
	title: string;
	description: string;
	lastUpdated: string;
}

export function LegalPageHeader({
	title,
	description,
	lastUpdated,
}: LegalPageHeaderProps) {
	return (
		<header className="max-w-5xl space-y-3">
			<h1 className="border-b border-border pb-2 text-heading-lg">{title}</h1>
			<p className="max-w-4xl text-body text-text-muted">{description}</p>
			<p className="text-body-xs text-text-muted">
				Last updated: {lastUpdated}
			</p>
		</header>
	);
}
