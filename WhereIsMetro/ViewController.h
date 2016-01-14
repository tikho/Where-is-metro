//
//  ViewController.h
//  WhereIsMetro
//
//  Created by user on 15.12.15.
//  Copyright © 2015 Ivan Tikhomirov. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <MapKit/MapKit.h>
#import <CoreLocation/CoreLocation.h>

@interface ViewController : UIViewController <MKMapViewDelegate, CLLocationManagerDelegate>

@property (nonatomic, strong) MKMapView *mapView;
@property (nonatomic, strong) NSArray *metroStations;
@property (strong, nonatomic) CLLocationManager *locationManager;
@property (nonatomic, strong) NSDictionary *currentClosestMetroStation;


@end

