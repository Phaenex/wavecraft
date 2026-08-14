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
//  WCAppDelegate.mm
//  BGMApp
//
//  Copyright © 2016-2022, 2026 Kyle Neideck
//  Copyright © 2021 Marcus Wu
//

// Self Include
#import "WCAppDelegate.h"

// Local Includes
#import "BGM_Utils.h"
#import "WCAppOutputRoutingController.h"
#import "WCHotkeys.h"
#import "WCAppVolumes.h"
#import "WCAppVolumesController.h"
#import "WCAutoPauseMusic.h"
#import "WCAutoPauseMenuItem.h"
#import "WCDoNotDisturb.h"
#import "BGMDebugLogging.h"
#import "WCDebugLoggingMenuItem.h"
#import "WCMainPanel.h"
#import "WCMusicPlayers.h"
#import "WCOutputDeviceMenuSection.h"
#import "WCOutputVolumeMenuItem.h"
#import "WCPreferencesMenu.h"
#import "WCPreferredOutputDevices.h"
#import "WCSetupWindow.h"
#import "WCStatusBarItem.h"
#import "WCSystemSoundsVolume.h"
#import "WCTermination.h"
#import "WCUserDefaults.h"
#import "WCXPCListener.h"
#import "SystemPreferences.h"

// System Includes
#import <AVFoundation/AVCaptureDevice.h>


#pragma clang assume_nonnull begin

static NSString* const kOptNoPersistentData  = @"--no-persistent-data";
static NSString* const kOptShowDockIcon      = @"--show-dock-icon";

@implementation WCAppDelegate {
    // The button in the system status bar that shows the main panel.
    WCStatusBarItem* statusBarItem;

    // The panel itself -- see WCMainPanel's header for why this app moved off NSMenu for its
    // main dropdown.
    WCMainPanel* mainPanel;

    // "What Wavecraft needs from your Mac, and why" -- auto-shown once per version, reachable
    // anytime afterwards from Preferences. See WCSetupWindow's header.
    WCSetupWindow* setupWindow;

    // Only show the 'BGMXPCHelper is missing' error dialog once.
    BOOL haveShownXPCHelperErrorMessage;

    // Persistently stores user settings and data.
    WCUserDefaults* userDefaults;

    WCAutoPauseMusic* autoPauseMusic;
    WCAutoPauseMenuItem* autoPauseMenuItem;
    WCMusicPlayers* musicPlayers;
    WCSystemSoundsVolume* systemSoundsVolume;
    WCOutputDeviceMenuSection* outputDeviceMenuSection;
    WCPreferencesMenu* prefsMenu;
    WCDebugLoggingMenuItem* debugLoggingMenuItem;
    WCXPCListener* xpcListener;
    WCPreferredOutputDevices* preferredOutputDevices;

    // Owns the per-app output-device routing overrides (see WCTapRoute). Created before the app
    // volumes menu items so their output-route pop-up buttons have it to hand at setup time.
    WCAppOutputRoutingController* outputRoutingController;

    // Global keyboard shortcuts for system/frontmost-app volume. Off by default -- see its header.
    WCHotkeys* hotkeys;

    // Mutes every app except a chosen priority app. Off by default -- see its header.
    WCDoNotDisturb* doNotDisturb;
}

@synthesize audioDevices = audioDevices;
@synthesize appVolumes = appVolumes;
@synthesize outputRoutingController = outputRoutingController;

