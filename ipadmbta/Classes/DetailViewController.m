//
//  DetailViewController.m
//  ipadmbta
//
//  Created by Daniel Choi on 9/29/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "DetailViewController.h"
#import "RootViewController.h"
#import "GetRemoteDataOperation.h"
#import "Preferences.h"
#import "ServerUrl.h"
#import <CoreLocation/CoreLocation.h>
#import "JSON.h"
#import "MapViewController.h"
#import "ScheduleViewController.h"
#import "StopsViewController.h"
#import "Preferences.h"
#import "HelpViewController.h"

@interface DetailViewController ()
@property (nonatomic, retain) UIPopoverController *popoverController;
- (void)configureView;

- (void)saveState;
- (void)adjustFrames;
@end



@implementation DetailViewController

@synthesize toolbar, popoverController, detailItem, detailDescriptionLabel;
@synthesize contentView;
@synthesize headsign, routeShortName, transportType, firstStop;
@synthesize stops, orderedStopIds, imminentStops, firstStops, regionInfo, headsignLabel, routeNameLabel, selectedStopId, bookmarkButton ;
@synthesize location;
@synthesize mapViewController, scheduleViewController;
@synthesize segmentedControl;
@synthesize currentContentView;
@synthesize stopsViewController;
@synthesize orderedStopNames;
@synthesize findStopButton, findingProgressView; 
@synthesize hvc;

- (void)viewDidLoad {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(loadTrips:)
                                                 name:@"loadMBTATrips" object:nil];
    
    operationQueue = [[NSOperationQueue alloc] init];    
    self.location = nil;

    mapViewController.detailViewController = self;
    scheduleViewController.detailViewController = self;

    self.navigationItem.title = @"openmbta";
    
    if (self.findingProgressView == nil) {
        NSArray *nib = [[NSBundle mainBundle] loadNibNamed:@"LocatingProgress" owner:self options:nil];
        NSEnumerator *enumerator = [nib objectEnumerator];
        id object;
        while ((object = [enumerator nextObject])) {
            if ([object isMemberOfClass:[UIView class]]) {
                self.findingProgressView = (UIView *)object;
            }
        }    
    }     

    [super viewDidLoad];
}


- (void)viewWillAppear:(BOOL)animated {
    [self adjustFrames];
    [super viewWillAppear:animated];

}

- (void)viewWillDisappear:(BOOL)animated { // will never happen in ipad
    self.navigationItem.rightBarButtonItem = nil;
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"lastViewedTrip"];
    [[NSUserDefaults standardUserDefaults] synchronize];    
    [operationQueue cancelAllOperations];
    [self hideNetworkActivity];
    
    [super viewWillDisappear:animated];
}



- (void)loadTrips:(NSNotification *)notification {
    [operationQueue cancelAllOperations];
    [self hideNetworkActivity];
    
    self.transportType = [[notification userInfo] objectForKey:@"transportType"];
    self.routeShortName = [[notification userInfo] objectForKey:@"routeShortName"];    
    self.headsign = [[notification userInfo] objectForKey:@"headsign"];
    self.firstStop = [[notification userInfo] objectForKey:@"firstStop"];    
    NSNumber *startOnSegmentIndex = [[notification userInfo] objectForKey:@"startOnSegmentIndex"];
    
    if (!transportType || !routeShortName || !headsign) {
        return;
    }

    shouldReloadRegion = [[[notification userInfo] objectForKey:@"shouldReloadMapRegion"] boolValue];    
    self.stops = [NSArray array];
    self.mapViewController.selectedStopAnnotation = nil;
    [self startLoadingData];
    
    headsignLabel.text = self.headsign;
    if ([self.transportType isEqualToString: @"Bus"]) {
        routeNameLabel.text = [NSString stringWithFormat:@"%@ %@", self.transportType, self.routeShortName];
        
    } else if ([self.transportType isEqualToString: @"Subway"]) {
        routeNameLabel.text = [NSString stringWithFormat:@"%@", self.firstStop];        
        
    } else if ([self.transportType isEqualToString: @"Commuter Rail"]) {
        routeNameLabel.text = [NSString stringWithFormat:@"%@ Line", self.routeShortName];     
        
    } else {
        routeNameLabel.text = self.routeShortName;            
    }

    [self styleBookmarkButton];
    
    if (startOnSegmentIndex) {
        self.segmentedControl.selectedSegmentIndex = [startOnSegmentIndex intValue];
    }
    [self toggleView:nil];    
    
    
}

