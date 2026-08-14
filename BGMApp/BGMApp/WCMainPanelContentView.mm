// This file is part of Background Music.
//
// Background Music is free software: you can redistribute it and/or
// modify it under the terms of the GNU General Public License as
// published by the Free Software Foundation, either version 2 of the
// License, or (at your option) any later version.
//
// Background Music is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Background Music. If not, see <http://www.gnu.org/licenses/>.

//
//  WCMainPanelContentView.mm
//  BGMApp
//
//  Copyright © 2026 Wavecraft contributors
//

// Self Include
#import "WCMainPanelContentView.h"


#pragma clang assume_nonnull begin

// Matches MainMenu.xib's existing appVolumeView row template width, so rows ported from there
// (Volumes section, per-app rows) don't need to be re-measured/re-justified for a new width.
static CGFloat const kContentWidth = 390;

static CGFloat const kContentVerticalPadding = 8;
static CGFloat const kRowHorizontalPadding = 14;
static CGFloat const kSeparatorTopBottomPadding = 6;

// NSMenu (what this panel replaced) scrolls automatically when its content is taller than the
// screen. A plain NSStackView doesn't -- with no cap at all, a user with enough apps open to
// produce audio (not a rare case for the exact people who'd want a per-app mixer) would get a
// panel that silently grows past the bottom of the screen, with the rows past the edge simply
// unreachable. This caps just the apps section (the only part with genuinely unbounded growth --
// everything else is a small, fixed number of rows) inside its own scroll view, so it scrolls
// independently while Output Device/Preferences/Quit below it stay pinned and always visible.
static CGFloat const kAppsScrollViewMaxHeight = 300;

@implementation WCMainPanelContentView {
    // The scroll view wrapping the apps section, and the stack view inside it that yourAppsStack/
    // the disclosure button/systemAndOtherAppsStack all actually live in -- see
    // updateAppsScrollViewHeight for why both are kept around.
    NSScrollView* appsScrollView;
    NSStackView* appsDocumentStack;
    NSLayoutConstraint* appsScrollViewHeightConstraint;
}

- (instancetype) initWithFrame:(NSRect)frameRect {
    #pragma unused (frameRect)

    self = [super initWithFrame:NSMakeRect(0, 0, kContentWidth, 0)];

    if (self) {
        self.wantsLayer = YES;
        self.layer.backgroundColor = NSColor.windowBackgroundColor.CGColor;
        self.layer.cornerRadius = 8;

        _rowStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
        _rowStack.orientation = NSUserInterfaceLayoutOrientationVertical;
        _rowStack.alignment = NSLayoutAttributeLeading;
        _rowStack.distribution = NSStackViewDistributionFill;
        _rowStack.spacing = 0;
        _rowStack.translatesAutoresizingMaskIntoConstraints = NO;

        [self addSubview:_rowStack];

        [NSLayoutConstraint activateConstraints:@[
            [_rowStack.topAnchor constraintEqualToAnchor:self.topAnchor
                                                  constant:kContentVerticalPadding],
            [_rowStack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor
                                                     constant:-kContentVerticalPadding],
            [_rowStack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_rowStack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_rowStack.widthAnchor constraintEqualToConstant:kContentWidth],
        ]];

        [self buildSections];
    }

    return self;
}

- (void) buildSections {
    _autoPauseButton = [self addRowButtonWithTitle:@""];
    [self addSeparator];

    [self addSectionHeaderWithTitle:@"Volumes"];
    _volumesStack = [self addVerticalStackWithSpacing:0];

    [self addSeparator];

    [self buildScrollableAppsSection];

    [self addSeparator];

    [self addSectionHeaderWithTitle:@"Output Device"];
    _outputDeviceStack = [self addVerticalStackWithSpacing:0];

    [self addSeparator];

    _preferencesButton = [self addRowButtonWithTitle:@"Preferences…"];
    _quitButton = [self addRowButtonWithTitle:@"Quit Wavecraft"];

    _debugLoggingButton = [self addRowButtonWithTitle:@"Debug Logging"];
    _debugLoggingButton.buttonType = NSButtonTypeSwitch;
}

