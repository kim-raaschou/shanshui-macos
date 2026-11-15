# Third-party code

Shan Shui for macOS is a port of [omarchy-shanshui](https://github.com/zednaked/omarchy-shanshui)
by Thiago Gonçalves (ZeD), under the MIT license in [LICENSE](LICENSE).

The landscape generator (`Sources/Core/ShanShui*.swift`) is {Shan, Shui}* by Lingdong
Huang, https://github.com/LingDong-/shan-shui-inf, written out in Swift from the
JavaScript in its index.html, with one hook added (onchunk, a seed per chunk). It is
distributed under its license, reproduced here:

```
MIT License

Copyright (c) 2018 Lingdong Huang

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

The Perlin noise in it is adapted by the original author from
p5.js (LGPL-2.1, https://github.com/processing/p5.js/blob/main/src/math/noise.js),
as noted in the original source.