- (void)saveState {    
    int index;
    if (self.segmentedControl) 
        index = self.segmentedControl.selectedSegmentIndex;
    else 
        index = 0;
        
    NSNumber *selectedSegmentAsNumber = [NSNumber numberWithInt:index]; 
    NSDictionary *lastViewedTrip = [NSDictionary dictionaryWithObjectsAndKeys: self.headsign, @"headsign", self.routeShortName, @"routeShortName", self.transportType, @"transportType", selectedSegmentAsNumber, @"selectedSegmentIndex", self.firstStop, @"firstStop", nil]; // subtle trick here since firstStop can be null and terminal the dictionary early, and properly
    
    [[Preferences sharedInstance] saveLastViewedRoute:lastViewedTrip]; 
    
}


- (BOOL)isBookmarked {
    Preferences *prefs = [Preferences sharedInstance]; 
    NSDictionary *bookmark = [NSDictionary dictionaryWithObjectsAndKeys: headsign, @"headsign", routeShortName, @"routeShortName", transportType, @"transportType", firstStop, @"firstStop", nil];
    return ([prefs isBookmarked:bookmark]);
}

- (void)styleBookmarkButton; {    
    if ([self isBookmarked]) {
        self.bookmarkButton.style = UIBarStyleBlackTranslucent;         
        self.bookmarkButton.title = @"Bookmarked";
    } else {
        self.bookmarkButton.style = UIBarStyleBlackOpaque;
        self.bookmarkButton.title = @"Bookmark";
    }
}


-(void)toggleBookmark:(id)sender {
    if ([self isBookmarked]) {
        Preferences *prefs = [Preferences sharedInstance]; 
        NSDictionary *bookmark = [NSDictionary dictionaryWithObjectsAndKeys: self.headsign, @"headsign", self.routeShortName, @"routeShortName", self.transportType, @"transportType", self.firstStop, @"firstStop", nil];
        [prefs removeBookmark: bookmark];
    } else {
        Preferences *prefs = [Preferences sharedInstance]; 
        NSDictionary *bookmark = [NSDictionary dictionaryWithObjectsAndKeys: self.headsign, @"headsign", self.routeShortName, @"routeShortName", self.transportType, @"transportType", self.firstStop, @"firstStop", nil];
        [prefs addBookmark: bookmark];
        //NSLog(@"bookmarks %@", [prefs orderedBookmarks]);
    }
    [self styleBookmarkButton];
}



- (void)reloadData:(id)sender {    
    [self.mapViewController.stopAnnotations removeAllObjects];
    self.mapViewController.selectedStopAnnotation = nil;
    self.stops = [NSArray array];    
    [self startLoadingData];
}


#pragma mark -
#pragma mark loading methods

