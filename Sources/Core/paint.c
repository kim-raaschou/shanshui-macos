#include "paint.h"

#include <math.h>
#include <stdlib.h>
#include <sys/mman.h>

// The shader's hash; only at the noise's lattice points, so sin is rare.
static float hash(float x, float y) {
  float v = sinf(x * 127.1f + y * 311.7f) * 43758.5453f;
  return v - floorf(v);
}

static inline float smooth(float t) { return t * t * (3.0f - 2.0f * t); }

// The front's wave, as the shader has it: two octaves of noise, 75 at most.
#define WAVE 75.0
static const float CELL[2] = {90.0f, 23.0f}, STRENGTH[2] = {120.0f, 30.0f};

// One octave over a run of columns.
typedef struct {
  int cells;    // cells the columns cross
  int *cut;   // cells + 1: the first column of each cell
  float *weight;  // per column: smoothstep of the place in the cell
  float *value; // the lattice: cells + 1 values for every row of cells the strip's height crosses
} Octave;

// A run of columns, the picture's or the delay's, and the wave along a row.
typedef struct {
  int n;
  float *rel;   // their x in the world, from the strip's left
  float *gx;    // and as the grain's cell, a third of a world unit
  float *wave;  // the wave of the row last asked for
  Octave octave[2];
} Columns;

// The columns x0.. of the `w` the strip is cut in.
static void openColumns(Columns *c, const Paint *p, int x0, int n, int w) {
  c->n = n;
  double *world = malloc(sizeof(double) * (size_t)n);
  c->rel = malloc(sizeof(float) * (size_t)n);
  c->gx = malloc(sizeof(float) * (size_t)n);
  c->wave = malloc(sizeof(float) * (size_t)n);
  for (int x = 0; x < n; x++) {
    double u = (x0 + x + 0.5) / w * p->width;
    c->rel[x] = (float)u;
    world[x] = p->start + u;
    c->gx[x] = floorf((float)world[x] * 3.0f);
  }
  for (int k = 0; k < 2; k++) {
    Octave *o = &c->octave[k];
    const double cell = CELL[k], first = floor(world[0] / cell), last = floor(world[n - 1] / cell);
    o->cut = malloc(sizeof(int) * (size_t)(last - first + 2));
    o->weight = malloc(sizeof(float) * (size_t)n);
    o->cells = 0;
    o->cut[0] = 0;
    for (int x = 0; x < n; x++) {
      double q = world[x] / cell, i = floor(q);
      while (first + o->cells < i) o->cut[++o->cells] = x;
      o->weight[x] = smooth((float)(q - i));
    }
    o->cut[++o->cells] = n;
    const int rows = (int)floorf((float)PAINT_HEIGHT / CELL[k]) + 2;
    o->value = malloc(sizeof(float) * (size_t)(rows * (o->cells + 1)));
    for (int j = 0; j < rows; j++)
      for (int i = 0; i <= o->cells; i++) o->value[j * (o->cells + 1) + i] = hash((float)(first + i), (float)j);
  }
  free(world);
}

static void closeColumns(Columns *c) {
  for (int k = 0; k < 2; k++) { free(c->octave[k].cut); free(c->octave[k].weight); free(c->octave[k].value); }
  free(c->rel); free(c->gx); free(c->wave);
}

// The row y of `h` in the world.
static inline float worldY(int y, int h) { return (float)((y + 0.5) / h * PAINT_HEIGHT); }

// The wave of that row: for each octave (noise - 0.5) * strength.
static void wave(Columns *c, int y, int h) {
  const float my = worldY(y, h);
  float *restrict out = c->wave;
  for (int x = 0; x < c->n; x++) out[x] = 0.0f;
  for (int k = 0; k < 2; k++) {
    const Octave *o = &c->octave[k];
    float q = my / CELL[k], j = floorf(q), f = smooth(q - j);
    const float *a = o->value + (int)j * (o->cells + 1), *b = a + o->cells + 1;
    for (int i = 0; i < o->cells; i++) {
      float e = a[i] + (b[i] - a[i]) * f, d = a[i + 1] + (b[i + 1] - a[i + 1]) * f;
      float base = (e - 0.5f) * STRENGTH[k], slope = (d - e) * STRENGTH[k];
      const float *restrict weight = o->weight;
      for (int x = o->cut[i]; x < o->cut[i + 1]; x++) out[x] += base + slope * weight[x];
    }
  }
}

