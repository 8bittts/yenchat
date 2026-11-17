/**
 * Unlisted YENI character bible — reuses the site's real design system
 * (DocPageShell narrow variant, DocSection, light-mode tokens). The shell
 * (Header/Footer/skip-link/mobile-nav) is shared via DocPageShell rather than
 * hand-rolled, so this page never re-derives that chrome. Yeni's violet is a
 * scoped design token (`--yeni-accent` / `bg-yeni-accent`) used only for small
 * accents (dots, icon strokes) — the page itself uses the site's normal light
 * background and brand-orange focus rings, not a purple theme.
 */

import type { DocNavItem } from "@/components/docs/doc-nav";
import { DocPageShell } from "@/components/docs/doc-page-shell";
import { DocSection } from "@/components/docs/doc-section";
import { TerminalCodeBlock } from "@/components/docs/terminal-code-block";

const NAV_ITEMS: DocNavItem[] = [
	{ id: "proof", title: "Locked-identity proof" },
	{ id: "turnaround", title: "Turnaround" },
	{ id: "fullbody", title: "Full body" },
	{ id: "expressions", title: "Expression range" },
	{ id: "signature", title: "Signature details" },
	{ id: "immutable", title: "Immutable identity" },
	{ id: "variable", title: "What varies" },
	{ id: "palette", title: "Palette" },
	{ id: "do-not-vary", title: "Do NOT vary" },
	{ id: "prompt", title: "Locked identity prompt" },
];

type Shot = { src: string; alt: string; caption: string; sub?: string };

const SCENES: Shot[] = [
	{
		src: "/yeni/yeni-scene-rain-neon-crosswalk.webp",
		alt: "Yeni at a neon Shibuya crossing in the rain",
		caption: "Neon Shibuya rain",
		sub: "night crossing, wet-neon reflections",
	},
	{
		src: "/yeni/yeni-scene-rooftop-infinity-pool.webp",
		alt: "Yeni on a rooftop overlooking the skyline at dusk",
		caption: "Rooftop skyline",
		sub: "glowing megacity at dusk",
	},
	{
		src: "/yeni/yeni-scene-bullet-train-golden-hour.webp",
		alt: "Yeni on a bullet train at golden hour",
		caption: "Bullet train",
		sub: "golden-hour window light",
	},
	{
		src: "/yeni/yeni-scene-vinyl-listening-bar.webp",
		alt: "Yeni in a vinyl listening bar",
		caption: "Vinyl listening bar",
		sub: "amber tungsten glow",
	},
	{
		src: "/yeni/yeni-scene-bamboo-forest-dawn.webp",
		alt: "Yeni in a misty bamboo forest at dawn",
		caption: "Bamboo forest",
		sub: "dawn god-rays through the mist",
	},
];

const TURNAROUND: Array<Shot & { badge: string; recipe: string }> = [
	{
		src: "/yeni/yeni-canonical-front.webp",
		alt: "Yeni, front view",
		caption: "Front 0°",
		badge: "FRONT",
		recipe: "seedream_v5_pro · refs=all · front, eyes to lens, neutral",
	},
	{
		src: "/yeni/yeni-canonical-3q-left.webp",
		alt: "Yeni, three-quarter left view",
		caption: "3/4 left",
		badge: "3/4 L",
		recipe: "seedream_v5_pro · refs=all · head turned ~35° left",
	},
	{
		src: "/yeni/yeni-canonical-3q-right.webp",
		alt: "Yeni, three-quarter right view",
		caption: "3/4 right",
		badge: "3/4 R",
		recipe: "seedream_v5_pro · refs=all · head turned ~35° right",
	},
	{
		src: "/yeni/yeni-canonical-profile.webp",
		alt: "Yeni, side profile view",
		caption: "Profile",
		badge: "PROFILE",
		recipe: "seedream_v5_pro · refs=all · true side profile",
	},
	{
		src: "/yeni/yeni-canonical-back.webp",
		alt: "Yeni, back view",
		caption: "Back",
		badge: "BACK",
		recipe: "seedream_v5_pro · hair back + center part + headphones",
	},
];