// This calls the server
- (void)startLoadingData {    
    
    [self showNetworkActivity];
    self.findStopButton.enabled = NO;
    [self.scheduleViewController clearGrid];
    
    // We need to substitute a different character for the ampersand in the
    // headsign because Rails splits parameters on ampersands, even escaped
    // ones.
    NSString *headsignAmpersandEscaped = [self.headsign stringByReplacingOccurrencesOfString:@"&" withString:@"^"];
    UIDevice *myDevice = [UIDevice currentDevice];
    NSString *deviceUDID = [[myDevice uniqueIdentifier] retain];

    NSString *apiUrl = [NSString stringWithFormat:@"%@/trips?version=3&udid=%@&route_short_name=%@&headsign=%@&transport_type=%@&base_time=%@&first_stop=%@",
                        ServerURL, 
                        deviceUDID,
                        self.routeShortName, 
                        headsignAmpersandEscaped, 
                        self.transportType, 
                        [NSDate date],
                        self.firstStop];
    NSString *apiUrlEscaped = [apiUrl stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    NSLog(@"loading form API: %@", apiUrlEscaped);
    GetRemoteDataOperation *operation = [[GetRemoteDataOperation alloc] initWithURL:apiUrlEscaped target:self action:@selector(didFinishLoadingData:)];
    [operationQueue addOperation:operation];
    [operation release];
}

- (void)didFinishLoadingData:(NSString *)rawData {
    if (rawData == nil) return;
    NSDictionary *data = [rawData JSONValue];
    scheduleViewController.stops = [data objectForKey:@"grid"];
    
    BOOL isRealTime = NO;
    if ([data objectForKey:@"realtime"]) {
        isRealTime = YES;
        // do something in view to indicate
    }
    [self checkForMessage:data];
    self.stops = [data objectForKey:@"stops"];
    
    // construct GRID
    self.orderedStopIds = [data objectForKey:@"ordered_stop_ids"]; // will use in the table
    self.imminentStops = [data objectForKey:@"imminent_stop_ids"];
    self.firstStops = [data objectForKey:@"first_stop"]; // an array of stop names
    self.regionInfo = [data objectForKey:@"region"];
    
    if (shouldReloadRegion == YES) {
        [mapViewController prepareMap:regionInfo];
        shouldReloadRegion = NO;
    }
    [mapViewController annotateStops:self.stops imminentStops:self.imminentStops firstStops:self.firstStops isRealTime:isRealTime];
    
    self.orderedStopNames = [NSMutableArray arrayWithCapacity:[self.orderedStopIds count]];
    for (id stopId in self.orderedStopIds) {
        NSDictionary *stop = [self.stops objectForKey:[stopId stringValue] ];
        [self.orderedStopNames addObject:[stop objectForKey:@"name"]];
    }
    
    NSDictionary *userInfo = [NSDictionary dictionaryWithObject:self.orderedStopNames forKey:@"orderedStopNames"];
    NSNotification *notification = [NSNotification notificationWithName:@"MBTAloadOrderedStopNames" object:nil userInfo:userInfo];
    [[NSNotificationCenter defaultCenter] postNotification:notification];

    self.scheduleViewController.orderedStopNames = self.orderedStopNames;
    [scheduleViewController createFloatingGrid];        
    [scheduleViewController highlightStopNamed:self.mapViewController.selectedStopName showCurrentColumn:NO];

    [self hideNetworkActivity];
    
    [scheduleViewController adjustScrollViewFrame];    
    [scheduleViewController alignGridAnimated:NO];
    self.findStopButton.enabled = YES;    
}


- (void)toggleView:(id)sender {

    NSUInteger selectedSegment = self.segmentedControl.selectedSegmentIndex;
    [currentContentView removeFromSuperview];
    if (selectedSegment == 0) { 
        [self adjustFrames];
        self.currentContentView = mapViewController.view;
        [contentView addSubview:mapViewController.view];
        
    } else { 
        [self adjustFrames];
        self.currentContentView = scheduleViewController.view;
        [contentView addSubview:scheduleViewController.view];
        
        [self.scheduleViewController scrollViewDidScroll:self.scheduleViewController.scrollView]; // to align table with grid
        [self.scheduleViewController alignGridAnimated:NO];
    }
    [self saveState];
}

- (void)adjustFrames {
    mapViewController.view.frame = CGRectMake(0, 0, self.contentView.frame.size.width, self.contentView.frame.size.height);
    scheduleViewController.view.frame = CGRectMake(0, 0, self.contentView.frame.size.width, self.contentView.frame.size.height);
  
    [scheduleViewController adjustScrollViewFrame];
    [scheduleViewController alignGridAnimated:NO];
    
}

- (void)showStopsController:(id)sender {
    [self presentModalViewController:self.stopsViewController animated:YES];
}

- (void)highlightStopNamed:(NSString *)stopName {
    
    
    [self.mapViewController highlightStopNamed:stopName];
    // map controller will trigger scheduleViewController
    //    [self.scheduleViewController highlightStopNamed:stopName showCurrentColumn:NO];
}


- (void)highlightStopPosition:(int)pos {
    NSString *stopName = [self.orderedStopNames objectAtIndex:pos];
    [self.mapViewController highlightStopNamed:stopName];
    //    [self.scheduleViewController highlightRow:pos showCurrentColumn:NO];
}


- (IBAction)helpButtonPressed:(id)sender {
    NSLog(@"%@", [self.popoverController.contentViewController class]);
    if (![self.popoverController.contentViewController isMemberOfClass:[HelpViewController class]]) {
        [self.popoverController dismissPopoverAnimated:YES];
        self.popoverController = nil;             
        if (!self.hvc)
            self.hvc = [[HelpViewController alloc] initWithNibName:@"HelpViewController" bundle:nil];

        hvc.viewName = self.segmentedControl.selectedSegmentIndex == 0 ? @"map" : @"schedule";
        hvc.transportType = self.transportType;
        if (!self.popoverController)
            self.popoverController = [[[UIPopoverController alloc] initWithContentViewController:hvc] autorelease];
        self.popoverController.delegate = self;
        hvc.container = self.popoverController;
        [self.popoverController presentPopoverFromBarButtonItem:sender
                                       permittedArrowDirections:UIPopoverArrowDirectionAny
                                                       animated:YES];
    } else {
        [self.popoverController dismissPopoverAnimated:YES];
        self.popoverController = nil;          
    }
        
}

- (void)handleDismissedPopoverController:(UIPopoverController*)aPopoverController {
  self.popoverController = nil;
}

#pragma mark -
#pragma mark finding indicators



- (void)showFindingIndicators {
    self.progressView.hidden = YES;
    self.findingProgressView.center = self.contentView.center;
    [self.view addSubview:self.findingProgressView];
}

- (void)hideFindingIndicators {
    self.progressView.hidden = YES;
    [self.findingProgressView removeFromSuperview];    
}

- (void)showLoadingIndicators {
    if ([[UIDevice currentDevice] orientation] == UIDeviceOrientationUnknown) {
        [NSTimer scheduledTimerWithTimeInterval: 0.5
                                         target: self
                                       selector: @selector(showLoadingIndicators)
                                       userInfo: nil
                                        repeats: NO];

    } else {
        self.progressView.center = self.contentView.center;        
        self.progressView.hidden = NO;        
    }


}

- (void)hideLoadingIndicators {
    self.progressView.hidden = YES;
}




#pragma mark -
#pragma mark Managing the detail item

/*
 When setting the detail item, update the view and dismiss the popover controller if it's showing.
 */
- (void)setDetailItem:(id)newDetailItem {
    if (detailItem != newDetailItem) {
        [detailItem release];
        detailItem = [newDetailItem retain];
        
        // Update the view.
        [self configureView];
    }

    if (popoverController != nil) {
        [popoverController dismissPopoverAnimated:YES];
    }        
}


- (void)configureView {
    // Update the user interface for the detail item.
    detailDescriptionLabel.text = [detailItem description];   
}


#pragma mark -
#pragma mark Split view support

- (void)splitViewController: (UISplitViewController*)svc willHideViewController:(UIViewController *)aViewController withBarButtonItem:(UIBarButtonItem*)barButtonItem forPopoverController: (UIPopoverController*)pc {
    
    barButtonItem.title = @"Menus";
    NSMutableArray *items = [[toolbar items] mutableCopy];
    [items insertObject:barButtonItem atIndex:0];
    [toolbar setItems:items animated:YES];
    [items release];
    [self.popoverController dismissPopoverAnimated:YES];    
    self.popoverController = pc;
}


// Called when the view is shown again in the split view, invalidating the button and popover controller.
- (void)splitViewController: (UISplitViewController*)svc willShowViewController:(UIViewController *)aViewController invalidatingBarButtonItem:(UIBarButtonItem *)barButtonItem {
    
    NSMutableArray *items = [[toolbar items] mutableCopy];
    [items removeObjectAtIndex:0];
    [toolbar setItems:items animated:YES];
    [items release];
    [self.popoverController dismissPopoverAnimated:YES];    
    self.popoverController = nil;
}

- (void)splitViewController:(UISplitViewController*)svc popoverController:(UIPopoverController*)pc willPresentViewController:(UIViewController *)aViewController {
    [self.popoverController dismissPopoverAnimated:YES];    
    self.popoverController = pc;
    
    
}


#pragma mark -
#pragma mark Rotation support

// Ensure that the view controller supports rotation and that the split view can therefore show in both portrait and landscape.
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    return YES;
}

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration {
    [self adjustFrames];

}

