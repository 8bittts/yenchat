import type { Metadata } from "next";
import { NOINDEX_ROBOTS } from "@/lib/seo";
import { NotFoundClient } from "./not-found-client";

export const metadata: Metadata = {
	title: "404 - Page Not Found",
	description: "The requested YEN page does not exist.",
	robots: NOINDEX_ROBOTS,
};

export default function NotFound() {
	return <NotFoundClient />;
}
