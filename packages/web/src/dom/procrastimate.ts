export type ProcrastimateConfig = {
  /** The ProcrastiMate web app whose `/feedback` popup opens. Defaults to `https://procrastimate.stf.lol`. */
  app?: string;
  /** The project the picker opens on, by name (ignoring case) or id, in place of the last one posted to. */
  project?: string;
  /**
   * The only projects the `/feedback` popup offers, by name (ignoring case) or id, in this order. The Inbox is not
   * offered. Required, and not empty.
   */
  projects: string[];
  /**
   * Another user's space (their ProcrastiMate user id) whose shared projects the popup lists. Leave it out to match
   * across the signed-in user's own and edit-shared projects.
   */
  space?: string;
};

export const defaultProcrastimateApp = "https://procrastimate.stf.lol";

export const procrastimateAppURL = (config: ProcrastimateConfig) =>
  (config.app ?? defaultProcrastimateApp).replace(/\/$/, "");

export type EncodedImage = { blob: Blob; width: number; height: number };

/**
 * A JPEG of the image no wider than `width` and no larger than `maxBytes`. ProcrastiMate's own clients fit the long
 * side. A full-length capture is many times taller than wide, so this fits the width, which keeps its text readable.
 */
async function jpeg(
  image: HTMLCanvasElement,
  width: number,
  maxBytes: number,
): Promise<EncodedImage> {
  for (
    let target = Math.min(width, image.width);
    target >= 64;
    target = Math.floor((target * 3) / 4)
  ) {
    const scaled = document.createElement("canvas");
    scaled.width = target;
    scaled.height = Math.max(1, Math.round((image.height * target) / image.width));
    const context = scaled.getContext("2d")!;
    context.imageSmoothingQuality = "high";
    context.drawImage(image, 0, 0, scaled.width, scaled.height);
    for (const quality of [0.8, 0.65, 0.5]) {
      const blob = await new Promise<Blob | null>((resolve) =>
        scaled.toBlob(resolve, "image/jpeg", quality),
      );
      if (blob && blob.size <= maxBytes)
        return { blob, width: scaled.width, height: scaled.height };
    }
  }
  throw new Error("The image could not be made small enough to upload.");
}

/** Encodes the full-size image and thumbnail JPEGs within ProcrastiMate's upload caps. */
export async function encodeTaskImages(
  image: HTMLCanvasElement,
): Promise<{ full: EncodedImage; thumb: EncodedImage }> {
  const full = await jpeg(image, 2048, 1_500_000);
  const thumb = await jpeg(image, 320, 200_000);
  return { full, thumb };
}
