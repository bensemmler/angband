/**
 * \file AngbandApplicationDelegate.m
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

#import "AngbandApplicationDelegate.h"

#import "AngbandCommon.h"
#import "AngbandDefaultTermView.h"
#import "AngbandTermConfiguration.h"
#import "AngbandTermWindow.h"
#import "NSFont+AngbandFont.h"
#import "grafmode.h"
#import "init.h"
#import "ui-game.h" /* savefile, play_game(), save_game() */

extern void AngbandInitialize(void);
extern void AngbandFinalize(void);
extern void AngbandRedrawAllTerminals(void);
extern void AngbandSaveGame(void);

extern term *term_data_link(int i, int rows, int columns);
extern BOOL AngbandApplicationShouldQuitImmediately(void);

NSModalResponse AngbandRunAlertPanel(NSString * __nullable title, NSString * __nullable message, NSString * __nullable defaultButtonTitle, BOOL showCancelButton)
{
	NSString *safeTitle = ([title length] > 0) ? title : NSLocalizedStringWithDefaultValue(@"Alert(UnknownError).Title", nil, [NSBundle mainBundle], @"Unknown Error", @"Alert title for an alert with no title provided.");
	NSString *safeMessage = (message != nil) ? message : @""; /* Informative text can't be nil. */
	NSString *cancelButtonTitle = NSLocalizedStringWithDefaultValue(@"Alert(UnknownError).Button(Cancel).Title", nil, [NSBundle mainBundle], @"Cancel", @"Cancel button title for an alert.");
	NSAlert *alert = [[NSAlert alloc] init];
	[alert setMessageText: safeTitle];
	[alert setInformativeText: safeMessage];

	if ([defaultButtonTitle length] > 0 && showCancelButton) {
		/* Use the custom default button and add a cancel button. */
		[alert addButtonWithTitle: defaultButtonTitle];
		[alert addButtonWithTitle: cancelButtonTitle];
	}
	else if ([defaultButtonTitle length] == 0 && showCancelButton) {
		/* Add a default button with a fallback title so that the cancel button
		 * is in the proper location. */
		NSString *safeDefaultButtonTitle = NSLocalizedStringWithDefaultValue(@"Alert(UnknownError).Button(Default).Title", nil, [NSBundle mainBundle], @"OK", @"Fallback button title for the default button in an alert.");
		[alert addButtonWithTitle: safeDefaultButtonTitle];
		[alert addButtonWithTitle: cancelButtonTitle];
	}
	else if ([defaultButtonTitle length] > 0 && !showCancelButton) {
		/* Use the custom default button. */
		[alert addButtonWithTitle: defaultButtonTitle];
	}
	else {
		/* Use the buttons provided by the system. */
	}

	NSModalResponse response = [alert runModal];
	[alert release];
	return response;
}

/**
 * Keep track of the save file currently being used. This is so that we can make
 * UI nicer for the user when they want to open it in the future.
 *
 * \param path The path to store.
 */
void AngbandSetCurrentSaveFilePath(NSString * __nonnull path)
{
	if ([path length] == 0) {
		return;
	}

	/* Save for general use, mainly for panel directory. */
	[[NSUserDefaults standardUserDefaults] setValue: path forKey: AngbandLastSaveFilePathDefaultsKey];
	[[NSUserDefaults standardUserDefaults] synchronize];

	/* Add to the recently opened files list. */
	[[NSDocumentController sharedDocumentController] noteNewRecentDocumentURL: [NSURL fileURLWithPath: path]];
}

@interface AngbandApplicationDelegate ()
@property (nonatomic, assign) BOOL gameInProgress;
@property (nonatomic, assign) BOOL readyToPlay;
@property (nonatomic, copy) NSString *savedGameFromLaunch;
@property (nonatomic, retain) IBOutlet NSMenu *commandMenu;
@property (nonatomic, retain) IBOutlet NSMenu *graphicsMenu;
@property (nonatomic, retain) NSArray *windows;
@property (nonatomic, retain) NSDictionary *commandMenuTagMap;
@property (nonatomic, retain) NSDictionary *soundNamesByMessageType;
@property (nonatomic, retain) NSDictionary *soundsBySoundName;
@end

@implementation AngbandApplicationDelegate

@synthesize commandMenu=_commandMenu;
@synthesize commandMenuTagMap=_commandMenuTagMap;
@synthesize gameInProgress=_gameInProgress;
@synthesize graphicsMenu=_graphicsMenu;
@synthesize readyToPlay=_readyToPlay;
@synthesize savedGameFromLaunch=_savedGameFromLaunch;
@synthesize soundNamesByMessageType=_soundNamesByMessageType;
@synthesize soundsBySoundName=_soundsBySoundName;
@synthesize windows=_windows;

#pragma mark -
#pragma mark Instance Setup and Teardown

#pragma mark -
#pragma mark Other Methods

/**
 * Register the default user defaults needed for platform specific preferences.
 * The actual preferences are read and updated as needed; there is no need to
 * load or set up anything beforehand.
 */
- (void)registerDefaults
{
	[AngbandTermConfiguration setMainTermIndex: 0];
	[AngbandTermConfiguration setDefaultTermInitializer: term_data_link];
	NSDictionary *configurations = [AngbandTermConfiguration defaultsToRegisterWithFont: [NSFont angband_defaultFont] maxTerminals: ANGBAND_TERM_MAX];

	/* Set up other preferences. */
	NSMutableDictionary *allDefaults = [[NSMutableDictionary alloc] init];
	[allDefaults setValue: [NSNumber numberWithInteger: 60] forKey: AngbandFramesPerSecondDefaultsKey];
	[allDefaults setValue: [NSNumber numberWithBool: YES] forKey: AngbandAllowSoundDefaultsKey];
	[allDefaults setValue: [NSNumber numberWithInteger: GRAPHICS_NONE] forKey: AngbandGraphicsIDDefaultsKey];
	[allDefaults addEntriesFromDictionary: configurations];

	[[NSUserDefaults standardUserDefaults] registerDefaults: allDefaults];
	[allDefaults release];
}

