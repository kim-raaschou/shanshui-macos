#ifndef PAINT_H
#define PAINT_H

#include <stdint.h>

// The world's view is this tall.
#define PAINT_HEIGHT 700.0
// The most columns `advance` takes at once: a tile's width.
#define PAINT_TILE 512

// pintura.frag of the original, on the CPU: columns of one strip, as
// premultiplied BGRA. The paper is not in it: it is what the strip is over.
typedef struct {
  const uint8_t *q;  // the picture: grey, or grey and alpha
  int channels;        // 1 or 2
  int w, h;
  const uint8_t *o;  // the delay: two bytes per pixel, high then low; 0 is the paper
  int ow, oh;
  double start;     // x of the strip's left side, in the world
  double width;    // the strip's width, in the world (the height is 700)
  double front;     // x of the painting front, in the world
  double spread;    // how far the largest delay pushes a stroke back
  double softness;      // width, in the world, of the edge where ink comes in
  double grain;       // strength of the paper's grain
  double mist;      // 0..1: how much the stroke fades toward the paper
  int ground;          // 1 on the back layer: only the paper is behind it
  int y0, y1;        // the rows to paint
  float paper[3];    // r, g, b
  float ink[3];
} Paint;

// The columns x0..x1, whole. `dst` is the pixel of column x0 in row y0;
// `stride` the bytes per row.
void paint(const Paint *p, int x0, int x1, uint8_t *dst, long stride);

// What the columns keep between steps: the delay's pixels in the order the
// front reaches them, so a step touches only what it changes. It is made when
// the front arrives and let go when it has passed; NULL before and after.
typedef struct List List;
void freeList(List *l);

// Whether the front going from `from` to p->front changes the columns x0..x1.
int reaches(const Paint *p, int x0, int x1, double from);

// Paints what that step changes; tells whether any pixel did. `dst` and
// `stride` as in paint.
int advance(const Paint *p, List **l, int x0, int x1, double from, uint8_t *dst, long stride);

// The rows of the columns x0..x1 that have anything in them; 0 when none has.
int extent(const Paint *p, int x0, int x1, int *y0, int *y1);

#endif
