#!/usr/bin/env python3
"""Generate the BTunes logo: a quarter note beside an italic capital B,
engraved into a radially polished silver disc.

The mark is built as a single mask (note stem doubles as the B's stem), then
inset into the disc with an inner shadow and an inner light catch so it reads
as carved metal rather than printed artwork.

Requires Pillow. No other third-party dependencies.
"""

import argparse
import math
import os
import random
import sys

try:
    from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont
except ImportError:
    sys.stderr.write(
        "Pillow is required to build the logo.\n"
        "Install it for the current user with: python3 -m pip install --user Pillow\n")
    sys.exit(1)


# Purple family shared with the BriansFlix, VideoSlideshow and QMS marks, run
# bright: a vivid violet body with a lit edge, rather than a dark plum.
PURPLE_DEEP = (50, 0, 140)      # #32008C shadow, still saturated
PURPLE_MAIN = (132, 0, 255)     # #8400FF body
PURPLE_LIGHT = (186, 122, 255)  # #BA7AFF lit edge
PURPLE_HOT = (238, 212, 255)    # #EED4FF the brightest catch

FONT_CANDIDATES = [
    "/System/Library/Fonts/Supplemental/Arial Black.ttf",
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    "/Library/Fonts/Arial Black.ttf",
    "/System/Library/Fonts/Supplemental/Impact.ttf",
]

ITALIC_SHEAR = 0.20   # tan of the italic angle, about 11.3 degrees
SHEAR_PIVOT = 0.52    # vertical pivot for the shear, in unit canvas coords

# Mark geometry, in unit coordinates of the drawing canvas (y grows downward).
#
# The note is drawn as though it were a glyph set beside the B: both stand on
# the same baseline and reach the same cap line, and both carry the same stroke
# weight. They join where the flag runs into the letter. The flag is a plain
# straight bar rather than a curled ribbon, which keeps the mark blocky.
CAP_TOP = 0.100       # cap line, shared by the note and the letter
BASELINE = 0.900      # baseline, shared by the note and the letter

# The letter comes first and the note follows it.
#
# A quarter note: head and stem, no flag. The stem carries the letter's own
# stroke weight, measured off the rendered glyph rather than guessed.
B_LEFT, B_TOP, B_CAP = 0.130, CAP_TOP, (BASELINE - CAP_TOP)

# The note sits to the right of the letter.
#
# The stem is pushed as far right as it can go: its right edge is very nearly
# tangent to the ball, and it stops at the height where that edge touches. Any
# further right and a corner of the upright appears outside the ball. Solving
# the line against the ellipse puts the tangent at a stem edge of 1.498 and a
# touch height of 0.732, so the stem sits a hair inside both.
#
# The ball is a circle, not an ellipse, and it hangs off the foot of the stem
# at about twenty degrees below horizontal: mostly to the left, only a little
# below. Sitting it down at forty five reads as the tail of a letter.
STEM_RIGHT = None   # solved below, against the ball
STEM_WIDTH_FALLBACK = 0.250
HEAD_CX, HEAD_CY = 1.214, 0.700
HEAD_RX, HEAD_RY = 0.270, 0.176
HEAD_ANGLE = -15.0  # tilted down toward the right
# The stem runs past the ball's centre so the two are one solid shape.
STEM_Y0, STEM_Y1 = CAP_TOP, None

# The flag: a straight blocky bar off the top of the stem, running down and to
# the right. No curl, in keeping with everything else here.
FLAG_REACH = 0.200          # how far right of the stem the flag runs
FLAG_TOP_Y = 0.360          # where its upper edge lands at that reach
FLAG_DEPTH = 0.150          # thickness of the bar, measured vertically
FLAG_ROOT_Y = 0.270         # where its lower edge leaves the stem

# The drawing canvas is wider than it is tall. The letter is wide enough at this
# cap height to run past a square canvas, which cut its right side off.
MARK_CANVAS_WIDTH = 1.85

MARK_FILL = 0.760     # mark height as a fraction of the disc diameter
MARK_MAX_WIDTH = 0.830   # wide enough that the letter passes over the rim
MARK_CENTER_Y = 0.500


