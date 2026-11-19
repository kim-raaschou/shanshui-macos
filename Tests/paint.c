// pintura.frag written out pixel by pixel, against paint.c: every pixel of
// seven tiles, painted whole and after the front has walked over them, for
// paper alone and for each kind of layer, with the delay at half and at full
// size. Fails when a channel is more than 3 of 255 off the shader (the layer with the grain rounds down twice).
//
//   make test    with the sanitizers
//   make bench   the time of a step
#include "paint.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static double now(void) { struct timespec a; clock_gettime(CLOCK_MONOTONIC, &a); return a.tv_sec * 1e3 + a.tv_nsec / 1e6; }

static float fract(float v) { return v - floorf(v); }
static float hash(float x, float y) { return fract(sinf(x * 127.1f + y * 311.7f) * 43758.5453f); }
static float mixf(float a, float b, float t) { return a + (b - a) * t; }
static float noise(float px, float py) {
  float ix = floorf(px), iy = floorf(py), fx = px - ix, fy = py - iy;
  fx = fx * fx * (3.0f - 2.0f * fx); fy = fy * fy * (3.0f - 2.0f * fy);
  return mixf(mixf(hash(ix, iy), hash(ix + 1, iy), fx), mixf(hash(ix, iy + 1), hash(ix + 1, iy + 1), fx), fy);
}

// The pixel as seen: over the paper (with its grain), r g b in 0..1.
static void shader(const Paint *p, int x, int y, float *out) {
  float u = (float)((x + 0.5) / p->w), v = (float)((y + 0.5) / p->h);
  float mx = (float)(p->start + (x + 0.5) / p->w * p->width), my = v * 700.0f;
  const uint8_t *q = p->q + ((long)y * p->w + x) * p->channels;
  float r = q[0] / 255.0f, qa = p->channels == 2 ? q[1] / 255.0f : 1.0f;
  int ox = (int)(u * p->ow), oy = (int)(v * p->oh);
  if (ox > p->ow - 1) ox = p->ow - 1;
  if (oy > p->oh - 1) oy = p->oh - 1;
  const uint8_t *o = p->o + ((long)oy * p->ow + ox) * 2;
  float code = o[0] * 256.0f + o[1], a = 1.0f;
  if (code > 0.0f) {
    float delay = (code - 1.0f) / 65534.0f;
    float wave = (noise(mx / 90.0f, my / 90.0f) - 0.5f) * 120.0f + (noise(mx / 23.0f, my / 23.0f) - 0.5f) * 30.0f;
    float when = (float)((x + 0.5) / p->w * p->width) + delay * (float)p->spread + wave;
    float t = ((float)(p->front - p->start) - when) / (float)p->softness;
    t = t < 0 ? 0 : (t > 1 ? 1 : t);
    a = t * t * (3.0f - 2.0f * t);
  }
  float g = (hash(floorf(mx * 3.0f), floorf(my * 3.0f)) - 0.5f) * (float)p->grain;
  if (g < 0) g = 0;
  for (int c = 0; c < 3; c++) {
    float cc = p->ink[c] * qa + (p->paper[c] - p->ink[c]) * r;
    cc = mixf(cc, p->paper[c] * qa, (float)p->mist);
    float over = cc * a + (1.0f - qa * a) * p->paper[c];
    out[c] = (1.0f - g) * over + g * p->ink[c];
  }
}

