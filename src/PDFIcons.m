#import "PDFIcons.h"

static UIImage *PDFRenderTemplateIcon(CGSize size, void (^drawBlock)(CGContextRef ctx)) {
    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0f);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (ctx && drawBlock) {
        [[UIColor blackColor] setStroke];
        [[UIColor blackColor] setFill];
        CGContextSetLineCap(ctx, kCGLineCapRound);
        CGContextSetLineJoin(ctx, kCGLineJoinRound);
        drawBlock(ctx);
    }
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

UIImage *PDFIconBack(void) {
    return PDFRenderTemplateIcon(CGSizeMake(22.0f, 22.0f), ^(CGContextRef ctx) {
        UIBezierPath *p = [UIBezierPath bezierPath];
        p.lineWidth = 2.2f;
        p.lineCapStyle = kCGLineCapRound;
        p.lineJoinStyle = kCGLineJoinRound;
        [p moveToPoint:CGPointMake(13.5f, 4.5f)];
        [p addLineToPoint:CGPointMake(7.0f, 11.0f)];
        [p addLineToPoint:CGPointMake(13.5f, 17.5f)];
        [p stroke];
    });
}

UIImage *PDFIconChevron(void) {
    return PDFRenderTemplateIcon(CGSizeMake(14.0f, 20.0f), ^(CGContextRef ctx) {
        UIBezierPath *p = [UIBezierPath bezierPath];
        p.lineWidth = 2.1f;
        p.lineCapStyle = kCGLineCapRound;
        p.lineJoinStyle = kCGLineJoinRound;
        [p moveToPoint:CGPointMake(4.5f, 4.5f)];
        [p addLineToPoint:CGPointMake(10.0f, 10.0f)];
        [p addLineToPoint:CGPointMake(4.5f, 15.5f)];
        [p stroke];
    });
}

UIImage *PDFIconRead(void) {
    return PDFRenderTemplateIcon(CGSizeMake(22.0f, 22.0f), ^(CGContextRef ctx) {
        UIBezierPath *book = [UIBezierPath bezierPath];
        book.lineWidth = 1.75f;
        book.lineCapStyle = kCGLineCapRound;
        book.lineJoinStyle = kCGLineJoinRound;
        // Left page
        [book moveToPoint:CGPointMake(11.0f, 6.0f)];
        [book addQuadCurveToPoint:CGPointMake(3.0f, 5.2f) controlPoint:CGPointMake(7.0f, 4.5f)];
        [book addLineToPoint:CGPointMake(3.0f, 16.8f)];
        [book addQuadCurveToPoint:CGPointMake(11.0f, 17.8f) controlPoint:CGPointMake(7.0f, 16.2f)];
        // Right page
        [book moveToPoint:CGPointMake(11.0f, 6.0f)];
        [book addQuadCurveToPoint:CGPointMake(19.0f, 5.2f) controlPoint:CGPointMake(15.0f, 4.5f)];
        [book addLineToPoint:CGPointMake(19.0f, 16.8f)];
        [book addQuadCurveToPoint:CGPointMake(11.0f, 17.8f) controlPoint:CGPointMake(15.0f, 16.2f)];
        // Spine
        [book moveToPoint:CGPointMake(11.0f, 6.0f)];
        [book addLineToPoint:CGPointMake(11.0f, 17.8f)];
        [book stroke];
    });
}

UIImage *PDFIconPen(void) {
    return PDFRenderTemplateIcon(CGSizeMake(22.0f, 22.0f), ^(CGContextRef ctx) {
        UIBezierPath *p = [UIBezierPath bezierPath];
        p.lineWidth = 1.75f;
        p.lineCapStyle = kCGLineCapRound;
        p.lineJoinStyle = kCGLineJoinRound;
        [p moveToPoint:CGPointMake(4.0f, 18.0f)];
        [p addLineToPoint:CGPointMake(5.2f, 13.6f)];
        [p addLineToPoint:CGPointMake(14.8f, 4.0f)];
        [p addLineToPoint:CGPointMake(18.0f, 7.2f)];
        [p addLineToPoint:CGPointMake(8.4f, 16.8f)];
        [p closePath];
        [p moveToPoint:CGPointMake(12.6f, 6.2f)];
        [p addLineToPoint:CGPointMake(15.8f, 9.4f)];
        [p stroke];
    });
}

