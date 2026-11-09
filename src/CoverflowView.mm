#import "CoverflowView.h"

static const CGFloat kSideAngle = 65.0 * M_PI / 180.0;

#pragma mark - Cover layer

// One cover: the image plus its mirrored reflection below.
@interface FCFCoverLayer : CALayer
@property(nonatomic) NSInteger index;
@property(nonatomic) BOOL coverResolved;   // image (or "no cover") has been set
@property(nonatomic, strong) CALayer* imageLayer;
@property(nonatomic, strong) CALayer* reflectionLayer;
@property(nonatomic, strong) CAGradientLayer* reflectionFade;
@property(nonatomic, strong) CATextLayer* placeholderText;
@property(nonatomic) CGFloat size;
@end

@implementation FCFCoverLayer

- (instancetype)init {
    if ((self = [super init])) {
        _imageLayer = [CALayer layer];
        _imageLayer.contentsGravity = kCAGravityResizeAspectFill;
        _imageLayer.masksToBounds = YES;
        _imageLayer.doubleSided = NO;

        _reflectionLayer = [CALayer layer];
        _reflectionLayer.contentsGravity = kCAGravityResizeAspectFill;
        _reflectionLayer.masksToBounds = YES;
        _reflectionLayer.transform = CATransform3DMakeScale(1, -1, 1);

        // Black overlay fading the reflection out into the background.
        _reflectionFade = [CAGradientLayer layer];
        _reflectionFade.colors = @[ (id)[NSColor colorWithWhite:0 alpha:0.6].CGColor,
                                    (id)[NSColor colorWithWhite:0 alpha:1.0].CGColor ];
        _reflectionFade.startPoint = CGPointMake(0.5, 1.0);   // unit coords: y=1 is the top on macOS
        _reflectionFade.endPoint = CGPointMake(0.5, 0.45);

        _placeholderText = [CATextLayer layer];
        _placeholderText.wrapped = YES;
        _placeholderText.alignmentMode = kCAAlignmentCenter;
        _placeholderText.foregroundColor = [NSColor colorWithWhite:0.75 alpha:1].CGColor;
        _placeholderText.font = (__bridge CFTypeRef)[NSFont systemFontOfSize:13 weight:NSFontWeightMedium];

        [self addSublayer:_reflectionLayer];
        [self addSublayer:_reflectionFade];
        [self addSublayer:_imageLayer];
        [_imageLayer addSublayer:_placeholderText];
    }
    return self;
}

- (void)setSize:(CGFloat)size {
    if (_size == size) return;
    _size = size;
    self.bounds = CGRectMake(0, 0, size, size);
    _imageLayer.frame = CGRectMake(0, 0, size, size);
    _reflectionLayer.frame = CGRectMake(0, -size, size, size);
    _reflectionFade.frame = CGRectMake(0, -size, size, size);
    _placeholderText.fontSize = MAX(10, size * 0.07);
    _placeholderText.frame = CGRectMake(size * 0.1, size * 0.3, size * 0.8, size * 0.4);
}

- (void)setScale:(CGFloat)scale {
    _placeholderText.contentsScale = scale;
}

- (void)showCover:(CGImageRef)image title:(NSString*)title {
    _imageLayer.contents = (__bridge id)image;
    _reflectionLayer.contents = (__bridge id)image;
    if (image) {
        _imageLayer.backgroundColor = nil;
        _reflectionLayer.backgroundColor = nil;
        _placeholderText.hidden = YES;
    } else {
        CGColorRef gray = [NSColor colorWithWhite:0.18 alpha:1].CGColor;
        _imageLayer.backgroundColor = gray;
        _reflectionLayer.backgroundColor = gray;
        _placeholderText.string = title;
        _placeholderText.hidden = NO;
    }
}

@end

#pragma mark - Coverflow view

