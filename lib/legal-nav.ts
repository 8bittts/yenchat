import type { DocNavItem } from "@/components/docs/doc-nav";

export const LEGAL_PRIVACY_NAV_ITEMS: DocNavItem[] = [
	{ id: "desktop", title: "Desktop Application" },
	{ id: "website", title: "Website" },
	{ id: "cookies", title: "Cookies" },
	{ id: "third-parties", title: "Third Parties" },
	{ id: "sub-processors", title: "Service Providers" },
	{ id: "retention", title: "Retention & Security" },
	{ id: "rights", title: "Your Rights" },
	{ id: "children", title: "Children's Privacy" },
	{ id: "changes", title: "Policy Changes" },
	{ id: "contact", title: "Privacy Contact" },
];

export const LEGAL_TERMS_NAV_ITEMS: DocNavItem[] = [
	{ id: "agreement", title: "Agreement" },
	{ id: "what-yen-is", title: "What YEN Is" },
	{ id: "license", title: "License" },
	{ id: "responsibilities", title: "Your Responsibilities" },
	{ id: "ip", title: "Intellectual Property" },
	{ id: "warranty", title: "No Warranty" },
	{ id: "liability", title: "Limitation of Liability" },
	{ id: "updates", title: "Updates" },
	{ id: "terms-changes", title: "Terms Changes" },
	{ id: "terms-contact", title: "Terms Contact" },
];

export const LEGAL_COMBINED_NAV_ITEMS: DocNavItem[] = [
	...LEGAL_PRIVACY_NAV_ITEMS,
	...LEGAL_TERMS_NAV_ITEMS,
];