UIImage *PDFIconMarker(void) {
    return PDFRenderTemplateIcon(CGSizeMake(22.0f, 22.0f), ^(CGContextRef ctx) {
        UIBezierPath *p = [UIBezierPath bezierPath];
        p.lineWidth = 1.75f;
        p.lineCapStyle = kCGLineCapRound;
        p.lineJoinStyle = kCGLineJoinRound;
        // Chisel highlighter body
        [p moveToPoint:CGPointMake(7.0f, 14.5f)];
        [p addLineToPoint:CGPointMake(14.5f, 4.0f)];
        [p addLineToPoint:CGPointMake(18.5f, 7.5f)];
        [p addLineToPoint:CGPointMake(10.5f, 17.0f)];
        [p closePath];
        // Chisel nib
        [p moveToPoint:CGPointMake(7.0f, 14.5f)];
        [p addLineToPoint:CGPointMake(4.2f, 18.0f)];
        [p addLineToPoint:CGPointMake(8.2f, 18.0f)];
        [p addLineToPoint:CGPointMake(10.5f, 17.0f)];
        // Highlight bar at bottom
        [p moveToPoint:CGPointMake(3.5f, 19.6f)];
        [p addLineToPoint:CGPointMake(15.5f, 19.6f)];
        [p stroke];
    });
}

UIImage *PDFIconEraser(void) {
    return PDFRenderTemplateIcon(CGSizeMake(22.0f, 22.0f), ^(CGContextRef ctx) {
        UIBezierPath *p = [UIBezierPath bezierPath];
        p.lineWidth = 1.75f;
        p.lineCapStyle = kCGLineCapRound;
        p.lineJoinStyle = kCGLineJoinRound;
        [p moveToPoint:CGPointMake(8.0f, 18.0f)];
        [p addLineToPoint:CGPointMake(3.8f, 13.8f)];
        [p addLineToPoint:CGPointMake(12.8f, 4.8f)];
        [p addLineToPoint:CGPointMake(18.2f, 10.2f)];
        [p addLineToPoint:CGPointMake(10.4f, 18.0f)];
        [p closePath];
        [p moveToPoint:CGPointMake(8.2f, 9.4f)];
        [p addLineToPoint:CGPointMake(13.6f, 14.8f)];
        [p moveToPoint:CGPointMake(10.4f, 18.0f)];
        [p addLineToPoint:CGPointMake(18.5f, 18.0f)];
        [p stroke];
    });
}

UIImage *PDFIconNote(void) {
    return PDFRenderTemplateIcon(CGSizeMake(22.0f, 22.0f), ^(CGContextRef ctx) {
        UIBezierPath *p = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(3.5f, 3.5f, 15.0f, 15.0f) cornerRadius:2.5f];
        p.lineWidth = 1.75f;
        [p stroke];

        UIBezierPath *lines = [UIBezierPath bezierPath];
        lines.lineWidth = 1.6f;
        lines.lineCapStyle = kCGLineCapRound;
        [lines moveToPoint:CGPointMake(7.0f, 8.0f)];
        [lines addLineToPoint:CGPointMake(15.0f, 8.0f)];
        [lines moveToPoint:CGPointMake(7.0f, 11.5f)];
        [lines addLineToPoint:CGPointMake(13.5f, 11.5f)];
        [lines moveToPoint:CGPointMake(7.0f, 15.0f)];
        [lines addLineToPoint:CGPointMake(11.0f, 15.0f)];
        [lines stroke];
    });
}

