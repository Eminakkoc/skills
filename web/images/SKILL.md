---
name: web-images
description: This skill should be used when adding, replacing, or optimizing images on a web page, or when diagnosing a slow, late-painting, or layout-shifting image. Covers choosing a framework image component vs hand-rolling, sizing and srcset, format selection, load priority, placeholders, caching, and how to verify the result. Activates on mentions of image performance, LCP, srcset, sizes, AVIF/WebP, lazy loading, blur placeholders, or layout shift.
---

# Images on a web page

## Step 0: do not hand-roll this if you do not have to

Before anything else, check whether the stack already has an image pipeline:

| Stack | Use |
|---|---|
| Next.js | `next/image` |
| Astro | `<Image>` / `<Picture>` from `astro:assets` |
| Nuxt | `<NuxtImg>` / `<NuxtPicture>` |
| SvelteKit | `@sveltejs/enhanced-img` |
| Gatsby | `gatsby-plugin-image` |
| Plain host | Cloudinary, imgix, Netlify Image CDN, Vercel, Cloudflare Images |

These give you srcset, modern formats, a blur placeholder, and priority hints
from one component. Reinventing them by hand is almost always worse.

**Hand-roll only for a specific reason**, and name it: a static export with no
image server, a CDN that must stay dumb, a hard constraint on adding
dependencies, or a handful of images where a build step is cheaper than a
runtime service. If you do hand-roll, the rest of this still applies; you are
just executing it yourself.

**Even with a component, check what it does not do for you.** Most do not pick
`sizes` correctly (Step 2), do not decide which image is the LCP element
(Step 4), and do not set cache headers on assets you serve yourself.

## The order of operations

Fix the cause before decorating the symptom. A blur placeholder over a 300KB
image that should have been 30KB is hiding a problem you could have deleted.

### 1. Reserve the box

The single most valuable thing on this list. An image without reserved space
reflows the page when it lands, which is both the worst-feeling failure and
the one that scores against you in Core Web Vitals.

Set `width` and `height` attributes matching the file's intrinsic aspect ratio
(browsers derive `aspect-ratio` from them even when CSS resizes the element),
or set `aspect-ratio` on the container explicitly when the box crops the
source. Do both when the box's ratio differs from the file's.

Verify by loading with the network throttled to Slow 3G and watching whether
anything below the image moves.

### 2. Right-size it

Usually the biggest single win, and the one most often skipped. The common
failure is one large file sent to everyone regardless of the box it lands in.

Build a `srcset` ladder covering 1x and 2x at every breakpoint, plus 3x on
phones. Use `w` descriptors with `sizes` for anything fluid; `x` descriptors
are only right for an image with one fixed CSS size.

**`sizes` is the part that decides everything, and you cannot guess it.**
It tells the browser the painted CSS width before layout exists, and the
browser trusts it completely. Measure the real rendered width at each
breakpoint (DevTools, resize, read the computed width) and write the
media conditions widest-first.

Two failure modes, both common:

- `sizes="100vw"` on something that is never full-width. Every visitor
  over-downloads and you have quietly undone the work.
- Forgetting the container's `max-width`. Past a certain viewport the column
  stops growing, so the last clause should be a fixed px value, not a `vw`
  expression that keeps climbing.

Also subtract any padding on the column. Two slots that look identical often
differ by an indent.

### 3. Pick the format by testing, not by reputation

Rough order for photographs: AVIF, then WebP, then progressive JPEG as the
fallback. But encode your actual file at two or three qualities and look at
the result before committing.

Content type changes the answer:

- **Photographs**: AVIF usually wins by a lot.
- **Screenshots with UI text**: small text is the first thing lossy codecs
  smear. Start higher and inspect the smallest text at 1:1.
- **Grainy or upscaled sources**: WebP can spend its whole budget on the grain
  and land *above* mozjpeg. Do not assume the usual ordering holds.
- **Flat colour, sharp edges, logos, icons**: use SVG. If it must be raster,
  lossless PNG often beats lossy anything.
- **Animation**: convert GIF to MP4/WebM video. A GIF is usually 5 to 10 times
  the bytes of the equivalent video.

Split quality by tier: widths a non-Retina screen paints 1:1 need higher
quality than widths that are always downscaled by half or more before
painting. The large ones can go noticeably lower for free.

Resist denoising to hit a byte target. It flatters the file size and destroys
texture. Compare before you accept it.