const FULL_BODY: Array<Shot & { badge: string; recipe: string }> = [
	{
		src: "/yeni/yeni-fullbody-front.webp",
		alt: "Yeni, full body front view",
		caption: "Full front",
		badge: "FULL FRONT",
		recipe:
			"seedream_v5_pro · refs=all · full body, signature streetwear, neutral stance",
	},
	{
		src: "/yeni/yeni-fullbody-3q.webp",
		alt: "Yeni, full body three-quarter view",
		caption: "Full 3/4",
		badge: "FULL 3/4",
		recipe: "seedream_v5_pro · refs=all · 3/4 body, hand at headphones",
	},
];

const EXPRESSIONS: Array<Shot & { badge: string }> = [
	{
		src: "/yeni/yeni-expr-neutral.webp",
		alt: "Yeni, neutral expression",
		caption: "Neutral",
		sub: "cool, composed",
		badge: "NEUTRAL",
	},
	{
		src: "/yeni/yeni-expr-smile.webp",
		alt: "Yeni, soft smile",
		caption: "Soft smile",
		sub: "warm",
		badge: "SMILE",
	},
	{
		src: "/yeni/yeni-expr-eyesclosed.webp",
		alt: "Yeni, eyes closed, feeling the music",
		caption: "Feeling the music",
		sub: "eyes soft/closed",
		badge: "EYES CLOSED",
	},
	{
		src: "/yeni/yeni-expr-sultry.webp",
		alt: "Yeni, cool sultry expression",
		caption: "Cool sultry",
		sub: "chin over shoulder",
		badge: "SULTRY",
	},
];

const IMMUTABLE_ROWS: Array<[string, React.ReactNode]> = [
	["Age read", "Mid-20s (reads 24–26), unambiguously adult"],
	["Ethnicity / styling", "Adult Korean, K-pop-idol-inspired"],
	["Face shape", "Soft oval tapering to a gentle V-line jaw"],
	[
		"Eyes",
		"Almond, slightly upturned; warm dark-brown irises; light natural aegyo-sal under-eye",
	],
	["Brows", 'Soft straight Korean ("ilja"-style) brows, low arch, dark'],
	["Nose", "Slim straight bridge, small refined rounded tip"],
	["Lips", "Full soft bow, glossy rose gradient"],
	[
		"Skin",
		"Fair warm-neutral, dewy glass-skin finish — REAL pore texture kept (never waxy/plastic)",
	],
	[
		"Freckles",
		<>
			Natural freckles across the nose bridge and her <b>RIGHT</b> cheek only
			(appears on the LEFT of the frame as viewed) — no beauty mark or mole
		</>,
	],
	[
		"Hair",
		<>
			Jet blue-black, mid-back, soft-wave straight, <b>center part</b>; subtle{" "}
			<b>#7C3AED</b> violet balayage confined to the underlayer + two
			face-framing pieces (reads at least 85% solid black at a glance — never an
			overall purple/lavender tint)
		</>,
	],
	["Body", "Slim-athletic idol frame, ~168 cm, long neck"],
	[
		"Signature accessory",
		"Matte-black over-ear studio headphones with a thin brushed-violet #7C3AED accent ring on each cup — treat as identity, never omit",
	],
	[
		"Recurring jewelry",
		"Extremely minimal — exactly one thin gold chain necklace with no pendant, and one pair of thin small gold hoop earrings, nothing else (no layering, no second necklace)",
	],
	[
		"Vibe",
		"Cool, sultry, self-possessed late-night selector — warmth under the ice",
	],
];