UIImage *PDFIconUndo(void) {
    return PDFRenderTemplateIcon(CGSizeMake(22.0f, 22.0f), ^(CGContextRef ctx) {
        UIBezierPath *p = [UIBezierPath bezierPath];
        p.lineWidth = 1.85f;
        p.lineCapStyle = kCGLineCapRound;
        p.lineJoinStyle = kCGLineJoinRound;
        [p moveToPoint:CGPointMake(8.5f, 5.5f)];
        [p addLineToPoint:CGPointMake(4.2f, 9.5f)];
        [p addLineToPoint:CGPointMake(8.5f, 13.5f)];
        [p moveToPoint:CGPointMake(4.8f, 9.5f)];
        [p addLineToPoint:CGPointMake(13.0f, 9.5f)];
        [p addArcWithCenter:CGPointMake(13.0f, 13.5f) radius:4.0f startAngle:-(CGFloat)M_PI_2 endAngle:(CGFloat)M_PI_2 clockwise:YES];
        [p addLineToPoint:CGPointMake(9.5f, 17.5f)];
        [p stroke];
    });
}

UIImage *PDFIconRedo(void) {
    return PDFRenderTemplateIcon(CGSizeMake(22.0f, 22.0f), ^(CGContextRef ctx) {
        UIBezierPath *p = [UIBezierPath bezierPath];
        p.lineWidth = 1.85f;
        p.lineCapStyle = kCGLineCapRound;
        p.lineJoinStyle = kCGLineJoinRound;
        [p moveToPoint:CGPointMake(13.5f, 5.5f)];
        [p addLineToPoint:CGPointMake(17.8f, 9.5f)];
        [p addLineToPoint:CGPointMake(13.5f, 13.5f)];
        [p moveToPoint:CGPointMake(17.2f, 9.5f)];
        [p addLineToPoint:CGPointMake(9.0f, 9.5f)];
        [p addArcWithCenter:CGPointMake(9.0f, 13.5f) radius:4.0f startAngle:-(CGFloat)M_PI_2 endAngle:(CGFloat)M_PI_2 clockwise:NO];
        [p addLineToPoint:CGPointMake(12.5f, 17.5f)];
        [p stroke];
    });
}

UIImage *PDFIconTrash(void) {
    return PDFRenderTemplateIcon(CGSizeMake(22.0f, 22.0f), ^(CGContextRef ctx) {
        UIBezierPath *p = [UIBezierPath bezierPath];
        p.lineWidth = 1.75f;
        p.lineCapStyle = kCGLineCapRound;
        p.lineJoinStyle = kCGLineJoinRound;
        [p moveToPoint:CGPointMake(4.0f, 6.5f)];
        [p addLineToPoint:CGPointMake(18.0f, 6.5f)];
        [p moveToPoint:CGPointMake(8.5f, 6.5f)];
        [p addLineToPoint:CGPointMake(8.5f, 4.2f)];
        [p addLineToPoint:CGPointMake(13.5f, 4.2f)];
        [p addLineToPoint:CGPointMake(13.5f, 6.5f)];
        [p moveToPoint:CGPointMake(6.0f, 6.5f)];
        [p addLineToPoint:CGPointMake(6.8f, 18.2f)];
        [p addLineToPoint:CGPointMake(15.2f, 18.2f)];
        [p addLineToPoint:CGPointMake(16.0f, 6.5f)];
        [p moveToPoint:CGPointMake(9.5f, 9.8f)];
        [p addLineToPoint:CGPointMake(9.5f, 15.2f)];
        [p moveToPoint:CGPointMake(12.5f, 9.8f)];
        [p addLineToPoint:CGPointMake(12.5f, 15.2f)];
        [p stroke];
    });
}