// A column's side in the world.
static inline double side(const Paint *p, int x) { return p->start + (double)x / p->w * p->width; }

// The delay's column (or row) of a pixel's: read without a filter, since
// blending two delays would invent a third.
static inline int delayAt(int x, int w, int ow) { return (int)((x + 0.5) / w * ow); }

// How much of the ink is in, `t` of the way through the edge.
static inline float inkIn(float t) { return smooth(t < 0.0f ? 0.0f : (t > 1.0f ? 1.0f : t)); }

// The paper's grain, as the shader has it: 0, or how much of the ink it puts
// on the pixel. The cell is a third of a world unit; `gx` is its column and
// `gy` its row.
static inline float grainAt(const Paint *p, float gx, float gy) {
  float g = (hash(gx, gy) - 0.5f) * (float)p->grain;
  return g > 0.0f ? g : 0.0f;
}

// The grain's row of the world's height `my`.
static inline float grainRow(float my) { return floorf(my * 3.0f); }

// One pixel: the picture with `a` of its ink in, and the grain over that. The
// paper is what is behind (the shader puts it under the back layer), and the
// shader mixes the grain into every layer; put over the top one alone it
// comes to the same picture.
static inline uint32_t pixel(const Paint *p, float a, const uint8_t *q, float g) {
  const float clear = (float)(1.0 - p->mist), mist = (float)p->mist;
  float r = (float)q[0] * (1.0f / 255.0f);
  float qa = p->channels == 2 ? (float)q[1] * (1.0f / 255.0f) : 1.0f;
  // The pixel is ink * ti + paper * pa, with alpha al.
  float ti = clear * (qa - r) * a, pa = (clear * r + mist * qa) * a, al = qa * a;
  ti = ti * (1.0f - g) + g;
  pa = pa * (1.0f - g);
  al = al * (1.0f - g) + g;
  uint32_t color = (uint32_t)(255.0f * al + 0.5f) << 24;
  for (int c = 0; c < 3; c++) color |= (uint32_t)(p->ink[c] * 255.0f * ti + p->paper[c] * 255.0f * pa + 0.5f) << (16 - 8 * c);
  return color;
}

// The same pixel over the paper alone, as one byte: its share of the ink. Over
// the paper, ink * ti + paper * pa + paper * (1 - al) is paper + (ink - paper) * ti,
// grain and mist included, so the colour is the system's to put on (mono).
static inline uint8_t share(const Paint *p, float a, const uint8_t *q, float g) {
  const float clear = (float)(1.0 - p->mist);
  float r = (float)q[0] * (1.0f / 255.0f);
  float qa = p->channels == 2 ? (float)q[1] * (1.0f / 255.0f) : 1.0f;
  float ti = clear * (qa - r) * a;
  ti = ti * (1.0f - g) + g;
  return (uint8_t)(255.0f * ti + 0.5f);
}

// Opaque: the colour of every share, with the paper in it and nothing to blend.
static void shades(const Paint *p, uint32_t *lut) {
  for (int s = 0; s < 256; s++) {
    uint32_t color = 0xFFu << 24;
    for (int c = 0; c < 3; c++) color |= (uint32_t)((p->paper[c] + (p->ink[c] - p->paper[c]) * (float)s * (1.0f / 255.0f)) * 255.0f + 0.5f) << (16 - 8 * c);
    lut[s] = color;
  }
}

// Large arrays straight from the system, so that letting go of them gives the
// memory back at once.
static void *pages(size_t bytes) {
  void *m = mmap(NULL, bytes, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0);
  return m == MAP_FAILED ? NULL : m;
}
static void unpages(void *m, size_t bytes) { if (m) munmap(m, bytes); }

