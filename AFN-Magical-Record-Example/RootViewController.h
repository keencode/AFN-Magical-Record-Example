//
//  ViewController.h
//  AFNetworkingCoreDataExample
//
//  Created by Yee Peng Chia on 12/27/12.
//  Copyright (c) 2012 Cocoa Star Apps. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface RootViewController : UITableViewController

@property (nonatomic, strong) IBOutlet UIBarButtonItem *refreshButton;

@property (nonatomic, strong) NSManagedObjectContext *managedObjectContext;
@property (nonatomic, strong) NSArray *posts;

//@property (nonatomic, strong) NSFetchedResultsController *fetchedResultsController;

- (IBAction)refreshButtonTouched:(id)sender;

@end