const VARIABLE_ROWS: Array<[string, React.ReactNode]> = [
	[
		"Scene",
		"tokyo-subway-night · japanese-garden-day · shibuya-neon-night · tatami-room-day · tokyo-rooftop-dusk",
	],
	[
		"Pose / action",
		'Approved register (vogue | chill) — the "feeling the music" groove',
	],
	["Lighting", "Free per render (neon spill, rim light, golden hour…)"],
	[
		"Expression",
		"neutral · soft smile · eyes-closed feeling-the-music · cool sultry",
	],
	["Background", "Time / weather / crowd free per scene"],
];

const WARDROBE_ROWS: Array<[string, React.ReactNode]> = [
	[
		"Silhouettes",
		"Fitted corset or bralette top · cropped fitted moto jacket worn open · fitted vinyl/leather-look pants, leggings, or a fitted mini skirt · sleek chunky boots or heeled sneakers (alt: cutout crop top, oversized off-shoulder bomber, baggy cargos, short shorts)",
	],
	[
		"Materials",
		"Matte tech fabric · leather/pleather · mesh layering (platform-safe) · cotton streetwear",
	],
	[
		"Constants",
		<>
			Headphones + right-cheek freckles + minimal jewelry do <b>not</b> change
			with the outfit
		</>,
	],
	[
		"Guardrails",
		"Platform-safe (no nudity/sheer/explicit/school-uniform); NEVER formal/business",
	],
];

const DO_NOT_VARY = [
	"different face or facial features",
	"a different / new person",
	"aging — younger or older",
	"changed hairstyle or hair color",
	"dropping the #7C3AED violet balayage",
	"changed eye color or shape",
	"changed skin tone",
	"removing the headphones",
	"moving/removing the right-cheek freckles, or adding a beauty mark",
	"added glasses",
	"altered body type",
	"waxy/plastic skin · extra fingers · text/logos",
];

const PALETTE = [
	{ name: "Amethyst (brand)", hex: "#7C3AED" },
	{ name: "Violet light", hex: "#A78BFA" },
	{ name: "Jet black", hex: "#0D0D12" },
	{ name: "Charcoal", hex: "#2A2A3A" },
	{ name: "Warm neutral", hex: "#E9C9B4" },
	{ name: "Chrome/silver", hex: "#C9CCD6" },
	{ name: "Gold (jewelry)", hex: "#D4AF37" },
];

const LOCKED_IDENTITY_PARAGRAPH =
	"Yeni — the SAME adult Korean K-pop-idol-inspired woman in her mid-20s in every render: soft oval face with a gentle V-line jaw, slightly upturned almond dark-brown eyes with soft straight brows, a slim straight nose, full glossy rose bow lips, and fair dewy glass-skin. A scattering of natural freckles sits across the bridge of her nose and her own RIGHT cheek only (the cheek that appears on the LEFT side of the frame as viewed) — no beauty mark or mole anywhere on her face. Her hair is jet blue-black — reads AT LEAST 85% solid black at a glance, mid-back, center-parted, with a subtle #7C3AED violet balayage CONFINED to the underlayer and face-framing pieces only, never an overall purple/lavender tint. Slim-athletic, ~168 cm. She always wears matte-black over-ear studio headphones with a thin violet accent ring, exactly ONE thin gold chain necklace with NO pendant, and ONE PAIR of thin small gold hoop earrings — nothing else, no layering. Keep her exact face, bone structure, features, and freckles identical across every image — do NOT invent a new person.";

