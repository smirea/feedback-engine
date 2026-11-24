import type { Frame } from "./model.ts";

/** The tallest capture in device pixels, as on iOS, where Core Animation stops drawing a taller image. */
export const captureLimit = 16_000;

/**
 * Where a capture that reaches its height limit should end: the lowest y from `floor` down to `limit` that no frame
 * crosses, so the last row is whole. `undefined` when frames cover the whole range. iOS's `Stitch.cut`.
 */
export function cut(limit: number, floor: number, frames: Frame[]): number | undefined {
  const candidates = [
    limit,
    ...frames.flatMap((frame) => [frame.y, frame.y + frame.height]),
  ].filter((y) => y === limit || (y > floor && y < limit));
  return candidates
    .toSorted((a, b) => b - a)
    .find((y) => !frames.some((frame) => frame.y < y - 0.5 && frame.y + frame.height > y + 0.5));
}

/**
 * The part of a page a capture covers, from `top` down `height` points, by the iOS rules. A page up to `limit` tall is
 * captured whole. A longer one is captured `limit` tall from its top, or, when the window is scrolled more than half
 * the room the limit leaves below the screen, with the part on screen near the middle. A capture that stops before
 * the page's end ends between two rows in its last screen, where none of `rows` crosses the cut.
 */
export function captureRange(
  page: number,
  screen: number,
  scroll: number,
  limit: number,
  rows: Frame[],
) {
  if (page <= limit) return { top: 0, height: page };
  const reach = limit - screen;
  const top = scroll > reach / 2 ? Math.max(0, Math.min(scroll - reach / 2, page - limit)) : 0;
  const end = top + limit;
  if (end >= page) return { top, height: page - top };
  const ending = cut(
    end,
    end - screen,
    rows.filter((row) => row.height < screen),
  );
  return { top, height: (ending ?? end) - top };
}
