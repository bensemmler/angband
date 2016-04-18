/**
 * \file AngbandCommon.h
 * \brief Common header for all files in the OS X port.
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

#ifndef OSX_AngbandCommon_h
#define OSX_AngbandCommon_h

#import "angband.h"

#if defined(SAFE_DIRECTORY)
#import "buildid.h" /* For VERSION_STRING */
#endif

/* Define a new MAX macro, since Angband's and Cocoa's cause ambiguity. */
#if !defined(MAXX)
#define MAXX(a, b)	(((a) < (b)) ? (b) : (a))
#endif

/* Define a new MIN macro, since Angband's and Cocoa's cause ambiguity. */
#if !defined(MINN)
#define MINN(a, b)	(((a) > (b)) ? (b) : (a))
#endif

#pragma mark Compiler Feature Compatibility

#if !__has_feature(objc_instancetype)
#define instancetype id
#endif

#if !__has_feature(nullability)
#define __nonnull
#define __nullable
#endif

#if defined(MACH_O_CARBON)
#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h> /* For keycodes */

#ifndef NS_DESIGNATED_INITIALIZER
#define NS_DESIGNATED_INITIALIZER
#endif

#ifndef NS_ENUM
#define NS_ENUM(_type, _name) _type _name; enum
#endif

#pragma mark General Constants

static CGFloat const AngbandFallbackTileHeight = 16.0;
static CGFloat const AngbandFallbackTileWidth = 8.0;
static NSInteger const AngbandCommandMenuItemTagBase = 2000;
static NSInteger const AngbandFallbackTerminalColumns = 80;
static NSInteger const AngbandFallbackTerminalRows = 24;
static NSInteger const AngbandWindowMenuItemTagBase = 1000;
static NSSize const AngbandScaleIdentity = {1.0, 1.0};
static NSString * const AngbandDirectoryNameBase = @"Angband";
static NSString * const AngbandDirectoryNameLib = @"lib";

/** The leftmost column that allows mouse clicks. */
static int const AngbandMainTermClickableLeftOffset = 14;

/** The topmost column that allows mouse clicks. */
static int const AngbandMainTermClickableTopOffset = 1;

/** The number of columns from the right to exclude from mouse clicks. */
static int const AngbandMainTermClickableRightOffset = 0;

/** The number of columns from the bottom to exclude from mouse clicks. */
static int const AngbandMainTermClickableBottomOffset = 1;

/** Value indicating left mouse button to \c Term_mousepress(). */
static int const AngbandButtonIndexLeftMouse = 1;

/** Value indicating right mouse button to \c Term_mousepress(). */
static int const AngbandButtonIndexRightMouse = 2;

#pragma mark User Defaults Keys

static NSString * const AngbandGraphicsIDDefaultsKey = @"GraphicsID"; // graphics mode/id requested by the user; determined by menu item tags
static NSString * const AngbandLastSaveFilePathDefaultsKey = @"AngbandLastSaveFile";
static NSString * const AngbandTermWindowNameDefaultsKeyFormat = @"AngbandTermWindow-%d";
static NSString * const AngbandTerminalColumnsDefaultsKey = @"Columns";
static NSString * const AngbandTerminalConfigurationDefaultsKeyFormat = @"AngbandTerminalConfiguration-%d";
static NSString * const AngbandTerminalFontNameDefaultsKey = @"FontName";
static NSString * const AngbandTerminalFontSizeDefaultsKey = @"FontSize";
static NSString * const AngbandTerminalRowsDefaultsKey = @"Rows";
static NSString * const AngbandTerminalVisibleDefaultsKey = @"Visible";

/* These key formats support older defaults formats. */
static NSString * const AngbandFramesPerSecondDefaultsKey = @"FramesPerSecond"; // game fps limit (0 is unthrottled); menu item tags store values
static NSString * const AngbandAllowSoundDefaultsKey = @"AllowSound"; // flag to prevent sounds; apparently, this is only used by the screen saver (which may not work anymore)
static NSString * const AngbandTerminalsDefaultsKey = @"Terminals";
static NSString * const AngbandFontNameDefaultsKeyFormat = @"FontName-%d";
static NSString * const AngbandFontSizeDefaultsKeyFormat = @"FontSize-%d";

