/**
 * \file AngbandTermConfiguration.h
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

#import <Cocoa/Cocoa.h>
#import "AngbandCommon.h"
#import "ui-term.h" /* term struct */

/**
 * A terminal configuration defines a set of properties that describe how a term
 * should look and behave. These properties mostly affect windows containing the
 * terminal as well as some drawing behavior. Instances can save to and reload
 * themselves from user defaults, and are otherwise immutable.
 */
@interface AngbandTermConfiguration : NSObject <NSCopying>
{
@private
	BOOL _visible;
	CGFloat _preferredAdvance;
	CGSize _tileSize;
	NSFont *_font;
	NSInteger _columns;
	NSInteger _rows;
	NSUInteger _index;
	term * (*_termInitializer)(int, int, int);
}

@property (nonatomic, assign) BOOL visible; /**< The visibility of the window based on user preference. */
@property (nonatomic, assign) term * __nullable (* __nullable termInitializer)(int index, int rows, int columns); /**< The function that should be called to create the term object in Angband. */
@property (nonatomic, assign, readonly) CGFloat preferredAdvance; /**< A measurement used to help position glyphs horizontally. Dependent on \c font. */
@property (nonatomic, assign, readonly) CGSize tileSize; /**< The width and height of an individual tile in this terminal. */
@property (nonatomic, assign, readonly) NSInteger columns; /**< The number of columns in this terminal. */
@property (nonatomic, assign, readonly) NSInteger rows; /**< The number of rows in this terminal. */
@property (nonatomic, assign, readonly) NSUInteger index; /**< The index of this terminal in \c angband_terminals[]. */
@property (nonatomic, retain, readonly) NSFont * __nullable font; /**< The font that is used to draw actual glyphs on screen. */

+ (void)setDefaultTermInitializer: (term * __nullable (* __nullable)(int, int, int))function;
+ (void)setMainTermIndex: (NSUInteger)mainTermIndex;
+ (NSDictionary * __nullable)defaultsToRegisterWithFont: (NSFont * __nonnull)defaultFont maxTerminals: (NSUInteger)maxTerminals;
+ (instancetype __nonnull)restoredConfigurationFromDefaultsWithIndex: (NSUInteger)index;
- (instancetype __nonnull)configurationByChangingFont: (NSFont * __nonnull)font;
- (instancetype __nonnull)configurationByChangingRows: (NSInteger)rows columns: (NSInteger)columns;
- (CGRect)preferredContentBounds;
- (void)saveToDefaults;
- (NSString * __nonnull)windowTitle;
- (NSUInteger)windowStyleMask;
- (NSSize)windowMinimumSize;
- (NSWindowCollectionBehavior)windowCollectionBehaviorWithBehavior: (NSWindowCollectionBehavior)existingBehavior;
@end