- (void) awakeFromNib {
    [super awakeFromNib];

    // Show BGMApp in the dock, if the command-line option for that was passed. This is used by the
    // UI tests.
    if ([NSProcessInfo.processInfo.arguments indexOfObject:kOptShowDockIcon] != NSNotFound) {
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    }

    haveShownXPCHelperErrorMessage = NO;

    // Set up audioDevices, which coordinates BGMDevice and the output device. It manages
    // playthrough, volume/mute controls, etc.
    if (![self initAudioDeviceManager]) {
        return;
    }

    // Set debug logging enabled/disabled to match BGMDriver. Do this early, so we can get debug
    // logs while BGMApp is launching.
    BGMLogAndSwallowExceptions("WCAppDelegate::awakeFromNib", [&] {
        BGMSetDebugLoggingEnabled([audioDevices bgmDevice].GetDebugLoggingEnabled());
    });

    // Stored user settings
    userDefaults = [self createUserDefaults];

    setupWindow = [[WCSetupWindow alloc] initWithUserDefaults:userDefaults];

    // The main dropdown's window. Created before statusBarItem so there's something for the
    // status bar button's click handler to show/hide.
    mainPanel = [WCMainPanel new];

    // Add the status bar item. (The thing you click to show BGMApp's main panel.)
    statusBarItem = [[WCStatusBarItem alloc] initWithPanel:mainPanel
                                                audioDevices:audioDevices
                                                userDefaults:userDefaults];
}

- (void) applicationDidFinishLaunching:(NSNotification*)aNotification {
    #pragma unused (aNotification)
    
    // Log the version/build number.
    //
    // TODO: NSLog should only be used for logging errors.
    // TODO: Automatically add the commit ID to the end of the build number for unreleased builds. (In the
    //       Info.plist or something -- not here.)
    NSLog(@"BGMApp version: %@, BGMApp build number: %@",
          NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"],
          NSBundle.mainBundle.infoDictionary[@"CFBundleVersion"]);

    // Handles changing (or not changing) the output device when devices are added or removed. Must
    // be initialised before calling setBGMDeviceAsDefault.
    preferredOutputDevices =
        [[WCPreferredOutputDevices alloc] initWithDevices:audioDevices userDefaults:userDefaults];

    // Shown first, before anything below touches a system permission -- so on a genuinely new
    // launch, the first thing the user sees is our own explanation of everything Wavecraft needs
    // and why, with a button for each, rather than an unexplained system dialog. See
    // WCSetupWindow's header.
    BOOL const showedSetupWindow = [setupWindow showOnFirstLaunchIfNeeded];

    // Skip this if we're compiling on a version of macOS before 10.14 as won't compile and it
    // isn't needed.
#if MAC_OS_X_VERSION_MAX_ALLOWED >= 101400  // MAC_OS_X_VERSION_10_14
    if (@available(macOS 10.14, *)) {
        // On macOS 10.14+ we need to get the user's permission to use input devices before we can
        // use BGMDevice for playthrough (see WCPlayThrough), so we wait until they've given it
        // before making BGMDevice the default device. This way, if the user is playing audio when
        // they open Wavecraft, we won't interrupt it while we're waiting for them to click
        // OK.
        if (showedSetupWindow) {
            // Don't request access ourselves here -- that would trigger the system permission
            // dialog immediately, before the user's had any chance to even read the Setup window
            // that's supposed to explain it first, defeating the entire point of that window.
            // WCSetupWindow's own Microphone row already has a button that requests access when
            // *they* click it; just wait for that to actually succeed (or for them to grant it in
            // System Settings and switch back -- see WCSetupWindow::applicationDidBecomeActive:)
            // before continuing the rest of launch.
            userDefaults.hasShownMicrophonePermissionExplanation = YES;

            WCAppDelegate* __weak weakSelf = self;
            setupWindow.microphoneAccessGrantedHandler = ^{
                [weakSelf continueLaunchAfterInputDevicePermissionGranted];
            };
        } else {
            [self explainMicrophonePermissionIfFirstRunThenRequestAccess];
        }
    }
    else
#endif
    {
        // We can change the device immediately on older versions of macOS because they don't
        // require user permission for input devices.
        [self continueLaunchAfterInputDevicePermissionGranted];
    }
}

