export const holdFingers = 3;
/** A quick three-finger touch, such as the start of a pinch or an accidental brush, shows nothing. */
export const holdDelay = 100;
/** From the third finger down to the capture. */
export const holdDuration = 700;
/** Fingers resting on glass drift a little. More than this is a pan or a pinch, and gives the touch back to the app. */
const slop = 20;

export type HoldEvents = {
	/** The hold has lasted `holdDelay`. The indicator grows for the rest of `holdDuration`. */
	onshow: () => void;
	/** A finger lifted, moved, or joined before the hold was done. */
	oncancel: () => void;
	ondone: () => void;
	/** Touches that start inside Feedback's own UI, such as a pinch on the editor's screenshot, are not a hold. */
	ignores: (event: TouchEvent) => boolean;
};

/**
 * Watches for three fingers held still on the page. Touch events, not pointer events: iOS Safari can claim a
 * multi-finger pointer for its own pinch and cancel it, while it keeps sending the touches. The listeners are passive,
 * so the app's scrolling and its own touch handling are untouched.
 */
export function watchHold(events: HoldEvents) {
	let starts = new Map<number, { x: number; y: number }>();
	let shown: ReturnType<typeof setTimeout> | undefined;
	let done: ReturnType<typeof setTimeout> | undefined;
	let visible = false;
	// After a hold fires, the fingers still on the glass must lift before another can start.
	let spent = false;

	const stop = () => {
		if (!done) return;
		clearTimeout(shown);
		clearTimeout(done);
		shown = done = undefined;
		if (visible) events.oncancel();
		visible = false;
	};

	const start = (event: TouchEvent) => {
		if (spent || event.touches.length !== holdFingers || events.ignores(event)) return stop();
		starts = new Map(
			Array.from(event.touches).map(touch => [touch.identifier, { x: touch.clientX, y: touch.clientY }]),
		);
		shown = setTimeout(() => {
			visible = true;
			events.onshow();
		}, holdDelay);
		done = setTimeout(() => {
			shown = done = undefined;
			visible = false;
			spent = true;
			events.ondone();
		}, holdDuration);
	};

	const move = (event: TouchEvent) => {
		if (!done) return;
		const moved = Array.from(event.changedTouches).some(touch => {
			const from = starts.get(touch.identifier);
			return from && Math.hypot(touch.clientX - from.x, touch.clientY - from.y) > slop;
		});
		if (moved) stop();
	};

	const end = (event: TouchEvent) => {
		stop();
		if (event.touches.length === 0) spent = false;
	};

	const options = { capture: true, passive: true };
	addEventListener('touchstart', start, options);
	addEventListener('touchmove', move, options);
	addEventListener('touchend', end, options);
	addEventListener('touchcancel', end, options);
	return () => {
		stop();
		removeEventListener('touchstart', start, options);
		removeEventListener('touchmove', move, options);
		removeEventListener('touchend', end, options);
		removeEventListener('touchcancel', end, options);
	};
}