UIImage *PDFIconShare(void) {
    return PDFRenderTemplateIcon(CGSizeMake(22.0f, 22.0f), ^(CGContextRef ctx) {
        UIBezierPath *p = [UIBezierPath bezierPath];
        p.lineWidth = 1.8f;
        p.lineCapStyle = kCGLineCapRound;
        p.lineJoinStyle = kCGLineJoinRound;
        [p moveToPoint:CGPointMake(11.0f, 13.5f)];
        [p addLineToPoint:CGPointMake(11.0f, 3.5f)];
        [p moveToPoint:CGPointMake(7.6f, 6.8f)];
        [p addLineToPoint:CGPointMake(11.0f, 3.4f)];
        [p addLineToPoint:CGPointMake(14.4f, 6.8f)];
        [p moveToPoint:CGPointMake(6.8f, 9.5f)];
        [p addLineToPoint:CGPointMake(5.0f, 9.5f)];
        [p addLineToPoint:CGPointMake(5.0f, 18.5f)];
        [p addLineToPoint:CGPointMake(17.0f, 18.5f)];
        [p addLineToPoint:CGPointMake(17.0f, 9.5f)];
        [p addLineToPoint:CGPointMake(15.2f, 9.5f)];
        [p stroke];
    });
}

UIImage *PDFIconGrid(void) {
    return PDFRenderTemplateIcon(CGSizeMake(22.0f, 22.0f), ^(CGContextRef ctx) {
        CGFloat rects[4][4] = {
            {4.0f, 4.0f, 5.8f, 5.8f},
            {12.2f, 4.0f, 5.8f, 5.8f},
            {4.0f, 12.2f, 5.8f, 5.8f},
            {12.2f, 12.2f, 5.8f, 5.8f},
        };
        for (int i = 0; i < 4; i++) {
            UIBezierPath *r = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(rects[i][0], rects[i][1], rects[i][2], rects[i][3]) cornerRadius:1.4f];
            r.lineWidth = 1.7f;
            [r stroke];
        }
    });
}

UIImage *PDFIconBookmark(BOOL filled) {
    return PDFRenderTemplateIcon(CGSizeMake(22.0f, 22.0f), ^(CGContextRef ctx) {
        UIBezierPath *p = [UIBezierPath bezierPath];
        p.lineWidth = 1.8f;
        p.lineCapStyle = kCGLineCapRound;
        p.lineJoinStyle = kCGLineJoinRound;
        [p moveToPoint:CGPointMake(6.0f, 4.0f)];
        [p addLineToPoint:CGPointMake(16.0f, 4.0f)];
        [p addLineToPoint:CGPointMake(16.0f, 18.5f)];
        [p addLineToPoint:CGPointMake(11.0f, 14.5f)];
        [p addLineToPoint:CGPointMake(6.0f, 18.5f)];
        [p closePath];
        if (filled) {
            [p fill];
        } else {
            [p stroke];
        }
    });
}

UIImage *PDFIconSearch(void) {
    return PDFRenderTemplateIcon(CGSizeMake(22.0f, 22.0f), ^(CGContextRef ctx) {
        UIBezierPath *c = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(4.0f, 4.0f, 10.8f, 10.8f)];
        c.lineWidth = 1.85f;
        [c stroke];

        UIBezierPath *h = [UIBezierPath bezierPath];
        h.lineWidth = 2.0f;
        h.lineCapStyle = kCGLineCapRound;
        [h moveToPoint:CGPointMake(13.4f, 13.4f)];
        [h addLineToPoint:CGPointMake(18.0f, 18.0f)];
        [h stroke];
    });
}

UIImage *PDFIconCrop(void) {
    return PDFRenderTemplateIcon(CGSizeMake(22.0f, 22.0f), ^(CGContextRef ctx) {
        UIBezierPath *p = [UIBezierPath bezierPath];
        p.lineWidth = 1.8f;
        p.lineCapStyle = kCGLineCapRound;
        p.lineJoinStyle = kCGLineJoinRound;
        [p moveToPoint:CGPointMake(6.5f, 3.0f)];
        [p addLineToPoint:CGPointMake(6.5f, 15.5f)];
        [p addLineToPoint:CGPointMake(19.0f, 15.5f)];
        [p moveToPoint:CGPointMake(3.0f, 6.5f)];
        [p addLineToPoint:CGPointMake(15.5f, 6.5f)];
        [p addLineToPoint:CGPointMake(15.5f, 19.0f)];
        [p stroke];
    });
}