// One size of strip; tells the most a channel is off the shader, or -1 when
// some steps were painted whole (no tile kept a list: the size is past what a list holds).
static int size(int w, int h, int steps) {
  int T = PAINT_TILE, worst = 0, whole = 0;
  printf("%d x %d\n", w, h);
  uint8_t *q1 = malloc((size_t)w * h), *q2 = malloc((size_t)w * h * 2);
  srand(7);
  for (long i = 0; i < (long)w * h; i++) {
    int a = (i / 97) % 5 == 0 ? 0 : ((i / 31) % 3 == 0 ? 255 : rand() & 255);
    q2[i * 2 + 1] = (uint8_t)a; q2[i * 2] = (uint8_t)(a ? rand() % (a + 1) : 0);
    q1[i] = (uint8_t)((i / 53) % 4 == 0 ? 255 : rand() & 255);
  }
  double view = 700.0 * w / h;
  for (int fine = 0; fine < 2; fine++) {
    int ow = fine ? w : w / 2, oh = fine ? h : h / 2;
    uint8_t *o = malloc((size_t)ow * oh * 2);
    for (int y = 0; y < oh; y++) for (int x = 0; x < ow; x++) {
      int bx = fine ? x / 14 : x / 7, by = fine ? y / 10 : y / 5;
      unsigned v = (unsigned)(bx * 7919 + by * 104729) * 2654435761u;
      unsigned code = (v >> 8) % 3 == 0 ? 0 : 1 + (v >> 12) % 65535;
      o[(y * ow + x) * 2] = (uint8_t)(code >> 8); o[(y * ow + x) * 2 + 1] = (uint8_t)code;
    }
    for (int variant = 0; variant < 8; variant++) {
      // 0 paper alone, 1 the layer in front (grain), 2 a middle layer, 3 the back layer (mist);
      // 4 and 5 are 0 and 3 in one byte a pixel (mono), 6 and 7 opaque with the paper in
      const int kind = variant < 4 ? variant : (variant % 2 == 0 ? 0 : 3), px = variant == 4 || variant == 5 ? 1 : 4, opaque = variant >= 6;
      Paint p = {kind == 0 ? q1 : q2, kind == 0 ? 1 : 2, w, h, o, ow, oh, 40 * view, view, 0, 140, 40,
                  kind <= 1 ? 0.06 : 0, kind == 3 ? 0.35 : 0, kind == 0 || kind == 3, kind == 0 ? 0 : 300, kind == 0 ? h : 1900,
                  {0.95f, 0.91f, 0.84f}, {0.17f, 0.17f, 0.17f}, px == 1, opaque};
      int nt = (w + T - 1) / T, hh = p.y1 - p.y0;
      uint8_t **tile = malloc(sizeof(void *) * nt);
      List **l = malloc(sizeof(void *) * nt);
      double f0 = 40 * view + 500, f = f0, step = view / 60 / 12;
      p.front = f0;
      double ta = now();
      for (int j = 0; j < nt; j++) { int x1 = (j + 1) * T > w ? w : (j + 1) * T; tile[j] = malloc((size_t)T * px * hh); paint(&p, j * T, x1, tile[j], T * px); }
      double tb = now();
      for (int j = 0; j < nt; j++) l[j] = NULL;
      // The first step makes the lists.
      int kept = 0;
      { double from = f; f += step; p.front = f; for (int j = 0; j < nt; j++) { int x1 = (j + 1) * T > w ? w : (j + 1) * T; advance(&p, &l[j], j * T, x1, from, tile[j], T * px); kept += l[j] != NULL; } }
      if (!kept) whole = 1;
      double tc = now();
      // The dense painting against the shader.
      long maxDense = 0, maxSteps = 0, differing = 0; double sum = 0; long nn = 0;
      for (int round = 0; round < 2; round++) {
        if (round == 1) {
          double t0 = now(); long items = 0;
          for (int v = 0; v < steps; v++) { double from = f; f += step; p.front = f; for (int j = 0; j < nt; j++) { int x1 = (j + 1) * T > w ? w : (j + 1) * T; if (reaches(&p, j * T, x1, from)) items += advance(&p, &l[j], j * T, x1, from, tile[j], T * px); } }
          double t1 = now();
          printf("  step %.3f ms, %ld tiles changed a step; ", (t1 - t0) / steps, items / steps);
        }
        for (int j = 0; j < nt; j++) {
          int x1 = (j + 1) * T > w ? w : (j + 1) * T;
          for (int y = p.y0; y < p.y1; y += 3) for (int x = j * T; x < x1; x++) {
            float s[3]; shader(&p, x, y, s);
            const uint8_t *b = tile[j] + (long)(y - p.y0) * T * px + (x - j * T) * px;
            for (int c = 0; c < 3; c++) {
              // Mono: the system puts the ink on the paper by the share.
              float ours = px == 1 ? (p.paper[c] + (p.ink[c] - p.paper[c]) * b[0] / 255.0f) * 255.0f : b[2 - c] + (255 - b[3]) * p.paper[c];
              float d = fabsf(ours - s[c] * 255.0f);
              if (round == 0) { if (d > maxDense) maxDense = (long)(d + 0.5f); }
              else { if (d > maxSteps) maxSteps = (long)(d + 0.5f); if (d > 1.5f) differing++; sum += d; nn++; }
            }
          }
        }
      }
      if (maxDense > worst) worst = (int)maxDense;
      if (maxSteps > worst) worst = (int)maxSteps;
      printf("delay %s case %d%s: dense %.1f ms a tile (max %ld off the shader), first step %.1f ms a tile; after the steps max %ld, mean %.3f, over 1.5: %ld of %ld\n",
             fine ? "1:1" : "1:2", kind, px == 1 ? " mono" : (opaque ? " opaque" : ""), (tb - ta) / nt, maxDense, (tc - tb) / nt, maxSteps, sum / nn, differing, nn);
      for (int j = 0; j < nt; j++) { freeList(l[j]); free(tile[j]); }
      free(tile); free(l);
    }
    free(o);
  }
  free(q1); free(q2);
  return whole ? -1 : worst;
}

int main(int argc, char **argv) {
  int steps = argc > 1 ? atoi(argv[1]) : 120, worst = 0;
  // A laptop's screen, and one taller than 4096.
  int sizes[2][2] = {{3456, 2234}, {4608, 4480}};
  for (int i = 0; i < 2; i++) {
    int d = size(sizes[i][0], sizes[i][1], steps);
    if (d < 0) { printf("FAILED: %d x %d is painted whole at every step\n", sizes[i][0], sizes[i][1]); return 1; }
    if (d > worst) worst = d;
  }
  if (worst > 3) { printf("FAILED: %d of 255 off the shader\n", worst); return 1; }
  printf("ok: at most %d of 255 off the shader\n", worst);
  return 0;
}