function ShotCard({
	shot,
	badge,
	recipe,
	aspect = "aspect-[4/5]",
	fit = "cover",
}: {
	shot: Shot;
	badge?: string;
	recipe?: string;
	aspect?: string;
	fit?: "cover" | "contain";
}) {
	return (
		<div className="rounded-xl border border-border bg-card overflow-hidden">
			<div className={`relative ${aspect} bg-card-header`}>
				{badge && (
					<span className="absolute top-2 left-2 z-10 rounded-md border border-border bg-background/80 px-2 py-0.5 font-mono text-body-xs tracking-wide text-text-muted backdrop-blur-sm">
						{badge}
					</span>
				)}
				{/* biome-ignore lint/performance/noImgElement: static local assets served as-is; next/image's optimizer proved unreliable for this gallery (intermittent empty renders in production). */}
				<img
					src={shot.src}
					alt={shot.alt}
					loading="lazy"
					className={`absolute inset-0 size-full ${fit === "cover" ? "object-cover" : "object-contain"}`}
				/>
			</div>
			<div className="px-3 py-2 border-t border-border">
				<p className="text-body-xs text-text-primary">
					{shot.caption}
					{shot.sub && <span className="text-text-muted"> · {shot.sub}</span>}
				</p>
				{recipe && (
					<p className="mt-1 font-mono text-body-xs leading-relaxed text-text-muted">
						{recipe}
					</p>
				)}
			</div>
		</div>
	);
}

function SignatureIcon({
	label,
	sub,
	children,
}: {
	label: string;
	sub: string;
	children: React.ReactNode;
}) {
	return (
		<div className="rounded-xl border border-border bg-card overflow-hidden">
			<div className="aspect-square flex items-center justify-center bg-card-header">
				{children}
			</div>
			<div className="px-3 py-2 border-t border-border">
				<p className="text-body-xs text-text-primary">
					{label} <span className="text-text-muted">· {sub}</span>
				</p>
			</div>
		</div>
	);
}

/**
 * Shared definition table for the "Immutable identity" and "What varies" grids
 * (previously three copy-pasted <table> blocks with identical cell markup).
 */
function DefinitionTable({
	rows,
	labelWidth,
}: {
	rows: Array<[string, React.ReactNode]>;
	labelWidth?: string;
}) {
	return (
		<div className="rounded-xl border border-border overflow-hidden">
			<table className="w-full text-sm">
				<tbody>
					{rows.map(([label, value]) => (
						<tr key={label} className="border-b border-border last:border-b-0">
							<th
								className={`text-left align-top px-4 py-3 font-semibold text-brand-dark whitespace-nowrap${
									labelWidth ? ` ${labelWidth}` : ""
								}`}
							>
								{label}
							</th>
							<td className="text-left align-top px-4 py-3 text-text-body">
								{value}
							</td>
						</tr>
					))}
				</tbody>
			</table>
		</div>
	);
}

// Static hero JSX — hoisted to module scope so it is built once, not on every
// render (react-doctor rendering-hoist-jsx).
const HERO = (
	<>
		<p className="eyebrow-text text-brand-dark">YEN Terminal &amp; Tunes</p>
		<h1 className="text-heading-lg mt-1">YENI</h1>
		<p className="text-body-sm text-text-muted mt-3">
			The one locked character behind every YEN Tunes cover, loop, and
			thumbnail. Scene, wardrobe, pose, lighting, and expression change — her
			face, hair, build, right-cheek freckles, and signature headphones never
			do.
		</p>
		<div className="flex flex-wrap gap-2 mt-4">
			<span className="rounded-full border border-border bg-card-header px-2.5 py-1 text-body-xs text-text-body">
				Look codename <b>Midnight Amethyst</b>
			</span>
			<span className="rounded-full border border-border bg-card-header px-2.5 py-1 text-body-xs text-text-body">
				Style <b>photoreal</b>
			</span>
			<span className="inline-flex items-center gap-1.5 rounded-full border border-border bg-card-header px-2.5 py-1 text-body-xs text-text-body">
				<span className="size-2.5 rounded-full border border-black/10 bg-yeni-accent" />
				<b>#7C3AED</b>
			</span>
			<span className="rounded-full border border-border bg-card-header px-2.5 py-1 text-body-xs text-text-body">
				<b>@yenFTW</b>
			</span>
		</div>
	</>
);