// The first time Wavecraft ever launches, explains up front why the permission prompt macOS is
// about to show says "Microphone" for an app that doesn't record audio, before actually
// triggering that prompt. Every launch after the first skips straight to requesting access, same
// as before this existed -- the explanation only needs to be seen once.
- (void) explainMicrophonePermissionIfFirstRunThenRequestAccess {
    if (userDefaults.hasShownMicrophonePermissionExplanation) {
        [self requestMicrophoneAccess];
        return;
    }

    // Set this before showing the alert, not after: if this dialog is somehow shown twice (e.g.
    // the app crashes and relaunches immediately after), that's a much smaller problem than
    // skipping it because a crash happened between showing it and recording that we did.
    userDefaults.hasShownMicrophonePermissionExplanation = YES;

    dispatch_async(dispatch_get_main_queue(), ^{
        NSAlert* alert = [NSAlert new];
        alert.messageText = @"Wavecraft needs “Microphone” access";
        alert.informativeText =
            @"macOS is about to ask you to allow Wavecraft to use the microphone. Wavecraft "
             "doesn’t actually listen to your microphone — it needs this permission "
             "because the virtual audio device it uses to capture your system’s audio (so it "
             "can apply per-app volume, EQ, and output routing) is classified as a microphone "
             "input by macOS, even though nothing about it is a real mic.\n\nClick Continue, then "
             "click Allow on the next prompt.";
        [alert addButtonWithTitle:@"Continue"];
        [alert runModal];

        [self requestMicrophoneAccess];
    });
}

// Only ever called from inside an `if (@available(macOS 10.14, *))` check (see
// applicationDidFinishLaunching), but the compiler's availability analysis doesn't see across
// that method-call boundary, so it needs its own guard here too.
- (void) requestMicrophoneAccess {
    if (@available(macOS 10.14, *)) {
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio
                                 completionHandler:^(BOOL granted) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (granted) {
                    DebugMsg("WCAppDelegate::requestMicrophoneAccess: Permission granted");
                    [self continueLaunchAfterInputDevicePermissionGranted];
                } else {
                    NSLog(@"WCAppDelegate::requestMicrophoneAccess: Permission denied");
                    // If they don't accept, Wavecraft won't work at all and the only way to fix
                    // it is in System Settings, so show an error dialog with a direct shortcut
                    // there.
                    [self showMicrophonePermissionDeniedError];
                }
            });
        }];
    }
}

- (void) showMicrophonePermissionDeniedError {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSAlert* alert = [NSAlert new];
        alert.messageText = @"Wavecraft needs “Microphone” permission to work.";
        alert.informativeText =
            @"It uses a virtual microphone to access your system’s audio — it doesn’t "
             "actually listen to anything. Grant the permission in System Settings > Privacy & "
             "Security > Microphone, then open Wavecraft again.";

        [alert addButtonWithTitle:@"Quit"];
        [alert addButtonWithTitle:@"Open Privacy Settings"];

        NSModalResponse buttonClicked = [alert runModal];

        if (buttonClicked != NSAlertFirstButtonReturn) {  // 'Quit' is the first button.
            [self openSysPrefsMicrophonePrivacy];
        }

        [NSApp terminate:self];
    });
}

// Deep-links straight to the Microphone list in Privacy & Security, rather than just describing
// where it is in the dialog text. Uses the same x-apple.systempreferences: URL scheme Apple has
// kept working across the System Preferences -> System Settings redesign, rather than the
// Scripting Bridge approach openSysPrefsSoundOutput (below) uses -- there's no
// "SystemPreferencesPane" for Privacy & Security's sub-sections to script the same way.
- (void) openSysPrefsMicrophonePrivacy {
    NSURL* __nullable url = [NSURL URLWithString:
        @"x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"];

    BOOL opened = url && [[NSWorkspace sharedWorkspace] openURL:BGMNN(url)];

    if (!opened) {
        NSLog(@"WCAppDelegate::openSysPrefsMicrophonePrivacy: Failed to open System Settings");
    }
}

