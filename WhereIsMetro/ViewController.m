//
//  ViewController.m
//  WhereIsMetro
//
//  Created by user on 15.12.15.
//  Copyright © 2015 Ivan Tikhomirov. All rights reserved.
//

#import "ViewController.h"

#define DEGREES_RADIANS(angle) ((angle) / 180.0 * M_PI)

@interface ViewController ()

@end

bool trackingFirstTime = YES;
bool mapDidLoadedFirstTIme = NO;
MKPointAnnotation *closestMetroStationAnnotation;
MKAnnotationView *userAnnotationView;
UILabel *distanceToClosestStationLabel;
double distanceToClosestStation = 10000000.0;

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    self.mapView = [[MKMapView alloc] initWithFrame:self.view.frame];
    self.mapView.delegate = self;
    
    self.locationManager = [[CLLocationManager alloc] init];
    self.locationManager.delegate = self;
    
    self.currentClosestMetroStation = [[NSDictionary alloc] init];
    
    if ([self.locationManager respondsToSelector:@selector(requestWhenInUseAuthorization)]) {
        [self.locationManager requestWhenInUseAuthorization];
    }
    
    CLAuthorizationStatus authorizationStatus = [CLLocationManager authorizationStatus];
    
    if (authorizationStatus == kCLAuthorizationStatusAuthorizedAlways ||
        authorizationStatus == kCLAuthorizationStatusAuthorizedAlways ||
        authorizationStatus == kCLAuthorizationStatusAuthorizedWhenInUse) {
        
        [self.locationManager startUpdatingHeading];
        [self.locationManager startUpdatingLocation];
        self.mapView.showsUserLocation = YES;
    } else{
        //Person refused to give access to geoposition
    }
    
    [self.view addSubview:self.mapView];
    
    
    NSUInteger labelHeight = 100;
    distanceToClosestStationLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, self.view.frame.size.height - labelHeight, self.view.frame.size.width, labelHeight)];
    distanceToClosestStationLabel.textAlignment = NSTextAlignmentCenter;
    UIFont *distanceFont = [UIFont systemFontOfSize:41 weight:UIFontWeightLight];
    distanceToClosestStationLabel.font = distanceFont;
    
    [self.view addSubview:distanceToClosestStationLabel];
    
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)fetchMetroStationsAsJSON{
    NSString *jsonPath = [[NSBundle mainBundle] pathForResource:@"metro-list" ofType:@"json"];
    NSError* error;
    NSData *jsonData = [NSData dataWithContentsOfFile:jsonPath];
    
    self.metroStations = [NSJSONSerialization
                          JSONObjectWithData:jsonData
                          options:kNilOptions
                          error:&error];
}

- (NSString *)parseLineName:(NSString *)jsonMetroName{
    NSRange range = [jsonMetroName rangeOfString:@"," options:NSCaseInsensitiveSearch];
    return [jsonMetroName substringToIndex:NSMaxRange(range) - 1];
}

- (NSString *)parseStationName:(NSString *)jsonMetroName{
    NSUInteger start = NSMaxRange([jsonMetroName rangeOfString:@"метро " options:NSCaseInsensitiveSearch]);
    
    if (start > 1000){//We didn't find any @"метро " there
        //Канатная дорога,
        start = NSMaxRange([jsonMetroName rangeOfString:@"Канатная дорога, " options:NSCaseInsensitiveSearch]);
    }
    
    NSRange range = NSMakeRange(start, jsonMetroName.length - start);
    return [jsonMetroName substringWithRange:range];
}

- (double)getMinimalDistanceToMetro:(MKUserLocation *)userLocation{
    
    double distance = 0;
    
    CLLocation *userCoordinates = [[CLLocation alloc] initWithLatitude:
                                   self.mapView.userLocation.coordinate.latitude
                                                             longitude:self.mapView.userLocation.coordinate.longitude];
    
    
    
    if (self.metroStations != nil){
        
        for (NSDictionary *metroStation in self.metroStations) {
            
            CLLocationDegrees latitude = [[metroStation objectForKey:@"lat"] doubleValue];
            CLLocationDegrees longitude = [[metroStation objectForKey:@"lng"] doubleValue];
            
            CLLocation *stationLocation = [[CLLocation alloc] initWithLatitude:latitude longitude:longitude];
            
            CLLocationDistance distance = [userCoordinates distanceFromLocation:stationLocation];
            
            if (distanceToClosestStation > distance){
                distanceToClosestStation = distance;
                [self changeClosestStationTo:metroStation];
            } else if ([self.currentClosestMetroStation isEqual:metroStation]){//getting away from nearest station, but not close enough for a different metro station
                distanceToClosestStation = distance;
            }
        }
    }
    
    return distance;
    
}