/**
 * Change the graphics mode of the game.
 *
 * \param graphicsID The ID of the graphics mode, provided by the game.
 */
- (void)switchGraphicsToModeWithID: (NSInteger)graphicsID
{
	/* We stashed the graphics mode ID in the menu item's tag */
	[[NSUserDefaults standardUserDefaults] setInteger: graphicsID forKey: AngbandGraphicsIDDefaultsKey];
	[[NSUserDefaults standardUserDefaults] synchronize];

	if (self.gameInProgress) {
		AngbandRedrawAllTerminals();
	}
}

/**
 * Create the actual terms that will be used to create windows to play the game.
 */
- (void)prepareTermWindows
{
	NSMutableArray *configurations = [[NSMutableArray alloc] init];

	for (NSInteger i = 0; i < ANGBAND_TERM_MAX; i++) {
		AngbandTermConfiguration *configuration = [AngbandTermConfiguration restoredConfigurationFromDefaultsWithIndex: i];
		[configurations addObject: configuration];
	}

	[AngbandTermConfiguration setDefaultWindowPlacementForConfigurations: configurations];

	NSMutableArray *windows = [[NSMutableArray alloc] init];

	for (NSInteger i = 0; i < ANGBAND_TERM_MAX; i++) {
		AngbandTermConfiguration *configuration = [configurations objectAtIndex: i];
		AngbandDefaultTermView *termView = [[AngbandDefaultTermView alloc] initWithFrame: NSZeroRect];
		AngbandTermWindow *window = [[AngbandTermWindow alloc] initWithConfiguration: configuration termView: termView];

		if (window != nil) {
			[windows addObject: window];
		}

		[window release];
		[termView release];
	}

	self.windows = [NSArray arrayWithArray: windows];
	[windows release];
	[configurations release];

	[self.windows makeObjectsPerformSelector: @selector(orderFront:) withObject: self];
}

/**
 * Start a game of Angband by calling \c play_game(). This method essentially
 * does not return.
 *
 * \param newGameNumber An \c NSNumber that contains the \c BOOL value YES if a
 *                      new game should be started, or NO if a saved game should
 *                      be loaded. This is an object so that it can be called
 *                      using \c performSelectorOnMainThread:withObject:.
 */
- (void)playAngbandStartingNewGame: (id)newGameNumber
{
	if (self.gameInProgress) {
		return;
	}

	if (![newGameNumber isKindOfClass: [NSNumber class]]) {
		[[NSException exceptionWithName: NSInvalidArgumentException reason: @"An NSNumber with a BOOL value must be used." userInfo: nil] raise];
		return;
	}

	/* play_game() returns when player dies or hits ^X. Angband should clean up
	 * enough stuff that AngbandApplicationShouldQuitImmediately() should cause
	 * the app to terminate immediately. */
	self.gameInProgress = YES;
	play_game([newGameNumber boolValue]);
	[[NSApplication sharedApplication] terminate: nil];
}

/**
 * Start playing Angband with a new character.
 */
- (void)playAngbandWithNewGame
{
	[self performSelectorOnMainThread: @selector(playAngbandStartingNewGame:) withObject: [NSNumber numberWithBool: YES] waitUntilDone: NO];
}

/**
 * Start playing Angband with a saved game.
 *
 * \param path The path to the save game file.
 */
- (void)playAngbandWithFileAtPath: (NSString * __nonnull)path
{
	if ([path length] == 0) {
		[[NSException exceptionWithName: NSInvalidArgumentException reason: @"File path was missing." userInfo: nil] raise];
		return;
	}

	/* Store the current file path for future reference, regardless of if we can
	 * open it. */
	AngbandSetCurrentSaveFilePath(path);

	if ([path getFileSystemRepresentation: savefile maxLength: sizeof(savefile)]) {
		/* Start the game by dispatching the method back to the main thread.
		 * This allows us to hand over control of the run loop to Angband in
		 * a consistent way, regardless of how the app was launched. */
		[self performSelectorOnMainThread: @selector(playAngbandStartingNewGame:) withObject: [NSNumber numberWithBool: NO] waitUntilDone: NO];
	}
	else {
		[[NSException exceptionWithName: NSInternalInconsistencyException reason: @"Unable to set savefile with the selected path. It's possible that the savefile path buffer is too small." userInfo: nil] raise];
	}
}

/**
 * Post a keydown event into the run loop so that Angband can pick it up and
 * process it. This makes it seems like the user pressed the key and makes it so
 * we don't have to interact directly with ui-term commands.
 *
 * \param command The command from the traditional Angband keymap. This command
 *        is sent with the appropriate escape characters.
 */
- (void)postAngbandCommandEventWithCommand: (NSString * __nonnull)command
{
	if ([command length] == 0) {
		return;
	}

	NSInteger windowNumber = [(AngbandTermWindow *)angband_term[0]->data windowNumber];

	/* Send a \ to bypass keymaps */
	NSEvent *escape = [NSEvent keyEventWithType: NSKeyDown
									   location: NSZeroPoint
								  modifierFlags: 0
									  timestamp: 0.0
								   windowNumber: windowNumber
										context: nil
									 characters: @"\\"
					charactersIgnoringModifiers: @"\\"
									  isARepeat: NO
										keyCode: 0];
	[[NSApplication sharedApplication] postEvent: escape atStart: NO];

	/* Send the actual command (from the original command set) */
	NSEvent *keyDown = [NSEvent keyEventWithType: NSKeyDown
										location: NSZeroPoint
								   modifierFlags: 0
									   timestamp: 0.0
									windowNumber: windowNumber
										 context: nil
									  characters: command
					 charactersIgnoringModifiers: command
									   isARepeat: NO
										 keyCode: 0];
	[[NSApplication sharedApplication] postEvent: keyDown atStart: NO];
}