void paint(const Paint *p, int x0, int x1, uint8_t *dst, long stride) {
  const int n = x1 - x0;
  if (n <= 0) return;
  const float front = (float)(p->front - p->start), softness = (float)(1.0 / p->softness), spread = (float)(p->spread / 65534.0);
  Columns c;
  openColumns(&c, p, x0, n, p->w);
  int *ox = malloc(sizeof(int) * (size_t)n);
  for (int i = 0; i < n; i++) ox[i] = delayAt(x0 + i, p->w, p->ow) * 2;
  uint32_t lut[256];
  if (p->opaque) shades(p, lut);
  for (int y = p->y0; y < p->y1; y++) {
    wave(&c, y, p->h);
    const float my = worldY(y, p->h);
    const uint8_t *ol = p->o + (long)delayAt(y, p->h, p->oh) * p->ow * 2;
    const uint8_t *ql = p->q + ((long)y * p->w + x0) * p->channels;
    uint8_t *restrict row = dst + (long)(y - p->y0) * stride;
    uint32_t *restrict out = (uint32_t *)(void *)row;
    for (int i = 0; i < n; i++) {
      // The front is taken at the pixel: its own x and the wave there. The
      // paper, which has no delay, is always in.
      const int code = ol[ox[i]] << 8 | ol[ox[i] + 1];
      const float a = code > 0 ? inkIn((front - (c.rel[i] + (float)(code - 1) * spread + c.wave[i])) * softness) : 1.0f;
      const float g = p->grain > 0.0 ? grainAt(p, c.gx[i], grainRow(my)) : 0.0f;
      if (p->mono) row[i] = share(p, a, ql + i * p->channels, g);
      else if (p->opaque) out[i] = lut[share(p, a, ql + i * p->channels, g)];
      else out[i] = pixel(p, a, ql + i * p->channels, g);
    }
  }
  free(ox);
  closeColumns(&c);
}

// ---- only what a step of the front changes

// Each item is a pixel of the delay: its row (14 bits: the tallest strip is
// 16384), its column (9 bits) and where in its bucket it is painted (9 bits).
// A bucket is one world unit.
struct List {
  float base;       // the first bucket's x, from the strip's left
  int buckets;
  int *start;      // the first item of each bucket, and the end of the last
  uint32_t *items;
  int *xs, *ys;     // the first column, from x0, of each of the delay's columns; and so the rows, from y0
  // Where the delay's pixel covers several of the picture's: how much later
  // than it each one is painted, in 64ths of a world unit.
  int8_t *offset;
  // A pixel is its colour with all the ink in, times how much is in: `full`
  // has that colour for every grey (and alpha) the picture can have. The layer
  // in front has the grain over it: per cell of the grain its strength
  // (`grains`, with the cell of each column and row in `gcol` and `grow`), and for
  // each strength its colour and what it leaves of the pixel (of 256).
  uint32_t *full;
  uint8_t *grains;
  uint16_t *gcol, *grow;
  int gcols;
  uint32_t grainColor[256];
  uint16_t rest[256];
  // Opaque: the colour of each share, the paper in it.
  uint32_t lut[256];
  // `items` and `offset` are the system's pages, given back whole when let go.
  size_t itemBytes, offsetBytes;
};

// The first of the pixels a..b, from a, in each of the delay's o0..o0 + n - 1; and b.
static int *cuts(int a, int b, int w, int ow, int o0, int n) {
  int *c = malloc(sizeof(int) * (size_t)(n + 1));
  int t = 0;
  c[0] = 0;
  for (int x = a; x < b; x++) while (delayAt(x, w, ow) - o0 > t) c[++t] = x - a;
  while (t < n) c[++t] = b - a;
  return c;
}

// A pixel is painted within the wave of its place: the buckets start a little
// before that.
#define SLACK ((float)WAVE + 5.0f)

