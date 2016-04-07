//
//  ViewController.m
//  WhereIsMetro
//
//  Created by user on 15.12.15.
//  Copyright © 2015 Ivan Tikhomirov. All rights reserved.
//

#import "ViewController.h"

#define DEGREES_RADIANS(angle) ((angle) / 180.0 * M_PI)
#define PIN_SIZE_NORMAL 30
#define PIN_SIZE_SMALL 10


@interface ViewController ()

@end

MKPointAnnotation *closestMetroStationAnnotation;
MKAnnotationView *userAnnotationView;
UILabel *distanceToClosestStationLabel;
double distanceToClosestStation = 10000000.0;
double userDegrees = 0;
BOOL initialZoomCheck = YES;
float GeoAngle = 0;


@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    [self fetchMetroStationsAsJSON];
    
    self.mapView = [[MKMapView alloc] initWithFrame:self.view.frame];
    self.mapView.delegate = self;
    
    for (NSDictionary *metroStation in self.metroStations) {
        [self.mapView addAnnotation:[self annotationForStation:metroStation]];
    }
    
    self.locationManager = [[CLLocationManager alloc] init];
    self.locationManager.delegate = self;
//    self.locationManager.distanceFilter = 10;
    
    [self.locationManager startUpdatingHeading];
//    self.locationManager.headingOrientation = CLDeviceOrientationPortrait;
    self.locationManager.headingFilter = 5;
    [self.locationManager startUpdatingLocation];
    
    [self startTrackingLocation];
    
    self.currentClosestMetroStation = [[NSDictionary alloc] init];
    
    self.view.backgroundColor = [UIColor whiteColor];
    
    [self.view addSubview:self.mapView];
    self.mapView.alpha = 0;
    self.mapView.rotateEnabled = NO;
    
    NSUInteger labelHeight = 100;
    distanceToClosestStationLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, self.view.frame.size.height - labelHeight, self.view.frame.size.width, labelHeight)];
    distanceToClosestStationLabel.textAlignment = NSTextAlignmentCenter;
    UIFont *distanceFont = [UIFont systemFontOfSize:41 weight:-0.5];
    distanceToClosestStationLabel.font = distanceFont;
    
    UITapGestureRecognizer* gesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(captureClosestStationRegion)];
    [distanceToClosestStationLabel setUserInteractionEnabled:YES];
    [distanceToClosestStationLabel addGestureRecognizer:gesture];
    
    distanceToClosestStationLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    
    [self.view addSubview:distanceToClosestStationLabel];
    
    
    //Adding currentLocationButton
    NSInteger buttonSize = 44;
    NSInteger buttonCornerRadius = 12;
    self.currentLocationButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.currentLocationButton.frame = CGRectMake(buttonCornerRadius, self.view.frame.size.height - buttonSize * 1.7 , buttonSize, buttonSize);
    [self.currentLocationButton setImage:[UIImage imageNamed:@"user-icon.png"] forState:UIControlStateNormal];
    self.currentLocationButton.imageEdgeInsets = UIEdgeInsetsMake(buttonCornerRadius, buttonCornerRadius, buttonCornerRadius, buttonCornerRadius);
    self.currentLocationButton.backgroundColor = [UIColor whiteColor];
    self.currentLocationButton.layer.cornerRadius = buttonCornerRadius;
    
    [self.currentLocationButton addTarget:self action:@selector(currentLocationButtonPressed:) forControlEvents:UIControlEventTouchDown];
    [self.currentLocationButton addTarget:self action:@selector(currentLocationButtonReleased:) forControlEvents:UIControlEventTouchUpInside];
    [self.currentLocationButton addTarget:self action:@selector(currentLocationButtonReleased:) forControlEvents:UIControlEventTouchUpOutside];

    self.currentLocationButton.autoresizingMask = UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    
    [self.view addSubview:self.currentLocationButton];
    [self.currentLocationButton setHidden:YES];
    self.currentLocationButton.alpha = 0;
    
}

- (void) currentLocationButtonPressed:(UIButton*)button {
    button.transform = CGAffineTransformMakeScale(1.1, 1.1);
}

// Scale down on button release
- (void) currentLocationButtonReleased:(UIButton*)button {
    button.transform = CGAffineTransformMakeScale(1.0, 1.0);
    [self captureClosestStationRegion];
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
                if (![self.currentClosestMetroStation isEqual:metroStation]){
                    [self changeClosestStationTo:metroStation];
                }
            } else if ([self.currentClosestMetroStation isEqual:metroStation]){
                distanceToClosestStation = distance;
            }

        }
    } else{//self.metroStation == nil
        return 0;
    }
    
    return distanceToClosestStation;
}

- (MKPointAnnotation *)annotationForStation:(NSDictionary *)station{
    MKPointAnnotation *point = [[MKPointAnnotation alloc] init];
    
    CLLocationDegrees latitude = [[station objectForKey:@"lat"] doubleValue];
    CLLocationDegrees longitude = [[station objectForKey:@"lng"] doubleValue];
    NSString *name = [station objectForKey:@"name"];
    
    point.coordinate = CLLocationCoordinate2DMake(latitude, longitude);
    
    point.title = [self parseStationName:name];
    point.subtitle = [self parseLineName:name];
    
    return point;
}

