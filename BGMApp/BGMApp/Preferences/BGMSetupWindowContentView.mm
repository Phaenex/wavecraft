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
//  BGMSetupWindowContentView.mm
//  BGMApp
//
//  Copyright © 2026 Wavecraft contributors
//

// Self Include
#import "BGMSetupWindowContentView.h"

// Local Includes
#import "BGM_Utils.h"


#pragma clang assume_nonnull begin

static CGFloat const kContentWidth = 460;
static CGFloat const kContentPadding = 20;
// Spacing between elements within one row (title -> body -> button).
static CGFloat const kInnerRowSpacing = 6;
// Extra spacing added after a row's last element, on top of kInnerRowSpacing, so rows read as
// distinct groups instead of one undifferentiated list.
static CGFloat const kBetweenRowsExtraSpacing = 14;

@implementation BGMSetupWindowRow

- (instancetype) initWithButton:(NSButton* __nullable)inButton
                     statusLabel:(NSTextField*)inStatusLabel {
    if ((self = [super init])) {
        _button = inButton;
        _statusLabel = inStatusLabel;
    }

    return self;
}

@end

@implementation BGMSetupWindowContentView {
    NSStackView* rowStack;
}

- (instancetype) initWithFrame:(NSRect)frameRect {
    #pragma unused (frameRect)

    self = [super initWithFrame:NSMakeRect(0, 0, kContentWidth, 0)];

    if (self) {
        rowStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
        rowStack.orientation = NSUserInterfaceLayoutOrientationVertical;
        rowStack.alignment = NSLayoutAttributeLeading;
        rowStack.distribution = NSStackViewDistributionFill;
        rowStack.spacing = kInnerRowSpacing;
        rowStack.translatesAutoresizingMaskIntoConstraints = NO;
        rowStack.edgeInsets = NSEdgeInsetsMake(kContentPadding,
                                                kContentPadding,
                                                kContentPadding,
                                                kContentPadding);

        [self addSubview:rowStack];

        [NSLayoutConstraint activateConstraints:@[
            [rowStack.topAnchor constraintEqualToAnchor:self.topAnchor],
            [rowStack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [rowStack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [rowStack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [rowStack.widthAnchor constraintEqualToConstant:kContentWidth],
        ]];
    }

    return self;
}

- (void) addIntroText:(NSString*)text {
    CGFloat const rowContentWidth = kContentWidth - (kContentPadding * 2);

    NSTextField* introLabel = [NSTextField wrappingLabelWithString:text];
    introLabel.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
    introLabel.preferredMaxLayoutWidth = rowContentWidth;
    introLabel.translatesAutoresizingMaskIntoConstraints = NO;

    [rowStack addArrangedSubview:introLabel];
    [NSLayoutConstraint activateConstraints:@[
        [introLabel.widthAnchor constraintEqualToConstant:rowContentWidth],
    ]];

    [rowStack setCustomSpacing:(kInnerRowSpacing + kBetweenRowsExtraSpacing) afterView:introLabel];
}

- (BGMSetupWindowRow*) addRowWithTitle:(NSString*)title
                                   body:(NSString*)body
                                 status:(BGMSetupRowStatus)status
                            buttonTitle:(NSString* __nullable)buttonTitle {
    CGFloat const rowContentWidth = kContentWidth - (kContentPadding * 2);

    // Title + status badge, side by side.
    NSTextField* titleLabel = [NSTextField labelWithString:title];
    titleLabel.font = [NSFont boldSystemFontOfSize:[NSFont systemFontSize]];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [titleLabel setContentHuggingPriority:NSLayoutPriorityDefaultLow
                            forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSTextField* statusLabel = [NSTextField labelWithString:@""];
    statusLabel.font = [NSFont boldSystemFontOfSize:[NSFont smallSystemFontSize]];
    statusLabel.alignment = NSTextAlignmentRight;
    statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [statusLabel setContentHuggingPriority:NSLayoutPriorityRequired
                             forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSStackView* titleRow = [NSStackView stackViewWithViews:@[titleLabel, statusLabel]];
    titleRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    titleRow.alignment = NSLayoutAttributeCenterY;
    titleRow.distribution = NSStackViewDistributionFill;
    titleRow.translatesAutoresizingMaskIntoConstraints = NO;

    [rowStack addArrangedSubview:titleRow];
    [NSLayoutConstraint activateConstraints:@[
        [titleRow.widthAnchor constraintEqualToConstant:rowContentWidth],
    ]];

    // Explanation body text -- wraps, so its height depends on rowContentWidth, which is why
    // preferredMaxLayoutWidth is set explicitly rather than left to intrinsic content size (an
    // NSTextField can't compute a wrapped height from its string alone; it needs a width first).
    NSTextField* bodyLabel = [NSTextField wrappingLabelWithString:body];
    bodyLabel.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
    bodyLabel.textColor = [NSColor secondaryLabelColor];
    bodyLabel.preferredMaxLayoutWidth = rowContentWidth;
    bodyLabel.translatesAutoresizingMaskIntoConstraints = NO;

    [rowStack addArrangedSubview:bodyLabel];
    [NSLayoutConstraint activateConstraints:@[
        [bodyLabel.widthAnchor constraintEqualToConstant:rowContentWidth],
    ]];

    NSButton* __nullable button = nil;
    NSView* lastElementInRow = bodyLabel;

    if (buttonTitle) {
        button = [NSButton buttonWithTitle:BGMNN(buttonTitle) target:nil action:nil];
        BGMNN(button).bezelStyle = NSBezelStyleRounded;
        BGMNN(button).controlSize = NSControlSizeSmall;
        BGMNN(button).translatesAutoresizingMaskIntoConstraints = NO;

        [rowStack addArrangedSubview:BGMNN(button)];
        lastElementInRow = BGMNN(button);
    }

    // Adds to kInnerRowSpacing (rowStack's default spacing, already applied after every arranged
    // subview) rather than replacing it, so this row's own internal gaps stay tight while the gap
    // before the *next* row reads as a clear break between groups.
    [rowStack setCustomSpacing:(kInnerRowSpacing + kBetweenRowsExtraSpacing)
                       afterView:lastElementInRow];

    BGMSetupWindowRow* result = [[BGMSetupWindowRow alloc] initWithButton:button
                                                                statusLabel:statusLabel];
    [BGMSetupWindowContentView setStatus:status onRow:result];

    return result;
}

+ (void) setStatus:(BGMSetupRowStatus)status onRow:(BGMSetupWindowRow*)row {
    switch (status) {
        case BGMSetupRowStatusNone:
            row.statusLabel.stringValue = @"";
            break;

        case BGMSetupRowStatusGranted:
            row.statusLabel.stringValue = @"✓ Granted";
            row.statusLabel.textColor = [NSColor systemGreenColor];
            break;

        case BGMSetupRowStatusNotGranted:
            row.statusLabel.stringValue = @"Not Granted";
            row.statusLabel.textColor = [NSColor systemOrangeColor];
            break;
    }
}

@end

#pragma clang assume_nonnull end