### 4. Get the priority right

Browsers fetch `<img>` at Low priority during head parse and only promote it
after layout proves it is in the viewport. That delay is invisible in the
markup and very visible on screen.

- **The LCP image** (usually the hero) gets `fetchpriority="high"` and a
  `<link rel="preload">`. One, maybe two per page.
- **Everything else** gets `loading="lazy"`.
- **Never lazy-load the LCP image.** This is the most costly common mistake:
  it delays the one paint the score is measured against. Blanket
  `loading="lazy"` on every image is how it happens.

Preloading a `<picture>` needs care. `rel=preload` cannot express type
negotiation, so preload the modern-format ladder and tag it with `type`.
Browsers that do not support the type skip the preload instead of fetching
something unusable.

**The preload's `imageSizes` and `imagesrcset` must match the element's
`sizes` and `srcset` exactly.** If they differ the browser selects a different
candidate for each and downloads the image twice, which is worse than not
preloading at all. Check this in the built HTML, not in the source.

### 5. Only now consider a placeholder

If steps 1 to 4 are done, the gap is often too short to be worth filling.
When it is not, pick by what you are covering:

- **LQIP / blur-up**: a 20 to 40px version of the same image, inlined as a
  base64 data URI. No extra request, paints with first HTML. Best default for
  a known image in a reserved box.
- **Dominant colour**: a single value. Cheapest, and enough when the image is
  decorative.
- **Skeleton / shimmer**: for content of *unknown shape arriving from a
  network call*. A shimmer over a fixed-size image announces "loading" on
  something that should feel settled, and adds motion competing with whatever
  else is on the page.
- **Nothing**: legitimate for small or below-the-fold images.

Two traps:

**Tone mismatch.** If the placeholder is lighter or darker than the real
image, the swap flashes and reads worse than a plain background. Render the
placeholder at the size it will actually paint, put it next to the real file,
and compare. Over-blurring is the usual cause: the browser's upscale from
32px to 500px is already a 16x interpolation and softens plenty unaided.

**Ungated fades.** A CSS transition cannot know the file was already cached,
so returning visitors sit through an animation hiding a wait that is not
happening. Gate on `img.complete` or skip the fade.

### 6. Measure the result

Verifying the markup is correct is not the same as verifying the page got
faster.

- Lighthouse or PageSpeed Insights: look at LCP and CLS, and at "Properly
  size images" / "Serve images in next-gen formats".
- DevTools Network with throttling: confirm which *rung* was actually
  downloaded. This is where a wrong `sizes` reveals itself.
- Chrome DevTools Performance panel: confirm the LCP element is the one you
  think it is.

## Cross-cutting concerns

**Caching and filenames.** Framework build assets usually get
`max-age=31536000, immutable`; files you drop in a static directory usually do
not, and revalidate on every load. If you generate variants yourself, either
hash the filenames and set a long immutable cache, or configure cache headers
for that path. Unhashed names plus a long cache is the worst combination:
replacing an image leaves cached clients on the old one forever.

**Art direction vs resolution switching.** `srcset` + `sizes` serves the same
crop at different sizes. When mobile needs a *different crop* (a tight portrait
where desktop has a wide landscape), that is `<picture>` with `media`
conditions on the sources. Do not try to solve a cropping problem with
`sizes`.

**Alt text.** Describe what the image conveys in context, not what it depicts
in general. Decorative images that add nothing get `alt=""`, which is not the
same as omitting the attribute: omitting it makes screen readers announce the
filename. If the site is localized, alt text is copy and belongs with the rest
of it.

**Metadata.** Strip EXIF from anything user-supplied or camera-sourced. It can
carry GPS coordinates. Most encoders drop it by default; confirm rather than
assume.

**Colour profiles.** Photos with a wide-gamut profile can shift noticeably
when the profile is stripped. Convert to sRGB deliberately rather than letting
a resize step discard it silently.

## Checklist of things that silently undo the work

- `sizes` that lies about the real painted width
- `loading="lazy"` on the LCP image
- a preload whose `imageSizes` does not match the element's `sizes`
- preloading below-the-fold images, stealing bandwidth from the visible one
- a placeholder whose tone does not match the real file
- a fade that plays for visitors who already had the file cached
- unhashed filenames behind a long cache lifetime
- no reserved box, so everything below reflows on load
