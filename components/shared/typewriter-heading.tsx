import type { TypewriterPhase } from "@/lib/hooks/use-typewriter";

interface TypewriterHeadingProps {
	title: string;
	placeholder: string;
	phase: TypewriterPhase;
	typedText: string;
}

export function TypewriterHeading({
	title,
	placeholder,
	phase,
	typedText,
}: TypewriterHeadingProps) {
	return (
		<>
			<h1 className="sr-only">{title}</h1>
			<div
				className="text-heading-lg heading-spacing tracking-tight"
				aria-hidden="true"
			>
				{phase === "waiting" ? (
					<span className="text-text-muted">
						{placeholder}
						<span className="cursor-blink bg-brand" />
					</span>
				) : phase === "recording" ? (
					<span className="flex items-center gap-3">
						<span className="status-indicator">
							<span className="status-indicator-ping" />
							<span className="status-indicator-dot" />
						</span>
						<span className="text-text-muted">{placeholder}</span>
					</span>
				) : (
					<>
						{typedText}
						{phase === "typing" && <span className="cursor-blink bg-brand" />}
					</>
				)}
			</div>
		</>
	);
}
