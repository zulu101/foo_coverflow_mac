#import "CoverflowViewController.h"
#import "AlbumModel.h"
#import "AlbumBackView.h"
#import "CoverflowView.h"

#include <memory>

@interface FCFCoverflowViewController () <FCFCoverflowViewDelegate, FCFAlbumBackViewDelegate>
- (void)scheduleReload;
@end

namespace {
// Reloads the albums when the media library changes.
class FCFLibraryWatcher : public library_callback_v2_dynamic_impl_base {
public:
    explicit FCFLibraryWatcher(FCFCoverflowViewController* owner) : m_owner(owner) {}
    void on_items_added(metadb_handle_list_cref) override { [m_owner scheduleReload]; }
    void on_items_removed(metadb_handle_list_cref) override { [m_owner scheduleReload]; }
    void on_items_modified_v2(metadb_handle_list_cref, metadb_io_callback_v2_data&) override { [m_owner scheduleReload]; }
    void on_library_initialized() override { [m_owner scheduleReload]; }
private:
    __weak FCFCoverflowViewController* m_owner;
};

constexpr int kCoverPixels = 512;
} // namespace

@implementation FCFCoverflowViewController {
    FCFCoverflowView* _flow;
    std::vector<FCFAlbum> _albums;
    std::unique_ptr<FCFLibraryWatcher> _watcher;
    BOOL _reloadScheduled;

    // Cover cache: index -> CGImage, or NSNull for "no cover"
    NSCache<NSNumber*, id>* _covers;
    NSMutableSet<NSNumber*>* _loading;
    NSUInteger _generation;   // bumped on reload, so stale background results are dropped
    dispatch_queue_t _coverQueue;

    // Back side
    FCFAlbumBackView* _back;
    NSInteger _backIndex;
    BOOL _flipping;
}

- (void)loadView {
    _flow = [[FCFCoverflowView alloc] initWithFrame:NSMakeRect(0, 0, 640, 360)];
    _flow.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _flow.delegate = self;

    NSView* root = [[NSView alloc] initWithFrame:_flow.frame];
    root.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [root addSubview:_flow];
    self.view = root;

    _covers = [[NSCache alloc] init];
    _covers.totalCostLimit = 300 * 1024 * 1024;   // ~300 MB of decoded covers
    _loading = [NSMutableSet set];
    _coverQueue = dispatch_queue_create("foo_coverflow_mac.covers",
        dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_CONCURRENT, QOS_CLASS_USER_INITIATED, 0));

    _watcher = std::make_unique<FCFLibraryWatcher>(self);
    [self reloadAlbums];
}

- (void)dealloc {
    _watcher.reset();
}

#pragma mark Library

- (void)scheduleReload {
    if (_reloadScheduled) return;
    _reloadScheduled = YES;
    __weak FCFCoverflowViewController* weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        FCFCoverflowViewController* s = weakSelf;
        if (!s) return;
        s->_reloadScheduled = NO;
        [s reloadAlbums];
    });
}

- (void)reloadAlbums {
    std::string currentKey;
    NSInteger current = _flow.centerIndex;
    if (current >= 0 && current < (NSInteger)_albums.size()) currentKey = _albums[current].key;

    [self closeBackAnimated:NO];
    _albums = FCFLoadAlbums();
    _generation++;
    [_covers removeAllObjects];
    [_loading removeAllObjects];

    NSInteger restore = 0;
    if (!currentKey.empty()) {
        for (size_t i = 0; i < _albums.size(); ++i) {
            if (_albums[i].key == currentKey) { restore = (NSInteger)i; break; }
        }
    }

    _flow.emptyMessage = library_manager::get()->is_library_enabled()
        ? @"Keine Alben in der Medienbibliothek."
        : @"Die Medienbibliothek ist noch nicht eingerichtet.\nfoobar2000 → Einstellungen → Media Library";
    [_flow reloadDataKeepingIndex:restore];
}

#pragma mark Coverflow data source

- (NSInteger)numberOfAlbumsInCoverflowView:(FCFCoverflowView*)view {
    return (NSInteger)_albums.size();
}

- (NSString*)coverflowView:(FCFCoverflowView*)view titleForIndex:(NSInteger)index {
    return FCFString(_albums[index].title.c_str());
}

- (NSString*)coverflowView:(FCFCoverflowView*)view artistForIndex:(NSInteger)index {
    return FCFString(_albums[index].artist.c_str());
}

