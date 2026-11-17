import { useEffect, useRef, useState } from "react";

export type TypewriterPhase = "waiting" | "recording" | "typing" | "done";

// Hero cadence: short placeholder beat, brief recording phase, then fast
// per-character typing of the LCP element.
const RECORDING_DELAY_MS = 400;
const TYPING_START_MS = 900;
const TYPING_INTERVAL_MS = 20;

/**
 * Shared hero typewriter animation used by the home and tunes hero titles.
 * Honors `prefers-reduced-motion` (renders the full text immediately) and
 * cleans up all timers on unmount.
 */
export function useTypewriter(initialText: string): {
	phase: TypewriterPhase;
	typedText: string;
} {
	// Both hero callers pass module constants. Capturing that initial value makes
	// the one-shot contract explicit instead of implying that a prop change can
	// restart the animation without first rendering stale phase/text state.
	const text = useRef(initialText).current;
	const [phase, setPhase] = useState<TypewriterPhase>("waiting");
	const [typedText, setTypedText] = useState("");

	// Per-frame setState is the animation itself. The initial text is deliberately
	// captured once, so reduced-motion hydration is not prop-to-state syncing.
	// The effect DOES clean up: every timer it creates is cleared in the returned
	// teardown below. react-doctor 0.9.5 flags the reduced-motion early return,
	// which runs before any timer exists and so has nothing to tear down.
	// react-doctor-disable-next-line react-doctor/effect-needs-cleanup
	// react-doctor-disable-next-line react-doctor/no-cascading-set-state
	useEffect(() => {
		if (window.matchMedia?.("(prefers-reduced-motion: reduce)").matches) {
			setTypedText(text);
			// react-doctor-disable-next-line react-doctor/no-adjust-state-on-prop-change
			setPhase("done");
			return;
		}

		let typingInterval: ReturnType<typeof setInterval> | undefined;
		let typedLength = 0;

		const recordingTimer = setTimeout(() => {
			setPhase("recording");
		}, RECORDING_DELAY_MS);

		const typingTimer = setTimeout(() => {
			setPhase("typing");
			typingInterval = setInterval(() => {
				if (typedLength >= text.length) {
					if (typingInterval) {
						clearInterval(typingInterval);
					}
					setPhase("done");
					return;
				}
				typedLength += 1;
				setTypedText(text.slice(0, typedLength));
			}, TYPING_INTERVAL_MS);
		}, TYPING_START_MS);

		return () => {
			clearTimeout(recordingTimer);
			clearTimeout(typingTimer);
			if (typingInterval) {
				clearInterval(typingInterval);
			}
		};
	}, [text]);

	return { phase, typedText };
}