// yourAppsStack/systemAndOtherAppsStack stay as their own addressable properties -- external
// callers (WCAppVolumesController) don't need to know they're now nested inside a scroll view
// rather than being direct children of rowStack; they just keep adding/removing arranged subviews
// exactly as before.
- (void) buildScrollableAppsSection {
    appsDocumentStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    appsDocumentStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    appsDocumentStack.alignment = NSLayoutAttributeLeading;
    appsDocumentStack.distribution = NSStackViewDistributionFill;
    appsDocumentStack.spacing = 0;
    appsDocumentStack.translatesAutoresizingMaskIntoConstraints = NO;

    NSView* header = [self sectionHeaderViewWithTitle:@"Your Apps"];
    [appsDocumentStack addArrangedSubview:header];

    _yourAppsStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    _yourAppsStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    _yourAppsStack.alignment = NSLayoutAttributeLeading;
    _yourAppsStack.distribution = NSStackViewDistributionFill;
    _yourAppsStack.spacing = 0;
    _yourAppsStack.translatesAutoresizingMaskIntoConstraints = NO;
    [appsDocumentStack addArrangedSubview:_yourAppsStack];
    [NSLayoutConstraint activateConstraints:@[
        [_yourAppsStack.widthAnchor constraintEqualToConstant:kContentWidth],
    ]];

    _systemAndOtherAppsDisclosureButton = [self rowButtonViewWithTitle:@"System & Other Apps ▾"
                                                             addToStack:appsDocumentStack];
    _systemAndOtherAppsDisclosureButton.target = self;
    _systemAndOtherAppsDisclosureButton.action = @selector(systemAndOtherAppsDisclosureClicked:);

    _systemAndOtherAppsStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    _systemAndOtherAppsStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    _systemAndOtherAppsStack.alignment = NSLayoutAttributeLeading;
    _systemAndOtherAppsStack.distribution = NSStackViewDistributionFill;
    _systemAndOtherAppsStack.spacing = 0;
    _systemAndOtherAppsStack.translatesAutoresizingMaskIntoConstraints = NO;
    _systemAndOtherAppsStack.hidden = YES;
    [appsDocumentStack addArrangedSubview:_systemAndOtherAppsStack];
    [NSLayoutConstraint activateConstraints:@[
        [_systemAndOtherAppsStack.widthAnchor constraintEqualToConstant:kContentWidth],
    ]];

    appsScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    appsScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    appsScrollView.hasVerticalScroller = YES;
    appsScrollView.hasHorizontalScroller = NO;
    appsScrollView.autohidesScrollers = YES;
    appsScrollView.drawsBackground = NO;
    appsScrollView.documentView = appsDocumentStack;

    // Pinned to the clip view on three edges, deliberately not the bottom -- an unpinned bottom is
    // what lets the document view's own height (the sum of its arranged subviews, which grows and
    // shrinks as apps launch/quit) determine the scrollable content size, instead of being forced
    // to exactly match the scroll view's own (capped, fixed) height.
    [NSLayoutConstraint activateConstraints:@[
        [appsDocumentStack.topAnchor constraintEqualToAnchor:appsScrollView.contentView.topAnchor],
        [appsDocumentStack.leadingAnchor
            constraintEqualToAnchor:appsScrollView.contentView.leadingAnchor],
        [appsDocumentStack.trailingAnchor
            constraintEqualToAnchor:appsScrollView.contentView.trailingAnchor],
        [appsDocumentStack.widthAnchor constraintEqualToConstant:kContentWidth],
        [appsScrollView.widthAnchor constraintEqualToConstant:kContentWidth],
    ]];

    appsScrollViewHeightConstraint = [appsScrollView.heightAnchor constraintEqualToConstant:0];
    appsScrollViewHeightConstraint.active = YES;

    [_rowStack addArrangedSubview:appsScrollView];

    [self updateAppsScrollViewHeight];
}

// Called by WCMainPanel right before every show -- rows get added/removed (apps launching/
// quitting) and the disclosure section gets shown/hidden while the panel isn't visible, so this
// can't just be measured once at construction time; it has to be freshly recomputed against
// whatever's actually in the stack right now.
- (void) updateAppsScrollViewHeight {
    CGFloat contentHeight = appsDocumentStack.fittingSize.height;
    appsScrollViewHeightConstraint.constant = MIN(contentHeight, kAppsScrollViewMaxHeight);
}

#pragma mark Building blocks