static List *makeList(const Paint *p, int x0, int x1) {
  const int n = x1 - x0, tall = p->y1 - p->y0;
  if (n <= 0 || tall <= 0) return NULL;
  const int o0 = delayAt(x0, p->w, p->ow), on = delayAt(x1 - 1, p->w, p->ow) - o0 + 1;
  const int r0 = delayAt(p->y0, p->h, p->oh), rn = delayAt(p->y1 - 1, p->h, p->oh) - r0 + 1;
  Columns l, f;
  openColumns(&l, p, o0, on, p->ow);
  const double buckets = ceil((double)(l.rel[on - 1] - l.rel[0]) + p->spread + 2.0 * SLACK) + 1.0;
  if (on > PAINT_TILE || p->oh > 16384 || buckets > 65536.0) { closeColumns(&l); return NULL; }
  List *s = calloc(1, sizeof(List));
  s->base = l.rel[0] - SLACK;
  s->buckets = (int)buckets;
  s->xs = cuts(x0, x1, p->w, p->ow, o0, on);
  s->ys = cuts(p->y0, p->y1, p->h, p->oh, r0, rn);
  // The picture's own columns, for what is kept per pixel.
  openColumns(&f, p, x0, n, p->w);
  if (p->ow != p->w || p->oh != p->h) { s->offsetBytes = (size_t)n * (size_t)tall; s->offset = pages(s->offsetBytes); }
  if (p->grain > 0.0) {
    // The grain's cells are larger than a fine strip's pixels: each cell once.
    s->gcol = malloc(sizeof(uint16_t) * (size_t)n);
    s->grow = malloc(sizeof(uint16_t) * (size_t)tall);
    float *cy = malloc(sizeof(float) * (size_t)tall);
    int cols = 0, rows = 0;
    for (int x = 0; x < n; x++) { if (x == 0 || f.gx[x] != f.gx[x - 1]) cols++; s->gcol[x] = (uint16_t)(cols - 1); }
    for (int y = 0; y < tall; y++) {
      const float gy = grainRow(worldY(p->y0 + y, p->h));
      if (y == 0 || gy != cy[rows - 1]) cy[rows++] = gy;
      s->grow[y] = (uint16_t)(rows - 1);
    }
    s->gcols = cols;
    s->grains = malloc((size_t)cols * (size_t)rows);
    // The strongest grain is half of `grain`: the strengths are parts of that.
    const float most = (float)p->grain * 0.5f;
    for (int y = 0; y < rows; y++) {
      int c = 0;
      for (int x = 0; x < n; x++) {
        if (x > 0 && s->gcol[x] == s->gcol[x - 1]) continue;
        s->grains[(long)y * cols + c++] = (uint8_t)(grainAt(p, f.gx[x], cy[y]) / most * 255.0f);
      }
    }
    free(cy);
  }
  // The strongest grain is half of `grain`: the strengths are parts of that.
  const float strongest = (float)p->grain * 0.5f, spread = (float)(p->spread / 65534.0);
  // The items with their buckets above them, then sorted by bucket: `start`
  // counts a bucket two places on, so that placing leaves it at its start.
  // Only for the making: taken from the system and given straight back.
  const size_t itemBytes = sizeof(uint64_t) * (size_t)on * (size_t)rn;
  uint64_t *item = mmap(NULL, itemBytes, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0);
  if (item == MAP_FAILED) { closeColumns(&l); closeColumns(&f); free(s->xs); free(s->ys); unpages(s->offset, s->offsetBytes); free(s->grains); free(s->gcol); free(s->grow); free(s); return NULL; }
  long total = 0;
  s->start = calloc((size_t)(s->buckets + 2), sizeof(int));
  for (int r = 0; r < rn; r++) {
    wave(&l, r0 + r, p->oh);
    const uint8_t *ol = p->o + ((long)(r0 + r) * p->ow + o0) * 2;
    for (int t = 0; t < on; t++) {
      // A pixel that looks the same before and after is left out: the paper,
      // one that is clear, and in the back layer, which has only the paper
      // behind it, also one of the paper's colour.
      const int code = ol[t * 2] << 8 | ol[t * 2 + 1];
      if (code == 0) continue;
      int has = 0;
      for (int y = s->ys[r]; y < s->ys[r + 1] && !has; y++)
        for (int x = s->xs[t]; x < s->xs[t + 1]; x++) {
          const uint8_t *q = p->q + ((long)(p->y0 + y) * p->w + x0 + x) * p->channels;
          int alpha = p->channels == 2 ? q[1] : 255;
          has |= p->ground ? alpha != q[0] : alpha != 0;
        }
      if (!has) continue;
      const float when = l.rel[t] + (float)(code - 1) * spread + l.wave[t];
      float d = when - s->base;
      d = d < 0.0f ? 0.0f : (d > (float)(s->buckets - 1) ? (float)(s->buckets - 1) : d);
      const int b = (int)d;
      item[total++] = (uint64_t)b << 32 | (uint64_t)r << 18 | (uint64_t)t << 9 | (uint64_t)((d - (float)b) * 512.0f);
      s->start[b + 2]++;
    }
    for (int y = s->ys[r]; y < s->ys[r + 1]; y++) {
      if (s->offset) {
        wave(&f, p->y0 + y, p->h);
        for (int t = 0; t < on; t++)
          for (int x = s->xs[t]; x < s->xs[t + 1]; x++) {
            float v = (f.rel[x] - l.rel[t] + f.wave[x] - l.wave[t]) * 64.0f;
            s->offset[(long)y * n + x] = (int8_t)(v < -127.0f ? -127 : (v > 127.0f ? 127 : (int)lrintf(v)));
          }
      }
    }
  }
  for (int b = 0; b < s->buckets; b++) s->start[b + 2] += s->start[b + 1];
  s->itemBytes = sizeof(uint32_t) * (size_t)(total > 0 ? total : 1);
  s->items = pages(s->itemBytes);
  for (long i = 0; i < total; i++) s->items[s->start[(item[i] >> 32) + 1]++] = (uint32_t)item[i];
  munmap(item, itemBytes);
  closeColumns(&f);
  closeColumns(&l);
  const int tones = p->channels == 2 ? 65536 : 256;
  s->full = malloc(sizeof(uint32_t) * (size_t)tones);
  for (int i = 0; i < tones; i++) {
    const int r = i & 255, qa = p->channels == 2 ? i >> 8 : 255;
    const uint8_t q[2] = {(uint8_t)(r < qa ? r : qa), (uint8_t)qa};
    s->full[i] = p->mono || p->opaque ? share(p, 1.0f, q, 0.0f) : pixel(p, 1.0f, q, 0.0f);
  }
  for (int i = 0; i < 256; i++) {
    const float g = (float)i * (1.0f / 255.0f) * strongest;
    const uint8_t none[2] = {0, 0};
    s->grainColor[i] = p->mono || p->opaque ? share(p, 0.0f, none, g) : pixel(p, 0.0f, none, g);
    s->rest[i] = (uint16_t)((1.0f - g) * 256.0f);
  }
  if (p->opaque) shades(p, s->lut);
  return s;
}

