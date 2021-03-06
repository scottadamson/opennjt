//
//  MapViewController.m
//  OpenMBTA
//
//  Created by Daniel Choi on 9/22/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "MapViewController.h"
#import "DetailViewController.h"
#import "StopAnnotation.h"
#import "ScheduleViewController.h"
#import "StopsViewController.h"
@interface MapViewController ()
- (void)showMap;
@end
@implementation MapViewController
@synthesize detailViewController, mapView, stopAnnotations, selectedStopAnnotation, triggerCalloutTimer, location, selectedStopName, initialRegion;

/*
 // The designated initializer.  Override if you create the controller programmatically and want to perform customization that is not appropriate for viewDidLoad.
- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    if ((self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil])) {
        // Custom initialization
    }
    return self;
}
*/

- (void)viewDidLoad {
    [super viewDidLoad];
    self.stopAnnotations = [NSMutableArray array];
    self.mapView.hidden = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(mapViewShouldHighlightStop:)
                                                 name:@"MBTAShouldHighlightStop" object:nil];  

}

- (void)didReceiveMemoryWarning {
    // override this so we don't lose the view if not visible 
}

- (void)mapViewShouldHighlightStop:(NSNotification *)notification {
    id sender = [notification object];
    if ([sender isEqual:self])
        return;
    NSString *stopName = [[notification userInfo] objectForKey:@"stopName"];
    [self highlightStopNamed:stopName];
    
}


- (void)viewDidUnload {
    [super viewDidUnload];
    [self.stopAnnotations removeAllObjects];
    self.detailViewController = nil;
    self.stopAnnotations = nil; 
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
}

- (void)dealloc {
    self.triggerCalloutTimer = nil;
    self.selectedStopName = nil;
    self.selectedStopAnnotation = nil;
    [super dealloc];
}

- (void)prepareMap:(NSDictionary *)regionInfo {
    [mapView removeAnnotations:self.stopAnnotations];
    [self.stopAnnotations removeAllObjects];
    
    if ([regionInfo objectForKey:@"center_lat"] == nil) 
        return;
    MKCoordinateRegion region;
    region.center.latitude = [[regionInfo objectForKey:@"center_lat"] floatValue];
    region.center.longitude = [[regionInfo objectForKey:@"center_lng"] floatValue];
    region.span.latitudeDelta = [[regionInfo objectForKey:@"lat_span"] floatValue] * 0.95;
    region.span.longitudeDelta = [[regionInfo objectForKey:@"lng_span"] floatValue] * 0.95;
    self.initialRegion = region;
    zoomInOnSelect = NO; // for ipad
    [mapView setRegion:region animated:NO];
    [mapView regionThatFits:region];
    [self showMap];
}

- (void)showMap {
    if ([[UIDevice currentDevice] orientation] == UIDeviceOrientationUnknown) {
        [NSTimer scheduledTimerWithTimeInterval: 0.5
                                         target: self
                                       selector: @selector(showMap:)
                                       userInfo: nil
                                        repeats: NO];
    } else {
        mapView.hidden = NO;
    }
    
}

- (void)annotateStops:(NSDictionary *)stops imminentStops:(NSArray *)imminentStops firstStops:(NSArray *)firstStops isRealTime:(BOOL)isRealTime {
    
    [self.mapView removeAnnotations: self.mapView.annotations];
    NSArray *stop_ids = [stops allKeys];
    for (NSString *stop_id in stop_ids) {
        StopAnnotation *annotation = [[StopAnnotation alloc] init];
        NSDictionary *stopDict = [stops objectForKey:stop_id];
        NSString *stopName =  [stopDict objectForKey:@"name"];
        annotation.subtitle = stopName;
        annotation.title = [self stopAnnotationTitle:((NSArray *)[stopDict objectForKey:@"next_arrivals"]) isRealTime:isRealTime];
        annotation.numNextArrivals = [NSNumber numberWithInt:[[stopDict objectForKey:@"next_arrivals"] count]];
        annotation.stop_id = stop_id;
        if ([imminentStops containsObject:stop_id]) {
            annotation.isNextStop = YES;
        }
        if ([firstStops containsObject:stopName]) annotation.isFirstStop = YES;
        CLLocationCoordinate2D coordinate;
        coordinate.latitude = [[stopDict objectForKey:@"lat"] doubleValue];
        coordinate.longitude = [[stopDict objectForKey:@"lng"] doubleValue];
        annotation.coordinate = coordinate;
        [self.stopAnnotations addObject:annotation];
        [annotation release];
    }
    [mapView addAnnotations:self.stopAnnotations];    
    if (!self.selectedStopAnnotation) {
        [self findNearestStop];
    }
}

-(void)mapView:(MKMapView *)mapView didAddAnnotationViews:(NSArray *)views {
     self.triggerCalloutTimer = [NSTimer scheduledTimerWithTimeInterval: 0.5
                                        target: self
                                      selector: @selector(triggerCallout:)
                                        userInfo: nil
                                        repeats: NO];
}