@implementation FCFCoverflowView {
    CALayer* _stage;
    CALayer* _overlay;
    CATextLayer* _titleLayer;
    CATextLayer* _artistLayer;
    CATextLayer* _emptyLayer;

    NSMutableDictionary<NSNumber*, FCFCoverLayer*>* _visible;
    NSMutableArray<FCFCoverLayer*>* _pool;

    NSInteger _count;
    CGFloat _pos;      // current (animated) position, fractional album index
    CGFloat _target;   // where the position is heading
    NSInteger _shownLabelIndex;
    BOOL _centerHidden;

    CADisplayLink* _link;
    CFTimeInterval _lastTick;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        CALayer* root = [CALayer layer];
        root.backgroundColor = NSColor.blackColor.CGColor;
        root.layoutManager = nil;
        self.layer = root;       // layer-hosting view
        self.wantsLayer = YES;
        self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawNever;

        _stage = [CALayer layer];
        [root addSublayer:_stage];

        _titleLayer = [self makeTextLayerWithSize:15 weight:NSFontWeightSemibold color:NSColor.whiteColor];
        _artistLayer = [self makeTextLayerWithSize:13 weight:NSFontWeightRegular color:[NSColor colorWithWhite:0.65 alpha:1]];
        _emptyLayer = [self makeTextLayerWithSize:14 weight:NSFontWeightRegular color:[NSColor colorWithWhite:0.7 alpha:1]];
        _emptyLayer.wrapped = YES;
        _emptyLayer.hidden = YES;
        [root addSublayer:_titleLayer];
        [root addSublayer:_artistLayer];
        [root addSublayer:_emptyLayer];

        _overlay = [CALayer layer];
        _overlay.zPosition = 1000;
        [root addSublayer:_overlay];

        _visible = [NSMutableDictionary dictionary];
        _pool = [NSMutableArray array];
        _shownLabelIndex = -1;
    }
    return self;
}

- (void)dealloc {
    [_link invalidate];
}

- (CATextLayer*)makeTextLayerWithSize:(CGFloat)size weight:(NSFontWeight)weight color:(NSColor*)color {
    CATextLayer* t = [CATextLayer layer];
    t.font = (__bridge CFTypeRef)[NSFont systemFontOfSize:size weight:weight];
    t.fontSize = size;
    t.foregroundColor = color.CGColor;
    t.alignmentMode = kCAAlignmentCenter;
    t.truncationMode = kCATruncationEnd;
    t.actions = @{ @"contents": [NSNull null], @"string": [NSNull null] };
    return t;
}

- (BOOL)isFlipped { return NO; }
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent*)event { return YES; }

- (CALayer*)overlayLayer { return _overlay; }
- (NSInteger)centerIndex { return _count ? MAX(0, MIN(_count - 1, lround(_target))) : -1; }

#pragma mark Data

- (void)reloadDataKeepingIndex:(NSInteger)index {
    _count = [self.delegate numberOfAlbumsInCoverflowView:self];
    for (FCFCoverLayer* l in _visible.allValues) [self recycle:l];
    [_visible removeAllObjects];
    _shownLabelIndex = -1;
    _target = _pos = _count ? MAX(0, MIN(_count - 1, index)) : 0;
    [self relayout];
}

- (void)coverDidLoadForIndex:(NSInteger)index {
    FCFCoverLayer* l = _visible[@(index)];
    if (!l) return;
    l.coverResolved = NO;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self resolveCover:l];
    [CATransaction commit];
}

- (void)setEmptyMessage:(NSString*)emptyMessage {
    _emptyMessage = [emptyMessage copy];
    [self relayout];
}

#pragma mark Geometry

// Vertical layout, bottom to top:
//   kBottomMargin | artist | title | reflection | cover | kTopMargin
static const CGFloat kBottomMargin = 12;
static const CGFloat kLabelArea = 44;          // title (20) + artist (18) + spacing
static const CGFloat kReflectionShare = 0.2;   // visible reflection below the cover, relative to cover size
static const CGFloat kTopMargin = 12;

- (CGFloat)coverSize {
    NSSize b = self.bounds.size;
    CGFloat fixed = kBottomMargin + kLabelArea + kTopMargin;
    CGFloat byHeight = (b.height - fixed) / (1 + kReflectionShare);
    return floor(MAX(40, MIN(byHeight, b.width * 0.34)));
}

- (CGPoint)coverCenter {
    NSSize b = self.bounds.size;
    CGFloat s = [self coverSize];
    CGFloat bottom = kBottomMargin + kLabelArea + s * kReflectionShare;
    // Spare height (e.g. limited by width) is split evenly above and below.
    CGFloat spare = MAX(0, b.height - bottom - s - kTopMargin);
    return CGPointMake(b.width / 2, bottom + spare / 2 + s / 2);
}

