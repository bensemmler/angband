/**
 * \file AngbandTermConfiguration.m
 * \brief OS X term behavior and appearance definition.
 *
 * Copyright (c) 2016 Ben Semmler
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

#import "AngbandTermConfiguration.h"

#import "AngbandCommon.h"

@interface AngbandTermConfiguration ()
@property (nonatomic, assign, readwrite) CGFloat preferredAdvance;
@property (nonatomic, assign, readwrite) CGSize tileSize;
@property (nonatomic, assign, readwrite) NSInteger columns;
@property (nonatomic, assign, readwrite) NSInteger rows;
@property (nonatomic, assign, readwrite) NSRect defaultWindowFrame;
@property (nonatomic, assign, readwrite) NSUInteger index;
@property (nonatomic, retain, readwrite) NSFont * __nullable font;
@end

@implementation AngbandTermConfiguration

@synthesize columns=_columns;
@synthesize defaultWindowFrame=_defaultWindowFrame;
@synthesize font=_font;
@synthesize index=_index;
@synthesize preferredAdvance=_preferredAdvance;
@synthesize rows=_rows;
@synthesize termInitializer=_termInitializer;
@synthesize tileSize=_tileSize;
@synthesize visible=_visible;

/** Storage for the default initializer function. */
static term * __nullable (* __nullable AngbandTermConfigurationDefaultTermInitializer)(int, int, int) = NULL;

/** Storage for the designated main term index. */
static NSUInteger AngbandTermConfigurationMainTermIndex = 0;

/** Minimum number of rows required in the main term. */
static NSInteger const AngbandTermConfigurationMainTermMinimumRows = 24;

/** Minimum number of columns required in the main term. */
static NSInteger const AngbandTermConfigurationMainTermMinimumColumns = 80;

/** Window style mask that should be used for all windows. */
static NSUInteger const AngbandTermConfigurationCommonWindowStyleMask = NSTitledWindowMask | NSResizableWindowMask | NSMiniaturizableWindowMask;

#pragma mark -
#pragma mark Instance Setup and Teardown

- (instancetype)init
{
	if ((self = [super init])) {
		/* Set fallbacks in case defaults don't get registered. */
		_font = [[NSFont systemFontOfSize: 13.0] retain];
		_columns = AngbandFallbackTerminalColumns;
		_defaultWindowFrame = NSZeroRect;
		_rows = AngbandFallbackTerminalRows;
		_tileSize = CGSizeMake(AngbandFallbackTileWidth, AngbandFallbackTileHeight);
		_index = 0;
		_termInitializer = AngbandTermConfigurationDefaultTermInitializer;
		_preferredAdvance = 0.0;
		_visible = YES;
	}

	return self;
}

- (void)dealloc
{
	[_font release];
	[super dealloc];
}

#pragma mark -
#pragma mark NSCopying Methods

- (id)copyWithZone: (NSZone *)zone
{
	AngbandTermConfiguration *newConfiguration = [[AngbandTermConfiguration alloc] init];
	newConfiguration.columns = self.columns;
	newConfiguration.defaultWindowFrame = self.defaultWindowFrame;
	newConfiguration.font = self.font;
	newConfiguration.index = self.index;
	newConfiguration.preferredAdvance = self.preferredAdvance;
	newConfiguration.rows = self.rows;
	newConfiguration.termInitializer = self.termInitializer;
	newConfiguration.tileSize = self.tileSize;
	newConfiguration.visible = self.visible;
	return newConfiguration;
}

#pragma mark -
#pragma mark Other Methods

/**
 * Set the default term initialization function that is used when instances are
 * initialized.
 *
 * \param function The function to be assigned to \c termInitializer by default.
 *        This will only affect instances that are created after this method is
 *        called.
 */
+ (void)setDefaultTermInitializer: (term * __nullable (* __nullable)(int, int, int))function
{
	AngbandTermConfigurationDefaultTermInitializer = function;
}

