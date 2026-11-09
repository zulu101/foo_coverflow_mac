#import "AlbumBackView.h"

static NSUserInterfaceItemIdentifier const kColNumber = @"num";
static NSUserInterfaceItemIdentifier const kColTitle = @"title";
static NSUserInterfaceItemIdentifier const kColLength = @"len";

// Table that plays the selected track on Return.
@interface FCFTrackTableView : NSTableView
@property(nonatomic, copy) void (^onReturn)(void);
@end

@implementation FCFTrackTableView
- (void)keyDown:(NSEvent*)event {
    if ((event.keyCode == 36 || event.keyCode == 76) && self.onReturn) {   // Return / Enter
        self.onReturn();
        return;
    }
    [super keyDown:event];
}
@end

@interface FCFAlbumBackView () <NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate>
@end

@implementation FCFAlbumBackView {
    NSView* _header;
    NSTextField* _titleField;
    NSTextField* _artistField;
    NSTextField* _infoField;
    NSScrollView* _scroll;
    FCFTrackTableView* _table;
    NSArray<NSArray<NSString*>*>* _rows;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
        self.wantsLayer = YES;
        self.layer.cornerRadius = 10;
        self.layer.masksToBounds = YES;
        [self buildUI];
    }
    return self;
}

- (BOOL)isOpaque { return NO; }

- (void)drawRect:(NSRect)dirtyRect {
    // Drawn (not a layer background) so -snapshot captures it, too.
    NSBezierPath* path = [NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:10 yRadius:10];
    [[NSColor colorWithWhite:0.11 alpha:1] setFill];
    [path fill];
    [[NSColor colorWithWhite:0.3 alpha:1] setStroke];
    path.lineWidth = 1;
    [path stroke];
}

