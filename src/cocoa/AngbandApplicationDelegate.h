/**
 * \file AngbandApplicationDelegate.h
 * \brief App delegate class, bridges Cocoa and Angband stuff.
 *
 * Copyright (c) 2011 Peter Ammon
 * Copyright (c) 2013, 2016 Ben Semmler
 *
 * This work is free software; you can redistribute it and/or modify it
 * under the terms of either:
 *
 * a) the GNU General Public License as published by the Free Software
 *    Foundation, version 2, or
 *
 * b) the "Angband licence":
 *    This software may be copied and distributed for educational, research,
 *    and not for profit purposes provided that this copyright and statement
 *    are included in all such copies.  Other copyrights may also apply.
 */

#import <Cocoa/Cocoa.h>
#import "AngbandCommon.h"
#import "AngbandSoundPlaying.h"

@interface AngbandApplicationDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate, AngbandSoundPlaying>
{
@private
	BOOL _gameInProgress;
	BOOL _readyToPlay;
	NSArray *_windows;
	NSDictionary *_commandMenuTagMap;
	NSDictionary *_soundNamesByMessageType;
	NSDictionary *_soundsBySoundName;
	NSMenu *_commandMenu;
	NSMenu *_graphicsMenu;
	NSString *_savedGameFromLaunch;
}

@end