#pragma mark -
#pragma mark Launch Website
- (IBAction)launchWebsite:(id)sender {
    NSURL *launchURL =  [NSURL URLWithString:@"http://openmbta.org"];
    if (![[UIApplication sharedApplication] openURL:launchURL])
          NSLog(@"%@%@",@"Failed to open url:",[launchURL description]);
}
 
#pragma mark -
#pragma mark View lifecycle

/*
 // Implement viewDidLoad to do additional setup after loading the view, typically from a nib.
- (void)viewDidLoad {
    [super viewDidLoad];
}
 */

/*
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
}
*/
/*
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
}
*/
/*
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
}
*/
/*
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
}
*/

- (void)viewDidUnload {
    // Release any retained subviews of the main view.
    // e.g. self.myOutlet = nil;
    [super viewDidUnload];
    self.popoverController = nil;

    // Release any retained subviews of the main view.
    // e.g. self.myOutlet = nil;
    mapViewController.detailViewController = nil;
    scheduleViewController.detailViewController = nil;
    self.findStopButton = nil;
    self.findingProgressView = nil;    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}
    

#pragma mark -
#pragma mark Memory management

/*
- (void)didReceiveMemoryWarning {
    // Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];
    
    // Release any cached data, images, etc that aren't in use.
}
*/

- (void)dealloc {
    [popoverController release];
    [toolbar release];
    
    [detailItem release];
    [detailDescriptionLabel release];
    
    self.imminentStops = nil;
    self.orderedStopIds = nil;
    self.orderedStopNames = nil;
    self.firstStops = nil;    
    self.stops = nil;
    self.regionInfo = nil;
    self.headsign = nil;
    self.routeShortName = nil;
    self.selectedStopId = nil;
    self.location = nil;
    [locationManager release];
    [operationQueue release];
    self.mapViewController = nil;
    self.scheduleViewController = nil;
    
    
    [super dealloc];
}

@end
