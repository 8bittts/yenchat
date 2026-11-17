import type { Metadata } from "next";
import { permanentRedirect } from "next/navigation";

export const metadata: Metadata = {
	title: "Cookies",
	description: "Cookie policy — redirects to /terms#cookies.",
	robots: { index: false, follow: false },
};

export default function Cookies() {
	permanentRedirect("/terms#cookies");
}
