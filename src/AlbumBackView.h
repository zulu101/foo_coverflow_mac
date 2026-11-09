#pragma once
#import "stdafx.h"

NS_ASSUME_NONNULL_BEGIN

@class FCFAlbumBackView;

@protocol FCFAlbumBackViewDelegate <NSObject>
- (void)albumBackViewRequestsClose:(FCFAlbumBackView*)view;
- (void)albumBackView:(FCFAlbumBackView*)view playTrack:(NSInteger)row;
- (void)albumBackView:(FCFAlbumBackView*)view addTracksToPlaylist:(NSIndexSet*)rows;
- (void)albumBackViewAddAlbumToPlaylist:(FCFAlbumBackView*)view;
@end

// The back side of a flipped cover: album header and track list.
@interface FCFAlbumBackView : NSView
@property(nonatomic, weak) id<FCFAlbumBackViewDelegate> delegate;

- (void)setAlbumTitle:(NSString*)title
               artist:(NSString*)artist
                 info:(NSString*)info
               tracks:(NSArray<NSArray<NSString*>*>*)rows;
- (void)focusTrackList;
// Renders the view into an image (used for the flip animation).
- (NSImage*)snapshot;
@end

NS_ASSUME_NONNULL_END