- (NSTextField*)labelWithSize:(CGFloat)size weight:(NSFontWeight)weight color:(NSColor*)color {
    NSTextField* f = [NSTextField labelWithString:@""];
    f.font = [NSFont systemFontOfSize:size weight:weight];
    f.textColor = color;
    f.lineBreakMode = NSLineBreakByTruncatingTail;
    f.translatesAutoresizingMaskIntoConstraints = NO;
    [f setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    return f;
}

- (void)buildUI {
    _header = [[NSView alloc] init];
    _header.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_header];

    _titleField = [self labelWithSize:15 weight:NSFontWeightSemibold color:NSColor.labelColor];
    _artistField = [self labelWithSize:12.5 weight:NSFontWeightRegular color:NSColor.secondaryLabelColor];
    _infoField = [self labelWithSize:11 weight:NSFontWeightRegular color:NSColor.tertiaryLabelColor];
    [_header addSubview:_titleField];
    [_header addSubview:_artistField];
    [_header addSubview:_infoField];

    NSBox* line = [[NSBox alloc] init];
    line.boxType = NSBoxSeparator;
    line.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:line];

    // Click on the header flips the cover back.
    NSClickGestureRecognizer* click = [[NSClickGestureRecognizer alloc] initWithTarget:self action:@selector(headerClicked:)];
    [_header addGestureRecognizer:click];
    _header.toolTip = @"Klicken, um zum Cover zurückzukehren";

    _table = [[FCFTrackTableView alloc] init];
    _table.headerView = nil;
    _table.style = NSTableViewStylePlain;
    _table.backgroundColor = NSColor.clearColor;
    _table.rowHeight = 22;
    _table.intercellSpacing = NSMakeSize(6, 0);
    _table.allowsMultipleSelection = YES;
    _table.columnAutoresizingStyle = NSTableViewNoColumnAutoresizing;   // see -layout
    _table.dataSource = self;
    _table.delegate = self;
    _table.target = self;
    _table.doubleAction = @selector(tableDoubleClicked:);
    __weak FCFAlbumBackView* weakSelf = self;
    _table.onReturn = ^{ [weakSelf playSelected]; };

    NSTableColumn* title = [[NSTableColumn alloc] initWithIdentifier:kColTitle];
    title.resizingMask = NSTableColumnAutoresizingMask;
    NSTableColumn* num = [[NSTableColumn alloc] initWithIdentifier:kColNumber];
    num.width = 34; num.resizingMask = NSTableColumnNoResizing;
    NSTableColumn* len = [[NSTableColumn alloc] initWithIdentifier:kColLength];
    len.width = 52; len.resizingMask = NSTableColumnNoResizing;
    [_table addTableColumn:num];
    [_table addTableColumn:title];
    [_table addTableColumn:len];

    NSMenu* menu = [[NSMenu alloc] init];
    menu.delegate = self;
    _table.menu = menu;

    _scroll = [[NSScrollView alloc] init];
    _scroll.translatesAutoresizingMaskIntoConstraints = NO;
    _scroll.drawsBackground = NO;
    _scroll.hasVerticalScroller = YES;
    _scroll.autohidesScrollers = YES;
    _scroll.documentView = _table;
    [self addSubview:_scroll];

    [NSLayoutConstraint activateConstraints:@[
        [_header.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_header.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_header.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

        [_titleField.topAnchor constraintEqualToAnchor:_header.topAnchor constant:14],
        [_titleField.leadingAnchor constraintEqualToAnchor:_header.leadingAnchor constant:16],
        [_titleField.trailingAnchor constraintLessThanOrEqualToAnchor:_header.trailingAnchor constant:-16],
        [_artistField.topAnchor constraintEqualToAnchor:_titleField.bottomAnchor constant:2],
        [_artistField.leadingAnchor constraintEqualToAnchor:_titleField.leadingAnchor],
        [_artistField.trailingAnchor constraintLessThanOrEqualToAnchor:_header.trailingAnchor constant:-16],
        [_infoField.topAnchor constraintEqualToAnchor:_artistField.bottomAnchor constant:3],
        [_infoField.leadingAnchor constraintEqualToAnchor:_titleField.leadingAnchor],
        [_infoField.trailingAnchor constraintLessThanOrEqualToAnchor:_header.trailingAnchor constant:-16],
        [_infoField.bottomAnchor constraintEqualToAnchor:_header.bottomAnchor constant:-10],

        [line.topAnchor constraintEqualToAnchor:_header.bottomAnchor],
        [line.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
        [line.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],

        [_scroll.topAnchor constraintEqualToAnchor:line.bottomAnchor constant:4],
        [_scroll.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:6],
        [_scroll.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-6],
        [_scroll.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-8],
    ]];
}

- (void)setAlbumTitle:(NSString*)title artist:(NSString*)artist info:(NSString*)info tracks:(NSArray<NSArray<NSString*>*>*)rows {
    _titleField.stringValue = title;
    _artistField.stringValue = artist;
    _infoField.stringValue = info;
    _rows = rows;
    [_table reloadData];
    self.needsLayout = YES;
}

- (void)layout {
    [super layout];
    // # and length are fixed; the title column takes the rest.
    NSTableColumn* title = [_table tableColumnWithIdentifier:kColTitle];
    CGFloat avail = _scroll.contentSize.width - 34 - 52 - _table.intercellSpacing.width * 3 - 4;
    if (avail > 40) title.width = avail;
}

- (void)focusTrackList {
    [self.window makeFirstResponder:_table];
}

- (NSImage*)snapshot {
    [self layoutSubtreeIfNeeded];
    NSBitmapImageRep* rep = [self bitmapImageRepForCachingDisplayInRect:self.bounds];
    if (!rep) return [[NSImage alloc] initWithSize:self.bounds.size];
    [self cacheDisplayInRect:self.bounds toBitmapImageRep:rep];
    NSImage* img = [[NSImage alloc] initWithSize:self.bounds.size];
    [img addRepresentation:rep];
    return img;
}

#pragma mark Actions

- (void)headerClicked:(id)sender {
    [self.delegate albumBackViewRequestsClose:self];
}

- (void)cancelOperation:(id)sender {   // Esc
    [self.delegate albumBackViewRequestsClose:self];
}

- (void)tableDoubleClicked:(id)sender {
    NSInteger row = _table.clickedRow;
    if (row >= 0) [self.delegate albumBackView:self playTrack:row];
}

- (void)playSelected {
    NSInteger row = _table.selectedRow;
    if (row >= 0) [self.delegate albumBackView:self playTrack:row];
}

// Rows the context menu applies to: the selection if the clicked row is part of it, otherwise the clicked row.
- (NSIndexSet*)menuRows {
    NSInteger clicked = _table.clickedRow;
    if (clicked < 0) return _table.selectedRowIndexes;
    if ([_table.selectedRowIndexes containsIndex:clicked]) return _table.selectedRowIndexes;
    return [NSIndexSet indexSetWithIndex:clicked];
}

- (void)menuNeedsUpdate:(NSMenu*)menu {
    [menu removeAllItems];
    NSIndexSet* rows = [self menuRows];
    if (rows.count > 0) {
        [menu addItemWithTitle:@"Abspielen" action:@selector(menuPlay:) keyEquivalent:@""].target = self;
        NSString* add = rows.count == 1 ? @"Zur Playlist hinzufügen"
                                        : [NSString stringWithFormat:@"%lu Titel zur Playlist hinzufügen", (unsigned long)rows.count];
        [menu addItemWithTitle:add action:@selector(menuAdd:) keyEquivalent:@""].target = self;
        [menu addItem:[NSMenuItem separatorItem]];
    }
    [menu addItemWithTitle:@"Ganzes Album zur Playlist hinzufügen" action:@selector(menuAddAlbum:) keyEquivalent:@""].target = self;
}

- (void)menuPlay:(id)sender {
    NSIndexSet* rows = [self menuRows];
    if (rows.count) [self.delegate albumBackView:self playTrack:rows.firstIndex];
}

- (void)menuAdd:(id)sender {
    NSIndexSet* rows = [self menuRows];
    if (rows.count) [self.delegate albumBackView:self addTracksToPlaylist:rows];
}

- (void)menuAddAlbum:(id)sender {
    [self.delegate albumBackViewAddAlbumToPlaylist:self];
}

#pragma mark Table

- (NSInteger)numberOfRowsInTableView:(NSTableView*)tableView {
    return (NSInteger)_rows.count;
}

- (NSView*)tableView:(NSTableView*)tableView viewForTableColumn:(NSTableColumn*)column row:(NSInteger)row {
    NSString* ident = column.identifier;
    NSTableCellView* cell = [tableView makeViewWithIdentifier:ident owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] init];
        cell.identifier = ident;
        NSTextField* f = [NSTextField labelWithString:@""];
        f.translatesAutoresizingMaskIntoConstraints = NO;
        f.lineBreakMode = NSLineBreakByTruncatingTail;
        BOOL secondary = ![ident isEqualToString:kColTitle];
        f.font = secondary ? [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightRegular]
                           : [NSFont systemFontOfSize:12.5];
        f.textColor = secondary ? NSColor.secondaryLabelColor : NSColor.labelColor;
        f.alignment = secondary ? NSTextAlignmentRight : NSTextAlignmentLeft;
        [f setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        [cell addSubview:f];
        cell.textField = f;
        [NSLayoutConstraint activateConstraints:@[
            [f.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:2],
            [f.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-2],
            [f.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
        ]];
    }
    NSInteger col = [ident isEqualToString:kColNumber] ? 0 : [ident isEqualToString:kColTitle] ? 1 : 2;
    cell.textField.stringValue = _rows[row][col];
    return cell;
}

@end