- (void) continueLaunchAfterInputDevicePermissionGranted {
    // Choose an output device for BGMApp to use to play audio.
    if (![self setInitialOutputDevice]) {
        return;
    }

    // Make BGMDevice the default device.
    [self setBGMDeviceAsDefault];

    // Handle some of the unusual reasons BGMApp might have to exit, mostly crashes.
    WCTermination::SetUpTerminationCleanUp(audioDevices);

    // Set up the rest of the UI and other external interfaces.
    musicPlayers = [[WCMusicPlayers alloc] initWithAudioDevices:audioDevices
                                                    userDefaults:userDefaults];

    autoPauseMusic = [[WCAutoPauseMusic alloc] initWithAudioDevices:audioDevices
                                                        musicPlayers:musicPlayers
                                                        userDefaults:userDefaults];

    [self setUpMainMenu];

    xpcListener = [[WCXPCListener alloc] initWithAudioDevices:audioDevices
                                  helperConnectionErrorHandler:^(NSError* error) {
        NSLog(@"WCAppDelegate::continueLaunchAfterInputDevicePermissionGranted: "
              "(helperConnectionErrorHandler) BGMXPCHelper connection error: %@",
              error);
        [self showXPCHelperErrorMessage:error];
    }];

    // prefsMenu (built in setUpMainMenu, above) needed xpcListener for its "Reconnect to
    // BGMXPCHelper" troubleshooter, but xpcListener doesn't exist until here -- see
    // WCTroubleshootMenu's header for why this is a separate call instead of an initializer param.
    [prefsMenu setXPCListener:xpcListener];
}

// Returns NO if (and only if) BGMApp is about to terminate because of a fatal error.
- (BOOL) initAudioDeviceManager {
    audioDevices = [WCAudioDeviceManager new];

    if (!audioDevices) {
        [self showBGMDeviceNotFoundErrorMessageAndExit];
        return NO;
    }

    return YES;
}

// Returns NO if (and only if) BGMApp is about to terminate because of a fatal error.
- (BOOL) setInitialOutputDevice {
    AudioObjectID preferredDevice = [preferredOutputDevices findPreferredDevice];

    if (preferredDevice != kAudioObjectUnknown) {
        NSError* __nullable error = [audioDevices setOutputDeviceWithID:preferredDevice
                                                        revertOnFailure:NO];
        if (error) {
            // Show the error message.
            [self showFailedToSetOutputDeviceErrorMessage:BGMNN(error)
                                          preferredDevice:preferredDevice];
        }
    } else {
        // We couldn't find a device to use, so show an error message and quit.
        [self showOutputDeviceNotFoundErrorMessageAndExit];
        return NO;
    }

    return YES;
}

// Sets the "Wavecraft" virtual audio device (BGMDevice) as the user's default audio device.
- (void) setBGMDeviceAsDefault {
    NSError* error = [audioDevices setBGMDeviceAsOSDefault];

    if (error) {
        [self showSetDeviceAsDefaultError:error
                                  message:@"Could not set the Wavecraft device as your"
                                           "default audio device."
                          informativeText:@"You might be able to change it yourself."];
    }
}