#pragma mark -
#pragma mark Menus

/**
 * Append menu items to the Window menu for each possible term. Because of the
 * way Angband handles subwindows, it's much easier just to add a menu item for
 * a term and then just disable it if it's not available in the game. These menu
 * items are enabled and disabled elsewhere.
 */
- (void)prepareWindowMenu
{
	/* Grab the Window menu defined in the nib and add a separator before we
	 * start appending our own items. The menu in the nib should already contain
	 * all of the standard and expected window actions. */
	NSMenu *windowsMenu = [[NSApplication sharedApplication] windowsMenu];
	[windowsMenu addItem: [NSMenuItem separatorItem]];

	NSString *mainTermItemTitle = NSLocalizedStringWithDefaultValue(@"Menu(Window).Item(MainTerm).Title", nil, [NSBundle mainBundle], @"Angband", @"Title for the menu item in the Window menu that brings forward the window containing the main term.");
	NSMenuItem *mainTermItem = [[NSMenuItem alloc] initWithTitle: mainTermItemTitle action: @selector(selectWindow:) keyEquivalent: @"0"];
	[mainTermItem setTarget: self];
	[mainTermItem setTag: AngbandWindowMenuItemTagBase];
	[windowsMenu addItem: mainTermItem];
	[mainTermItem release];

	/* Add items for the rest of the term windows, using the term index as a key
	 * equivalent. */
	NSString *additionalTermTitleFormat = NSLocalizedStringWithDefaultValue(@"Menu(Window).Item(AdditionalTerm).Title", nil, [NSBundle mainBundle], @"Term %d", @"Title format for a menu item that represents additional terms in the Window menu. The placeholder is replaced with a localized number.");

	for (NSInteger i = 1; i < ANGBAND_TERM_MAX; i++) {
		NSString *title = [NSString localizedStringWithFormat: additionalTermTitleFormat, (int)i];
		NSString *keyEquivalent = [NSString stringWithFormat: @"%ld", (long)i];
		NSMenuItem *windowItem = [[NSMenuItem alloc] initWithTitle: title action: @selector(selectWindow:) keyEquivalent: keyEquivalent];
		[windowItem setTarget: self];
		[windowItem setTag: AngbandWindowMenuItemTagBase + i];
		[windowsMenu addItem: windowItem];
		[windowItem release];
	}
}

/**
 * Create a string that describes the key equivalent and modifiers, which can be
 * used to identify that key combination. This checks all available key masks,
 * so it should be able to describe all possible key combinations.
 *
 * \param key The key equivalent, as returned from a menu item.
 * \param modifiers The key modifier mask, as returned from a menu item.
 * \return A unique string describing the key combination or the empty string if
 *         one could not be created.
 */
- (NSString * __nonnull)keyEquivalentDescriptionForKey: (NSString * __nullable)key modifiers: (NSUInteger)modifiers
{
	if ([key length] == 0) {
		return @"";
	}

	BOOL capsLock = !!(modifiers & NSAlphaShiftKeyMask);
	BOOL shift = !!(modifiers & NSShiftKeyMask);
	BOOL control = !!(modifiers & NSControlKeyMask);
	BOOL option = !!(modifiers & NSAlternateKeyMask);
	BOOL command = !!(modifiers & NSCommandKeyMask);
	BOOL keypad = !!(modifiers & NSNumericPadKeyMask);
	BOOL help = !!(modifiers & NSHelpKeyMask);
	BOOL fn = !!(modifiers & NSFunctionKeyMask);
	return [NSString stringWithFormat: @"%@%d%d%d%d%d%d%d%d",
			key,
			capsLock,
			shift,
			control,
			option,
			command,
			keypad,
			help,
			fn];
}

/**
 * Recursively decend through a menu to gather all of its key equivalents.
 *
 * \param menu The menu whose items and subitems should be collected.
 * \return A set containing key equivalent description strings for the given
 *         menu.
 */
- (NSMutableSet * __nullable)keyEquivalentsForMenu: (NSMenu * __nullable)menu
{
	if (menu == nil) {
		return nil;
	}

	NSMutableSet *keyEquivalents = [NSMutableSet set];

	for (NSMenuItem *item in [menu itemArray]) {
		if (item.separatorItem) {
			continue;
		}

		NSString *keyEquivalent = [self keyEquivalentDescriptionForKey: [item keyEquivalent] modifiers: [item keyEquivalentModifierMask]];
		[keyEquivalents addObject: keyEquivalent];

		if ([item hasSubmenu]) {
			NSMutableSet *submenuEquivalents = [self keyEquivalentsForMenu: [item submenu]];
			[keyEquivalents unionSet: submenuEquivalents];
		}
	}

	return keyEquivalents;
}

/**
 * Collect all key equivalents for all items in the menu bar.
 *
 * \return A set containing key equivalent description strings.
 */
- (NSMutableSet * __nullable)existingKeyEquivalents
{
	NSMutableSet *allEquivalents = [self keyEquivalentsForMenu: [[NSApplication sharedApplication] mainMenu]];
	[allEquivalents removeObject: @""]; /* Remove the placeholder equivalent. */
	return allEquivalents;
}

/**
 * Append items from the given command menu file to the Command menu. This can
 * be called multiple times with different files and should safely add commands
 * as needed.
 *
 * \param commandMenuPath The command menu file to use for menu items.
 */