/**
 * Let instances know what terminal (by index) should be considered the main
 * terminal. The main term has some slight differences in behavior than the
 * secondary terms. Instances created before this method is called may need to
 * be updated or recreated to notice any change in this value. This method is
 * provided for explicitness and completeness.
 *
 * \param mainTermIndex The index that should be considered the main term. This
 *        should probably always be zero; the OS X port doesn't really care, but
 *        Angband may make assumptions that term 0 is the main term.
 */
+ (void)setMainTermIndex: (NSUInteger)mainTermIndex
{
	AngbandTermConfigurationMainTermIndex = mainTermIndex;
}

/**
 * Prepare a nice arrangement for the term windows if the user has not moved or
 * resized the windows yet. This is a bit hacky, since this method modifies the
 * configurations; configurations are intended to be immutable.
 *
 * \param configurations The set of configurations to use to arrange the windows
 *        when they are first created.
 */
+ (void)setDefaultWindowPlacementForConfigurations: (NSArray * __nonnull)configurations
{
	if ([configurations count] == 0) {
		return;
	}

	static NSRect containingFrame = {0};
	static BOOL containingFrameSet = NO;

	if (!containingFrameSet) {
		/* Get a frame that excludes the dock and the menu bar and inset it to
		 * center and pad our collection of windows. */
		containingFrame = [[NSScreen mainScreen] visibleFrame];
		containingFrame = NSInsetRect(containingFrame, NSWidth(containingFrame) * 0.05, NSHeight(containingFrame) * 0.05);
		containingFrame = NSIntegralRect(containingFrame);
		containingFrameSet = YES;
	}

	/* The presentation we are shooting for looks like this (which is somewhat
	 * based on the default subwindow flags):
	 *   +-----+-+   0: main term
	 *   |0    |2|   1: messages
	 *   |     +-+   2: inventory
	 *   |     |4|   3: monster list
	 *   +--+--+-+   4: object list
	 *   |1 |5 |3|   5: recall
	 *   +--+--+-+   6/7: not visible by default, but minimap and sidebar
	 * This leads to a 5 unit wide by 3 unit high grid to position the windows.
	 */

	static CGFloat const windowSpacing = 1.0;
	CGFloat horizontalUnit = floor(NSWidth(containingFrame) / 5.0);
	CGFloat verticalUnit = floor(NSHeight(containingFrame) / 3.0);

	for (AngbandTermConfiguration *configuration in configurations) {
		/* Get the window frame to account for UI elements and then move it to
		 * the origin of the containing frame. From there, the position and size
		 * are adjusted. */
		NSRect contentBounds = NSRectFromCGRect([configuration preferredContentBounds]);
		NSRect frame = [NSWindow frameRectForContentRect: contentBounds styleMask: AngbandTermConfigurationCommonWindowStyleMask];
		frame.origin = containingFrame.origin;

		if (configuration.index == 0) {
			frame.origin.x += 0.0;
			frame.origin.y += verticalUnit;
			frame.size.width = ceil(MAXX(NSWidth(frame), horizontalUnit * 4.0)) - windowSpacing;
			frame.size.height = ceil(MAXX(NSHeight(frame), verticalUnit * 2.0));
		}
		else if (configuration.index == 1) {
			frame.origin.x += 0.0;
			frame.origin.y += 0.0;
			frame.size.width = ceil(MAXX(NSWidth(frame), horizontalUnit * 2.0)) - windowSpacing;
			frame.size.height = ceil(MAXX(NSHeight(frame), verticalUnit)) - windowSpacing;
		}
		else if (configuration.index == 2) {
			frame.origin.x += horizontalUnit * 4.0;
			frame.origin.y += verticalUnit * 2.0;
			frame.size.width = ceil(MAXX(NSWidth(frame), horizontalUnit));
			frame.size.height = ceil(MAXX(NSHeight(frame), verticalUnit));
		}
		else if (configuration.index == 3) {
			frame.origin.x += horizontalUnit * 4.0;
			frame.origin.y += 0.0;
			frame.size.width = ceil(MAXX(NSWidth(frame), horizontalUnit));
			frame.size.height = ceil(MAXX(NSHeight(frame), verticalUnit)) - windowSpacing;
		}
		else if (configuration.index == 4) {
			frame.origin.x += horizontalUnit * 4.0;
			frame.origin.y += verticalUnit;
			frame.size.width = ceil(MAXX(NSWidth(frame), horizontalUnit));
			frame.size.height = ceil(MAXX(NSHeight(frame), verticalUnit)) - windowSpacing;
		}
		else if (configuration.index == 5) {
			frame.origin.x += horizontalUnit * 2.0;
			frame.origin.y += 0.0;
			frame.size.width = ceil(MAXX(NSWidth(frame), horizontalUnit * 2.0)) - windowSpacing;
			frame.size.height = ceil(MAXX(NSHeight(frame), verticalUnit)) - windowSpacing;
		}
		else {
			/* Cascade remaining windows from the top left of the main term. */
			CGFloat offset = (configuration.index - 5) * 30.0;
			frame.origin.x += offset;
			frame.origin.y += (verticalUnit * 3.0) - NSHeight(frame) - offset;
		}

		configuration.defaultWindowFrame = frame;
	}
}