void freeList(List *l) {
  if (!l) return;
  free(l->start); unpages(l->items, l->itemBytes); free(l->xs); free(l->ys); unpages(l->offset, l->offsetBytes); free(l->full); free(l->grains); free(l->gcol); free(l->grow);
  free(l);
}

// How much of the ink is in (of 256), `t` 2^20ths of the way through the
// edge: for the pixels that are painted apart from their item.
static uint16_t edge[1025];
static inline uint32_t inside(int64_t t) {
  t = t < 0 ? 0 : (t > 1048576 ? 1048576 : t);
  return edge[t >> 10];
}

// What changes when the front goes from `from` to p->front; tells how many of
// the delay's pixels that was.
static int repaint(const Paint *p, const List *l, int x0, int n, double from, uint8_t *dst, long stride) {
  const float front = (float)(p->front - p->start), softness = (float)(1.0 / p->softness);
  double a = from < p->front ? from : p->front, b = from < p->front ? p->front : from;
  // A pixel changes while the front is between its moment and `softness` after
  // it, and a pixel of an item is at most two world units from it.
  const int8_t *const dv = l->offset;
  const double slack = dv ? 2.0 : 0.0;
  double first = floor(a - p->start - p->softness - slack - (double)l->base), last = floor(b - p->start + slack - (double)l->base);
  if (last < 0 || first > l->buckets - 1) return 0;
  int b0 = first < 0 ? 0 : (int)first, b1 = last > l->buckets - 1 ? l->buckets - 1 : (int)last;
  if (!edge[1024]) for (int i = 0; i <= 1024; i++) edge[i] = (uint16_t)(smooth((float)i * (1.0f / 1024.0f)) * 256.0f + 0.5f);
  const int64_t perOffset = (int64_t)(softness * (1048576.0f / 64.0f) + 0.5f);
  // Two channels at a time, each with eight bits of room above it. Under the
  // grain it is rounded down, so the grain added to it never passes a channel.
  const uint32_t pair = 0x00FF00FFu, half = l->grains ? 0 : 0x00800080u;
  for (int bucket = b0; bucket <= b1; bucket++) {
    float base = l->base + (float)bucket;
    for (int i = l->start[bucket]; i < l->start[bucket + 1]; i++) {
      uint32_t item = l->items[i];
      int oy = (int)(item >> 18), t = (int)(item >> 9) & 511;
      const float when = base + (float)(item & 511u) * (1.0f / 512.0f);
      // The item's place in the edge; each pixel's is that less its own delay.
      // Far from the edge it is all in or all out: kept where a whole number holds it.
      const float t0 = (front - when) * softness, near = t0 < -4096.0f ? -4096.0f : (t0 > 4096.0f ? 4096.0f : t0);
      const int64_t place = (int64_t)(near * 1048576.0f);
      const uint32_t whole = (uint32_t)(inkIn(t0) * 256.0f + 0.5f);
      for (int y = l->ys[oy]; y < l->ys[oy + 1]; y++) {
        const uint8_t *ql = p->q + ((long)(p->y0 + y) * p->w + x0) * p->channels;
        const int8_t *dl = dv ? dv + (long)y * n : NULL;
        const uint8_t *gl = l->grains ? l->grains + (long)l->grow[y] * l->gcols : NULL;
        const uint16_t *gc = l->gcol;
        uint8_t *row = dst + (long)y * stride;
        uint32_t *out = (uint32_t *)(void *)row;
        for (int x = l->xs[t]; x < l->xs[t + 1]; x++) {
          const uint32_t amount = dl ? inside(place - dl[x] * perOffset) : whole;
          const uint32_t e = l->full[p->channels == 2 ? ql[x * 2] | ql[x * 2 + 1] << 8 : ql[x]];
          const uint32_t g = gl ? gl[gc[x]] : 0;
          const uint32_t m = gl ? (amount * l->rest[g]) >> 8 : amount;
          // One byte: the share alone, rounded as each channel is.
          if (p->mono || p->opaque) {
            const uint8_t s = (uint8_t)(((e * m + (half & 0xFFu)) >> 8) + (gl ? l->grainColor[g] : 0));
            if (p->mono) row[x] = s;
            else out[x] = l->lut[s];
            continue;
          }
          out[x] =(((((e & pair) * m + half) >> 8) & pair) | ((((e >> 8) & pair) * m + half) & ~pair)) + (gl ? l->grainColor[g] : 0);
        }
      }
    }
  }
  return l->start[b1 + 1] - l->start[b0];
}

