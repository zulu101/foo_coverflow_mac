#pragma once
#import "stdafx.h"

#include <string>
#include <vector>

// One album of the media library, grouped by %album artist% + %album%.
struct FCFAlbum {
    std::string key;      // grouping key, used to restore the position after a reload
    std::string title;
    std::string artist;
    std::string year;
    metadb_handle_list tracks;   // sorted by disc / track number
    double totalLength = 0;
};

// Reads the whole media library. Main thread only.
std::vector<FCFAlbum> FCFLoadAlbums();

// One row of the track list on the back side: number, title, length.
NSArray<NSArray<NSString*>*>* FCFTrackRows(const FCFAlbum& album);

// "2019 · 12 Titel · 48:12"
NSString* FCFAlbumInfoLine(const FCFAlbum& album);

// Loads the front cover of the given tracks as a downscaled image.
// Thread-safe, meant to run on a background queue. Returns nullptr when there is no cover.
CGImageRef FCFLoadCover(metadb_handle_list_cref tracks, int maxPixelSize) CF_RETURNS_RETAINED;

// Variante B: play only this track (adds it to the active playlist if it is not in there yet).
void FCFPlayTrack(metadb_handle_ptr track);
// Appends tracks to the active playlist without starting playback.
void FCFAddToPlaylist(metadb_handle_list_cref tracks);

NSString* FCFString(const char* utf8);
