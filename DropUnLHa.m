#import "DropUnLHa.h"

@implementation DropUnLHa

// ************************ Delegation ****************************

- (void) applicationWillFinishLaunching : (NSNotification *) notification
{
#ifdef DEBUG
    NSLog(@"applicationWillFinishlaunching()");
#endif

    // initialize properties
    targetItem = [[NSMutableArray array] retain];
    appStatus = WAITING;
    createFolder = YES;
    quitAfterTask = YES;
    shouldQuit = NO;
    droppedItemCount = 0;
    theTask = nil;

    // load preferences
    [self loadPreferences];

    // register observer to notification
    [[NSNotificationCenter defaultCenter]
      addObserver : self
         selector : @selector(shouldStartNewTaskNotification:)
             name : @"ShouldStartNewTaskNotification"
           object : self];
}

- (BOOL) application : (NSApplication *) sender
            openFile : (NSString *) filename
{
    NSNotification *notification;
    NSArray *forModes;

#ifdef DEBUG
    NSLog(@"openFile(%@)", filename);
#endif

    if (appStatus != WAITING) {
        NSRunAlertPanel(NSLocalizedString(@"Error", ""),
                        NSLocalizedString(@"Task_is_running", ""),
                        NSLocalizedString(@"OK", ""), nil, nil);
        return NO;
    }

    // increment counter
    droppedItemCount++;
    // append filename to target
    [targetItem addObject : filename];

    // notify to start the task
    notification = [NSNotification notificationWithName : @"ShouldStartNewTaskNotification"
                                                 object : self];
    forModes = [NSArray arrayWithObject : NSDefaultRunLoopMode];
    [[NSNotificationQueue defaultQueue]
      enqueueNotification : notification
             postingStyle : NSPostWhenIdle
             coalesceMask : NSNotificationCoalescingOnName
                 forModes : forModes];

    return YES;
}

- (void) applicationDidFinishLaunching : (NSNotification *) notification
{
#ifdef DEBUG
    NSLog(@"applicationDidFinishlaunching()");
#endif

    // launched by drag & dropped, quit after the task
    if (quitAfterTask == YES && droppedItemCount > 0) {
        shouldQuit = YES;
    }
}

- (NSApplicationTerminateReply) applicationShouldTerminate : (NSApplication *) notification
{
    int result;
#ifdef DEBUG
    NSLog(@"applicationShouldTerminate()");
#endif

    // if some task is running yet, cancel to quit
    if (appStatus != WAITING) {
        result = NSRunAlertPanel(NSLocalizedString(@"Warning", ""),
                                 NSLocalizedString(@"Really_quit", ""),
                                 NSLocalizedString(@"Cancel", ""),
                                 NSLocalizedString(@"OK", ""), nil);
        // if OK was clicked, abort task
        if (result == NSAlertAlternateReturn) {
            [self stopTask];
            return YES;
        }
        return NO;
    }
    
    return YES;
}

- (void) applicationWillTerminate : (NSNotification *) notification
{
#ifdef DEBUG
    NSLog(@"applicationWillTerminate()");
#endif

    // save preferences
    [self savePreferences];

    // deallocate properties
    [targetItem release];

    if (theTask != nil)
        [theTask release];
}

// for enable or disable menu item
- (BOOL) validateMenuItem : (NSMenuItem *) anItem
{
#ifdef DEBUG
    NSLog(@"validateMenuItem()");
#endif
    if (appStatus == WAITING) {
        return YES;
    }

    if ([anItem action] == @selector(openMenuSelected:) ||
        [anItem action] == @selector(prefMenuSelected:))
    {
        return NO;
    }

    return YES;
}

// ************************ Notification ****************************

// this method will call when items are dropped
- (void) shouldStartNewTaskNotification : (NSNotification *) notification
{
#ifdef DEBUG
    NSLog(@"shouldStartNewTaskNotification()");
#endif

    if (appStatus == WAITING) {
        // execute task at here
        [self doTask];
    } else {
        NSRunAlertPanel(NSLocalizedString(@"Error", ""),
                        NSLocalizedString(@"Task_is_running", ""),
                        NSLocalizedString(@"OK", ""), nil, nil);
    }
}

// ************************ Action ****************************

// this method will call when "Open..." menu are selected
- (IBAction) openMenuSelected : (id) sender
{
    NSOpenPanel *aPanel;
    NSArray *fileTypes;
    int i, rc;
    
    // create instance of open file dialog
    aPanel = [NSOpenPanel openPanel];
    fileTypes = [NSArray arrayWithObjects : @"lzh", @"LZH", @"lha", @"LHA", @"lzs", @"LZS", nil];
    // set properties
    [aPanel setCanChooseDirectories : YES];
    [aPanel setCanChooseFiles : YES];
    [aPanel setAllowsMultipleSelection : YES];

    // show dialog and get value
    rc = [aPanel runModalForDirectory : NSHomeDirectory()
                                 file : @"Documents" types : fileTypes];
    if (rc == NSOKButton) {
        for (i=0; i<[[aPanel filenames] count]; i++) {
            [targetItem addObject : [[aPanel filenames] objectAtIndex : i]];
        }

        // do task
        [[NSNotificationCenter defaultCenter]
          postNotificationName : @"ShouldStartNewTaskNotification"
                        object : self];
    }
}