- (NSRect)centerCoverFrame {
    CGFloat s = [self coverSize];
    CGPoint c = [self coverCenter];
    return NSMakeRect(c.x - s / 2, c.y - s / 2, s, s);
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    [self relayout];
}

- (void)viewDidChangeBackingProperties {
    [super viewDidChangeBackingProperties];
    [self relayout];
}

- (CGFloat)backingScale {
    return self.window ? self.window.backingScaleFactor : 2.0;
}

- (void)relayout {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    NSRect bounds = self.bounds;
    _stage.frame = bounds;
    _overlay.frame = bounds;

    CGFloat s = [self coverSize];
    CATransform3D perspective = CATransform3DIdentity;
    perspective.m34 = -1.0 / (s * 3.2);
    _stage.sublayerTransform = perspective;

    CGFloat scale = [self backingScale];
    CGPoint c = [self coverCenter];
    // Labels sit just under the reflection, but never lower than the bottom margin.
    CGFloat spare = MAX(0, c.y - s / 2 - s * kReflectionShare - kBottomMargin - kLabelArea);
    CGFloat artistY = kBottomMargin + spare;
    _titleLayer.contentsScale = _artistLayer.contentsScale = _emptyLayer.contentsScale = scale;
    _artistLayer.frame = CGRectMake(20, artistY, bounds.size.width - 40, 18);
    _titleLayer.frame = CGRectMake(20, artistY + 22, bounds.size.width - 40, 20);
    _emptyLayer.frame = CGRectMake(30, bounds.size.height / 2 - 30, bounds.size.width - 60, 60);

    _emptyLayer.hidden = _count > 0;
    _emptyLayer.string = _emptyMessage ?: @"";
    _titleLayer.hidden = _artistLayer.hidden = _count == 0;

    [self layoutCovers];
    [CATransaction commit];
}

- (void)layoutCovers {
    if (_count == 0) {
        for (FCFCoverLayer* l in _visible.allValues) [self recycle:l];
        [_visible removeAllObjects];
        return;
    }

    NSSize b = self.bounds.size;
    CGFloat s = [self coverSize];
    CGPoint c = [self coverCenter];
    CGFloat gap = s * 0.62;      // distance center cover -> first side cover
    CGFloat spacing = s * 0.2;   // distance between side covers
    NSInteger side = (NSInteger)ceil(MAX(0, b.width / 2 - gap) / spacing) + 2;
    side = MAX(3, MIN(side, 40));

    NSInteger mid = lround(_pos);
    NSInteger lo = MAX(0, mid - side), hi = MIN(_count - 1, mid + side);

    for (NSNumber* key in _visible.allKeys) {
        NSInteger i = key.integerValue;
        if (i < lo || i > hi) {
            [self recycle:_visible[key]];
            [_visible removeObjectForKey:key];
        }
    }

    CGFloat scale = [self backingScale];
    for (NSInteger i = lo; i <= hi; ++i) {
        FCFCoverLayer* l = _visible[@(i)];
        if (!l) {
            l = [self dequeue];
            l.index = i;
            l.coverResolved = NO;
            _visible[@(i)] = l;
            [_stage addSublayer:l];
        }
        l.size = s;
        [l setScale:scale];
        if (!l.coverResolved) [self resolveCover:l];

        CGFloat d = i - _pos;
        CGFloat ad = fabs(d);
        CGFloat t = MAX(-1, MIN(1, d));
        CGFloat x = ad <= 1 ? t * gap : copysign(gap + (ad - 1) * spacing, d);
        CGFloat z = -MIN(ad, 1) * s * 0.45;

        CATransform3D tr = CATransform3DMakeTranslation(x, 0, z);
        tr = CATransform3DRotate(tr, -t * kSideAngle, 0, 1, 0);   // side covers face the center
        l.position = c;
        l.transform = tr;
        l.zPosition = -ad;
        l.hidden = (i == mid && _centerHidden && fabs(_pos - mid) < 0.01);
        // Fade out the outermost covers.
        CGFloat edge = side - ad;
        l.opacity = edge < 1.5 ? MAX(0, edge / 1.5) : 1;
    }

    [self updateLabels];
}