/**
 * Create a new configuration by copying the current configuration and updating
 * it with the provided font.
 *
 * \param font The font to be used in the new configuration. Any associated
 *        properties will be updated as necessary.
 * \return An updated configuration. If an error occurred, a copy of the current
 *         configuration will be returned.
 */
- (instancetype __nonnull)configurationByChangingFont: (NSFont * __nonnull)font
{
	AngbandTermConfiguration *newConfiguration = [self copy];

	if (font != nil) {
		newConfiguration.font = font;
		[newConfiguration updateMetrics];
	}

	return [newConfiguration autorelease];
}

/**
 * Create a new configuration by copying the current configuration and updating
 * it with the desired rows and columns.
 *
 * \param rows The absolute number of rows that the configuration should have.
 * \param columns The absolute number of columns that the configuration should
 *        have.
 * \return An updated configuration. If an error occurred, a copy of the current
 *         configuration will be returned.
 */
- (instancetype __nonnull)configurationByChangingRows: (NSInteger)rows columns: (NSInteger)columns
{
	AngbandTermConfiguration *newConfiguration = [self copy];

	if (self.index == AngbandTermConfigurationMainTermIndex) {
		/* Make sure the main term doesn't go below its minimum size. */
		newConfiguration.rows = MAXX(rows, AngbandTermConfigurationMainTermMinimumRows);
		newConfiguration.columns = MAXX(columns, AngbandTermConfigurationMainTermMinimumColumns);
	}
	else {
		newConfiguration.rows = MAXX(rows, 1);
		newConfiguration.columns = MAXX(columns, 1);
	}

	return [newConfiguration autorelease];
}

/**
 * Calculate and return the bounds that would contain the content fully.
 *
 * \return A bounds rect with an appropriate height and width. The origin will
 *         always be (0, 0).
 */
- (CGRect)preferredContentBounds
{
	return CGRectMake(0.0, 0.0, ceil(self.tileSize.width * (CGFloat)self.columns), ceil(self.tileSize.height * (CGFloat)self.rows));
}

#pragma mark -
#pragma mark User Defaults

/**
 * Return the user defaults key associated with the term at the given index.
 *
 * \param index The index of the term to use to create the key.
 * \return A string that can be used to get the persisted data from user
 *         defaults. The key returned from this method is not guaranteed to have
 *         a value associated with it.
 */
+ (NSString * __nonnull)defaultsKeyWithIndex: (NSUInteger)index
{
	return [NSString stringWithFormat: AngbandTerminalConfigurationDefaultsKeyFormat, (int)index];
}

/**
 * Create a set of defaults that can be registered so that the user defaults for
 * terminal configurations are always in a consistent state.
 *
 * \param defaultFont The default font to be applied to all terminals.
 * \param maxTerminals The number of configurations to create defaults for. Each
 *        entry in the returned dictionary will be the same. This value may be
 *        clamped to a sensible value.
 * \return A dictionary with keys and values that are suitable to be registered
 *         as defaults in user defaults.
 */