- (id)coverflowView:(FCFCoverflowView*)view coverForIndex:(NSInteger)index {
    NSNumber* key = @(index);
    id cached = [_covers objectForKey:key];
    if (cached) return cached;
    if ([_loading containsObject:key]) return nil;
    [_loading addObject:key];

    // Art lookup uses the first track of the album (embedded art or folder.jpg & co.)
    metadb_handle_list first;
    first.add_item(_albums[index].tracks[0]);
    NSUInteger gen = _generation;
    __weak FCFCoverflowViewController* weakSelf = self;

    dispatch_async(_coverQueue, ^{
        CGImageRef img = FCFLoadCover(first, kCoverPixels);
        id obj = img ? (__bridge_transfer id)img : (id)[NSNull null];
        NSUInteger cost = img ? CGImageGetBytesPerRow(img) * CGImageGetHeight(img) : 0;
        dispatch_async(dispatch_get_main_queue(), ^{
            FCFCoverflowViewController* s = weakSelf;
            if (!s || s->_generation != gen) return;
            [s->_loading removeObject:key];
            [s->_covers setObject:obj forKey:key cost:cost];
            [s->_flow coverDidLoadForIndex:index];
        });
    });
    return nil;
}

- (void)coverflowView:(FCFCoverflowView*)view didActivateIndex:(NSInteger)index {
    if (_back) [self closeBackAnimated:YES];
    else [self openBackForIndex:index];
}

- (void)coverflowViewWillScroll:(FCFCoverflowView*)view {
    if (_back && !_flipping) [self closeBackAnimated:NO];
}

- (void)coverflowViewDidClickWhileSuspended:(FCFCoverflowView*)view {
    // Click anywhere next to the back side flips it back to the cover.
    if (_back && !_flipping) [self closeBackAnimated:YES];
}

#pragma mark Flip

static CATransform3D FCFRotY(CGFloat angle) {
    return CATransform3DMakeRotation(angle, 0, 1, 0);
}

- (NSRect)backFrameForCover:(NSRect)cover {
    NSRect b = self.view.bounds;
    CGFloat w = MIN(MAX(cover.size.width * 1.45, 340), b.size.width - 24);
    CGFloat h = MIN(MAX(cover.size.height * 1.25, 260), b.size.height - 24);
    NSRect r = NSMakeRect(NSMidX(cover) - w / 2, NSMidY(cover) - h / 2, w, h);
    r.origin.x = MAX(12, MIN(r.origin.x, b.size.width - w - 12));
    r.origin.y = MAX(12, MIN(r.origin.y, b.size.height - h - 12));
    return NSIntegralRect(r);
}

// A layer that shows `contents` at `frame`, inside a container with perspective.
- (CALayer*)flipLayerWithContents:(id)contents frame:(NSRect)frame container:(CALayer*)container {
    CALayer* l = [CALayer layer];
    l.frame = frame;
    l.contents = contents;
    l.contentsGravity = kCAGravityResizeAspectFill;
    l.masksToBounds = YES;
    l.cornerRadius = 0;
    l.doubleSided = NO;
    l.backgroundColor = contents ? nil : [NSColor colorWithWhite:0.18 alpha:1].CGColor;
    [container addSublayer:l];
    return l;
}

- (CALayer*)makeFlipContainer {
    CALayer* container = [CALayer layer];
    container.frame = _flow.bounds;
    CATransform3D p = CATransform3DIdentity;
    p.m34 = -1.0 / 1400.0;
    container.sublayerTransform = p;
    [_flow.overlayLayer addSublayer:container];
    return container;
}

- (id)coverContentsForIndex:(NSInteger)index {
    id c = [_covers objectForKey:@(index)];
    return (c && c != [NSNull null]) ? c : nil;
}

