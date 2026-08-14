/*
 * BGMApp.h
 *
 * Generated with
 * sdef "/Applications/Wavecraft.app" | sdp -fh --basename BGMApp
 */

#import <AppKit/AppKit.h>
#import <ScriptingBridge/ScriptingBridge.h>


@class WCAppOutputDevice, WCAppApplication;



/*
 * Wavecraft
 */

// A hardware device that can play audio
@interface WCAppOutputDevice : SBObject

@property (copy, readonly) NSString *name;  // The name of the output device.
@property BOOL selected;  // Is this the device to be used for audio output?

@end

// The application program
@interface WCAppApplication : SBApplication

- (SBElementArray<WCAppOutputDevice *> *) outputDevices;

@property (copy) WCAppOutputDevice *selectedOutputDevice;  // The device to be used for audio output

@end

