//
//  ViewController.m
//  AFNetworkingCoreDataExample
//
//  Created by Yee Peng Chia on 12/27/12.
//  Copyright (c) 2012 Cocoa Star Apps. All rights reserved.
//

#import "RootViewController.h"
//#import "AFNCoreDataController.h"
#import "AFNSyncEngine.h"
#import "Post.h"
#import "User.h"
#import "PostTableViewCell.h"

@interface RootViewController ()

- (void)loadRecordsFromCoreData;
- (void)checkSyncStatus;
- (void)replaceRefreshButtonWithActivityIndicator;
- (void)removeActivityIndicatorFromRefreshButton;

@end


@implementation RootViewController

@synthesize refreshButton;
@synthesize managedObjectContext = _managedObjectContext;
@synthesize posts = _posts;
//@synthesize fetchedResultsController = _fetchedResultsController;


#pragma mark - View lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.posts = [NSArray array];
    
    self.managedObjectContext = [NSManagedObjectContext MR_contextForCurrentThread];
    
    [self loadRecordsFromCoreData];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:kAFNSyncEngineSyncCompletedNotificationName
                                                      object:nil
                                                       queue:nil
                                                  usingBlock:^(NSNotification *note) {
                                                      [self loadRecordsFromCoreData];
                                                      [self.tableView reloadData];
                                                  }];
    
    [[AFNSyncEngine sharedEngine] addObserver:self forKeyPath:@"syncInProgress"
                                      options:NSKeyValueObservingOptionNew
                                      context:nil];
}

- (void)viewDidDisappear:(BOOL)animated
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kAFNSyncEngineSyncCompletedNotificationName object:nil];
    
    [[AFNSyncEngine sharedEngine] removeObserver:self forKeyPath:@"syncInProgress"];
 
    [super viewDidDisappear:animated];
}


#pragma mark - IBActions

- (IBAction)refreshButtonTouched:(id)sender
{
    [[AFNSyncEngine sharedEngine] startSync];
}


#pragma mark - Data loading

- (void)loadRecordsFromCoreData
{
//    [self.managedObjectContext performBlockAndWait:^{
//        [self.managedObjectContext reset];
//        NSError *error = nil;
//        NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"Post"];
//        [request setSortDescriptors:[NSArray arrayWithObject:[NSSortDescriptor sortDescriptorWithKey:@"createdAt" ascending:NO]]];
//        self.posts = [self.managedObjectContext executeFetchRequest:request error:&error];
//        NSLog(@"loadRecordsFromCoreData:%@", self.posts);
//    }];
    
    [self.managedObjectContext reset];
    
    self.posts = [Post MR_findAllSortedBy:@"createdAt"
                                ascending:NO
                            withPredicate:nil
                                inContext:self.managedObjectContext];
    
    NSLog(@"loadRecordsFromCoreData:posts:%@", self.posts);
}


#pragma mark - Key-Value observation

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ([keyPath isEqualToString:@"syncInProgress"]) {
        [self checkSyncStatus];
    }
}


#pragma mark - Sync status

- (void)checkSyncStatus
{
    if ([[AFNSyncEngine sharedEngine] syncInProgress]) {
        [self replaceRefreshButtonWithActivityIndicator];
    } else {
        [self removeActivityIndicatorFromRefreshButton];
    }
}

- (void)replaceRefreshButtonWithActivityIndicator
{
    UIActivityIndicatorView *activityIndicator = [[UIActivityIndicatorView alloc] initWithFrame:CGRectMake(0, 0, 25, 25)];
    [activityIndicator setAutoresizingMask:(UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin)];
    [activityIndicator startAnimating];
    UIBarButtonItem *activityItem = [[UIBarButtonItem alloc] initWithCustomView:activityIndicator];
    self.navigationItem.rightBarButtonItem = activityItem;
}

- (void)removeActivityIndicatorFromRefreshButton
{
    self.navigationItem.rightBarButtonItem = self.refreshButton;
}


#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [self.posts count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *CellIdentifier = @"PostCell";
    
    PostTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];

    Post *post = [self.posts objectAtIndex:indexPath.row];
//    NSLog(@"created at:%@", post.createdAt);
    
    User *user = (User *)post.user;
    cell.nameLabel.text = user.username;
    
    cell.textLabel.text = post.text;
    
    [cell.imageView setImageWithURL:[NSURL URLWithString:user.avatarImageSrc]
                   placeholderImage:[UIImage imageNamed:@"profile-image-placeholder.png"]];
    return cell;
}


#pragma mark - UITableViewDelegate

//- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
//{
//    return [PostTableViewCell heightForCellWithPost:[_posts objectAtIndex:indexPath.row]];
//}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}


#pragma mark - NSFetchedResultsController Delegate Methods

- (void)controllerWillChangeContent:(NSFetchedResultsController *)controller
{
    // The fetch controller is about to start sending change notifications, so prepare the table view for updates.
    [self.tableView beginUpdates];
}

- (void)controller:(NSFetchedResultsController *)controller didChangeObject:(id)anObject atIndexPath:(NSIndexPath *)indexPath forChangeType:(NSFetchedResultsChangeType)type newIndexPath:(NSIndexPath *)newIndexPath
{
    UITableView *tableView = self.tableView;
    
    switch(type)
    {
        case NSFetchedResultsChangeInsert:
            [tableView insertRowsAtIndexPaths:[NSArray arrayWithObject:newIndexPath] withRowAnimation:UITableViewRowAnimationFade];
            break;
            
        case NSFetchedResultsChangeDelete:
            [tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationFade];
            break;
            
        case NSFetchedResultsChangeUpdate:
//            [self configureCell:[tableView cellForRowAtIndexPath:indexPath] atIndexPath:indexPath];
            break;
            
        case NSFetchedResultsChangeMove:
            [tableView deleteRowsAtIndexPaths:[NSArray
                                               arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationFade];
            [tableView insertRowsAtIndexPaths:[NSArray
                                               arrayWithObject:newIndexPath] withRowAnimation:UITableViewRowAnimationFade];
            break;
    }
}

- (void)controller:(NSFetchedResultsController *)controller didChangeSection:(id <NSFetchedResultsSectionInfo>)sectionInfo atIndex:(NSUInteger)sectionIndex forChangeType:(NSFetchedResultsChangeType)type
{
    
    switch(type)
    {
        case NSFetchedResultsChangeInsert:
            [self.tableView insertSections:[NSIndexSet indexSetWithIndex:sectionIndex] withRowAnimation:UITableViewRowAnimationFade];
            break;
            
        case NSFetchedResultsChangeDelete:
            [self.tableView deleteSections:[NSIndexSet indexSetWithIndex:sectionIndex] withRowAnimation:UITableViewRowAnimationFade];
            break;
    }
}

- (void)controllerDidChangeContent:(NSFetchedResultsController *)controller
{
    // The fetch controller has sent all current change notifications, so tell the table view to process all updates.
    [self.tableView endUpdates];
}

@end
