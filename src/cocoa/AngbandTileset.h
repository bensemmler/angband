/**
 * \file AngbandTileset.h
 * \brief Class to manage graphic tileset resources.
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

/**
 * A tileset contains all of the resources needed for a view to render graphic
 * tiles instead of text characters (where appropriate).
 */
@interface AngbandTileset : NSObject
{
@private
	CGImageRef _image;
	CGSize _imageSize;
	CGSize _tileSize;
	NSInteger _columns;
	NSInteger _rows;
	NSURL *_fileURL;
}

@property (nonatomic, assign, readonly) CGImageRef __nullable image; /**< A reference to the image data. */
@property (nonatomic, assign, readonly) CGSize imageSize; /**< The size of \c image. */
@property (nonatomic, assign, readonly) CGSize tileSize; /**< The size of an individual tile. This value is provided by the graphics info file. */
@property (nonatomic, assign, readonly) NSInteger columns; /**< The number of columns in the image, as derived by the image size and the tile size. */
@property (nonatomic, assign, readonly) NSInteger rows; /**< The number of rows in the image, as derived by the image size and the tile size. */

+ (instancetype __nullable)imageTilesetAtPath: (NSString * __nonnull)path tileWidth: (CGFloat)tileWidth tileHeight: (CGFloat)tileHeight;
- (CGRect)boundsForFeatureTileWithEntity: (AngbandTerminalEntity * __nonnull)entity;
- (CGRect)boundsForTerrainTileWithEntity: (AngbandTerminalEntity * __nonnull)entity;
@end