- (void) addSeparator {
    NSBox* line = [[NSBox alloc] initWithFrame:NSZeroRect];
    line.boxType = NSBoxSeparator;
    line.translatesAutoresizingMaskIntoConstraints = NO;

    [_rowStack addArrangedSubview:line];

    [NSLayoutConstraint activateConstraints:@[
        [line.widthAnchor constraintEqualToConstant:kContentWidth],
    ]];

    [_rowStack setCustomSpacing:kSeparatorTopBottomPadding afterView:line];
}

- (void) addSectionHeaderWithTitle:(NSString*)title {
    [_rowStack addArrangedSubview:[self sectionHeaderViewWithTitle:title]];
}

// Builds the same row addSectionHeaderWithTitle: does, but doesn't add it anywhere -- for
// buildScrollableAppsSection, which needs the row added to appsDocumentStack instead of rowStack.
- (NSView*) sectionHeaderViewWithTitle:(NSString*)title {
    NSTextField* label = [NSTextField labelWithString:title];
    label.font = [NSFont boldSystemFontOfSize:[NSFont smallSystemFontSize]];
    label.textColor = [NSColor secondaryLabelColor];
    label.translatesAutoresizingMaskIntoConstraints = NO;

    return [self wrapInRowContainer:label height:kBGMMainPanelRowHeight];
}

// A plain, left-aligned, borderless button matching a flat NSMenuItem's look -- used both for
// clickable rows (Preferences, Quit, the disclosure toggle, Auto-pause) and reused as the base for
// this file's other row-building helpers.
- (NSButton*) addRowButtonWithTitle:(NSString*)title {
    return [self rowButtonViewWithTitle:title addToStack:_rowStack];
}

// Same as addRowButtonWithTitle:, but adds the row to an arbitrary stack instead of always
// rowStack -- for buildScrollableAppsSection, which needs the disclosure button added to
// appsDocumentStack.
- (NSButton*) rowButtonViewWithTitle:(NSString*)title addToStack:(NSStackView*)stack {
    NSButton* button = [NSButton buttonWithTitle:title target:nil action:nil];
    button.bezelStyle = NSBezelStyleRegularSquare;
    button.bordered = NO;
    button.alignment = NSTextAlignmentLeft;
    button.translatesAutoresizingMaskIntoConstraints = NO;

    NSView* row = [self wrapInRowContainer:button height:kBGMMainPanelRowHeight];
    [stack addArrangedSubview:row];

    return button;
}

- (NSStackView*) addVerticalStackWithSpacing:(CGFloat)spacing {
    NSStackView* stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.distribution = NSStackViewDistributionFill;
    stack.spacing = spacing;
    stack.translatesAutoresizingMaskIntoConstraints = NO;

    [_rowStack addArrangedSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.widthAnchor constraintEqualToConstant:kContentWidth],
    ]];

    return stack;
}

+ (NSView*) rowContainerWithControl:(NSView*)innerView height:(CGFloat)height {
    NSView* row = [[NSView alloc] initWithFrame:NSZeroRect];
    row.translatesAutoresizingMaskIntoConstraints = NO;

    [row addSubview:innerView];

    [NSLayoutConstraint activateConstraints:@[
        [row.widthAnchor constraintEqualToConstant:kContentWidth],
        [row.heightAnchor constraintEqualToConstant:height],
        [innerView.leadingAnchor constraintEqualToAnchor:row.leadingAnchor
                                                  constant:kRowHorizontalPadding],
        [innerView.trailingAnchor constraintLessThanOrEqualToAnchor:row.trailingAnchor
                                                              constant:-kRowHorizontalPadding],
        [innerView.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
    ]];

    return row;
}

// Pins innerView inside a fixed-width, fixed-height container with the standard row padding, so
// every row (label, button, whatever) lines up consistently regardless of its own intrinsic size.
- (NSView*) wrapInRowContainer:(NSView*)innerView height:(CGFloat)height {
    return [WCMainPanelContentView rowContainerWithControl:innerView height:height];
}

#pragma mark Actions

- (void) systemAndOtherAppsDisclosureClicked:(id)sender {
    #pragma unused (sender)

    BOOL willExpand = _systemAndOtherAppsStack.hidden;

    _systemAndOtherAppsStack.hidden = !willExpand;
    _systemAndOtherAppsDisclosureButton.title =
        willExpand ? @"System & Other Apps ▴" : @"System & Other Apps ▾";

    // Not just at show time -- clicking this while the panel is already open should resize the
    // scroll view immediately, in the same click, not wait for the next time the panel opens.
    [self updateAppsScrollViewHeight];
}

@end

#pragma clang assume_nonnull end