- (void)updateLabels {
    NSInteger idx = [self centerIndex];
    if (idx == _shownLabelIndex || idx < 0) return;
    _shownLabelIndex = idx;
    _titleLayer.string = [self.delegate coverflowView:self titleForIndex:idx];
    _artistLayer.string = [self.delegate coverflowView:self artistForIndex:idx];
}

- (void)resolveCover:(FCFCoverLayer*)l {
    id cover = [self.delegate coverflowView:self coverForIndex:l.index];
    if (cover == nil) {
        // still loading: show the placeholder, the delegate calls -coverDidLoadForIndex: later
        [l showCover:nil title:[self.delegate coverflowView:self titleForIndex:l.index]];
        l.coverResolved = YES;
        return;
    }
    CGImageRef img = (cover == [NSNull null]) ? nil : (__bridge CGImageRef)cover;
    [l showCover:img title:[self.delegate coverflowView:self titleForIndex:l.index]];
    l.coverResolved = YES;
}

- (FCFCoverLayer*)dequeue {
    FCFCoverLayer* l = _pool.lastObject;
    if (l) {
        [_pool removeLastObject];
        l.hidden = NO;
        return l;
    }
    l = [FCFCoverLayer layer];
    // No implicit animations: positions are driven by our own display link.
    NSDictionary* none = @{ @"position": [NSNull null], @"transform": [NSNull null],
                            @"bounds": [NSNull null], @"opacity": [NSNull null],
                            @"zPosition": [NSNull null], @"hidden": [NSNull null],
                            @"contents": [NSNull null], @"sublayers": [NSNull null] };
    l.actions = none;
    l.imageLayer.actions = none;
    l.reflectionLayer.actions = none;
    l.reflectionFade.actions = none;
    l.placeholderText.actions = none;
    return l;
}

- (void)recycle:(FCFCoverLayer*)l {
    [l removeFromSuperlayer];
    [l showCover:nil title:@""];
    l.coverResolved = NO;
    if (_pool.count < 100) [_pool addObject:l];
}

#pragma mark Flip support

- (void)setCenterCoverHidden:(BOOL)hidden {
    _centerHidden = hidden;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self layoutCovers];
    [CATransaction commit];
}

- (void)setDimmed:(BOOL)dimmed {
    [CATransaction begin];
    [CATransaction setAnimationDuration:0.3];
    float o = dimmed ? 0.25f : 1.0f;
    for (CALayer* l in @[ _stage, _titleLayer, _artistLayer ]) {
        CABasicAnimation* a = [CABasicAnimation animationWithKeyPath:@"opacity"];
        a.fromValue = @(l.presentationLayer ? l.presentationLayer.opacity : l.opacity);
        a.toValue = @(o);
        a.duration = 0.3;
        [l addAnimation:a forKey:@"dim"];
        l.opacity = o;
    }
    [CATransaction commit];
}

#pragma mark Animation

- (void)scrollToIndex:(NSInteger)index animated:(BOOL)animated {
    if (_count == 0) return;
    _target = MAX(0, MIN(_count - 1, index));
    if (animated) {
        [self startAnimating];
    } else {
        _pos = _target;
        [self relayout];
    }
}