- (void)changeClosestStationTo:(NSDictionary *)station{
    
    self.currentClosestMetroStation = [NSDictionary dictionaryWithDictionary:station];
    
    MKMapPoint userPoint = MKMapPointForCoordinate(self.mapView.userLocation.coordinate);
    
    double pointOffset = 0.5;
    
    MKMapRect zoomRect = MKMapRectMake(userPoint.x, userPoint.y, pointOffset, pointOffset);
    
    
    MKMapPoint closestMetroStationPoint = MKMapPointForCoordinate(CLLocationCoordinate2DMake([[station objectForKey:@"lat"] doubleValue], [[station objectForKey:@"lng"] doubleValue]));
    MKMapRect pointRect = MKMapRectMake(closestMetroStationPoint.x, closestMetroStationPoint.y, pointOffset, pointOffset);
    zoomRect = MKMapRectUnion(zoomRect, pointRect);
    
    NSUInteger inset = 50;
    UIEdgeInsets insets = UIEdgeInsetsMake(inset, inset, inset * 2, inset);
    [self.mapView setVisibleMapRect:[self.mapView mapRectThatFits:zoomRect edgePadding:insets] animated:NO];
    
}


#pragma mark MKMapViewDelegate methods

- (void)mapView:(MKMapView *)mapView didUpdateUserLocation:(MKUserLocation *)userLocation{
    
    CLLocation *userCoordinates = [[CLLocation alloc] initWithLatitude:
                                   self.mapView.userLocation.coordinate.latitude
                                                             longitude:self.mapView.userLocation.coordinate.longitude];
    
    if (trackingFirstTime){
        
        trackingFirstTime = NO;

        [self fetchMetroStationsAsJSON];
        
        NSDictionary *closestMetroStation = [[NSDictionary alloc] init];
        CLLocationDistance distanceToClosest = 100000000.0;
        
        for (NSDictionary *metroStation in self.metroStations) {
            CLLocationDegrees latitude = [[metroStation objectForKey:@"lat"] doubleValue];
            CLLocationDegrees longitude = [[metroStation objectForKey:@"lng"] doubleValue];
            NSString *name = [metroStation objectForKey:@"name"];
            
            
            MKPointAnnotation *point = [[MKPointAnnotation alloc] init];
            point.coordinate = CLLocationCoordinate2DMake(latitude, longitude);
            
            point.title = [self parseStationName:name];
            point.subtitle = [self parseLineName:name];
            
            [mapView addAnnotation:point];
            
            CLLocation *stationLocation = [[CLLocation alloc] initWithLatitude:latitude longitude:longitude];
            
            CLLocationDistance distance = [userCoordinates distanceFromLocation:stationLocation];
            
            if (distanceToClosest > distance){
                distanceToClosest = distance;
                distanceToClosestStation = distance;
                closestMetroStation = [NSDictionary dictionaryWithDictionary:metroStation];
                self.currentClosestMetroStation = [NSDictionary dictionaryWithDictionary:closestMetroStation];
                closestMetroStationAnnotation = point;
            }
        }
        
        MKMapPoint userPoint = MKMapPointForCoordinate(mapView.userLocation.coordinate);
        
        double pointOffset = 0.5;
        
        MKMapRect zoomRect = MKMapRectMake(userPoint.x, userPoint.y, pointOffset, pointOffset);
        
        
        MKMapPoint closestMetroStationPoint = MKMapPointForCoordinate(CLLocationCoordinate2DMake([[closestMetroStation objectForKey:@"lat"] doubleValue], [[closestMetroStation objectForKey:@"lng"] doubleValue]));
        MKMapRect pointRect = MKMapRectMake(closestMetroStationPoint.x, closestMetroStationPoint.y, pointOffset, pointOffset);
        zoomRect = MKMapRectUnion(zoomRect, pointRect);
        
        NSUInteger inset = 50;
        UIEdgeInsets insets = UIEdgeInsetsMake(inset, inset, inset * 2, inset);
        [mapView setVisibleMapRect:[self.mapView mapRectThatFits:zoomRect edgePadding:insets] animated:NO];
        
        return;
    }
    
    for (NSDictionary *metroStation in self.metroStations) {
        CLLocationDegrees latitude = [[metroStation objectForKey:@"lat"] doubleValue];
        CLLocationDegrees longitude = [[metroStation objectForKey:@"lng"] doubleValue];
        
        CLLocation *stationLocation = [[CLLocation alloc] initWithLatitude:latitude longitude:longitude];
        
        CLLocationDistance distance = [userCoordinates distanceFromLocation:stationLocation];
        
        if (distanceToClosestStation > distance){
            distanceToClosestStation = distance;
            self.currentClosestMetroStation = [NSDictionary dictionaryWithDictionary:metroStation];
        }
    }
    
    distanceToClosestStationLabel.text = [NSString stringWithFormat:@"%1.0f м.", distanceToClosestStation];
    
}

