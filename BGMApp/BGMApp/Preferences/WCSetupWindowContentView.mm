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
//  WCSetupWindowContentView.mm
//  BGMApp
//
//  Copyright © 2026 Wavecraft contributors
//

// Self Include
#import "WCSetupWindowContentView.h"

// Local Includes
#import "BGM_Utils.h"


#pragma clang assume_nonnull begin

// 460 read as cramped on a real screen -- confirmed by actually looking at it, not guessed --
// especially with small-system-sized body text as the thing a user is meant to actually read
// before making a permission decision. Widened along with the font sizes below, not just one or
// the other, so the wider window doesn't just leave more empty margin around still-small text.
static CGFloat const kContentWidth = 560;
static CGFloat const kContentPadding = 26;
// Spacing between elements within one row (title -> body -> button).
static CGFloat const kInnerRowSpacing = 8;
// Extra spacing added after a row's last element, on top of kInnerRowSpacing, so rows read as
// distinct groups instead of one undifferentiated list.
static CGFloat const kBetweenRowsExtraSpacing = 18;
static CGFloat const kHeaderIconSize = 64;

// The amber from the app icon's four-bar mark (sampled directly from
// Images.xcassets/AppIcon.appiconset/appicon_512.png, not eyeballed) -- the one accent color this
// project already uses consistently everywhere else it has visual identity (the README's
// comparison table, the "how it works" diagram), reused here rather than introducing a new one.
// Only applied to this window's own action buttons -- everything else (background, body text)
// stays on system colors so the window still respects the user's light/dark mode setting.
static NSColor* BGMBrandAmberColor(void) {
    return [NSColor colorWithSRGBRed:(232.0 / 255.0)
                                green:(176.0 / 255.0)
                                 blue:(75.0 / 255.0)
                                alpha:1.0];
}

@implementation WCSetupWindowRow

- (instancetype) initWithButton:(NSButton* __nullable)inButton
                     statusLabel:(NSTextField*)inStatusLabel {
    if ((self = [super init])) {
        _button = inButton;
        _statusLabel = inStatusLabel;
    }

    return self;
}

@end

@implementation WCSetupWindowContentView {
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

- (void) addHeaderWithTitle:(NSString*)title subtitle:(NSString*)subtitle {
    CGFloat const rowContentWidth = kContentWidth - (kContentPadding * 2);

    NSImageView* iconView = [NSImageView new];
    iconView.image = NSApp.applicationIconImage;
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [iconView.widthAnchor constraintEqualToConstant:kHeaderIconSize],
        [iconView.heightAnchor constraintEqualToConstant:kHeaderIconSize],
    ]];

    NSTextField* titleLabel = [NSTextField labelWithString:title];
    titleLabel.font = [NSFont boldSystemFontOfSize:24];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField* subtitleLabel = [NSTextField labelWithString:subtitle];
    subtitleLabel.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
    subtitleLabel.textColor = [NSColor secondaryLabelColor];
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    NSStackView* titleStack = [NSStackView stackViewWithViews:@[titleLabel, subtitleLabel]];
    titleStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    titleStack.alignment = NSLayoutAttributeLeading;
    titleStack.spacing = 2;
    titleStack.translatesAutoresizingMaskIntoConstraints = NO;

    NSStackView* headerRow = [NSStackView stackViewWithViews:@[iconView, titleStack]];
    headerRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    headerRow.alignment = NSLayoutAttributeCenterY;
    headerRow.spacing = 14;
    headerRow.translatesAutoresizingMaskIntoConstraints = NO;

    [rowStack addArrangedSubview:headerRow];
    [NSLayoutConstraint activateConstraints:@[
        [headerRow.widthAnchor constraintEqualToConstant:rowContentWidth],
    ]];

    [rowStack setCustomSpacing:(kInnerRowSpacing + kBetweenRowsExtraSpacing) afterView:headerRow];
}

- (void) addIntroText:(NSString*)text {
    CGFloat const rowContentWidth = kContentWidth - (kContentPadding * 2);

    NSTextField* introLabel = [NSTextField wrappingLabelWithString:text];
    introLabel.font = [NSFont systemFontOfSize:15];
    introLabel.preferredMaxLayoutWidth = rowContentWidth;
    introLabel.translatesAutoresizingMaskIntoConstraints = NO;

    [rowStack addArrangedSubview:introLabel];
    [NSLayoutConstraint activateConstraints:@[
        [introLabel.widthAnchor constraintEqualToConstant:rowContentWidth],
    ]];

    [rowStack setCustomSpacing:(kInnerRowSpacing + kBetweenRowsExtraSpacing) afterView:introLabel];
}

- (WCSetupWindowRow*) addRowWithTitle:(NSString*)title
                                   body:(NSString*)body
                                 status:(BGMSetupRowStatus)status
                            buttonTitle:(NSString* __nullable)buttonTitle {
    CGFloat const rowContentWidth = kContentWidth - (kContentPadding * 2);

    // Title + status badge, side by side.
    NSTextField* titleLabel = [NSTextField labelWithString:title];
    titleLabel.font = [NSFont boldSystemFontOfSize:16];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [titleLabel setContentHuggingPriority:NSLayoutPriorityDefaultLow
                            forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSTextField* statusLabel = [NSTextField labelWithString:@""];
    statusLabel.font = [NSFont boldSystemFontOfSize:13];
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
    bodyLabel.font = [NSFont systemFontOfSize:14];
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
        BGMNN(button).controlSize = NSControlSizeRegular;
        BGMNN(button).bezelColor = BGMBrandAmberColor();
        BGMNN(button).translatesAutoresizingMaskIntoConstraints = NO;

        [rowStack addArrangedSubview:BGMNN(button)];
        lastElementInRow = BGMNN(button);
    }

    // Adds to kInnerRowSpacing (rowStack's default spacing, already applied after every arranged
    // subview) rather than replacing it, so this row's own internal gaps stay tight while the gap
    // before the *next* row reads as a clear break between groups.
    [rowStack setCustomSpacing:(kInnerRowSpacing + kBetweenRowsExtraSpacing)
                       afterView:lastElementInRow];

    WCSetupWindowRow* result = [[WCSetupWindowRow alloc] initWithButton:button
                                                                statusLabel:statusLabel];
    [WCSetupWindowContentView setStatus:status onRow:result];

    return result;
}

+ (void) setStatus:(BGMSetupRowStatus)status onRow:(WCSetupWindowRow*)row {
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