- (void)startAnimating {
    if (_link) return;
    _link = [self displayLinkWithTarget:self selector:@selector(tick:)];
    [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    _lastTick = 0;
}

- (void)tick:(CADisplayLink*)link {
    CFTimeInterval now = link.timestamp;
    CFTimeInterval dt = _lastTick > 0 ? now - _lastTick : 1.0 / 60.0;
    _lastTick = now;
    dt = MIN(dt, 0.05);

    CGFloat k = 1 - exp(-dt * 11.0);
    _pos += (_target - _pos) * k;
    if (fabs(_target - _pos) < 0.0008) {
        _pos = _target;
        [_link invalidate];
        _link = nil;
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self layoutCovers];
    [CATransaction commit];
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (!self.window) {
        [_link invalidate];
        _link = nil;
    }
    [self relayout];
}

#pragma mark Input

- (void)moveBy:(NSInteger)delta {
    if (_count == 0) return;
    [self.delegate coverflowViewWillScroll:self];
    [self scrollToIndex:lround(_target) + delta animated:YES];
}

- (void)scrollWheel:(NSEvent*)event {
    if (_count == 0) return;
    CGFloat dx = event.scrollingDeltaX, dy = event.scrollingDeltaY;
    CGFloat d = fabs(dx) > fabs(dy) ? dx : dy;
    if (d == 0) return;
    // Closes an open back side; input stays suspended only during a flip animation.
    [self.delegate coverflowViewWillScroll:self];
    if (self.inputSuspended) return;

    if (event.hasPreciseScrollingDeltas) {
        // Trackpad / Magic Mouse: follow the fingers, snap to the nearest album afterwards.
        _target = MAX(0, MIN(_count - 1, _target - d / ([self coverSize] * 0.22)));
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(snapToNearest) object:nil];
        [self performSelector:@selector(snapToNearest) withObject:nil afterDelay:0.12];
    } else {
        // Classic mouse wheel: one album per notch.
        NSInteger steps = MAX(1, lround(fabs(d)));
        _target = MAX(0, MIN(_count - 1, lround(_target) + (d > 0 ? -steps : steps)));
    }
    [self startAnimating];
}

- (void)snapToNearest {
    _target = MAX(0, MIN(_count - 1, lround(_target)));
    [self startAnimating];
}

- (void)keyDown:(NSEvent*)event {
    if (self.inputSuspended) return;
    NSString* chars = event.charactersIgnoringModifiers;
    unichar ch = chars.length ? [chars characterAtIndex:0] : 0;
    switch (ch) {
        case NSLeftArrowFunctionKey:
        case NSUpArrowFunctionKey: [self moveBy:-1]; return;
        case NSRightArrowFunctionKey:
        case NSDownArrowFunctionKey: [self moveBy:1]; return;
        case NSPageUpFunctionKey: [self moveBy:-10]; return;
        case NSPageDownFunctionKey: [self moveBy:10]; return;
        case NSHomeFunctionKey: [self moveBy:-(NSInteger)_count]; return;
        case NSEndFunctionKey: [self moveBy:(NSInteger)_count]; return;
        case ' ':
        case '\r':
        case 3:   // Enter on the numeric keypad
            if (_count) [self.delegate coverflowView:self didActivateIndex:[self centerIndex]];
            return;
    }
    [super keyDown:event];
}

- (NSInteger)indexAtPoint:(NSPoint)p {
    // Ask Core Animation first (handles the 3D transforms) ...
    CALayer* hit = [_stage hitTest:p];
    while (hit && ![hit isKindOfClass:[FCFCoverLayer class]]) hit = hit.superlayer;
    if (hit) return ((FCFCoverLayer*)hit).index;

    // ... and fall back to an estimate from the layout formula.
    CGFloat s = [self coverSize];
    CGPoint c = [self coverCenter];
    if (p.y < c.y - s / 2 || p.y > c.y + s / 2) return -1;
    CGFloat dx = p.x - c.x;
    CGFloat gap = s * 0.62, spacing = s * 0.2;
    NSInteger mid = lround(_pos);
    if (fabs(dx) <= s / 2) return mid;
    NSInteger off = 1 + (NSInteger)floor(MAX(0, fabs(dx) - gap) / spacing);
    NSInteger idx = mid + (dx > 0 ? off : -off);
    return (idx >= 0 && idx < _count) ? idx : -1;
}

- (void)mouseDown:(NSEvent*)event {
    [self.window makeFirstResponder:self];
    if (_count == 0) return;
    if (self.inputSuspended) {
        // e.g. a click next to the open back side
        [self.delegate coverflowViewDidClickWhileSuspended:self];
        return;
    }
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger idx = [self indexAtPoint:p];
    if (idx < 0) return;

    NSInteger center = [self centerIndex];
    if (idx == center && fabs(_pos - _target) < 0.3) {
        [self.delegate coverflowView:self didActivateIndex:idx];
    } else {
        [self.delegate coverflowViewWillScroll:self];
        [self scrollToIndex:idx animated:YES];
    }
}

@end