+ (NSDictionary * __nullable)defaultsToRegisterWithFont: (NSFont * __nonnull)defaultFont maxTerminals: (NSUInteger)maxTerminals
{
	if (defaultFont == nil) {
		[[NSException exceptionWithName: NSInvalidArgumentException reason: @"A font is required when registering defaults." userInfo: nil] raise];
		return nil;
	}

	/* Clamp the number of terminal defaults to generate to a sensible number. */
	NSUInteger safeMaxTerminals = MINN(maxTerminals, 16);
	NSMutableDictionary *defaults = [[NSMutableDictionary alloc] init];

	for (NSUInteger i = 0; i < safeMaxTerminals; i++) {
		/* The following values were determined experimentally to find a nice
		 * balance between font, font size, and window size. */
		NSInteger rows = 24;
		NSInteger columns = 80;
		BOOL visible = YES;
		CGFloat defaultFontSize = [defaultFont pointSize];
		static CGFloat const smallFontSize = 10.0;

		switch (i) {
			case 0:
				columns = 124;
				rows = 31;
				break;
			case 1:
				columns = 79;
				rows = 20;
				defaultFontSize = smallFontSize;
				break;
			case 2:
				columns = 42;
				rows = 20; /* This will clip the inventory list as of 4.0.4. */
				defaultFontSize = smallFontSize;
				break;
			case 3:
				columns = 42;
				rows = 20;
				defaultFontSize = smallFontSize;
				break;
			case 4:
				columns = 42;
				rows = 20;
				defaultFontSize = smallFontSize;
				break;
			case 5:
				columns = 79;
				rows = 20;
				defaultFontSize = smallFontSize;
				break;
			default:
				columns = 80;
				rows = 24;
				defaultFontSize = smallFontSize;
				visible = NO;
				break;
		}

		/* Set up default properties for each term, regardless of its visibility. */
		NSMutableDictionary *standardTerm = [[NSMutableDictionary alloc] init];
		[standardTerm setValue: [NSNumber numberWithInteger: rows] forKey: AngbandTerminalRowsDefaultsKey];
		[standardTerm setValue: [NSNumber numberWithInteger: columns] forKey: AngbandTerminalColumnsDefaultsKey];
		[standardTerm setValue: [defaultFont fontName] forKey: AngbandTerminalFontNameDefaultsKey];
		[standardTerm setValue: [NSNumber numberWithDouble: defaultFontSize] forKey: AngbandTerminalFontSizeDefaultsKey];
		[standardTerm setValue: [NSNumber numberWithBool: visible] forKey: AngbandTerminalVisibleDefaultsKey];
		[defaults setValue: standardTerm forKey: [self defaultsKeyWithIndex: (int)i]];
		[standardTerm release];
	}

	return [defaults autorelease];
}

/**
 * Return a configuration that has values loaded from user defaults. This is the
 * primary way to get a terminal configuration.
 *
 * \param index The index of the terminal that needs to have its configuration
 *        loaded from user defaults.
 * \return A terminal configuration object that is ready for use.
 */
+ (instancetype __nonnull)restoredConfigurationFromDefaultsWithIndex: (NSUInteger)index
{
	AngbandTermConfiguration *configuration = [[AngbandTermConfiguration alloc] init];
	NSDictionary *terminal = [[NSUserDefaults standardUserDefaults] valueForKey: [self defaultsKeyWithIndex: index]];

	if (terminal == nil) {
		/* This means that the user hasn't set anything AND the defaults weren't
		 * registered properly. This will fall back to values set in -init. */
		return [configuration autorelease];
	}

	NSString *fontName = [terminal valueForKey: AngbandTerminalFontNameDefaultsKey];
	CGFloat fontSize = [[terminal valueForKey: AngbandTerminalFontSizeDefaultsKey] doubleValue];
	configuration.font = [NSFont fontWithName: fontName size: fontSize];
	configuration.columns = [[terminal valueForKey: AngbandTerminalColumnsDefaultsKey] integerValue];
	configuration.rows = [[terminal valueForKey: AngbandTerminalRowsDefaultsKey] integerValue];
	configuration.visible = [[terminal valueForKey: AngbandTerminalVisibleDefaultsKey] boolValue];
	configuration.index = index;
	[configuration updateMetrics];
	return [configuration autorelease];
}

