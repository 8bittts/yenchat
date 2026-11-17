import type { Metadata } from "next";
import { permanentRedirect } from "next/navigation";

export const metadata: Metadata = {
	title: "Privacy",
	description: "Privacy and cookie policy — redirects to /terms.",
	robots: { index: false, follow: true },
};

export default function PrivacyPage() {
	permanentRedirect("/terms");
}