- (void)appendCommandMenuItemsWithFilePath: (NSString * __nonnull)commandMenuPath
{
	NSArray *commandMenuItems = [[NSArray alloc] initWithContentsOfFile: commandMenuPath];

	if ([commandMenuItems count] == 0) {
		[commandMenuItems release];
		return;
	}

	/* Start with the existing command map so that we can merge additional items
	 * into it. That way, we can build the menu from different sources. */
	NSMutableDictionary *angbandCommands = [[NSMutableDictionary alloc] initWithDictionary: self.commandMenuTagMap];
	NSNumber *maxTag = [[angbandCommands allKeys] valueForKeyPath: @"@max.integerValue"];
	NSInteger tagOffset = (maxTag != nil) ? [maxTag integerValue] - AngbandCommandMenuItemTagBase : 0;
	NSMutableSet *existingKeyEquivalents = [self existingKeyEquivalents];

	for (NSDictionary *item in commandMenuItems) {
		NSString *title = [item valueForKey: AngbandCommandMenuItemTitleKey];
		NSString *angbandCommand = [item valueForKey: AngbandCommandMenuAngbandCommandKey];

		if ([title length] == 0 || [angbandCommand length] == 0) {
			/* A title and an Angband command are required; a key equivalent is
			 * not, since someone might just want something they can select with
			 * the mouse. */
			continue;
		}

		NSString *key = [item valueForKey: AngbandCommandMenuKeyEquivalentKey];
		key = (key != nil) ? key : @""; /* The key equivalent can't be nil. */

		/* Get modifiers. Using control isn't allowed for now, because it might
		 * interfere with normal handling of Angband commands. This, along with
		 * always using the command key, are something that could be changed in
		 * the future if more picky event handling is implemented. */
		BOOL useShiftModifier = [[item valueForKey: AngbandCommandMenuShiftModifierKey] boolValue];
		BOOL useOptionModifier = [[item valueForKey: AngbandCommandMenuOptionModifierKey] boolValue];
		NSUInteger keyModifiers = NSCommandKeyMask;
		keyModifiers |= (useShiftModifier) ? NSShiftKeyMask : 0;
		keyModifiers |= (useOptionModifier) ? NSAlternateKeyMask : 0;

		/* Check this key combination to see if it is already in use. If so, we
		 * will add the menu item, but just not assign the key equivalent. */
		NSString *keyEquivalentDescription = [self keyEquivalentDescriptionForKey: key modifiers: keyModifiers];

		if ([existingKeyEquivalents containsObject: keyEquivalentDescription]) {
			key = @"";
			keyModifiers = 0;
		}

		/* Add the menu item, with the tag as the identifier that maps back to
		 * the desired Angband command. */
		NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle: title action: @selector(sendAngbandCommand:) keyEquivalent: key];
		[menuItem setTarget: self];
		[menuItem setKeyEquivalentModifierMask: keyModifiers];
		[menuItem setTag: AngbandCommandMenuItemTagBase + tagOffset];
		[self.commandMenu addItem: menuItem];
		[menuItem release];

		[angbandCommands setObject: angbandCommand forKey: [NSNumber numberWithInteger: [menuItem tag]]];
		[existingKeyEquivalents addObject: keyEquivalentDescription];
		tagOffset++;
	}

	NSDictionary *safeCommands = [[NSDictionary alloc] initWithDictionary: angbandCommands];
	self.commandMenuTagMap = safeCommands;
	[safeCommands release];
	[angbandCommands release];
	[commandMenuItems release];
}

/**
 * Build the Command menu, first with the built-in definitions, followed by
 * any user-supplied ones. If the menu is empty, we add a placeholder.
 */
- (void)prepareCommandMenu
{
	NSString *defaultCommandFilePath = [[NSBundle mainBundle] pathForResource: AngbandCommandMenuFileName ofType: @"plist"];
	[self appendCommandMenuItemsWithFilePath: defaultCommandFilePath];

	NSString *userCommandFilePath = [[[self angbandApplicationSupportPath] stringByAppendingPathComponent: AngbandCommandMenuFileName] stringByAppendingPathExtension: @"plist"];
	[self appendCommandMenuItemsWithFilePath: userCommandFilePath];

	if ([[self.commandMenu itemArray] count] == 0) {
		NSString *placeholderTitle = NSLocalizedStringWithDefaultValue(@"Menu(Command).Item(NoCommands).Title", nil, [NSBundle mainBundle], @"No Commands Defined", @"Placeholder menu item for when no menu items are available in the Command menu.");
		NSMenuItem *placeholderItem = [[NSMenuItem alloc] initWithTitle: placeholderTitle action: NULL keyEquivalent: @""];
		[placeholderItem setEnabled: NO];
		[self.commandMenu addItem: placeholderItem];
		[placeholderItem release];
	}
}

/**
 * Build the Graphics menu based on the graphics modes available to Angband. The
 * directory paths must be set up so that \c init_graphics_modes() can prepare
 * the appropriate data.
 */
- (void)prepareGraphicsMenu
{
	if (graphics_modes == NULL) {
		NSLog(@"[%@ %@]: graphics_mode was null; make sure paths are set up and graphics have been initialized", NSStringFromClass([self class]), NSStringFromSelector(_cmd));
		// !!!: this may need to be delayed until a window is actually shown, since it sticks around
		AngbandRunAlertPanel(NSLocalizedStringWithDefaultValue(@"Alert(MissingResources).Title", nil, [NSBundle mainBundle], @"Couldn't Load Tile Graphics", @"Title for alert when Angband was unable to load the tiles info."),
							 NSLocalizedStringWithDefaultValue(@"Alert(MissingResources).Message", nil, [NSBundle mainBundle], @"Angband wasn't able to load the information for graphic tiles. ASCII graphics mode will be used instead. Please report a bug on the Angband forums.", @"Message for alert when Angband was unable to load the tiles info."),
							 nil,
							 NO);

		[self switchGraphicsToModeWithID: GRAPHICS_NONE];
		return;
	}

	for (NSInteger i = 0; graphics_modes[i].pNext; i++) {
		graphics_mode const *mode = &graphics_modes[i];
		NSString *title = nil;

		if (mode == NULL) {
			continue;
		}

		if (strlen(mode->menuname)) {
			title = [NSString stringWithUTF8String: mode->menuname];
		}
		else {
			NSString *titleFormat = NSLocalizedStringWithDefaultValue(@"Menu(Graphics).Item(UnknownMode).Title", nil, [NSBundle mainBundle], @"Unknown %d", @"Placeholder string for a graphics mode with a missing name. The placeholder is replaced with an index.");
			title = [NSString localizedStringWithFormat: titleFormat, (long)i];
		}

		NSMenuItem *item = [[NSMenuItem alloc] initWithTitle: title action: @selector(selectGraphicsMode:) keyEquivalent: @""];
		[item setTarget: self];
		[item setTag: mode->grafID];
		[self.graphicsMenu addItem: item];
		[item release];
	}
}