- (void)findNearestStop {
    self.location = mapView.userLocation.location;
    
    if (!location || [self.mapView.annotations count] < 2) {
        if (self.triggerCalloutTimer != nil)
            self.triggerCalloutTimer.invalidate;
       self.triggerCalloutTimer = [NSTimer scheduledTimerWithTimeInterval: 1.4
                                        target: self
                                       selector: @selector(findNearestStop)
                                        userInfo: nil
                                        repeats: NO];
       return;
    }

    self.selectedStopAnnotation = nil;
    self.selectedStopName = nil;
    float minDistance = -1;
    for (id annotation in self.stopAnnotations) {
        CLLocation *stopLocation = [[CLLocation alloc] initWithCoordinate:((StopAnnotation *)annotation).coordinate altitude:0 horizontalAccuracy:kCLLocationAccuracyNearestTenMeters verticalAccuracy:kCLLocationAccuracyHundredMeters timestamp:[NSDate date]];
        CLLocationDistance distance = [stopLocation distanceFromLocation:location];
        [stopLocation release];
        if ((minDistance == -1) || (distance < minDistance)) {
            self.selectedStopAnnotation = (StopAnnotation *)annotation;
            self.selectedStopName = self.selectedStopAnnotation.subtitle;
            minDistance = distance;
        } 
    }

    // Show callout of nearest stop.  We delay this to give the map time to
    // draw the pins for the stops
    if (self.triggerCalloutTimer != nil)
        self.triggerCalloutTimer.invalidate;
    [self.detailViewController showFindingIndicators];
    self.triggerCalloutTimer = [NSTimer scheduledTimerWithTimeInterval: 2.0
                                     target: self
                                   selector: @selector(triggerCallout:)
                                   userInfo: nil
                                    repeats: NO];
    
     NSDictionary *userInfo = [NSDictionary dictionaryWithObject:self.selectedStopName forKey:@"stopName"];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"MBTAShouldHighlightStop" object:self userInfo:userInfo];
}

- (void)triggerCallout:(NSDictionary *)userInfo {
    [self.detailViewController hideFindingIndicators];
    if (self.selectedStopAnnotation == nil && self.selectedStopName == nil) {
        return;
    }
    if (self.selectedStopAnnotation == nil && self.selectedStopName != nil) {
        for (id annotation in self.stopAnnotations) {
            if ( [((StopAnnotation *)annotation).subtitle isEqualToString:self.selectedStopName] ) {
                self.selectedStopAnnotation = ((StopAnnotation *)annotation);
                break;
            }
        }
    }
    
    [mapView selectAnnotation:self.selectedStopAnnotation animated:YES]; 
    self.selectedStopName = self.selectedStopAnnotation.subtitle;

}


- (NSString *)stopAnnotationTitle:(NSArray *)nextArrivals isRealTime:(BOOL)isRealTime {
    NSMutableArray *times = [NSMutableArray array];
    int count = 0;
    for (NSArray *pair in nextArrivals) {
        [times addObject:[pair objectAtIndex:0]];       
        count = count + 1;
        if (count == 4) break;
    }
    NSString *title;
    if ( [nextArrivals count] > 0 ) {
        title = [times componentsJoinedByString:@" "];
    } else {
        title = @"No more arrivals today";
    }
    return title;
}


- (MKAnnotationView *)mapView:(MKMapView *)aMapView viewForAnnotation:(id <MKAnnotation>) annotation {
    if (annotation == mapView.userLocation) return nil;
    static NSString *pinID = @"mbtaPin";
	MKPinAnnotationView *pinView =  (MKPinAnnotationView *)[mapView dequeueReusableAnnotationViewWithIdentifier:pinID];
    if (pinView == nil) {
        pinView = [[[MKPinAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:pinID] autorelease];
        //pinView.pinColor = MKPinAnnotationColorRed;
        pinView.canShowCallout = YES;
        //pinView.animatesDrop = YES; // this causes a callout bug where the callout get obscured by some pins
    }
    if ([annotation respondsToSelector:@selector(isFirstStop)] && ((StopAnnotation *)annotation).isFirstStop) {
        pinView.pinColor = MKPinAnnotationColorGreen;
    } else if ([annotation respondsToSelector:@selector(isNextStop)] && ((StopAnnotation *)annotation).isNextStop) {
        pinView.pinColor = MKPinAnnotationColorPurple;
    } else {
        pinView.pinColor = MKPinAnnotationColorRed;   
    }
	return pinView;
}

- (void)mapView:(MKMapView *)mapView didSelectAnnotationView:(MKAnnotationView *)view {
    self.triggerCalloutTimer.invalidate;
    NSString *stopName = ((StopAnnotation *)view.annotation).subtitle;
    
//    [self.detailViewController.stopsViewController selectStopNamed:stopName]; // CHANGEME for iPad
    
    [self.detailViewController.scheduleViewController highlightStopNamed:stopName showCurrentColumn:YES];
    [self.detailViewController hideFindingIndicators];
    
    
    NSDictionary *userInfo = [NSDictionary dictionaryWithObject:stopName forKey:@"stopName"];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"MBTAShouldHighlightStop" object:self userInfo:userInfo];
}

- (void)highlightStopNamed:(NSString *)stopName {
    if (stopName == nil)
        return;
    self.selectedStopAnnotation = nil;
    for (id annotation in self.stopAnnotations) {
        if ( [((StopAnnotation *)annotation).subtitle isEqualToString:stopName] ) {
            self.selectedStopAnnotation = (StopAnnotation *)annotation;
            break;
        }
    }
    [self triggerCallout:nil];
    
}


#pragma mark -
#pragma mark Rotation support

// Ensure that the view controller supports rotation and that the split view can therefore show in both portrait and landscape.
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    return YES;
}

@end