- (void)changeClosestStationTo:(NSDictionary *)station{
    
    self.currentClosestMetroStation = [NSDictionary dictionaryWithDictionary:station];
    
    //changing closestMetroStationAnnotation
    
    closestMetroStationAnnotation = [self annotationForStation:station];
    
    //changing mapView region — capturing the rect with a person and a station
    
    [self captureClosestStationRegion];

}

- (void)captureClosestStationRegion{
    
    //initial check for fade in
    if (self.mapView.alpha == 0){
        [UIView animateWithDuration:0.3 animations:^{
            self.mapView.alpha = 1;
        }];
    }
    
    MKMapPoint userPoint = MKMapPointForCoordinate(self.mapView.userLocation.coordinate);
    
    double pointOffset = 0.5;
    
    MKMapRect zoomRect = MKMapRectMake(userPoint.x, userPoint.y, pointOffset, pointOffset);
    
    MKMapPoint closestMetroStationPoint = MKMapPointForCoordinate(CLLocationCoordinate2DMake([[self.currentClosestMetroStation objectForKey:@"lat"] doubleValue], [[self.currentClosestMetroStation objectForKey:@"lng"] doubleValue]));
    MKMapRect pointRect = MKMapRectMake(closestMetroStationPoint.x, closestMetroStationPoint.y, pointOffset, pointOffset);
    zoomRect = MKMapRectUnion(zoomRect, pointRect);
    
    NSUInteger inset = 50;
    UIEdgeInsets insets = UIEdgeInsetsMake(inset, inset, inset * 2, inset);
    [self.mapView setVisibleMapRect:[self.mapView mapRectThatFits:zoomRect edgePadding:insets] animated:NO];
    
    //poping up the callout view
    
    for (id<MKAnnotation> currentAnnotation in self.mapView.annotations) {
        MKPointAnnotation* annotation = currentAnnotation;
        if ([annotation.title isEqual:closestMetroStationAnnotation.title]){
            [self.mapView selectAnnotation:currentAnnotation animated:YES];
        }
    }
    
}


- (UIImage *)imageWithSize:(CGSize)size image:(UIImage *)image{
    
    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
    [image drawInRect:CGRectMake(0, 0, size.width, size.height)];
    image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    return image;
    
}

- (void)startTrackingLocation{
    if ([self.locationManager respondsToSelector:@selector(requestWhenInUseAuthorization)]) {
        [self.locationManager requestWhenInUseAuthorization];
    }
    
    CLAuthorizationStatus status = [CLLocationManager authorizationStatus];
    if (status == kCLAuthorizationStatusNotDetermined){
        return;
    }else if (status == kCLAuthorizationStatusDenied){
        [self handleLocationDeniedStatus];
    }
}


- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == 1) {
        // Send the user to the Settings for this app
        NSURL *settingsURL = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
        [[UIApplication sharedApplication] openURL:settingsURL];
        [alertView dismissWithClickedButtonIndex:0 animated:YES];
    }
}

- (void)handleLocationDeniedStatus{
    
    NSString *title = @"Location services are not enabled";
    NSString *message = @"Enable location services in settings. Without it app is useless";
    
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:title
                                                        message:message
                                                       delegate:self
                                              cancelButtonTitle:@"Cancel"
                                              otherButtonTitles:@"Settings", nil];
    [alertView show];
}




- (NSUInteger)zoomLevelForMapRect:(MKMapRect)mRect withMapViewSizeInPixels:(CGSize)viewSizeInPixels
{
    NSInteger MAXIMUM_ZOOM = 20;
    NSUInteger zoomLevel = MAXIMUM_ZOOM; // MAXIMUM_ZOOM is 20 with MapKit
    MKZoomScale zoomScale = mRect.size.width / viewSizeInPixels.width; //MKZoomScale is just a CGFloat typedef
    double zoomExponent = log2(zoomScale);
    zoomLevel = (NSUInteger)(MAXIMUM_ZOOM - ceil(zoomExponent));
    return zoomLevel;
}

#pragma mark MKMapViewDelegate methods

- (void)mapView:(MKMapView *)mapView didUpdateUserLocation:(MKUserLocation *)userLocation{
    
    distanceToClosestStationLabel.text = [NSString stringWithFormat:@"%1.0f м", [self getMinimalDistanceToMetro:userLocation]];
    
    GeoAngle = [self setLatLonForDistanceAndAngle:userLocation.location];
    
}