- (BOOL)validateMenuItem: (NSMenuItem *)menuItem
{
	SEL sel = [menuItem action];
	NSInteger tag = [menuItem tag];

	// !!!: flatten out this branch when the window menu is fixed
	if (tag >= AngbandWindowMenuItemTagBase && tag < AngbandWindowMenuItemTagBase + ANGBAND_TERM_MAX) {
		if (tag == AngbandWindowMenuItemTagBase) {
			/* The main window should always be available and visible */
			return YES;
		}
		else {
			NSInteger subwindowNumber = tag - AngbandWindowMenuItemTagBase;
			return (window_flag[subwindowNumber] > 0);
		}

		return NO;
	}

	if (sel == @selector(newGame:)) {
		return (self.readyToPlay && !self.gameInProgress);
	}
	else if (sel == @selector(openGame:)) {
		return (self.readyToPlay && !self.gameInProgress);
	}
	else if (sel == @selector(saveGame:)) {
		return self.gameInProgress;
	}
	else if (sel == @selector(selectGraphicsMode:)) {
		NSInteger requestedGraphicsMode = [[NSUserDefaults standardUserDefaults] integerForKey: AngbandGraphicsIDDefaultsKey];
		[menuItem setState: (tag == requestedGraphicsMode)];
		return YES;
	}
	else if (sel == @selector(sendAngbandCommand:)) {
		/* we only want to be able to send commands during an active game */
		return self.gameInProgress;
	}

	/* Enable any menu items we don't know about. */
	return YES; // !!!: this should be NO, but there are some commands that aren't caught yet (save)
}

#pragma mark -
#pragma mark Sounds

/**
 * Load sound effects based on sound.cfg. NSSound is used for simple loading and
 * playback, and all sounds are loaded at once to prevent latency. All formats
 * and containers supported by Core Audio and QuickTime can be used.
 */