UIImage *PDFIconTheme(void) {
    return PDFRenderTemplateIcon(CGSizeMake(22.0f, 22.0f), ^(CGContextRef ctx) {
        UIBezierPath *p = [UIBezierPath bezierPath];
        p.lineWidth = 1.8f;
        p.lineCapStyle = kCGLineCapRound;
        p.lineJoinStyle = kCGLineJoinRound;
        [p addArcWithCenter:CGPointMake(11.5f, 10.5f) radius:6.5f startAngle:(CGFloat)(0.28 * M_PI) endAngle:(CGFloat)(1.38 * M_PI) clockwise:YES];
        [p addQuadCurveToPoint:CGPointMake(15.6f, 15.5f) controlPoint:CGPointMake(10.0f, 12.2f)];
        [p closePath];
        [p stroke];
    });
}

UIImage *PDFIconPlus(void) {
    return PDFRenderTemplateIcon(CGSizeMake(22.0f, 22.0f), ^(CGContextRef ctx) {
        UIBezierPath *p = [UIBezierPath bezierPath];
        p.lineWidth = 2.0f;
        p.lineCapStyle = kCGLineCapRound;
        [p moveToPoint:CGPointMake(11.0f, 4.5f)];
        [p addLineToPoint:CGPointMake(11.0f, 17.5f)];
        [p moveToPoint:CGPointMake(4.5f, 11.0f)];
        [p addLineToPoint:CGPointMake(17.5f, 11.0f)];
        [p stroke];
    });
}

UIImage *PDFIconFolder(void) {
    return PDFRenderTemplateIcon(CGSizeMake(24.0f, 24.0f), ^(CGContextRef ctx) {
        UIBezierPath *p = [UIBezierPath bezierPath];
        p.lineWidth = 1.8f;
        p.lineCapStyle = kCGLineCapRound;
        p.lineJoinStyle = kCGLineJoinRound;
        [p moveToPoint:CGPointMake(3.0f, 7.0f)];
        [p addLineToPoint:CGPointMake(3.0f, 18.5f)];
        [p addLineToPoint:CGPointMake(21.0f, 18.5f)];
        [p addLineToPoint:CGPointMake(21.0f, 8.5f)];
        [p addLineToPoint:CGPointMake(11.5f, 8.5f)];
        [p addLineToPoint:CGPointMake(9.5f, 6.0f)];
        [p addLineToPoint:CGPointMake(3.0f, 6.0f)];
        [p closePath];
        [p stroke];
    });
}

UIImage *PDFIconSort(void) {
    return PDFRenderTemplateIcon(CGSizeMake(22.0f, 22.0f), ^(CGContextRef ctx) {
        UIBezierPath *p = [UIBezierPath bezierPath];
        p.lineWidth = 1.85f;
        p.lineCapStyle = kCGLineCapRound;
        [p moveToPoint:CGPointMake(4.0f, 6.5f)];
        [p addLineToPoint:CGPointMake(18.0f, 6.5f)];
        [p moveToPoint:CGPointMake(4.0f, 11.5f)];
        [p addLineToPoint:CGPointMake(14.0f, 11.5f)];
        [p moveToPoint:CGPointMake(4.0f, 16.5f)];
        [p addLineToPoint:CGPointMake(10.0f, 16.5f)];
        [p stroke];
    });
}

UIImage *PDFIconMore(void) {
    return PDFRenderTemplateIcon(CGSizeMake(22.0f, 22.0f), ^(CGContextRef ctx) {
        for (int i = 0; i < 3; i++) {
            CGFloat cx = 5.5f + i * 5.5f;
            UIBezierPath *dot = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(cx - 1.5f, 9.5f, 3.0f, 3.0f)];
            [dot fill];
        }
    });
}