- (void)mapView:(MKMapView *)mapView regionDidChangeAnimated:(BOOL)animated{
    
    MKMapRect visibleMapRect = mapView.visibleMapRect;
    NSSet *visibleAnnotations = [mapView annotationsInMapRect:visibleMapRect];
    if ([visibleAnnotations containsObject:mapView.userLocation]) {
        [UIView animateWithDuration:0.3 animations:^{
            self.currentLocationButton.alpha = 0;
        } completion: ^(BOOL finished){
            self.currentLocationButton.hidden = finished;
        }];
    } else if (closestMetroStationAnnotation != nil){//userLocation is not visible
        self.currentLocationButton.hidden = NO;
        [UIView animateWithDuration:0.3 animations:^{
            self.currentLocationButton.alpha = 1;
        }];
    }
    
    //if zoomlvl is pretty high, we change M signs to small dots
    
    NSUInteger zoomLevel = [self zoomLevelForMapRect:mapView.visibleMapRect withMapViewSizeInPixels:mapView.frame.size];
    
    if (zoomLevel <= 11){
        for (id <MKAnnotation> annotation in mapView.annotations){
            MKAnnotationView* annotationView = [mapView viewForAnnotation:annotation];
            if (annotation != mapView.userLocation) {
                annotationView.image = [self imageWithSize:CGSizeMake(PIN_SIZE_SMALL, PIN_SIZE_SMALL) image:[UIImage imageNamed:@"metro-sign.png"]];
            }
        }
    } else {// normal zoomLevel
        for (id <MKAnnotation> annotation in mapView.annotations){
            MKAnnotationView* annotationView = [mapView viewForAnnotation:annotation];
            if (annotation != mapView.userLocation) {
                annotationView.image = [self imageWithSize:CGSizeMake(PIN_SIZE_NORMAL, PIN_SIZE_NORMAL) image:[UIImage imageNamed:@"metro-sign.png"]];
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
            
            pinView.image = [self imageWithSize:CGSizeMake(PIN_SIZE_NORMAL, PIN_SIZE_NORMAL) image:[UIImage imageNamed:@"metro-sign.png"]];
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
            pinView.image = [self imageWithSize:CGSizeMake(PIN_SIZE_NORMAL, PIN_SIZE_NORMAL) image:[UIImage imageNamed:@"metro-sign.png"]];
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
            
            UIImage *userImage = [UIImage imageNamed:@"user-icon.png"];
            CGSize newSize = CGSizeMake(PIN_SIZE_NORMAL, PIN_SIZE_NORMAL);
            
            pinView.image = [self imageWithSize:newSize image:userImage];
            [pinView setTransform:CGAffineTransformMakeRotation(-.001)];
        }
    }
    return pinView;
}

-(float)setLatLonForDistanceAndAngle:(CLLocation *)userlocation
{
    float lat1 = DEGREES_RADIANS(userlocation.coordinate.latitude);
    float lon1 = DEGREES_RADIANS(userlocation.coordinate.longitude);
    
    float lat2 = DEGREES_RADIANS(closestMetroStationAnnotation.coordinate.latitude);
    float lon2 = DEGREES_RADIANS(closestMetroStationAnnotation.coordinate.longitude);
    
    float dLon = lon2 - lon1;
    
    float y = sin(dLon) * cos(lat2);
    float x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
    float radiansBearing = atan2(y, x);
    if(radiansBearing < 0.0){
        radiansBearing += 2*M_PI;
    }
    
    return radiansBearing;
}


#pragma mark CCLocationManagerDelegate methods

//rotating the head of user compas with device turn
-(void)locationManager:(CLLocationManager *)manager didUpdateHeading:(CLHeading *)newHeading {
//    NSTimeInterval age = -[newHeading.timestamp timeIntervalSinceNow];
//    if (age > 120){
//        return;
//    }
//    if (newHeading.headingAccuracy < 0)
//        return;
    
    // Use the true heading if it is valid.

    if (newHeading.trueHeading < 0){
        return;
    }
    
    CLLocationDirection direction = newHeading.trueHeading + 180; // + 180 to rotate user icon. It is heading to the bottom by default
        for (id <MKAnnotation> currentAnnotation in self.mapView.annotations) {
        if (currentAnnotation == self.mapView.userLocation) {
            
            self.mapView.userLocation.title = @"Вы здесь";
            
            MKAnnotationView* annotationView = [self.mapView viewForAnnotation:currentAnnotation];
            
            [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
//                [annotationView setTransform:CGAffineTransformMakeRotation(DEGREES_RADIANS(direction + 45) + GeoAngle)];
                [annotationView setTransform:CGAffineTransformMakeRotation(DEGREES_RADIANS(direction))];
            } completion:nil];

        }
    }
}

-(void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status{
    if (status == kCLAuthorizationStatusAuthorizedWhenInUse ||
        status == kCLAuthorizationStatusAuthorized) {
        
        self.mapView.showsUserLocation = YES;
        
    } else{
        //Person refused to give access to geoposition
        self.mapView.showsUserLocation = NO;
        if (self.mapView.alpha == 0){
            [UIView animateWithDuration:0.3 animations:^{
                self.mapView.alpha = 1;
            }];
        }
        self.mapView.centerCoordinate = CLLocationCoordinate2DMake(55.7522222, 37.6155556);//Moscow center
        MKCoordinateRegion viewRegion = MKCoordinateRegionMakeWithDistance(self.mapView.centerCoordinate, 12000, 12000);//showing overview of Moscow
        MKCoordinateRegion adjustedRegion = [self.mapView regionThatFits:viewRegion];
        [self.mapView setRegion:adjustedRegion animated:YES];
        
    }
}

@end
