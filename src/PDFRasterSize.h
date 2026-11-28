#ifndef PDFRasterSize_h
#define PDFRasterSize_h

#include <math.h>

typedef struct {
    int width, height;
} PDFRasterSize;

// One iPad 3 screen of pixels (~12 MiB at 4 bytes/pixel), even at high zoom.
enum { PDFPageMaxSide = 2560, PDFPageMaxPixels = 2048 * 1536 };

static inline PDFRasterSize PDFRasterFit(double width, double height, double targetWidth,
                                         int maxSide, int maxPixels) {
    if (!isfinite(width) || !isfinite(height) || !isfinite(targetWidth) ||
        width <= 0 || height <= 0 || targetWidth <= 0 || maxSide <= 0 || maxPixels <= 0)
        return (PDFRasterSize){0, 0};

    if (maxSide > maxPixels) maxSide = maxPixels;
    double w = fmin(targetWidth, maxSide);
    double h = w * (height / width);
    if (h > maxSide) {
        h = maxSide;
        w = h * (width / height);
    }
    if (w * h > maxPixels) {
        double scale = sqrt(maxPixels / (w * h));
        w *= scale;
        h *= scale;
    }
    return (PDFRasterSize){(int)fmax(1, floor(w)), (int)fmax(1, floor(h))};
}

static inline PDFRasterSize PDFTrimSampleSize(double width, double height) {
    return PDFRasterFit(width, height, 200, 512, 200 * 512);
}

#endif