// this method will call when "Preferences..." menu are selected
- (IBAction) prefMenuSelected : (id) sender
{
    // centering PrefWindow
    [prefWindow center];
    // show PrefWindow as modal dialog
    [[NSApplication sharedApplication] runModalForWindow : prefWindow];
    // close prefWindow
    [prefWindow orderOut : self];
}

// this method will call when "Stop" button are clicked
- (IBAction) stopClicked : (id) sender
{
    [self stopTask];
}

// this method will call when "OK" button in PrefWindow are clicked
- (IBAction) prefOkClicked : (id) sender
{
    // close prefWindow
    [[NSApplication sharedApplication] stopModal];

    // save and reload preferences
    [self savePreferences];
    [self loadPreferences];
}

// this method will call when "Cancel" button in PrefWindow are clicked
- (IBAction) prefCancelClicked : (id) sender
{
    // close prefWindow
    [[NSApplication sharedApplication] stopModal];

    // reload preferences
    [self loadPreferences];
}

// this method will call when "Select" button in PrefWindow are clicked
- (IBAction) destSelectClicked : (id) sender
{
    NSString *aPath;
    
    aPath = [self askDestination];
    if ([aPath length] > 0) {
        [destText setStringValue : aPath];
    }
}

// ************************ <AMShellWrapper> ****************************

- (void)appendOutput:(NSString *)output
{
#ifdef DEBUG
    NSLog(@"appendOutput()\n<<%@>>", output);
#endif
}

- (void)appendError:(NSString *)error
{
#ifdef DEBUG
    NSLog(@"appendOutput()\n<<%@>>", error);
#endif
}

- (void) processStarted:(id)sender
{
    NSString *curItem;
    int remItem;
    
#ifdef DEBUG
    NSLog(@"processStarted()");
#endif

    remItem = [targetItem count];
    curItem = [[targetItem objectAtIndex : 0] lastPathComponent];

    // set application status to WAITING
    appStatus = RUNNING;
    // update Window
    [remCountText setIntValue : remItem];
    [extItemText setStringValue : curItem];
    // show window
    [taskWindow center];
    [taskWindow makeKeyAndOrderFront : self];
    [taskIndicator startAnimation : self];
}

- (void) processFinished:(id)sender withTerminationStatus:(int)resultCode
{
#ifdef DEBUG
    NSLog(@"processFinished()");
#endif

    // show error dialog
    if (resultCode != 0) {
        NSRunAlertPanel(NSLocalizedString(@"Error", ""),
                        NSLocalizedString(@"Error_occured", ""),
                        NSLocalizedString(@"OK", ""), nil, nil);
    }

    // hide window
    [taskIndicator stopAnimation : self];
    [taskWindow orderOut : self];

    // set application status to WAITING
    appStatus = WAITING;
    
    [targetItem removeObjectAtIndex : 0];
    // do task recursive
    if ([targetItem count] > 0) {
        [[NSNotificationCenter defaultCenter]
            postNotificationName : @"ShouldStartNewTaskNotification"
                        object : self];
    } else { // no target
        // if launched by drag & drop, then quit
        if (shouldQuit == YES) {
            [NSApp terminate : self];
        }
    }
}

// ************************ Other Method ****************************

// return lha command path
- (NSString *) getLhaPath
{
    NSString *aPath;

    aPath = [[[NSBundle mainBundle] resourcePath]
              stringByAppendingPathComponent : @"lha"];

    return aPath;
}

// return lha's option
- (NSString *) getLhaOption
{
    NSMutableString *aOption;

#ifdef DEBUG
    aOption = [NSMutableString stringWithString : @"xfgw="];
#else
    aOption = [NSMutableString stringWithString : @"xq2fgw="];
#endif
    return aOption;
}

// return destination path
- (NSString *) getDestination
{
    NSString *aPath;
    
    switch ([[destRadio selectedCell] tag]) {
    case 1: // same as original
        aPath = [NSString stringWithString : [[targetItem objectAtIndex : 0]
        	  stringByDeletingLastPathComponent]];
        break;
    case 2: // Ask
        aPath = [NSString stringWithString : [self askDestination]];
        break;
    case 3: // Use
        aPath = [NSString stringWithString : [destText stringValue]];
        break;
    case 0: // Desktop
    default: // default is Desktop
        aPath = [[NSString stringWithString : NSHomeDirectory()]
                  stringByAppendingPathComponent : @"Desktop"];
        break;
    }
    
    return aPath;
}