def find_font():
    for path in FONT_CANDIDATES:
        if os.path.exists(path):
            return path
    sys.stderr.write(
        "No suitable heavy sans font was found. Looked for:\n  " +
        "\n  ".join(FONT_CANDIDATES) + "\n")
    sys.exit(1)


def bezier(p0, p1, p2, t):
    u = 1.0 - t
    return (u * u * p0[0] + 2 * u * t * p1[0] + t * t * p2[0],
            u * u * p0[1] + 2 * u * t * p1[1] + t * t * p2[1])


def bezier_tangent(p0, p1, p2, t):
    u = 1.0 - t
    return (2 * u * (p1[0] - p0[0]) + 2 * t * (p2[0] - p1[0]),
            2 * u * (p1[1] - p0[1]) + 2 * t * (p2[1] - p1[1]))


def flag_polygon(size):
    """Straight flag: a bar running down and to the right off the stem.

    Anchored to the stem's edge, which is solved against the ball rather than
    fixed, so the flag follows it.
    """
    left = STEM_RIGHT - 0.010
    right = STEM_RIGHT + FLAG_REACH
    points = ((left, CAP_TOP), (right, FLAG_TOP_Y),
              (right, FLAG_TOP_Y + FLAG_DEPTH), (left, FLAG_ROOT_Y))
    return [(p[0] * size, p[1] * size) for p in points]


def stem_tangent():
    """Right edge and stopping height for the stem.

    The stem's right edge is a slanted line, so the test is not the ball's
    rightmost point on the page but the point that reaches furthest along that
    slant. Measuring at the ball's centre height instead is wrong once the ball
    is tilted: the ball keeps moving right below the join and pushes past the
    edge. Taking the extreme over the whole outline puts the line where nothing
    lies to its right, and the stem stops at the height where they touch.
    """
    a = math.radians(HEAD_ANGLE)
    ca, sa = math.cos(a), math.sin(a)
    best_reach, best_y = None, None
    for i in range(8000):
        th = 2.0 * math.pi * i / 8000.0
        ex, ey = HEAD_RX * math.cos(th), HEAD_RY * math.sin(th)
        x = HEAD_CX + ex * ca - ey * sa
        y = HEAD_CY + ex * sa + ey * ca
        reach = x + ITALIC_SHEAR * (y - SHEAR_PIVOT)
        if best_reach is None or reach > best_reach:
            best_reach, best_y = reach, y
    return best_reach, best_y


def head_polygon(size, steps=96):
    """The ball, given in the coordinates of the finished image.

    The italic shear applied to the whole mark turns a circle into an oval
    leaning about forty degrees. The ball is therefore drawn pre-sheared the
    other way, so that what comes out the far side is the circle asked for.
    The stem and the flag are left alone: they should lean with the letter.
    """
    pts = []
    a = math.radians(HEAD_ANGLE)
    ca, sa = math.cos(a), math.sin(a)
    for i in range(steps):
        th = 2.0 * math.pi * i / steps
        ex, ey = HEAD_RX * math.cos(th), HEAD_RY * math.sin(th)
        x = HEAD_CX + ex * ca - ey * sa
        y = HEAD_CY + ex * sa + ey * ca
        x += ITALIC_SHEAR * (y - SHEAR_PIVOT)
        pts.append((x * size, y * size))
    return pts