#pragma mark Command Menu File Keys

/** The name of the file containing entries for the Command menu. This file must be a plist. */
static NSString * const AngbandCommandMenuFileName = @"CommandMenu";

/** Dictionary key for the shift modifier. Value is NSNumber/BOOL. */
static NSString * const AngbandCommandMenuShiftModifierKey = @"ShiftModifier";

/** Dictionary key for the option modifier. Value is NSNumber/BOOL. */
static NSString * const AngbandCommandMenuOptionModifierKey = @"OptionModifier";

/** Dictionary key for the title of the menu item to add. Value is NSString. Required. */
static NSString * const AngbandCommandMenuItemTitleKey = @"Title";

/** Dictionary key for the actual key equivalent. Value is NSString. */
static NSString * const AngbandCommandMenuKeyEquivalentKey = @"KeyEquivalent";

/** Dictionary key for the command to execute when the menu item is selected. Value is NSString. Required. */
static NSString * const AngbandCommandMenuAngbandCommandKey = @"AngbandCommand";

#pragma mark -

/**
 * A representation of a terminal tile. We keep our own copy, since the way the
 * term system updates itself doesn't work well with how Cocoa likes to draw
 * views.
 */
typedef struct AngbandTerminalEntity {
	wchar_t character; /**< The character that is the highest-priority for this tile. */
	int attributes; /**< The attributes to be applied to \c character. */
	wchar_t terrainCharacter; /**< The character that is drawn underneath \c character. */
	int terrainAttributes; /**< Attributes to be applied to the terrain character. */
} AngbandTerminalEntity;

/**
 * An entity to represent an unused space in our entity storage. Note that this
 * does not necessarily imply the same thing as a blank space in the game. Most
 * of the time, Angband will provide a "blank" character used to fill space; we
 * honor that character, even if it is invisible to the player.
 */
static AngbandTerminalEntity const AngbandTerminalEntityNull = {
	0,
	0,
	0,
	0,
};

static byte const AngbandTerminalEntityGraphicMask = 0x80;
static byte const AngbandTerminalEntityValueMask = 0x7F;

/**
 * A struct to pass parameters from the Term callbacks to the handling methods.
 * This is for compactness and to help future-proof a bit.
 */
typedef struct AngbandTerminalUpdateInfo {
	int x; /**< Terminal column of the first updated character. */
	int y; /**< Terminal row of the first updated character. */
	wchar_t const *featureChars; /**< The characters to place. Must not be null. */
	int const *featureAttrs; /**< The attributes to use for the feature characters. Must not be null. */
	wchar_t const *terrainChars; /**< The terrain characters to place underneath the feature characters. Optional. */
	int const *terrainAttrs; /**< The attributes for the terrain characters. Optional. */
	int count; /**< Number of characters being updated in this run. */
} AngbandTerminalUpdateInfo;

typedef NS_ENUM(short, AngbandApplicationEventSubtype) {
	AngbandApplicationEventSubtypeQuitRequested = 1,
};

/* The max number of glyphs we support */
#define GLYPH_COUNT 256

#define COLOR_TABLE_RED 1
#define COLOR_TABLE_GREEN 2
#define COLOR_TABLE_BLUE 3

#define ERRR_NONE 0

/* Redeclare some 10.7 constants and methods so we can build on 10.6 */
enum {
	Angband_NSWindowCollectionBehaviorFullScreenPrimary = 1 << 7,
	Angband_NSWindowCollectionBehaviorFullScreenAuxiliary = 1 << 8
};

@interface NSWindow (AngbandLionRedeclares)
- (void)setRestorable:(BOOL)flag;
@end

#endif /* MACINTOSH || MACH_O_CARBON */
#endif /* OSX_AngbandCommon_h */