// ask destination directory
- (NSString *) askDestination
{
    NSString *aDestination;
    NSOpenPanel *aPanel;
    int rc;
    
    // open file dialog
    aPanel = [NSOpenPanel openPanel];
    // set propaties of file dialog
    [aPanel setCanChooseDirectories : YES];
    [aPanel setCanChooseFiles : NO];
    [aPanel setAllowsMultipleSelection : NO];
    [aPanel setPrompt : NSLocalizedString(@"Select", "")];
    [aPanel setTitle : NSLocalizedString(@"Select_destination", "")];

    // get selected folder path
    rc = [aPanel runModalForDirectory : NSHomeDirectory()
                                 file : @"Desktop" types : nil];
    if (rc == NSOKButton) {
        aDestination = [aPanel filename];
    } else {
        aDestination = [NSString stringWithString : @""];
    }
    
    return aDestination;
}

// check destination is valid, if valid, then return true
- (BOOL) checkDestination : (NSString *) aPath
{
    NSFileManager *aManager;
    BOOL isDir;

    aManager = [NSFileManager defaultManager];
    if ([aPath length] < 1)
        return false;
    if (![aManager fileExistsAtPath : aPath isDirectory : &isDir] || !isDir)
        return false;
    if (![aManager isWritableFileAtPath : aPath])
        return false;

    return true;
}

// load preferences
- (void) loadPreferences
{
    NSUserDefaults *aPref;
    NSString *aValue;

    aPref = [NSUserDefaults standardUserDefaults];
    
    if ([aPref boolForKey : @"doNotQuitAfterTask"]) {
        [noQuitToggle setState : NSOnState];
        quitAfterTask = NO;
    } else {
        [noQuitToggle setState : NSOffState];
        quitAfterTask = YES;
    }
    if ([aPref boolForKey : @"doNotCreateFolder"]) {
        [noCreateFolderToggle setState : NSOnState];
        createFolder = NO;
    } else {
        [noCreateFolderToggle setState : NSOffState];
        createFolder = YES;
    }
    aValue = [aPref stringForKey : @"DestinationDir"];
    if (aValue) {
        [destText setStringValue : aValue];
    } else {
        [destText setStringValue : @""];
    }
    [destRadio selectCellWithTag : [aPref integerForKey : @"DestinationType"]];
}

// save preferences
- (void) savePreferences
{
    NSUserDefaults *aPref;

    aPref = [NSUserDefaults standardUserDefaults];

    [aPref setInteger : [[destRadio selectedCell] tag]
               forKey : @"DestinationType"];
    [aPref setObject : [destText stringValue]
              forKey : @"DestinationDir"];
    if ([noQuitToggle state] == NSOnState) {
        [aPref setBool : true
                forKey : @"doNotQuitAfterTask"];
    } else {
        [aPref setBool : false
                forKey : @"doNotQuitAfterTask"];
    }
    if ([noCreateFolderToggle state] == NSOnState) {
        [aPref setBool : true
                forKey : @"doNotCreateFolder"];
    } else {
        [aPref setBool : false
                forKey : @"doNotCreateFolder"];
    }
}

- (void) doTask
{
    int i;
    NSMutableArray *aCommand;
    NSString *aDestination, *outputPath;

#ifdef DEBUG
    NSLog(@"doTask()");
#else
    i = 0;
#endif

    // check destination
    aDestination = [self getDestination];
    if ([self checkDestination : aDestination] != true) {
        NSRunAlertPanel(NSLocalizedString(@"Error", ""),
                        NSLocalizedString(@"Bad_destination", ""),
                        NSLocalizedString(@"OK", ""), nil, nil);
        return;
    }

    // build command line
    if (createFolder == YES) {
        outputPath = [aDestination stringByAppendingPathComponent :
                       [[[targetItem objectAtIndex : 0] lastPathComponent]
                         stringByDeletingPathExtension]];
    } else {
        outputPath = [NSString stringWithString : aDestination];
    }
    aCommand = [NSMutableArray arrayWithObjects :
                 [self getLhaPath],
                 [NSString stringWithFormat : @"%@%@", [self getLhaOption], outputPath],
                 @"--extract-broken-archive",
                 [targetItem objectAtIndex : 0], nil];

#ifdef DEBUG
    for (i=0; i<[aCommand count]; i++)
        NSLog(@"aCommand: %@", [aCommand objectAtIndex:i]);
#endif

    // allocate memory for and initialize a new TaskWrapper object
    if (theTask != nil)
        [theTask release];
    theTask = [[AMShellWrapper alloc]
                initWithController:self
                         inputPipe:nil outputPipe:nil errorPipe:nil
                  workingDirectory:NSHomeDirectory() environment:nil
                         arguments:aCommand];
    // kick off the process asynchronously
    [theTask startProcess];
}

- (void) stopTask
{
    if (appStatus == RUNNING) {
        [theTask stopProcess];
    }
}

@end
