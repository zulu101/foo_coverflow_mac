#pragma once
#import "stdafx.h"

NS_ASSUME_NONNULL_BEGIN

@class FCFCoverflowView;

@protocol FCFCoverflowViewDelegate <NSObject>
- (NSInteger)numberOfAlbumsInCoverflowView:(FCFCoverflowView*)view;
// Returns a CGImageRef (bridged to id), NSNull when the album has no cover,
// or nil while the cover is still loading (call -coverDidLoadForIndex: when done).
- (nullable id)coverflowView:(FCFCoverflowView*)view coverForIndex:(NSInteger)index;
- (NSString*)coverflowView:(FCFCoverflowView*)view titleForIndex:(NSInteger)index;
- (NSString*)coverflowView:(FCFCoverflowView*)view artistForIndex:(NSInteger)index;
// The centered cover was clicked (or Space/Return pressed).
- (void)coverflowView:(FCFCoverflowView*)view didActivateIndex:(NSInteger)index;
// Called before the view scrolls because of user input.
- (void)coverflowViewWillScroll:(FCFCoverflowView*)view;
// A click landed on the coverflow while input is suspended (back side open or flipping).
- (void)coverflowViewDidClickWhileSuspended:(FCFCoverflowView*)view;
@end

// Layer-hosting view that draws the 3D coverflow.
@interface FCFCoverflowView : NSView
@property(nonatomic, weak) id<FCFCoverflowViewDelegate> delegate;
@property(nonatomic, readonly) NSInteger centerIndex;
@property(nonatomic, copy, nullable) NSString* emptyMessage;
// While YES, mouse and keyboard input is ignored (used during the flip animation).
@property(nonatomic) BOOL inputSuspended;

- (void)reloadDataKeepingIndex:(NSInteger)index;
- (void)scrollToIndex:(NSInteger)index animated:(BOOL)animated;
- (void)coverDidLoadForIndex:(NSInteger)index;

// For the flip animation
- (NSRect)centerCoverFrame;
- (CGFloat)coverSize;
- (void)setCenterCoverHidden:(BOOL)hidden;
- (void)setDimmed:(BOOL)dimmed;
// Layer above the covers for temporary animation layers.
@property(nonatomic, readonly) CALayer* overlayLayer;
@end

NS_ASSUME_NONNULL_END
