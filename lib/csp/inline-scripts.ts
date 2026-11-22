export const ORGANIZATION_STRUCTURED_DATA_SCRIPT = JSON.stringify({
	"@context": "https://schema.org",
	"@type": "Organization",
	"@id": "https://yen.chat/#organization",
	name: "YEN",
	url: "https://yen.chat",
	logo: "https://yen.chat/favicons/android-chrome-512x512.png",
	description: "GPU-accelerated terminal for macOS with Metal rendering",
	sameAs: ["https://twitter.com/yenFTW", "https://blog.yen.chat/"],
});

export const WEBSITE_STRUCTURED_DATA_SCRIPT = JSON.stringify({
	"@context": "https://schema.org",
	"@type": "WebSite",
	"@id": "https://yen.chat/#website",
	name: "YEN",
	alternateName: "YEN Terminal",
	url: "https://yen.chat",
	inLanguage: "en-US",
	publisher: {
		"@id": "https://yen.chat/#organization",
	},
});
