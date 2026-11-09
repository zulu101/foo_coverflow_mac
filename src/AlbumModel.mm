#import "AlbumModel.h"
#import <ImageIO/ImageIO.h>

NSString* FCFString(const char* utf8) {
    NSString* s = utf8 ? [NSString stringWithUTF8String:utf8] : nil;
    return s ?: @"";
}

static titleformat_object::ptr FCFCompile(const char* spec) {
    titleformat_object::ptr script;
    titleformat_compiler::get()->compile_safe(script, spec);
    return script;
}

static std::string FCFFormat(const metadb_handle_ptr& h, const titleformat_object::ptr& script) {
    pfc::string8 out;
    h->format_title(nullptr, out, script, nullptr);
    return out.c_str();
}

std::vector<FCFAlbum> FCFLoadAlbums() {
    std::vector<FCFAlbum> albums;

    auto lib = library_manager::get();
    if (!lib->is_library_enabled()) return albums;

    metadb_handle_list items;
    lib->get_all_items(items);
    if (items.get_count() == 0) return albums;

    // Sorting by artist, album, disc, track puts every album's tracks next to each other.
    auto sortScript = FCFCompile(
        "$lower($if2(%album artist%,~))|$lower($if2(%album%,~))|"
        "$num(%discnumber%,3)|$num(%tracknumber%,4)|%title%");
    metadb_handle_list_helper::sort_by_format(items, sortScript, nullptr);

    auto keyScript = FCFCompile("$lower(%album artist%)|$lower(%album%)");
    auto titleScript = FCFCompile("$if2(%album%,Unbekanntes Album)");
    auto artistScript = FCFCompile("$if2(%album artist%,Unbekannter Interpret)");
    auto yearScript = FCFCompile("[$left(%date%,4)]");

    std::string lastKey;
    for (size_t i = 0; i < items.get_count(); ++i) {
        const metadb_handle_ptr& h = items[i];
        std::string key = FCFFormat(h, keyScript);
        if (albums.empty() || key != lastKey) {
            FCFAlbum a;
            a.key = key;
            a.title = FCFFormat(h, titleScript);
            a.artist = FCFFormat(h, artistScript);
            a.year = FCFFormat(h, yearScript);
            albums.push_back(std::move(a));
            lastKey = key;
        }
        FCFAlbum& a = albums.back();
        a.tracks.add_item(h);
        double len = h->get_length();
        if (len > 0) a.totalLength += len;
    }
    return albums;
}

static NSString* FCFDuration(double seconds) {
    long s = lround(seconds);
    if (s >= 3600) return [NSString stringWithFormat:@"%ld:%02ld:%02ld", s / 3600, (s / 60) % 60, s % 60];
    return [NSString stringWithFormat:@"%ld:%02ld", s / 60, s % 60];
}

NSArray<NSArray<NSString*>*>* FCFTrackRows(const FCFAlbum& album) {
    auto numScript = FCFCompile("$if($greater(%totaldiscs%,1),%discnumber%.)[%tracknumber%]");
    auto titleScript = FCFCompile("%title%");
    auto lengthScript = FCFCompile("[%length%]");

    NSMutableArray* rows = [NSMutableArray arrayWithCapacity:album.tracks.get_count()];
    for (size_t i = 0; i < album.tracks.get_count(); ++i) {
        const metadb_handle_ptr& h = album.tracks[i];
        [rows addObject:@[
            FCFString(FCFFormat(h, numScript).c_str()),
            FCFString(FCFFormat(h, titleScript).c_str()),
            FCFString(FCFFormat(h, lengthScript).c_str()),
        ]];
    }
    return rows;
}

NSString* FCFAlbumInfoLine(const FCFAlbum& album) {
    NSMutableArray* parts = [NSMutableArray array];
    if (!album.year.empty()) [parts addObject:FCFString(album.year.c_str())];
    size_t n = album.tracks.get_count();
    [parts addObject:[NSString stringWithFormat:@"%zu %@", n, n == 1 ? @"Titel" : @"Titel"]];
    if (album.totalLength > 0) [parts addObject:FCFDuration(album.totalLength)];
    return [parts componentsJoinedByString:@" · "];
}

CGImageRef FCFLoadCover(metadb_handle_list_cref tracks, int maxPixelSize) {
    try {
        abort_callback_dummy abort;
        pfc::list_single_ref_t<GUID> ids(album_art_ids::cover_front);
        auto extractor = album_art_manager_v2::get()->open(tracks, ids, abort);
        album_art_data_ptr data = extractor->query(album_art_ids::cover_front, abort);
        if (!data.is_valid() || data->get_size() == 0) return nullptr;

        CFDataRef cf = CFDataCreate(nullptr, (const UInt8*)data->get_ptr(), (CFIndex)data->get_size());
        if (!cf) return nullptr;
        CGImageSourceRef src = CGImageSourceCreateWithData(cf, nullptr);
        CFRelease(cf);
        if (!src) return nullptr;

        NSDictionary* opts = @{
            (id)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
            (id)kCGImageSourceCreateThumbnailWithTransform: @YES,
            (id)kCGImageSourceThumbnailMaxPixelSize: @(maxPixelSize),
        };
        CGImageRef img = CGImageSourceCreateThumbnailAtIndex(src, 0, (__bridge CFDictionaryRef)opts);
        CFRelease(src);
        return img;
    } catch (...) {
        return nullptr;   // no cover, unreadable file, ...
    }
}

static t_size FCFActivePlaylist() {
    auto pm = playlist_manager::get();
    t_size pl = pm->get_active_playlist();
    if (pl == pfc_infinite || pl >= pm->get_playlist_count()) {
        pl = pm->create_playlist("Coverflow", pfc_infinite, pfc_infinite);
        pm->set_active_playlist(pl);
    }
    return pl;
}

void FCFPlayTrack(metadb_handle_ptr track) {
    auto pm = playlist_manager::get();
    t_size pl = FCFActivePlaylist();
    t_size index;
    if (!pm->playlist_find_item(pl, track, index)) {
        index = pm->playlist_get_item_count(pl);
        metadb_handle_list one;
        one.add_item(track);
        pm->playlist_add_items(pl, one, pfc::bit_array_false());
    }
    pm->playlist_set_focus_item(pl, index);
    pm->playlist_execute_default_action(pl, index);
}

void FCFAddToPlaylist(metadb_handle_list_cref tracks) {
    auto pm = playlist_manager::get();
    t_size pl = FCFActivePlaylist();
    pm->playlist_add_items(pl, tracks, pfc::bit_array_false());
}
