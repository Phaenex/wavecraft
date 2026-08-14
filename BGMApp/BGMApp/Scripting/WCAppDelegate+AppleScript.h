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
//  WCAppDelegate+AppleScript.h
//  BGMApp
//
//  Copyright © 2017 Kyle Neideck
//  Copyright © 2021 Marcus Wu
//

#import "WCAppDelegate.h"

// Local Includes
#import "WCAudioDeviceManager.h"
#import "WCAppVolumesController.h"

// Local Includes
#import "WCASOutputDevice.h"
#import "WCASApplication.h"

// System Includes
#import <Foundation/Foundation.h>


#pragma clang assume_nonnull begin

@interface WCAppDelegate (AppleScript)

- (BOOL) application:(NSApplication*)sender delegateHandlesKey:(NSString*)key;

@property WCASOutputDevice* selectedOutputDevice;
@property (readonly) NSArray<WCASOutputDevice*>* outputDevices;
@property double mainVolume;
@property (readonly) NSArray<WCASApplication*>* applications;

@end

#pragma clang assume_nonnull end