int reaches(const Paint *p, int x0, int x1, double from) {
  if (from == p->front) return 0;
  double a = from < p->front ? from : p->front, b = from < p->front ? p->front : from;
  // A pixel at x is painted between x - WAVE and x + spread + WAVE, and
  // takes `softness` to come in.
  return side(p, x1) > a - p->softness - p->spread - (WAVE + 1.0) && side(p, x0) < b + (WAVE + 1.0);
}

int advance(const Paint *p, List **l, int x0, int x1, double from, uint8_t *dst, long stride) {
  if (!*l) *l = makeList(p, x0, x1);
  int changed = 1;
  if (*l) changed = repaint(p, *l, x0, x1 - x0, from, dst, stride) > 0;
  else paint(p, x0, x1, dst, stride);
  // All of it is painted: the list has no more to tell.
  if (p->front - p->softness > side(p, x1) + p->spread + (WAVE + 1.0)) { freeList(*l); *l = NULL; }
  return changed;
}

int extent(const Paint *p, int x0, int x1, int *y0, int *y1) {
  // The grain covers all of the layer it is on.
  if (p->channels != 2 || p->grain > 0.0) { *y0 = 0; *y1 = p->h; return 1; }
  int a = -1, b = -1;
  for (int y = 0; y < p->h; y++) {
    const uint8_t *ql = p->q + ((long)y * p->w + x0) * 2 + 1;
    int has = 0;
    for (int x = 0; x < x1 - x0; x++) has |= ql[x * 2];
    if (has) { if (a < 0) a = y; b = y + 1; }
  }
  if (a < 0) return 0;
  *y0 = a; *y1 = b;
  return 1;
}