- (void)mapViewDidFinishLoadingMap:(MKMapView *)mapView{
    if (!mapDidLoadedFirstTIme){
        mapDidLoadedFirstTIme = YES;
        for (id<MKAnnotation> currentAnnotation in mapView.annotations) {
            if ([currentAnnotation isEqual:closestMetroStationAnnotation]) {
                [mapView selectAnnotation:currentAnnotation animated:YES];
            }
        }
    }
}


-(MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id <MKAnnotation>)annotation
{
    MKAnnotationView *pinView = nil;
    if(annotation != mapView.userLocation)
    {
        static NSString *defaultPinID = @"MetroStationPinID";
        pinView = (MKAnnotationView *)[mapView dequeueReusableAnnotationViewWithIdentifier:defaultPinID];
        if ( pinView == nil ){
            pinView = [[MKAnnotationView alloc]
                       initWithAnnotation:annotation reuseIdentifier:defaultPinID];
        pinView.canShowCallout = YES;
        pinView.image = [UIImage imageNamed:@"metro-logo.png"];
        }
    }
    else if ([annotation isEqual:closestMetroStationAnnotation]){
        //closest annotation annotation
        static NSString *closestPinID = @"ClosestMetroStationPinID";
        pinView = (MKAnnotationView *)[mapView dequeueReusableAnnotationViewWithIdentifier:closestPinID];
        if ( pinView == nil ){
            pinView = [[MKAnnotationView alloc]
                       initWithAnnotation:annotation reuseIdentifier:closestPinID];
            pinView.canShowCallout = YES;
            //TO-DO — image for closest station
            pinView.image = [UIImage imageNamed:@"metro-logo.png"];
        }
    }
    else{
        //user pin
        static NSString *userPinID = @"userPinID";
        pinView = (MKAnnotationView *)[mapView dequeueReusableAnnotationViewWithIdentifier:userPinID];
        if ( pinView == nil ){
            pinView = [[MKAnnotationView alloc]
                       initWithAnnotation:annotation reuseIdentifier:userPinID];
            pinView.canShowCallout = YES;
            //TO-DO — image compass for user
            pinView.image = [UIImage imageNamed:@"metro-logo.png"];
            [pinView setTransform:CGAffineTransformMakeRotation(.001)];
        }
    }
    return pinView;
}

#pragma mark CCLocationManagerDelegate methods

-(void)locationManager:(CLLocationManager *)manager didUpdateHeading:(CLHeading *)newHeading {
    CLLocationDirection direction = newHeading.magneticHeading;
    for (id <MKAnnotation> currentAnnotation in self.mapView.annotations) {
        if (currentAnnotation == self.mapView.userLocation) {
            MKAnnotationView* annotationView = [self.mapView viewForAnnotation:currentAnnotation];
            
            [UIView animateWithDuration:0.5 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
                
                [annotationView setTransform:CGAffineTransformMakeRotation(DEGREES_RADIANS(direction))];
            } completion:nil];
//            [annotationView setTransform:CGAffineTransformMakeRotation(DEGREES_RADIANS(direction))];
        }
    }
}

@end