/**
 * Save the current configuration to user defaults.
 */
- (void)saveToDefaults
{
	NSMutableDictionary *currentConfiguration = [[NSMutableDictionary alloc] init];
	[currentConfiguration setValue: [NSNumber numberWithInteger: self.rows] forKey: AngbandTerminalRowsDefaultsKey];
	[currentConfiguration setValue: [NSNumber numberWithInteger: self.columns] forKey: AngbandTerminalColumnsDefaultsKey];
	[currentConfiguration setValue: [self.font fontName] forKey: AngbandTerminalFontNameDefaultsKey];
	[currentConfiguration setValue: [NSNumber numberWithDouble: [self.font pointSize]] forKey: AngbandTerminalFontSizeDefaultsKey];
	[currentConfiguration setValue: [NSNumber numberWithBool: self.visible] forKey: AngbandTerminalVisibleDefaultsKey];
	[[NSUserDefaults standardUserDefaults] setValue: currentConfiguration forKey: [[self class] defaultsKeyWithIndex: self.index]];
	[[NSUserDefaults standardUserDefaults] synchronize];
}

#pragma mark -
#pragma mark Window Properties

/**
 * Create a title to be used by the owning window. This currently returns a
 * value that will not change between invocations.
 *
 * \return A formatted, localized title string.
 */
- (NSString * __nonnull)windowTitle
{
	NSString *title = nil;

	if (self.index == AngbandTermConfigurationMainTermIndex) {
		title = NSLocalizedStringWithDefaultValue(@"Window(MainTerm).Title", nil, [NSBundle mainBundle], @"Angband", @"Title for the window containing the main term.");
	}
	else {
		NSString *additionalTermTitleFormat = NSLocalizedStringWithDefaultValue(@"Window(AdditionalTerm).Title", nil, [NSBundle mainBundle], @"Term %d", @"Title format for a window for additional terms. The placeholder is replaced with a localized number.");
		title = [NSString localizedStringWithFormat: additionalTermTitleFormat, (int)self.index];
	}

	return title;
}

/**
 * Return a style mask that is appropriate for the current terminal.
 *
 * \return A style mask that can be used for window creation.
 */
- (NSUInteger)windowStyleMask
{
	NSUInteger styleMask = AngbandTermConfigurationCommonWindowStyleMask;

	if (self.index != AngbandTermConfigurationMainTermIndex) {
		/* Make every window other than the main window closable. */
		styleMask |= NSClosableWindowMask;
	}

	return styleMask;
}

/**
 * Return the minimum that a window is allowed to be resized to. This value is
 * dependent on the font and tile size, as well as the term index. Also, it does
 * not take into account any additional geometry modifications that the window
 * itself might do (such as adding padding). Thus, the window should check this
 * value frequently and make further adjustments as needed.
 *
 * \return The minimum permitted window size.
 */
- (NSSize)windowMinimumSize
{
	/* Use a default minimum size of one tile. That way we can have at least one
	 * row safely. */
	NSSize minimumSize = NSSizeFromCGSize(self.tileSize);

	if (self.index == AngbandTermConfigurationMainTermIndex) {
		/* The main term can gracefully handle sizes smaller than 80x24, but we
		 * will assume that most people won't need or want it to be smaller. */
		minimumSize = NSMakeSize((CGFloat)AngbandTermConfigurationMainTermMinimumColumns * self.tileSize.width, (CGFloat)AngbandTermConfigurationMainTermMinimumRows * self.tileSize.height);
	}

	return minimumSize;
}

/**
 * Modify any full screen behavior of the window.
 *
 * \param existingBehavior Current behavior flags of the window.
 * \return Modified flags, by ORing values to the existing flags.
 */