def render_letter_b(size, font_path):
    """Render a capital B sized to the target cap height and return its mask."""
    target_h = int(round(B_CAP * size))
    guess = int(target_h * 1.45)
    for _ in range(30):
        font = ImageFont.truetype(font_path, guess)
        tmp = Image.new("L", (guess * 2, guess * 2), 0)
        ImageDraw.Draw(tmp).text((guess // 4, guess // 4), "B", fill=255, font=font)
        box = tmp.getbbox()
        if box is None:
            guess = int(guess * 1.2)
            continue
        h = box[3] - box[1]
        if abs(h - target_h) <= 1:
            return tmp.crop(box)
        guess = max(8, int(round(guess * target_h / float(h))))
    return tmp.crop(box)


def measure_stem(letter):
    """Width of the letter's upright stroke, in pixels.

    Read off the rendered glyph rather than taken from the face's metrics, so
    the note's stem carries the same weight as the letter beside it whatever
    font is found.
    """
    w, h = letter.size
    pixels = letter.load()
    runs = []
    for percent in range(8, 95, 4):
        y = int(h * percent / 100.0)
        run = 0
        for x in range(w):
            if pixels[x, y] > 127:
                run += 1
            elif run:
                runs.append(run)
                break
    # The narrowest run is the upright on its own. Rows through the waist of the
    # letter run straight from the upright into the middle arm and measure far
    # too wide, which is what put the note's stem inside the letter.
    return min(runs) if runs else int(w * 0.19)


_MEASURED_STEM = [None]
_MEASURED_LETTER_WIDTH = [None]


def measured_stem_weight():
    """The letter's stroke, as a fraction of the canvas height."""
    return _MEASURED_STEM[0] if _MEASURED_STEM[0] else 0.25


def measured_letter_width():
    return _MEASURED_LETTER_WIDTH[0] if _MEASURED_LETTER_WIDTH[0] else 0.74


def build_mark_mask(size, font_path):
    global STEM_RIGHT, STEM_Y1
    tangent_x, tangent_y = stem_tangent()
    # A hair inside the touch point, so the corner sits on the ball rather than
    # a whisker outside it.
    STEM_RIGHT = tangent_x
    STEM_Y1 = tangent_y
    """Draw the note and the B on one canvas and shear it into italic.

    Coordinates are unit fractions of the canvas height, so x may run past 1.0;
    the canvas is made wide enough to hold that.
    """
    width = int(round(size * MARK_CANVAS_WIDTH))
    canvas = Image.new("L", (width, size), 0)
    draw = ImageDraw.Draw(canvas)

    letter = render_letter_b(size, font_path)
    stem_weight = measure_stem(letter) / float(size)
    _MEASURED_STEM[0] = stem_weight
    _MEASURED_LETTER_WIDTH[0] = letter.size[0] / float(size)

    # The note and the letter are two glyphs side by side and must not touch.
    letter_right = B_LEFT + _MEASURED_LETTER_WIDTH[0]
    head_left = HEAD_CX - HEAD_RX
    gap = head_left - letter_right
    if gap < stem_weight * 0.25:
        sys.stderr.write(
            "The letter reaches %.3f and the note starts at %.3f, a gap of %.3f.\n"
            "Move the note right: the two glyphs run into each other.\n"
            % (letter_right, head_left, gap))
        sys.exit(1)

    # Both bottom corners of the stem have to finish inside the ball, or a
    # corner of the upright shows outside its edge.
    for corner_x in (STEM_RIGHT - stem_weight, STEM_RIGHT):
        final_x = corner_x - ITALIC_SHEAR * (STEM_Y1 - SHEAR_PIVOT)
        angle = math.radians(HEAD_ANGLE)
        dx = final_x - HEAD_CX
        dy = STEM_Y1 - HEAD_CY
        along = dx * math.cos(angle) + dy * math.sin(angle)
        across = -dx * math.sin(angle) + dy * math.cos(angle)
        reach = (along / HEAD_RX) ** 2 + (across / HEAD_RY) ** 2
        if reach > 1.02:
            sys.stderr.write(
                "The stem's bottom corner reaches %.2f of the way to the ball's "
                "edge.\nLower STEM_Y1 or move STEM_RIGHT left: the corner hangs "
                "out.\n" % reach)
            sys.exit(1)

    canvas.paste(255, (int(round(B_LEFT * size)), int(round(B_TOP * size))), letter)

    draw.polygon(head_polygon(size), fill=255)
    draw.rounded_rectangle(
        [(STEM_RIGHT - stem_weight) * size, STEM_Y0 * size, STEM_RIGHT * size, STEM_Y1 * size],
        radius=0.012 * size, fill=255)
    draw.polygon(flag_polygon(size), fill=255)

    k = ITALIC_SHEAR
    canvas = canvas.transform(
        (width, size), Image.AFFINE,
        (1.0, k, -k * SHEAR_PIVOT * size, 0.0, 1.0, 0.0),
        resample=Image.BICUBIC)

    # Anything reaching an edge of the canvas has been cut. Twice now that has
    # shipped as a flattened notehead, so it fails here instead.
    box = canvas.getbbox()
    if box is None:
        sys.stderr.write("The mark came out empty.\n")
        sys.exit(1)
    left, top, right, bottom = box
    touching = []
    if left <= 0: touching.append("left")
    if top <= 0: touching.append("top")
    if right >= width: touching.append("right")
    if bottom >= size: touching.append("bottom")
    if touching:
        sys.stderr.write(
            "The mark runs off the %s of the drawing canvas and would be cut.\n"
            "Move the geometry in, or raise MARK_CANVAS_WIDTH.\n" % " and ".join(touching))
        sys.exit(1)

    return canvas


def fit_mark(mark, size, diameter, drawn_height):
    """Scale the mark and place it so the gap between the two glyphs is centred.

    Centring the bounding box instead would put the divide off to one side,
    since the letter is wider than the note and would carry more of the disc.
    """
    box = mark.getbbox()
    crop = mark.crop(box)
    w, h = crop.size
    target_h = diameter * MARK_FILL
    target_w = target_h * w / float(h)
    max_w = diameter * MARK_MAX_WIDTH
    if target_w > max_w:
        target_h *= max_w / target_w
        target_w = max_w
    scale = target_w / float(w)
    crop = crop.resize((max(1, int(round(target_w))), max(1, int(round(target_h)))),
                       Image.LANCZOS)

    # Where the divide sits, in the cropped and scaled mark.
    gap_unit = (B_LEFT + measured_letter_width() + HEAD_CX - HEAD_RX) / 2.0
    gap_in_crop = (gap_unit * drawn_height - box[0]) * scale

    out = Image.new("L", (size, size), 0)
    out.paste(crop, (int(round(size * 0.5 - gap_in_crop)),
                     int(round(size * MARK_CENTER_Y - crop.size[1] * 0.5))))
    return out


def radial_profile(r):
    """Luminance of the polished disc as a function of normalised radius."""
    v = 172.0
    v += 26.0 * math.exp(-(r / 0.22) ** 2)          # soft bloom at the hub
    v -= 30.0 * (r ** 1.7)                          # gentle falloff outward
    v += 3.0 * math.sin(r * math.pi * 2.0 * 34.0)   # fine turned rings
    v += 3.0 * math.sin(r * math.pi * 2.0 * 9.0)    # broad rings, disc read
    if r > 0.93:
        v += 46.0 * math.sin(math.pi * min(1.0, (r - 0.93) / 0.045))
    if r > 0.975:
        v -= 150.0 * ((r - 0.975) / 0.025)
    return max(0.0, min(255.0, v))


def angular_profile(steps, seed):
    """Brightness deviation around the disc: specular lobes plus brush grain."""
    rng = random.Random(seed)
    grain = [rng.gauss(0.0, 1.0) for _ in range(steps)]
    for _ in range(6):
        grain = [(grain[i - 2] + 2 * grain[i - 1] + 3 * grain[i] +
                  2 * grain[(i + 1) % steps] + grain[(i + 2) % steps]) / 9.0
                 for i in range(steps)]
    coarse = [(rng.random() - 0.5) for _ in range(48)]
    # Narrow specular sweeps, as a spun surface throws under a single source.
    # The light runs along the same lean as the glyphs rather than across the
    # mark at a diagonal, so the bright axis passes between the letter and the
    # note instead of cutting through both. The angle is the italic slant
    # itself: a stem sheared by this much stands that far off vertical.
    axis = 90.0 - math.degrees(math.atan(ITALIC_SHEAR))

    # Stronger, narrower sweeps read as polished rather than brushed flat.
    sweeps = [(axis, 54.0, 0.17), (axis + 180.0, 46.0, 0.19),
              (axis + 46.0, 22.0, 0.12), (axis + 226.0, 19.0, 0.13)]
    values = []
    for i in range(steps):
        a = 2.0 * math.pi * i / steps
        v = 21.0 * math.cos(2.0 * (a - math.radians(axis)))
        for centre, amp, width in sweeps:
            da = (a - math.radians(centre) + math.pi) % (2.0 * math.pi) - math.pi
            v += amp * math.exp(-(da / width) ** 2)
        f = i * 48.0 / steps
        i0 = int(f) % 48
        frac = f - int(f)
        v += 10.0 * (coarse[i0] * (1.0 - frac) + coarse[(i0 + 1) % 48] * frac)
        v += 11.0 * grain[i]
        values.append(v)
    return values


def build_metal(size, seed):
    """Silver disc with radial brushing, turned rings and a machined rim."""
    radial = Image.new("L", (size, size), 0)
    dr = ImageDraw.Draw(radial)
    half = size / 2.0
    steps = int(half)
    for i in range(steps, 0, -1):
        r = i / float(steps)
        v = int(round(radial_profile(r)))
        dr.ellipse([half - i, half - i, half + i, half + i], fill=v)

    wedges = 2000
    streak = Image.new("L", (size, size), 128)
    ds = ImageDraw.Draw(streak)
    ang = angular_profile(wedges, seed)
    box = [0, 0, size - 1, size - 1]
    span = 360.0 / wedges
    for i in range(wedges):
        v = int(round(max(0.0, min(255.0, 128.0 + ang[i]))))
        ds.pieslice(box, i * span, (i + 1) * span + span * 0.7, fill=v)
    streak = streak.filter(ImageFilter.GaussianBlur(size / 500.0))

    lum = ImageChops.add(radial, streak, 1.0, -128)

    # Overall lighting from the upper left, matching the engraved shading.
    corners = Image.new("L", (2, 2))
    corners.putpixel((0, 0), 150)
    corners.putpixel((1, 0), 132)
    corners.putpixel((0, 1), 132)
    corners.putpixel((1, 1), 108)
    tilt = corners.resize((size, size), Image.BILINEAR)
    lum = ImageChops.add(lum, tilt, 1.0, -128)

    # Slightly cool silver tint.
    r_ch = lum.point(lambda v: min(255, int(v * 0.975 + 3)))
    g_ch = lum.point(lambda v: min(255, int(v * 0.985 + 4)))
    b_ch = lum.point(lambda v: min(255, int(v * 1.010 + 8)))
    return Image.merge("RGB", (r_ch, g_ch, b_ch)), lum


def solid(size, color):
    return Image.new("RGB", (size, size), color)


def mark_texture(size, seed):
    """Grain for the cut floor: fine speckle drawn out into vertical streaks.

    Returns a luminance image centred near 255 so it can be multiplied into the
    purple without darkening it much.
    """
    rng = random.Random(seed)
    cols = max(8, size // 6)
    rows = max(8, size // 90)
    small = Image.new("L", (cols, rows))
    small.putdata([int(max(0, min(255, rng.gauss(230, 22))))
                   for _ in range(cols * rows)])
    streaks = small.resize((size, size), Image.BICUBIC)

    speck = Image.new("L", (size // 3, size // 3))
    speck.putdata([int(max(0, min(255, rng.gauss(241, 10))))
                   for _ in range(speck.size[0] * speck.size[1])])
    speck = speck.resize((size, size), Image.BILINEAR)

    tex = ImageChops.multiply(streaks, speck).point(lambda v: min(255, int(v * 1.22)))
    return tex.filter(ImageFilter.GaussianBlur(size / 900.0))


def scaled(mask, factor):
    return mask.point(lambda v: int(v * factor))


def engrave(metal, lum, mark, size):
    """Cut the mark into the metal with an inner shadow and a light catch."""
    d = max(1, int(round(size * 0.0072)))
    wall = size * 0.0040
    inv = ImageChops.invert(mark)

    # Light arrives from the upper left, so the far wall of the cut is lit and
    # the near wall sits in shadow.
    inner_shadow = ImageChops.multiply(
        ImageChops.offset(inv, int(d * 1.6), int(d * 1.6)).filter(
            ImageFilter.GaussianBlur(wall * 2.2)), mark)
    inner_light = ImageChops.multiply(
        ImageChops.offset(inv, -d, -d).filter(ImageFilter.GaussianBlur(wall)), mark)
    inner_glow = ImageChops.multiply(
        ImageChops.offset(inv, -d * 2, -d * 2).filter(
            ImageFilter.GaussianBlur(wall * 3.0)), mark)
    # Contact darkening all the way round the cut.
    occlusion = ImageChops.multiply(
        inv.filter(ImageFilter.GaussianBlur(size * 0.009)), mark)
    outer_light = ImageChops.multiply(
        ImageChops.offset(mark, -max(1, int(d * 0.6)), -max(1, int(d * 0.6))).filter(
            ImageFilter.GaussianBlur(wall * 0.6)), inv)
    outer_shadow = ImageChops.multiply(
        ImageChops.offset(mark, d, d).filter(ImageFilter.GaussianBlur(size * 0.009)),
        inv)

    # Purple floor, lit from the upper left and running bright: the light half
    # goes past the body colour toward the lit edge rather than toward black.
    # A gentle lift across the mark rather than a full sweep from the lit edge to
    # the shadow. At full spread the letter sits at the light end and the note at
    # the dark one, so the two read as different colours.
    def toward(colour, amount):
        return tuple(int(round(PURPLE_MAIN[i] + (colour[i] - PURPLE_MAIN[i]) * amount))
                     for i in range(3))

    # Centred on the disc rather than running corner to corner: a diagonal ramp
    # hands the letter one end of the range and the note the other, however
    # narrow the range is.
    ramp = Image.new("L", (size, 1))
    ramp.putdata([int(round(255.0 * (x / float(size - 1)))) for x in range(size)])
    steps = 256
    lut = []
    for i in range(steps):
        t = i / float(steps - 1)
        colour = toward(PURPLE_LIGHT, 0.30) if t < 0.5 else toward(PURPLE_DEEP, 0.30)
        blend = abs(t - 0.5) * 2.0
        lut.append(tuple(int(round(PURPLE_MAIN[c] + (colour[c] - PURPLE_MAIN[c]) * blend))
                         for c in range(3)))

    radial = Image.new("L", (size, size))
    half = size / 2.0
    pixels = radial.load()
    for y in range(size):
        dy = (y - half) / half
        for x in range(size):
            dx = (x - half) / half
            distance = math.hypot(dx, dy)
            pixels[x, y] = max(0, min(255, int(round(distance * 255.0 / 1.15))))

    grad = Image.new("RGB", (size, size))
    grad.putdata([lut[min(steps - 1, v * steps // 256)] for v in radial.getdata()])

    # Its own grain, coarser than the brushing on the surrounding metal, so the
    # cut floor reads as a different material rather than tinted silver.
    grain = mark_texture(size, 31)
    metal_echo = lum.point(lambda v: int(max(0, min(255, 190 + (v - 168) * 0.22))))
    floor = ImageChops.multiply(grad, Image.merge("RGB", (grain,) * 3))
    floor = ImageChops.multiply(floor, Image.merge("RGB", (metal_echo,) * 3))
    floor = floor.point(lambda v: min(255, int(v * 1.26)))

    floor = Image.composite(solid(size, PURPLE_DEEP), floor, scaled(occlusion, 0.45))
    floor = Image.composite(solid(size, (58, 12, 150)), floor, scaled(inner_shadow, 0.90))
    floor = Image.composite(solid(size, PURPLE_LIGHT), floor, scaled(inner_glow, 0.55))
    floor = Image.composite(solid(size, PURPLE_HOT), floor, scaled(inner_light, 0.90))

    surface = Image.composite(solid(size, (66, 68, 76)), metal,
                              scaled(outer_shadow, 0.32))
    surface = Image.composite(solid(size, (253, 253, 255)), surface,
                              scaled(outer_light, 0.45))

    return Image.composite(floor, surface, mark)


# A compact disc is 120mm across with a 15mm hole, so the hole is an eighth of
# the diameter.
HOLE_FRACTION = 0.125


def hole_alpha(size, supersample=3):
    big = size * supersample
    a = Image.new("L", (big, big), 0)
    radius = big * HOLE_FRACTION / 2.0
    centre = big / 2.0
    ImageDraw.Draw(a).ellipse([centre - radius, centre - radius,
                               centre + radius, centre + radius], fill=255)
    return a.resize((size, size), Image.LANCZOS)


def disc_alpha(size, supersample=3):
    big = size * supersample
    a = Image.new("L", (big, big), 0)
    ImageDraw.Draw(a).ellipse([0, 0, big - 1, big - 1], fill=255)
    return a.resize((size, size), Image.LANCZOS)


def build(size, seed):
    font_path = find_font()
    # Drawn at twice the output height on a canvas wider than it is tall, then
    # cropped to what was actually drawn and fitted to the disc.
    mark = build_mark_mask(size * 2, font_path)
    mark = fit_mark(mark, size, size, size * 2)
    metal, lum = build_metal(size, seed)
    art = engrave(metal, lum, mark, size)

    disc = disc_alpha(size)

    # The mark runs wider than the disc, and the part that hangs over the rim
    # stays visible rather than being cut off at the edge. A soft dark violet
    # edge under that overhang keeps it legible against whatever is behind it.
    outside = ImageChops.subtract(mark, disc)
    rim = ImageChops.subtract(
        mark.filter(ImageFilter.GaussianBlur(size * 0.006)), mark)
    rim = ImageChops.multiply(rim, ImageChops.invert(disc))
    rim = rim.point(lambda v: min(255, int(v * 2.4)))

    art = Image.composite(solid(size, PURPLE_DEEP), art, rim)

    alpha = ImageChops.lighter(disc, mark)
    alpha = ImageChops.lighter(alpha, scaled(rim, 0.85))

    # Punch the spindle hole clean through, and darken the metal just around it
    # so the edge reads as thickness rather than as a sticker.
    # The hole goes through the disc only. Where the letter or the note crosses
    # it, the glyph stays whole and the hole gives way.
    hole = ImageChops.subtract(hole_alpha(size), mark)
    lip = ImageChops.subtract(hole.filter(ImageFilter.GaussianBlur(size * 0.010)), hole)
    lip = ImageChops.subtract(lip, mark)
    art = Image.composite(solid(size, (96, 98, 104)), art, scaled(lip, 0.55))
    alpha = ImageChops.subtract(alpha, hole)

    art.putalpha(alpha)
    return art


ICONSET = [(16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"),
           (128, "128x128"), (256, "128x128@2x"), (256, "256x256"),
           (512, "256x256@2x"), (512, "512x512"), (1024, "512x512@2x")]


def main():
    ap = argparse.ArgumentParser(description="Build the BTunes logo artwork.")
    ap.add_argument("--master", type=int, default=2048,
                    help="internal render size in pixels (default: 2048)")
    ap.add_argument("--sizes", default="1024,512,256,128",
                    help="comma separated PNG sizes (default: 1024,512,256,128)")
    ap.add_argument("--splash", type=int, default=480,
                    help="splash image size in pixels (default: 480)")
    ap.add_argument("--seed", type=int, default=7,
                    help="brushing pattern seed (default: 7)")
    ap.add_argument("--iconset", default=None,
                    help="also write a macOS .iconset directory here")
    ap.add_argument("outdir", help="directory to write the PNG files into")
    args = ap.parse_args()

    os.makedirs(args.outdir, exist_ok=True)
    art = build(args.master, args.seed)

    for s in [int(x) for x in args.sizes.split(",") if x.strip()]:
        out = os.path.join(args.outdir, "btunes-%d.png" % s)
        art.resize((s, s), Image.LANCZOS).save(out)
        print("wrote %s" % out)

    splash = os.path.join(args.outdir, "btunes-splash.png")
    art.resize((args.splash, args.splash), Image.LANCZOS).save(splash)
    print("wrote %s" % splash)

    if args.iconset:
        os.makedirs(args.iconset, exist_ok=True)
        for px, name in ICONSET:
            art.resize((px, px), Image.LANCZOS).save(
                os.path.join(args.iconset, "icon_%s.png" % name))
        print("wrote %s" % args.iconset)


if __name__ == "__main__":
    main()