- (void) setUpMainMenu {
    autoPauseMenuItem =
        [[WCAutoPauseMenuItem alloc] initWithButton:mainPanel.mainContentView.autoPauseButton
                                       autoPauseMusic:autoPauseMusic
                                         musicPlayers:musicPlayers
                                         userDefaults:userDefaults];

    [self initVolumesMenuSection];

    // Output device selection.
    outputDeviceMenuSection =
            [[WCOutputDeviceMenuSection alloc]
                    initWithDeviceStack:mainPanel.mainContentView.outputDeviceStack
                           audioDevices:audioDevices
                       preferredDevices:preferredOutputDevices];
    [audioDevices setOutputDeviceMenuSection:outputDeviceMenuSection];

    // Global keyboard shortcuts. Constructing this doesn't request any permission or start
    // monitoring by itself unless the user already had hotkeys enabled and granted Accessibility
    // trust in a previous run -- see WCHotkeys's header.
    hotkeys = [[WCHotkeys alloc] initWithAudioDevices:audioDevices userDefaults:userDefaults];

    // Mutes every app except a chosen priority app. Constructing this resumes muting immediately
    // if it was left enabled from a previous run -- see WCDoNotDisturb's header.
    doNotDisturb = [[WCDoNotDisturb alloc] initWithAudioDevices:audioDevices
                                                     userDefaults:userDefaults];

    // Preferences submenu. self.bgmMenu is loaded from the XIB but never shown directly any more
    // -- this just extracts its Preferences submenu's static structure. See prefsMenu.menu's
    // wiring below and WCAppDelegate.h's comment on bgmMenu.
    prefsMenu = [[WCPreferencesMenu alloc] initWithBGMMenu:self.bgmMenu
                                               audioDevices:audioDevices
                                               musicPlayers:musicPlayers
                                              statusBarItem:statusBarItem
                                                 aboutPanel:self.aboutPanel
                                      aboutPanelLicenseView:self.aboutPanelLicenseView
                                               userDefaults:userDefaults
                                     preferredOutputDevices:preferredOutputDevices
                                    outputRoutingController:outputRoutingController
                                                    hotkeys:hotkeys
                                               doNotDisturb:doNotDisturb];

    // "Setup & Permissions…" -- reopens the same window shown automatically on first launch (see
    // WCSetupWindow's header). Wired directly to setupWindow itself, the same way prefsMenu wires
    // its own "About" item directly to aboutPanel, rather than routing the action through
    // WCAppDelegate.
    NSMenuItem* setupMenuItem = [[NSMenuItem alloc] initWithTitle:@"Setup & Permissions…"
                                                             action:@selector(show)
                                                      keyEquivalent:@""];
    setupMenuItem.target = setupWindow;
    [prefsMenu.menu addItem:[NSMenuItem separatorItem]];
    [prefsMenu.menu addItem:setupMenuItem];

    mainPanel.mainContentView.preferencesButton.target = self;
    mainPanel.mainContentView.preferencesButton.action = @selector(showPreferencesMenu:);

    mainPanel.mainContentView.quitButton.target = NSApp;
    mainPanel.mainContentView.quitButton.action = @selector(terminate:);

    // Enable/disable debug logging. Hidden unless you option-click the status bar icon.
    debugLoggingMenuItem =
        [[WCDebugLoggingMenuItem alloc] initWithButton:mainPanel.mainContentView.debugLoggingButton
                                            audioDevices:audioDevices];
    [statusBarItem setDebugLoggingMenuItem:debugLoggingMenuItem];

    // Refresh content that can go stale while the panel's closed (the routed-app indicator, the
    // Auto-pause row's title) right before it's shown again -- the equivalent of the old
    // NSMenu-based design's -menuWillOpen:.
    WCAppDelegate* __weak weakSelf = self;
    mainPanel.willShowBlock = ^{
        WCAppDelegate* __strong strongSelf = weakSelf;
        [strongSelf.appVolumes refreshRoutedIndicators];
        [strongSelf->autoPauseMenuItem refreshBeforeShow];
    };
}

// Pops the Preferences menu up from the button that was clicked, positioned the same way an
// NSMenu opened from a status item would be -- see WCPreferencesMenu.menu's header comment for
// why this stays a real NSMenu instead of also moving into the panel.
- (void) showPreferencesMenu:(NSButton*)sender {
    [prefsMenu.menu popUpMenuPositioningItem:nil
                                    atLocation:NSMakePoint(0, sender.bounds.size.height)
                                        inView:sender];
}

- (WCUserDefaults*) createUserDefaults {
    BOOL persistentDefaults =
        [NSProcessInfo.processInfo.arguments indexOfObject:kOptNoPersistentData] == NSNotFound;
    NSUserDefaults* wrappedDefaults = persistentDefaults ? [NSUserDefaults standardUserDefaults] : nil;
    return [[WCUserDefaults alloc] initWithDefaults:wrappedDefaults];
}

