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

@implementation WCMainPanelContentView

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

    [self addSectionHeaderWithTitle:@"Your Apps"];
    _yourAppsStack = [self addVerticalStackWithSpacing:0];

    _systemAndOtherAppsDisclosureButton = [self addRowButtonWithTitle:@"System & Other Apps ▾"];
    _systemAndOtherAppsDisclosureButton.target = self;
    _systemAndOtherAppsDisclosureButton.action = @selector(systemAndOtherAppsDisclosureClicked:);

    _systemAndOtherAppsStack = [self addVerticalStackWithSpacing:0];
    _systemAndOtherAppsStack.hidden = YES;

    [self addSeparator];

    [self addSectionHeaderWithTitle:@"Output Device"];
    _outputDeviceStack = [self addVerticalStackWithSpacing:0];

    [self addSeparator];

    _preferencesButton = [self addRowButtonWithTitle:@"Preferences…"];
    _quitButton = [self addRowButtonWithTitle:@"Quit Wavecraft"];

    _debugLoggingButton = [self addRowButtonWithTitle:@"Debug Logging"];
    _debugLoggingButton.buttonType = NSButtonTypeSwitch;
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
    NSTextField* label = [NSTextField labelWithString:title];
    label.font = [NSFont boldSystemFontOfSize:[NSFont smallSystemFontSize]];
    label.textColor = [NSColor secondaryLabelColor];
    label.translatesAutoresizingMaskIntoConstraints = NO;

    NSView* row = [self wrapInRowContainer:label height:kBGMMainPanelRowHeight];
    [_rowStack addArrangedSubview:row];
}

// A plain, left-aligned, borderless button matching a flat NSMenuItem's look -- used both for
// clickable rows (Preferences, Quit, the disclosure toggle, Auto-pause) and reused as the base for
// this file's other row-building helpers.
- (NSButton*) addRowButtonWithTitle:(NSString*)title {
    NSButton* button = [NSButton buttonWithTitle:title target:nil action:nil];
    button.bezelStyle = NSBezelStyleRegularSquare;
    button.bordered = NO;
    button.alignment = NSTextAlignmentLeft;
    button.translatesAutoresizingMaskIntoConstraints = NO;

    NSView* row = [self wrapInRowContainer:button height:kBGMMainPanelRowHeight];
    [_rowStack addArrangedSubview:row];

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
}

@end

#pragma clang assume_nonnull end