export function YeniClient() {
	return (
		<DocPageShell
			variant="narrow"
			currentPage="home"
			navItems={NAV_ITEMS}
			hero={HERO}
		>
			<DocSection
				id="proof"
				title="Locked-identity proof — one Yeni, five worlds"
			>
				<p className="text-body-sm text-text-muted -mt-2">
					Every image below is the SAME canonical Yeni, generated across five
					hyperrealistic environments from a single locked reference — identical
					face, hair, right-cheek freckles, and violet-ring headphones
					throughout. Only the scene, wardrobe, and light change.
				</p>
				<div className="grid gap-4 grid-cols-2 sm:grid-cols-3 lg:grid-cols-3">
					{SCENES.map((shot) => (
						<ShotCard key={shot.src} shot={shot} aspect="aspect-video" />
					))}
					<div className="rounded-xl border border-border bg-card overflow-hidden">
						<div className="aspect-video flex items-center justify-center bg-card-header px-4 text-center">
							<p className="text-body-xs text-text-muted">
								Same reference →{" "}
								<span className="font-semibold text-brand-dark">
									same person
								</span>{" "}
								every render
							</p>
						</div>
						<div className="px-3 py-2 border-t border-border">
							<p className="text-body-xs text-text-primary">
								The lock{" "}
								<span className="text-text-muted">· identity, not style</span>
							</p>
						</div>
					</div>
				</div>
			</DocSection>

			<DocSection id="turnaround" title="Turnaround — head &amp; shoulders">
				<p className="text-body-sm text-text-muted -mt-2">
					Flat grey background, same face every angle, headroom kept.
				</p>
				<div className="grid gap-4 grid-cols-2 sm:grid-cols-3 lg:grid-cols-5">
					{TURNAROUND.map((shot) => (
						<ShotCard
							key={shot.src}
							shot={shot}
							badge={shot.badge}
							recipe={shot.recipe}
						/>
					))}
				</div>
			</DocSection>

			<DocSection id="fullbody" title="Full body — locks proportions">
				<p className="text-body-sm text-text-muted -mt-2">
					~168 cm, slim-athletic idol frame.
				</p>
				<div className="grid gap-4 grid-cols-1 sm:grid-cols-2">
					{FULL_BODY.map((shot) => (
						<ShotCard
							key={shot.src}
							shot={shot}
							badge={shot.badge}
							recipe={shot.recipe}
							aspect="aspect-[3/4]"
							fit="contain"
						/>
					))}
				</div>
			</DocSection>

			<DocSection id="expressions" title="Expression range">
				<p className="text-body-sm text-text-muted -mt-2">
					SAME face — only the expression changes.
				</p>
				<div className="grid gap-4 grid-cols-2 sm:grid-cols-4 lg:grid-cols-4">
					{EXPRESSIONS.map((shot) => (
						<ShotCard key={shot.src} shot={shot} badge={shot.badge} />
					))}
				</div>
			</DocSection>

			<DocSection id="signature" title="Signature details — never omit">
				<p className="text-body-sm text-text-muted -mt-2">
					These read as identity, not styling.
				</p>
				<div className="grid gap-4 grid-cols-2 sm:grid-cols-4 lg:grid-cols-4">
					<SignatureIcon label="Freckles" sub="nose & RIGHT cheek">
						<svg viewBox="0 0 120 120" className="w-16 h-16" aria-hidden="true">
							<ellipse cx="60" cy="58" rx="30" ry="20" fill="#f0d3bf" />
							<path d="M40 56 q20 -14 40 0 q-20 12 -40 0Z" fill="#fff" />
							<circle cx="60" cy="56" r="8" fill="#5b3a1e" />
							<circle cx="60" cy="56" r="3.4" fill="#160c06" />
							<circle cx="42" cy="60" r="1.4" fill="#b8794f" opacity=".7" />
							<circle cx="46" cy="65" r="1.2" fill="#b8794f" opacity=".6" />
							<circle cx="40" cy="66" r="1.2" fill="#b8794f" opacity=".6" />
							<circle cx="50" cy="70" r="1.2" fill="#b8794f" opacity=".55" />
							<circle cx="53" cy="61" r="1.2" fill="#b8794f" opacity=".5" />
						</svg>
					</SignatureIcon>
					<SignatureIcon label="Headphones" sub="matte black · violet ring">
						<svg viewBox="0 0 120 120" className="w-16 h-16" aria-hidden="true">
							<path
								d="M30 66 C32 34 88 34 90 66"
								stroke="#0d0d12"
								strokeWidth="10"
								fill="none"
								strokeLinecap="round"
							/>
							<rect
								x="24"
								y="70"
								width="20"
								height="34"
								rx="9"
								fill="#0d0d12"
							/>
							<rect
								x="76"
								y="70"
								width="20"
								height="34"
								rx="9"
								fill="#0d0d12"
							/>
							<rect
								x="27"
								y="78"
								width="14"
								height="18"
								rx="7"
								fill="none"
								stroke="var(--yeni-accent)"
								strokeWidth="3"
							/>
							<rect
								x="79"
								y="78"
								width="14"
								height="18"
								rx="7"
								fill="none"
								stroke="var(--yeni-accent)"
								strokeWidth="3"
							/>
						</svg>
					</SignatureIcon>
					<SignatureIcon label="Hair" sub="center part · violet balayage">
						<svg viewBox="0 0 120 120" className="w-16 h-16" aria-hidden="true">
							<path
								d="M60 20 C40 30 32 60 34 100 L44 100 C44 66 50 40 60 34 C70 40 76 66 76 100 L86 100 C88 60 80 30 60 20Z"
								fill="#15131b"
							/>
							<path
								d="M76 100 C76 74 72 52 66 40 C74 56 80 78 82 100Z"
								fill="var(--yeni-accent)"
								opacity=".6"
							/>
						</svg>
					</SignatureIcon>
					<SignatureIcon
						label="Necklace + hoops"
						sub="one thin chain, small hoops"
					>
						<svg viewBox="0 0 120 120" className="w-16 h-16" aria-hidden="true">
							<path
								d="M40 30 q20 -12 40 0"
								stroke="#d4af37"
								strokeWidth="2.5"
								fill="none"
							/>
							<path d="M60 30 v10" stroke="#d4af37" strokeWidth="2.5" />
							<ellipse
								cx="34"
								cy="76"
								rx="7"
								ry="9"
								fill="none"
								stroke="#d4af37"
								strokeWidth="2.5"
							/>
							<ellipse
								cx="86"
								cy="76"
								rx="7"
								ry="9"
								fill="none"
								stroke="#d4af37"
								strokeWidth="2.5"
							/>
						</svg>
					</SignatureIcon>
				</div>
			</DocSection>

			<DocSection id="immutable" title="Immutable identity — locked forever">
				<p className="text-body-sm text-text-muted -mt-2">
					Every render, no exceptions.
				</p>
				<DefinitionTable rows={IMMUTABLE_ROWS} labelWidth="w-48" />
			</DocSection>

			<DocSection id="variable" title="What varies per render">
				<p className="text-body-sm text-text-muted -mt-2">
					The only things allowed to change.
				</p>
				<div className="grid gap-4 lg:grid-cols-2">
					<DefinitionTable rows={VARIABLE_ROWS} labelWidth="w-36" />
					<DefinitionTable rows={WARDROBE_ROWS} labelWidth="w-36" />
				</div>
			</DocSection>

			<DocSection id="palette" title="Palette">
				<p className="text-body-sm text-text-muted -mt-2">Brand-locked.</p>
				<div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-7 gap-4">
					{PALETTE.map((swatch) => (
						<div
							key={swatch.hex}
							className="rounded-xl border border-border overflow-hidden"
						>
							{/* Data-driven color swatch: the literal palette hex IS the
							    content (rendered alongside its own hex label), so an inline
							    style is the correct tool here — same class of exception as
							    the AI-provider brand colors. */}
							<div
								className="h-28 sm:h-36"
								style={{ background: swatch.hex }}
							/>
							<div className="px-3 py-2.5">
								<p className="text-body-sm text-text-primary">{swatch.name}</p>
								<p className="font-mono text-body-xs text-text-muted mt-0.5">
									{swatch.hex}
								</p>
							</div>
						</div>
					))}
				</div>
			</DocSection>

			<DocSection id="do-not-vary" title="Do NOT vary">
				<p className="text-body-sm text-text-muted -mt-2">
					Negative prompt / QC reject list.
				</p>
				<div className="rounded-xl border border-border p-5 grid gap-x-6 gap-y-2 sm:grid-cols-2">
					{DO_NOT_VARY.map((flag) => (
						<div
							key={flag}
							className="flex gap-2 items-start text-sm text-text-body"
						>
							<span className="text-status-error font-bold font-mono">✕</span>
							<span>{flag}</span>
						</div>
					))}
				</div>
			</DocSection>

			<DocSection id="prompt" title="Locked identity prompt">
				<p className="text-body-sm text-text-muted -mt-2">
					Copy verbatim into any generator.
				</p>
				<TerminalCodeBlock
					code={LOCKED_IDENTITY_PARAGRAPH}
					title="character_bible.locked_identity_paragraph"
					wrap
				/>
			</DocSection>

			<div className="border-t border-border pt-6 text-body-xs text-text-muted space-y-3">
				<p>
					<b className="text-text-primary">How the lock works.</b> Text (the
					paragraph above) only <i>reinforces</i> identity; the reference image
					(
					<code className="inline-code-brand">
						seedream_v5_pro --image-references
					</code>
					) <i>creates</i> it. Always regenerate from the prior approved{" "}
					<code className="inline-code-brand">yeni-canonical-front.png</code> —
					never text-to-image a new face from scratch, or the face drifts.
				</p>
				<p>
					<b className="text-text-primary">Bootstrap recipe.</b>
					<br />1 · Render the turnaround above with{" "}
					<code className="inline-code-brand">seedream_v5_pro</code> from the
					locked paragraph; curate the single most consistent face.
					<br />2 · Save the stills as the filenames referenced above — they
					auto-appear on this page.
					<br />3 · Set{" "}
					<code className="inline-code-brand">
						character_bible.reference_image
					</code>{" "}
					in <code className="inline-code-brand">prompts/personas.json</code> →
					covers auto-lock via{" "}
					<code className="inline-code-brand">cover.ts</code>.
					<br />4 · Soul 2.0 training is complete and its ID is stored in{" "}
					<code className="inline-code-brand">character_bible.soul_id</code>. It
					is kept as a secondary reference asset only —{" "}
					<code className="inline-code-brand">
						text2image_soul_v2 --custom_reference_id &lt;id&gt;
					</code>{" "}
					returns a 9-panel moodboard/collage, not a usable single portrait, so
					the render-time identity lock stays{" "}
					<code className="inline-code-brand">seedream_v5_pro</code> +{" "}
					<code className="inline-code-brand">--image-references</code>.
					<br />5 · Loops lock automatically:{" "}
					<code className="inline-code-brand">cover.ts --loop</code> renders a
					face-locked <code className="inline-code-brand">seedream_v5_pro</code>{" "}
					keyframe and animates it as the{" "}
					<code className="inline-code-brand">kling3_0</code>{" "}
					<code className="inline-code-brand">--start-image</code>/
					<code className="inline-code-brand">--end-image</code>.
				</p>
				<p>
					Soul ID:{" "}
					<span className="font-mono text-body-xs border border-border rounded px-1.5 py-0.5">
						Yeni-v2 · ed0a7e19-1e81-4f45-9b7e-b4fed927706b
					</span>{" "}
					· References:{" "}
					<code className="inline-code-brand">
						release/yeni/persona/yeni-canonical-*.png
					</code>{" "}
					· Canon:{" "}
					<code className="inline-code-brand">
						prompts/personas.json → personas[yeni].character_bible
					</code>
				</p>
			</div>
		</DocPageShell>
	);
}