- (void) initVolumesMenuSection {
    // Create the row with the (main) output volume slider.
    WCOutputVolumeMenuItem* outputVolume =
            [[WCOutputVolumeMenuItem alloc] initWithAudioDevices:audioDevices
                                                             view:self.outputVolumeView
                                                           slider:self.outputVolumeSlider
                                                      deviceLabel:self.outputVolumeLabel];
    [audioDevices setOutputVolumeMenuItem:outputVolume];

    NSStackView* volumesStack = mainPanel.mainContentView.volumesStack;

    // Not kBGMMainPanelRowHeight (22pt) -- unlike a flat menu-item row, outputVolumeView is the
    // XIB's original two-line template (a label above the slider), 47pt tall by design. Forcing
    // it into a 22pt container doesn't shrink it, it just overflows -- confirmed on a real screen,
    // rendering on top of the row above it. Read from the view's own designed frame height, not a
    // second hardcoded number, so this can't drift out of sync with the XIB again.
    [volumesStack addArrangedSubview:
        [WCMainPanelContentView rowContainerWithControl:outputVolume.view
                                                    height:outputVolume.view.frame.size.height]];

    // Add the volume control for system (UI) sounds.
    BGMAudioDevice uiSoundsDevice = [audioDevices bgmDevice].GetUISoundsBGMDeviceInstance();

    systemSoundsVolume =
        [[WCSystemSoundsVolume alloc] initWithUISoundsDevice:uiSoundsDevice
                                                         view:self.systemSoundsView
                                                       slider:self.systemSoundsSlider];

    [volumesStack addArrangedSubview:
        [WCMainPanelContentView rowContainerWithControl:systemSoundsVolume.view
                                                    height:kBGMMainPanelRowHeight]];

    // Owns per-app output-device routing overrides. Created here (rather than earlier, alongside
    // audioDevices) because it doesn't need to exist until there are app volume rows whose
    // output-route pop-up buttons can use it, and restoring persisted routes needs userDefaults,
    // which isn't set up until awakeFromNib.
    outputRoutingController =
        [[WCAppOutputRoutingController alloc] initWithUserDefaults:userDefaults];

    // Add the app volume rows.
    WCMainPanelContentView* contentView = mainPanel.mainContentView;
    appVolumes = [[WCAppVolumesController alloc]
            initWithYourAppsStack:contentView.yourAppsStack
           systemAndOtherAppsStack:contentView.systemAndOtherAppsStack
                  disclosureButton:contentView.systemAndOtherAppsDisclosureButton
                     appVolumeView:self.appVolumeView
                      audioDevices:audioDevices
           outputRoutingController:outputRoutingController];
}

- (void) applicationWillTerminate:(NSNotification*)aNotification {
    #pragma unused (aNotification)
    
    DebugMsg("WCAppDelegate::applicationWillTerminate");

    // Change the user's default output device back.
    NSError* error = [audioDevices unsetBGMDeviceAsOSDefault];
    
    if (error) {
        [self showSetDeviceAsDefaultError:error
                                  message:@"Failed to reset your system's audio output device."
                          informativeText:@"You'll have to change it yourself to get audio working again."];
    }
}

#pragma mark Error messages

- (void) showBGMDeviceNotFoundErrorMessageAndExit {
    // BGMDevice wasn't found on the system. Most likely, BGMDriver isn't installed. Show an error
    // dialog and exit.
    //
    // TODO: Check whether the driver files are in /Library/Audio/Plug-Ins/HAL? Might even want to
    //       offer to install them if not.
    [self showErrorMessage:@"Could not find the Wavecraft virtual audio device."
           informativeText:@"Make sure you've installed Background Music Device.driver to "
                            "/Library/Audio/Plug-Ins/HAL and restarted coreaudiod (e.g. \"sudo "
                            "killall coreaudiod\")."
 exitAfterMessageDismissed:YES];
}

- (void) showFailedToSetOutputDeviceErrorMessage:(NSError*)error
                                 preferredDevice:(BGMAudioDevice)device {
    NSLog(@"Failed to set initial output device. Error: %@", error);

    dispatch_async(dispatch_get_main_queue(), ^{
        NSAlert* alert = [NSAlert alertWithError:BGMNN(error)];
        alert.messageText = @"Failed to set the output device.";

        NSString* __nullable name = nil;
        BGM_Utils::LogAndSwallowExceptions(BGMDbgArgs, [&] {
            name = (__bridge NSString* __nullable)device.CopyName();
        });

        alert.informativeText =
                [NSString stringWithFormat:@"Could not start the device '%@'. (Error: %ld)",
                        name, error.code];

        [alert runModal];
    });
}