- (NSWindowCollectionBehavior)windowCollectionBehaviorWithBehavior: (NSWindowCollectionBehavior)existingBehavior
{
	/* If this is the first term, and we support full screen (Mac OS X Lion or
	 * later), then allow it to go full screen (sweet). Allow other terms to be
	 * FullScreenAuxilliary, so they can at least show up. Unfortunately in
	 * Lion they don't get brought to the full screen space; but they would
	 * only make sense on multiple displays anyways so it's not a big loss. */

	NSWindowCollectionBehavior modifiedBehavior = existingBehavior;

	if (self.index == AngbandTermConfigurationMainTermIndex) {
		modifiedBehavior |= Angband_NSWindowCollectionBehaviorFullScreenPrimary;
	}
	else {
		modifiedBehavior |= Angband_NSWindowCollectionBehaviorFullScreenAuxiliary;
	}

	return modifiedBehavior;
}

#pragma mark -
#pragma mark -

/* qsort-compatible compare function for CGSizes */
static int compare_advances(const void *ap, const void *bp)
{
	const CGSize *a = ap, *b = bp;
	return (a->width > b->width) - (a->width < b->width);
}

- (void)updateMetrics
{
	/* "Glyph info": an array of the CGGlyphs and their widths corresponding to the above font. */
	CGGlyph glyphArray[GLYPH_COUNT];
	CGFloat glyphWidths[GLYPH_COUNT];

	/* Update glyphArray and glyphWidths */
	NSFont *screenFont = [self.font screenFont];

	/* Generate a string containing each MacRoman character */
	unsigned char latinString[GLYPH_COUNT];
	size_t i;
	for (i=0; i < GLYPH_COUNT; i++) latinString[i] = (unsigned char)i;

	/* Turn that into unichar. Angband uses ISO Latin 1. */
	unichar unicharString[GLYPH_COUNT] = {0};
	NSString *allCharsString = [[NSString alloc] initWithBytes:latinString length:sizeof latinString encoding:NSISOLatin1StringEncoding];
	[allCharsString getCharacters:unicharString range:NSMakeRange(0, MINN(GLYPH_COUNT, [allCharsString length]))];
	[allCharsString autorelease];

	/* Get glyphs */
	memset(glyphArray, 0, sizeof(glyphArray));
	CTFontGetGlyphsForCharacters((CTFontRef)screenFont, unicharString, glyphArray, GLYPH_COUNT);

	/* Get advances. Record the max advance. */
	CGSize advances[GLYPH_COUNT] = {};
	CTFontGetAdvancesForGlyphs((CTFontRef)screenFont, kCTFontHorizontalOrientation, glyphArray, advances, GLYPH_COUNT);
	for (i=0; i < GLYPH_COUNT; i++) {
		glyphWidths[i] = advances[i].width;
	}

	/* For good non-mono-font support, use the median advance. Start by sorting
	 * all advances. */
	qsort(advances, GLYPH_COUNT, sizeof *advances, compare_advances);

	/* Skip over any initially empty run */
	size_t startIdx;
	for (startIdx = 0; startIdx < GLYPH_COUNT; startIdx++)
	{
		if (advances[startIdx].width > 0) break;
	}

	/* Pick the center to find the median */
	CGFloat medianAdvance = 0;
	if (startIdx < GLYPH_COUNT)
	{
		/* In case we have all zero advances for some reason */
		medianAdvance = advances[(startIdx + GLYPH_COUNT)/2].width;
	}

	self.preferredAdvance = medianAdvance;

	/* Record the tile size. Note that these are typically fractional values -
	 * which seems sketchy, but we end up scaling the heck out of our view
	 * anyways, so it seems to not matter. */
	//	_tileSize.width = medianAdvance;
	//	_tileSize.height = [screenFont ascender] - [screenFont descender];

	if (self.index == AngbandTermConfigurationMainTermIndex) {
		_tileSize.width = ceil(medianAdvance);
		_tileSize.height = ceil([screenFont ascender] - [screenFont descender]);
	}
	else {
		_tileSize.width = medianAdvance;
		_tileSize.height = [screenFont ascender] - [screenFont descender];
	}
}

@end