- (void)openBackForIndex:(NSInteger)index {
    if (_flipping || index < 0 || index >= (NSInteger)_albums.size()) return;
    const FCFAlbum& album = _albums[index];

    NSRect coverFrame = [_flow centerCoverFrame];
    NSRect backFrame = [self backFrameForCover:coverFrame];

    _back = [[FCFAlbumBackView alloc] initWithFrame:backFrame];
    _back.delegate = self;
    [_back setAlbumTitle:FCFString(album.title.c_str())
                  artist:FCFString(album.artist.c_str())
                    info:FCFAlbumInfoLine(album)
                  tracks:FCFTrackRows(album)];
    _back.alphaValue = 0;
    [self.view addSubview:_back];
    _backIndex = index;
    NSImage* snapshot = [_back snapshot];

    _flipping = YES;
    _flow.inputSuspended = YES;

    CALayer* container = [self makeFlipContainer];
    CALayer* front = [self flipLayerWithContents:[self coverContentsForIndex:index] frame:coverFrame container:container];
    CALayer* backLayer = [self flipLayerWithContents:snapshot frame:backFrame container:container];
    backLayer.cornerRadius = 10;
    backLayer.transform = FCFRotY(-M_PI_2);
    [CATransaction flush];

    [_flow setCenterCoverHidden:YES];
    [_flow setDimmed:YES];

    // Phase 1: the cover turns away and grows towards the size of the back side.
    [CATransaction begin];
    [CATransaction setAnimationDuration:0.22];
    [CATransaction setAnimationTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn]];
    [CATransaction setCompletionBlock:^{
        front.hidden = YES;
        // Phase 2: the back side turns in.
        [CATransaction begin];
        [CATransaction setAnimationDuration:0.24];
        [CATransaction setAnimationTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut]];
        [CATransaction setCompletionBlock:^{
            self->_back.alphaValue = 1;
            [container removeFromSuperlayer];
            self->_flipping = NO;
            [self->_back focusTrackList];
        }];
        backLayer.transform = CATransform3DIdentity;
        [CATransaction commit];
    }];
    front.transform = FCFRotY(M_PI_2);
    front.bounds = CGRectMake(0, 0, backFrame.size.width, backFrame.size.height);
    front.position = CGPointMake(NSMidX(backFrame), NSMidY(backFrame));
    [CATransaction commit];
}

- (void)closeBackAnimated:(BOOL)animated {
    if (!_back || (_flipping && animated)) return;

    FCFAlbumBackView* back = _back;
    _back = nil;
    _flow.inputSuspended = NO;

    if (!animated) {
        [back removeFromSuperview];
        [_flow setCenterCoverHidden:NO];
        [_flow setDimmed:NO];
        [self.view.window makeFirstResponder:_flow];
        return;
    }

    NSRect backFrame = back.frame;
    NSRect coverFrame = [_flow centerCoverFrame];
    NSImage* snapshot = [back snapshot];
    [back removeFromSuperview];
    [self.view.window makeFirstResponder:_flow];

    _flipping = YES;
    _flow.inputSuspended = YES;
    CALayer* container = [self makeFlipContainer];
    CALayer* backLayer = [self flipLayerWithContents:snapshot frame:backFrame container:container];
    backLayer.cornerRadius = 10;
    CALayer* front = [self flipLayerWithContents:[self coverContentsForIndex:_backIndex] frame:backFrame container:container];
    front.transform = FCFRotY(-M_PI_2);
    [CATransaction flush];

    [_flow setDimmed:NO];

    [CATransaction begin];
    [CATransaction setAnimationDuration:0.2];
    [CATransaction setAnimationTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn]];
    [CATransaction setCompletionBlock:^{
        backLayer.hidden = YES;
        [CATransaction begin];
        [CATransaction setAnimationDuration:0.24];
        [CATransaction setAnimationTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut]];
        [CATransaction setCompletionBlock:^{
            [self->_flow setCenterCoverHidden:NO];
            [container removeFromSuperlayer];
            self->_flipping = NO;
            self->_flow.inputSuspended = NO;
        }];
        front.transform = CATransform3DIdentity;
        front.bounds = CGRectMake(0, 0, coverFrame.size.width, coverFrame.size.height);
        front.position = CGPointMake(NSMidX(coverFrame), NSMidY(coverFrame));
        [CATransaction commit];
    }];
    backLayer.transform = FCFRotY(M_PI_2);
    [CATransaction commit];
}

- (void)viewDidLayout {
    [super viewDidLayout];
    if (_back && !_flipping) {
        _back.frame = [self backFrameForCover:[_flow centerCoverFrame]];
    }
}

#pragma mark Back side actions

- (void)albumBackViewRequestsClose:(FCFAlbumBackView*)view {
    [self closeBackAnimated:YES];
}

- (void)albumBackView:(FCFAlbumBackView*)view playTrack:(NSInteger)row {
    const FCFAlbum& a = _albums[_backIndex];
    if (row >= 0 && (size_t)row < a.tracks.get_count()) FCFPlayTrack(a.tracks[row]);
}

- (void)albumBackView:(FCFAlbumBackView*)view addTracksToPlaylist:(NSIndexSet*)rows {
    const FCFAlbum& a = _albums[_backIndex];
    metadb_handle_list list;
    for (NSUInteger row = rows.firstIndex; row != NSNotFound; row = [rows indexGreaterThanIndex:row]) {
        if (row < a.tracks.get_count()) list.add_item(a.tracks[row]);
    }
    if (list.get_count()) FCFAddToPlaylist(list);
}

- (void)albumBackViewAddAlbumToPlaylist:(FCFAlbumBackView*)view {
    FCFAddToPlaylist(_albums[_backIndex].tracks);
}

@end