- (void)prepareSounds
{
	char path[2048];

	/* Find and open the config file */
	path_build(path, sizeof(path), ANGBAND_DIR_SOUNDS, "sound.cfg");
	NSString *configPath = [NSString stringWithUTF8String: path];
	NSString *configFile = [[NSString alloc] initWithContentsOfFile: configPath encoding: NSUTF8StringEncoding error: nil];

	if ([configFile length] == 0) {
		[configFile release];
		return;
	}

	/* Open the file and filter out the lines that we don't care about. */
	NSPredicate *commentLine = [NSPredicate predicateWithFormat: @"SELF MATCHES[c] %@", @"^#.*$"];
	NSPredicate *emptyLine = [NSPredicate predicateWithFormat: @"SELF MATCHES[c] %@", @"^\\s*$"];
	NSPredicate *dataLine = [NSPredicate predicateWithFormat: @"SELF CONTAINS[c] %@", @"="];
	NSPredicate *excludePredicate = [NSCompoundPredicate notPredicateWithSubpredicate: [NSCompoundPredicate orPredicateWithSubpredicates: [NSArray arrayWithObjects: commentLine, emptyLine, nil]]];
	NSPredicate *lineFilterPredicate = [NSCompoundPredicate andPredicateWithSubpredicates: [NSArray arrayWithObjects: dataLine, excludePredicate, nil]];
	NSArray *allLines = [configFile componentsSeparatedByString: @"\n"];
	NSArray *eventLines = [allLines filteredArrayUsingPredicate: lineFilterPredicate];

	NSMutableDictionary *soundNamesByMessageType = [[NSMutableDictionary alloc] init];
	NSMutableDictionary *soundsBySoundName = [[NSMutableDictionary alloc] init];

	for (NSString *event in eventLines) {
		NSArray *components = [event componentsSeparatedByString: @"="];

		if ([components count] < 2) {
			/* Something went wrong or no sounds are assigned to an event. */
			continue;
		}

		NSString *messageName = [[components objectAtIndex: 0] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
		int messageType = message_lookup_by_sound_name([messageName UTF8String]);

		if (messageType < 0) {
			/* Invalid event name. */
			continue;
		}

		/* Split and trim the names of the sound files. */
		NSArray *soundNames = [[components objectAtIndex: 1] componentsSeparatedByCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
		soundNames = [soundNames filteredArrayUsingPredicate: [NSPredicate predicateWithFormat: @"SELF.length > 0"]];

		if ([soundNames count] == 0) {
			/* No sounds assigned (there were spaces after the event name though). */
			continue;
		}

		/* Map the sound names to the event type and then load sound files. */
		[soundNamesByMessageType setObject: soundNames forKey: [NSNumber numberWithInt: messageType]];

		for (NSString *soundName in soundNames) {
			NSSound *sound = [soundsBySoundName valueForKey: soundName];

			if (sound != nil) {
				/* The sound has already been loaded. */
				continue;
			}

			path_build(path, sizeof(path), ANGBAND_DIR_SOUNDS, [soundName UTF8String]);
			sound = [[NSSound alloc] initWithContentsOfFile: [NSString stringWithUTF8String: path] byReference: YES];

			if (sound != nil) {
				[soundsBySoundName setValue: sound forKey: soundName];
			}

			[sound release];
		}
	}

	self.soundsBySoundName = [NSDictionary dictionaryWithDictionary: soundsBySoundName];
	self.soundNamesByMessageType = [NSDictionary dictionaryWithDictionary: soundNamesByMessageType];
	[soundsBySoundName release];
	[soundNamesByMessageType release];
	[configFile release];
}

/**
 * For a given event, play a random sound.
 *
 * \param eventType The message/event type which has sounds assigned to it.
 */
- (void)playRandomSoundForMessageType: (int)messageType
{
	NSArray *possibleSoundNames = [self.soundNamesByMessageType objectForKey: [NSNumber numberWithInt: messageType]];

	if ([possibleSoundNames count] == 0) {
		return;
	}

	NSString *soundName = [possibleSoundNames objectAtIndex: randint0((int)[possibleSoundNames count])];
	NSSound *sound = [self.soundsBySoundName valueForKey: soundName];

	if (sound != nil) {
		/* Restart the sound if it is currently playing. */
		[sound stop];
		[sound play];
	}
}

#pragma mark -
#pragma mark Directories and Paths

/**
 * Return the path for Angband's lib directory and bail if it isn't found. The
 * lib directory should be in the bundle's resources directory, since it's
 * copied when built.
 */
- (NSString * __nonnull)libDirectoryPath
{
	NSString *bundleLibPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent: AngbandDirectoryNameLib];
	BOOL isDirectory = NO;
	BOOL libExists = [[NSFileManager defaultManager] fileExistsAtPath: bundleLibPath isDirectory: &isDirectory];

	if (!libExists || !isDirectory) {
		NSLog(@"[%@ %@]: can't find %@/ in bundle: isDirectory: %d libExists: %d", NSStringFromClass([self class]), NSStringFromSelector(_cmd), AngbandDirectoryNameLib, isDirectory, libExists);
		AngbandRunAlertPanel(NSLocalizedStringWithDefaultValue(@"Alert(MissingResources).Title", nil, [NSBundle mainBundle], @"Missing Resources", @"Title for alert when Angband can't find the lib directory."),
							 NSLocalizedStringWithDefaultValue(@"Alert(MissingResources).Message", nil, [NSBundle mainBundle], @"Angband was unable to find required resources and must quit. Please report a bug on the Angband forums.", @"Message for alert when Angband can't find the lib directory."),
							 NSLocalizedStringWithDefaultValue(@"Alert(MissingResources).Button(Default).Title", nil, [NSBundle mainBundle], @"Quit", @"Button to dismiss missing resources alert and quit Angband."),
							 NO);

		/* Use exit() since the app may not be in a state to accept the
		 * terminate: message. */
		exit(0);
	}

	return bundleLibPath;
}

/**
 * Build a path for the specified search path directory. The returned path will
 * be affected by the \c SAFE_DIRECTORY preprocessor flag.
 *
 * \param directory The user domain directory where the path should be rooted.
 * \param baseName The name of the directory path component.
 * \return A valid path.
 */
- (NSString * __nonnull)safeDirectoryForUserSearchPathDirectory: (NSSearchPathDirectory)directory baseName: (NSString * __nullable)baseName
{
	NSString *safeBaseName = ([baseName length] != 0) ? baseName : AngbandDirectoryNameBase;
	NSString *path = [NSSearchPathForDirectoriesInDomains(directory, NSUserDomainMask, YES) lastObject];

#if defined(SAFE_DIRECTORY)
	NSString *versionedDirectory = [NSString stringWithFormat: @"%@-%s", safeBaseName, VERSION_STRING];
	return [path stringByAppendingPathComponent: versionedDirectory];
#else
	return [path stringByAppendingPathComponent: safeBaseName];
#endif
}

/**
 * Return the path for the directory where Angband should look for its standard
 * user file tree.
 */
- (NSString * __nonnull)angbandDocumentsPath
{
	return [self safeDirectoryForUserSearchPathDirectory: NSDocumentDirectory baseName: AngbandDirectoryNameBase];
}

/**
 * Return the path for the application support directory.
 */
- (NSString * __nonnull)angbandApplicationSupportPath
{
	return [self safeDirectoryForUserSearchPathDirectory: NSApplicationSupportDirectory baseName: AngbandDirectoryNameBase];
}

/**
 * Adjust directory paths as needed to correct for any differences needed by
 * Angband. \c init_file_paths() currently requires that all paths provided have
 * a trailing slash and all other platforms honor this.
 *
 * \param originalPath The directory path to adjust.
 * \return A path suitable for Angband or nil if an error occurred.
 */
- (NSString * __nullable)correctedDirectoryPath:(NSString * __nonnull) originalPath
{
	if ([originalPath length] == 0) {
		return nil;
	}

	if (![originalPath hasSuffix: @"/"]) {
		return [originalPath stringByAppendingString: @"/"];
	}

	return originalPath;
}

/**
 * Give Angband the base paths that should be used for the various directories
 * it needs. It will create any needed directories.
 */
- (void)prepareFilePathsAndDirectories
{
	char libpath[PATH_MAX + 1] = "\0";
	NSString *libDirectoryPath = [self correctedDirectoryPath: [self libDirectoryPath]];
	[libDirectoryPath getFileSystemRepresentation: libpath maxLength: sizeof(libpath)];

	char basepath[PATH_MAX + 1] = "\0";
	NSString *angbandDocumentsPath = [self correctedDirectoryPath: [self angbandDocumentsPath]];
	[angbandDocumentsPath getFileSystemRepresentation: basepath maxLength: sizeof(basepath)];

	init_file_paths(libpath, libpath, basepath);
	create_needed_dirs();
}

#pragma mark -
#pragma mark Action Methods

- (IBAction)newGame: (id)sender
{
	[self playAngbandWithNewGame];
}

- (IBAction)openGame: (id)sender
{
	NSOpenPanel *panel = [NSOpenPanel openPanel];
	[panel setCanChooseFiles: YES];
	[panel setCanChooseDirectories: NO];
	[panel setResolvesAliases: YES];
	[panel setAllowsMultipleSelection: NO];
	[panel setTreatsFilePackagesAsDirectories: NO];

	/* Limit enabled files to save files only. */
	NSString *saveFileUTI = [[[NSBundle mainBundle] infoDictionary] valueForKey: @"AngbandFileUTISave"];
	[panel setAllowedFileTypes: [NSArray arrayWithObject: saveFileUTI]];

	/* Set the panel's directory to the directory containing the last played
	 * save file, or to the general Angband document directory if not found. */
	NSString *lastDirectoryPath = [[[NSUserDefaults standardUserDefaults] valueForKey: AngbandLastSaveFilePathDefaultsKey] stringByDeletingLastPathComponent];

	if ([lastDirectoryPath length] == 0) {
		lastDirectoryPath = [self angbandDocumentsPath];
	}

	if ([panel respondsToSelector: @selector(setDirectoryURL:)]) {
		/* 10.6 and above. */
		[panel setDirectoryURL: [NSURL fileURLWithPath: lastDirectoryPath]];
	}
	else {
		/* 10.5. This should be removed when the deployment target is raised. */
		[panel setDirectory: lastDirectoryPath];
	}

	NSInteger result = [panel runModal];

	if (result != NSFileHandlingPanelOKButton) {
		return;
	}

	if (![[panel URL] isFileURL]) {
		/* If it's not a file URL, the URL path may not be usable. */
		[[NSException exceptionWithName: NSInternalInconsistencyException reason: @"The selected file was not a file URL." userInfo: nil] raise];
		return;
	}

	[self playAngbandWithFileAtPath: [[panel URL] path]];
}

- (IBAction)saveGame: (id)sender
{
	AngbandSaveGame();
}

/**
 * Menu item action to bring a window forward. The action is assigned to the
 * dynamically-created menu items in the Window menu.
 */
- (IBAction)selectWindow: (id)sender
{
	NSInteger subwindowNumber = [(NSMenuItem *)sender tag] - AngbandWindowMenuItemTagBase;
	AngbandTermWindow *window = angband_term[subwindowNumber]->data;
	[window makeKeyAndOrderFront: self];
	[window saveWindowVisibleToDefaults: YES];
}

/**
 * Menu item action to change graphics mode. The action is assigned directly to
 * the static ASCII menu item and assigned to dynamically-created menu items in
 * the Graphics menu.
 */
- (IBAction)selectGraphicsMode: (id)sender
{
	[self switchGraphicsToModeWithID: [sender tag]];
}

/**
 * Send a command to Angband from a menu item via the command map.
 */
- (void)sendAngbandCommand: (id)sender
{
	NSMenuItem *menuItem = (NSMenuItem *)sender;
	NSString *command = [self.commandMenuTagMap objectForKey: [NSNumber numberWithInteger: [menuItem tag]]];
	[self postAngbandCommandEventWithCommand: command];
}

/**
 * Handle standard help menu item.
 */
- (IBAction)showHelp: (id)sender
{
	if (self.gameInProgress) {
		[self postAngbandCommandEventWithCommand: @"?"];
	}
	else {
		/* Help won't show on the splash screen, so just alert to acknowledge. */
		AngbandRunAlertPanel(NSLocalizedStringWithDefaultValue(@"Alert(HelpOutOfGame).Title", nil, [NSBundle mainBundle], @"Built-In Angband Help", @"Alert title when the show help menu item is selected, but the game can't present the built-in help system."),
							 NSLocalizedStringWithDefaultValue(@"Alert(HelpOutOfGame).Message", nil, [NSBundle mainBundle], @"The built-in help system can only be shown while playing. Start a new game or open an existing game, and then press \"?\".", @"Alert message when the show help menu item is selected, but the game can't present the built-in help system."),
							 nil,
							 NO);
	}
}

/**
 * Open the Angband web site in the user's preferred browser.
 */
- (IBAction)showAngbandSite: (id)sender
{
	[[NSWorkspace sharedWorkspace] openURL: [NSURL URLWithString: @"http://rephial.org/"]];
}

/**
 * Open the Angband community site in the user's preferred browser.
 */
- (IBAction)showCommunitySite: (id)sender
{
	[[NSWorkspace sharedWorkspace] openURL: [NSURL URLWithString: @"http://angband.oook.cz/"]];
}

#pragma mark -
#pragma mark NSApplicationDelegate Methods

/**
 * Do a few things before files could possibly be opened, in case Angband is
 * launched by opening files. UI should generally not be presented here, since
 * the system may do some state restoration between this method and
 * \c applicationDidFinishLaunching:.
 */
- (void)applicationWillFinishLaunching: (NSNotification *)notification
{
	self.gameInProgress = NO;
	self.readyToPlay = NO;
	[self registerDefaults];
}

/**
 * Handle single-file open events by just forwarding it to the more general
 * delegate method for handling open events.
 */
- (BOOL)application: (NSApplication *)sender openFile: (NSString *)filename
{
	[self application: sender openFiles: [NSArray arrayWithObject: filename]];
	return YES; /* Returning YES will keep the file in the recent files list. */
}

/**
 * Handle open file events from Finder or some other app. This could be called
 * during launch or once the app is open and being played.
 */
- (void)application: (NSApplication *)sender openFiles: (NSArray *)filenames
{
	/* Figure out what kinds of files we are being asked to open; we only really
	 * care about save game files. We get the UTI from a key we stashed in the
	 * root of Info.plist so that we don't have to dig through all of the UTI or
	 * document type arrays to find something that might match. */
	NSString *saveFileUTI = [[[NSBundle mainBundle] infoDictionary] valueForKey: @"AngbandFileUTISave"];
	NSError *error = nil;
	NSMutableArray *possibleSaveFiles = [NSMutableArray array];

	for (NSString *path in filenames) {
		/* Let the system figure out what the file is, based on our Info.plist. */
		NSString *preferredUTI = [[NSWorkspace sharedWorkspace] typeOfFile: path error: &error];

		if (preferredUTI == nil || error != nil) {
			[[NSException exceptionWithName: NSInternalInconsistencyException reason: @"Unable to get a preferred UTI from the workspace." userInfo: nil] raise];
			continue;
		}

		if ([[NSWorkspace sharedWorkspace] type: preferredUTI conformsToType: saveFileUTI]) {
			[possibleSaveFiles addObject: path];
		}
	}

	if ([possibleSaveFiles count] == 0) {
		/* Ignore the open event, since the app was told to open some other kind
		 * of Angband file. We don't need to alert, since we don't do anything
		 * directly with these files. */
		return;
	}

	if (self.gameInProgress) {
		/* Run an alert, regardless of the number of files being opened. */
		AngbandRunAlertPanel(NSLocalizedStringWithDefaultValue(@"Alert(GameInProgress).Title", nil, [NSBundle mainBundle], @"Game in Progress", @"Alert title for when a game is opened from the Finder while another game is being played."),
							 NSLocalizedStringWithDefaultValue(@"Alert(GameInProgress).Message", nil, [NSBundle mainBundle], @"Angband can't open saved games while a game is in progress. To play a saved game, first quit Angband and open it from Finder or from the Angband splash screen.", @"Alert message for when a game is opened from the Finder while another game is being played."),
							 nil,
							 NO);
		return;
	}

	if ([possibleSaveFiles count] > 1) {
		AngbandRunAlertPanel(NSLocalizedStringWithDefaultValue(@"Alert(TooManySaveFilesOpened).Title", nil, [NSBundle mainBundle], @"Too Many Saved Game Files", @"Alert title for when opening more than one save game file from Finder."),
							 NSLocalizedStringWithDefaultValue(@"Alert(TooManySaveFilesOpened).Message", nil, [NSBundle mainBundle], @"Angband can only open one saved game at a time. Select a single file in Finder to start playing.", @"Alert message for when opening more than one save game file from Finder."),
							 nil,
							 NO);
		return;
	}

	/* At this point, we should have one save game file that we can try to have
	 * Angband open. If Angband can't do anything with it, it will handle the
	 * explanation to the user. */
	NSString *gamePath = [possibleSaveFiles lastObject];

	if (self.readyToPlay) {
		/* Start playing immediately. */
		[self playAngbandWithFileAtPath: gamePath];
	}
	else {
		/* Wait until the game is ready and then open this file when possible. */
		self.savedGameFromLaunch = gamePath;
	}
}

/**
 * Set up all of the stuff we need for the OS X port and then start initializing
 * Angband itself. In order for everything to work right, this method needs to
 * return properly so that the run loop can handle events for the splash screen
 * (such as opening a saved game). If the app was launched in response to a save
 * game file being opened, that game will automatically start. Do not call any
 * Angband functions from here that will not return in an expected manner.
 */
- (void)applicationDidFinishLaunching: (NSNotification *)notification
{
	[self prepareWindowMenu];
	[self prepareCommandMenu];

	/* Build the graphics menu. To do that, we first set up paths so that the
	 * graphics info can be loaded, and then actually load the info so that we
	 * can get the mode names for the menu. */
	[self prepareFilePathsAndDirectories];
	init_graphics_modes();
	[self prepareGraphicsMenu];

	[self prepareSounds];
	[self prepareTermWindows];

	AngbandInitialize();
	self.readyToPlay = YES;

	if ([self.savedGameFromLaunch length] > 0) {
		/* If the app was launched due to a save game being opened, we are ready
		 * to open it and play. */
		[self playAngbandWithFileAtPath: self.savedGameFromLaunch];
	}
}

/**
 * Figure out when the app can actually be terminated. This is determined by
 * delegating the check back to the Angband glue functions.
 */
- (NSApplicationTerminateReply)applicationShouldTerminate: (NSApplication *)sender
{
	if (AngbandApplicationShouldQuitImmediately()) {
		/* All of the conditions to quit have been met, so we can proceed to 
		 * applicationWillTerminate: to do any final bits of cleanup. */
		return NSTerminateNow;
	}

	/* In all other cases, we have to work around how Angband works to be able
	 * to check specific conditions for quitting. We send a custom event so that
	 * it is picked up in the event handler that is hooked up to Angband. At
	 * that point, it can set conditions and call terminate: again. */
	NSEvent *quitEvent = [NSEvent otherEventWithType: NSApplicationDefined
											location: NSZeroPoint
									   modifierFlags: 0
										   timestamp: [NSDate timeIntervalSinceReferenceDate]
										windowNumber: 0
											 context: nil
											 subtype: AngbandApplicationEventSubtypeQuitRequested
											   data1: 0
											   data2: 0];
	[[NSApplication sharedApplication] postEvent: quitEvent atStart: NO];

	return NSTerminateCancel;
}

/**
 * Clean up anything right before the app is killed. It's not the safest to do
 * something critical like file saving here, since the app could be killed
 * quickly or not have some resources available (such as quitting from the
 * splash screen when there is no game to save).
 */
- (void)applicationWillTerminate: (NSNotification *)notification
{
	self.gameInProgress = NO;
	self.readyToPlay = NO;
	AngbandFinalize();
}

@end