- (void) showOutputDeviceNotFoundErrorMessageAndExit {
    // We couldn't find any output devices. Show an error dialog and exit.
    [self showErrorMessage:@"Could not find an audio output device."
           informativeText:@"If you do have one installed, this is probably a bug. Sorry about "
                            "that. Feel free to file an issue on GitHub."
 exitAfterMessageDismissed:YES];
}

- (void) showXPCHelperErrorMessage:(NSError*)error {
    if (!haveShownXPCHelperErrorMessage) {
        haveShownXPCHelperErrorMessage = YES;
        
        // NSAlert should only be used on the main thread.
        dispatch_async(dispatch_get_main_queue(), ^{
            NSAlert* alert = [NSAlert new];
            
            // TODO: Offer to install BGMXPCHelper if it's missing.
            // TODO: Show suppression button?
            [alert setMessageText:@"Error connecting to BGMXPCHelper."];
            [alert setInformativeText:[NSString stringWithFormat:@"%s%s%@ (%lu)",
                                       "Make sure you have BGMXPCHelper installed. There are instructions in the "
                                       "README.md file.\n\n"
                                       "Wavecraft might still work, but it won't work as well as it could.",
                                       "\n\nDetails:\n",
                                       [error localizedDescription],
                                       [error code]]];
            [alert runModal];
        });
    }
}

- (void) showErrorMessage:(NSString*)message
          informativeText:(NSString*)informativeText
exitAfterMessageDismissed:(BOOL)fatal {
    // NSAlert should only be used on the main thread.
    dispatch_async(dispatch_get_main_queue(), ^{
        NSAlert* alert = [NSAlert new];
        [alert setMessageText:message];
        [alert setInformativeText:informativeText];

        // This crashes if built with Xcode 9.0.1, but works with versions of Xcode before 9 and
        // with 9.1.
        [alert runModal];

        if (fatal) {
            [NSApp terminate:self];
        }
    });
}

- (void) showSetDeviceAsDefaultError:(NSError*)error
                             message:(NSString*)msg
                     informativeText:(NSString*)info {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"%@ %@ Error: %@", msg, info, error);
        
        NSAlert* alert = [NSAlert alertWithError:error];
        alert.messageText = msg;
        alert.informativeText = info;
        
        [alert addButtonWithTitle:@"OK"];
        [alert addButtonWithTitle:@"Open Sound in System Preferences"];
        
        NSModalResponse buttonClicked = [alert runModal];
        
        if (buttonClicked != NSAlertFirstButtonReturn) {  // 'OK' is the first button.
            [self openSysPrefsSoundOutput];
        }
    });
}

- (void) openSysPrefsSoundOutput {
    SystemPreferencesApplication* __nullable sysPrefs =
        [SBApplication applicationWithBundleIdentifier:@"com.apple.systempreferences"];
    
    if (!sysPrefs) {
        NSLog(@"Could not open System Preferences");
        return;
    }
    
    // In System Preferences, go to the "Output" tab on the "Sound" pane.
    for (SystemPreferencesPane* pane : [sysPrefs panes]) {
        DebugMsg("WCAppDelegate::openSysPrefsSoundOutput: pane = %s", [pane.name UTF8String]);
        
        if ([pane.id isEqualToString:@"com.apple.preference.sound"]) {
            sysPrefs.currentPane = pane;
            
            for (SystemPreferencesAnchor* anchor : [pane anchors]) {
                DebugMsg("WCAppDelegate::openSysPrefsSoundOutput: anchor = %s", [anchor.name UTF8String]);
                
                if ([[anchor.name lowercaseString] isEqualToString:@"output"]) {
                    DebugMsg("WCAppDelegate::openSysPrefsSoundOutput: Showing Output in Sound pane.");
                    
                    [anchor reveal];
                }
            }
        }
    }
    
    // Bring System Preferences to the foreground.
    [sysPrefs activate];
}

@end

#pragma clang assume_nonnull end

