//
//  SDSyncEngine.m
//  SignificantDates
//
//  Created by Yee Peng Chia on 12/20/12.
//
//

#import "AFNSyncEngine.h"
#import "AFNAppDotNetClient.h"
#import "Post.h"
#import "User.h"

NSString * const kAFNSyncEngineInitialCompleteKey = @"AFNSyncEngineInitialSyncCompleted";
NSString * const kAFNSyncEngineSyncCompletedNotificationName = @"AFNSyncEngineSyncCompleted";
NSString * const kPostIDKey = @"postID";


@interface AFNSyncEngine ()

@property (nonatomic, strong) NSManagedObjectContext *masterMOC;
@property (nonatomic, strong) NSManagedObjectContext *backgroundMOC;
@property (nonatomic, strong) NSManagedObjectContext *privateWriterMOC;
@property (nonatomic, strong) NSMutableArray *registeredClassesToSync;
@property (nonatomic, strong) NSDateFormatter *dateFormatter;

- (void)downloadDataForRegisteredObjects;

@end


@implementation AFNSyncEngine

@synthesize masterMOC = _masterMOC;
@synthesize backgroundMOC = _backgroundMOC;
@synthesize privateWriterMOC = _privateWriterMOC;
@synthesize registeredClassesToSync = _registeredClassesToSync;
@synthesize syncInProgress = _syncInProgress;
@synthesize dateFormatter = _dateFormatter;


#pragma mark - Initialization

+ (AFNSyncEngine *)sharedEngine
{
    static AFNSyncEngine *sharedEngine = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedEngine = [[AFNSyncEngine alloc] init];
    });
    
    return sharedEngine;
}


#pragma mark - Initial sync

- (void)registerNSManagedObjectClassToSync:(Class)aClass
{
    if (!self.registeredClassesToSync) {
        self.registeredClassesToSync = [NSMutableArray array];
    }
    
    if ([aClass isSubclassOfClass:[NSManagedObject class]]) {
        if (![self.registeredClassesToSync containsObject:NSStringFromClass(aClass)]) {
            [self.registeredClassesToSync addObject:NSStringFromClass(aClass)];
        } else {
            NSLog(@"Unable to register %@ as it is already registered", NSStringFromClass(aClass));
        }
    } else {
        NSLog(@"Unable to register %@ as it is not a subclass of NSManagedObject", NSStringFromClass(aClass));
    }
    
}

- (BOOL)initialSyncComplete
{
    return [[[NSUserDefaults standardUserDefaults] valueForKey:kAFNSyncEngineInitialCompleteKey] boolValue];
}

- (void)setInitialSyncCompleted
{
    [[NSUserDefaults standardUserDefaults] setValue:[NSNumber numberWithBool:YES] forKey:kAFNSyncEngineInitialCompleteKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)executeSyncCompletedOperations
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self setInitialSyncCompleted];
        
        [[NSNotificationCenter defaultCenter] postNotificationName:kAFNSyncEngineSyncCompletedNotificationName
                                                            object:nil];
        
        [self willChangeValueForKey:@"syncInProgress"];
        _syncInProgress = NO;
        [self didChangeValueForKey:@"syncInProgress"];
    });
}

- (void)startSync
{
    if (!self.syncInProgress) {
        [self willChangeValueForKey:@"syncInProgress"];
        _syncInProgress = YES;
        [self didChangeValueForKey:@"syncInProgress"];
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
            [self downloadDataForRegisteredObjects];
        });
    }
}


#pragma mark - Download data

- (void)downloadDataForRegisteredObjects
{
    NSMutableArray *operations = [NSMutableArray array];
    
    for (NSString *className in self.registeredClassesToSync) {
        NSMutableURLRequest *request = [[AFNAppDotNetClient sharedClient] GETRequestForAllRecordsOfClass:className];

        AFHTTPRequestOperation *operation = [[AFNAppDotNetClient sharedClient] HTTPRequestOperationWithRequest:request
           success:^(AFHTTPRequestOperation *operation, id responseObject) {
               if ([responseObject isKindOfClass:[NSDictionary class]]) {
                   [self writeJSONResponse:responseObject toDiskForClassWithName:className];
               }
           } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
               NSLog(@"Request for class %@ failed with error: %@", className, error);
        }];
        
        [operations addObject:operation];
    }
    
    [[AFNAppDotNetClient sharedClient] enqueueBatchOfHTTPRequestOperations:operations
         progressBlock:^(NSUInteger numberOfCompletedOperations, NSUInteger totalNumberOfOperations) {
             // Do something?
         } completionBlock:^(NSArray *operations) {
             NSLog(@"All operations completed");
             [self processJSONDataRecordsIntoCoreData];
    }];
}


#pragma mark - Process JSON data

- (void)processJSONDataRecordsIntoCoreData
{
    //
    // Iterate over all registered classes to sync
    //
    for (NSString *className in self.registeredClassesToSync) {
        if (![self initialSyncComplete]) { // import all downloaded data to Core Data for initial sync
            //
            // If this is the initial sync then the logic is pretty simple, you will fetch the JSON data from disk
            // for the class of the current iteration and create new NSManagedObjects for each record
            //
            NSDictionary *JSONDictionary = [self JSONDictionaryForClassWithName:className];
            NSArray *records = [JSONDictionary objectForKey:@"data"];
            
            for (NSDictionary *record in records) {
                [self newManagedObjectWithClassName:className forRecord:record];
            }
        } else {
            //
            // Otherwise you need to do some more logic to determine if the record is new or has been updated.
            // First get the downloaded records from the JSON response, verify there is at least one object in
            // the data, and then fetch all records stored in Core Data whose objectId matches those from the JSON response.
            //
            NSArray *downloadedRecords = [self JSONDataRecordsForClass:className sortedByKey:@"id"];
            if ([downloadedRecords lastObject]) {
                //
                // Now you have a set of objects from the remote service and all of the matching objects
                // (based on objectId) from your Core Data store. Iterate over all of the downloaded records
                // from the remote service.
                //
                NSArray *storedRecords = [self managedObjectsForClass:className
                                                          sortedByKey:kPostIDKey
                                                      usingArrayOfIds:[downloadedRecords valueForKey:@"id"]
                                                         inArrayOfIds:YES];
                int currentIndex = 0;
                //
                // If the number of records in your Core Data store is less than the currentIndex, you know that
                // you have a potential match between the downloaded records and stored records because you sorted
                // both lists by objectId, this means that an update has come in from the remote service
                //
                for (NSDictionary *record in downloadedRecords) {
                    NSManagedObject *storedManagedObject = nil;
                    
                    if ([storedRecords count] > currentIndex) {
                        //
                        // Do a quick spot check to validate the objectIds in fact do match, if they do update the stored
                        // object with the values received from the remote service
                        //
                        storedManagedObject = [storedRecords objectAtIndex:currentIndex];
                    }
                    
                    if ([[storedManagedObject valueForKey:kPostIDKey] isEqualToString:[record valueForKey:@"id"]]) {
                        //
                        // Otherwise you have a new object coming in from your remote service so create a new
                        // NSManagedObject to represent this remote object locally
                        //
                        [self updateManagedObject:[storedRecords objectAtIndex:currentIndex] withRecord:record];
                    } else {
                        [self newManagedObjectWithClassName:className forRecord:record];
                    }
                    currentIndex++;
                }
            }
        }
        //
        // Once all NSManagedObjects are created in your context you can save the context to persist the objects
        // to your persistent store. In this case though you used an NSManagedObjectContext who has a parent context
        // so all changes will be pushed to the parent context
        //
        [self.backgroundMOC MR_saveNestedContextsErrorHandler:^(NSError *error) {
                NSLog(@"error saving to backgroundMOC:%@", [error userInfo]);
            } completion:^{
                NSLog(@"context saved!");
                // You are now done with the downloaded JSON responses so you can delete them to clean up after yourself,
                // then call your -executeSyncCompletedOperations to save off your master context and set the
                // syncInProgress flag to NO
                //
                [self deleteJSONDataRecordsForClassWithName:className];
                [self executeSyncCompletedOperations];
            }];        
    }
}


#pragma mark -  JSON data methods

- (NSDictionary *)JSONDictionaryForClassWithName:(NSString *)className
{
    NSURL *fileURL = [NSURL URLWithString:className relativeToURL:[self JSONDataRecordsDirectory]];
    return [NSDictionary dictionaryWithContentsOfURL:fileURL];
}

- (NSArray *)JSONDataRecordsForClass:(NSString *)className sortedByKey:(NSString *)key
{
    NSDictionary *JSONDictionary = [self JSONDictionaryForClassWithName:className];
    NSArray *records = [JSONDictionary objectForKey:@"data"];
    return [records sortedArrayUsingDescriptors:[NSArray arrayWithObject:
                                                 [NSSortDescriptor sortDescriptorWithKey:key ascending:YES]]];
}

- (void)deleteJSONDataRecordsForClassWithName:(NSString *)className
{
    NSURL *url = [NSURL URLWithString:className relativeToURL:[self JSONDataRecordsDirectory]];
    NSError *error = nil;
    BOOL deleted = [[NSFileManager defaultManager] removeItemAtURL:url error:&error];
    if (!deleted) {
        NSLog(@"Unable to delete JSON Records at %@, reason: %@", url, error);
    }
}


#pragma mark - Managed Objects methods

- (NSManagedObject *)newManagedObjectWithClassName:(NSString *)className forRecord:(NSDictionary *)record
{
    NSManagedObject *newManagedObject = nil;
    
    if ([className isEqualToString:@"Post"]) {
        newManagedObject = [Post createInContext:self.backgroundMOC];        
    } else if ([className isEqualToString:@"User"]) {
        newManagedObject = [User createInContext:self.backgroundMOC];
    }
    
    
    [record enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        [self setValue:obj forKey:key forManagedObject:newManagedObject];
    }];
    
    [record setValue:[NSNumber numberWithInt:AFNObjectSynced] forKey:@"syncStatus"];
    
    //    NSLog(@"newManagedObjectWithClassName:%@", newManagedObject);
    return newManagedObject;
}

- (void)updateManagedObject:(NSManagedObject *)managedObject withRecord:(NSDictionary *)record
{
    [record enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        [self setValue:obj forKey:key forManagedObject:managedObject];
    }];
}

- (void)setValue:(id)value forKey:(NSString *)key forManagedObject:(NSManagedObject *)managedObject
{
    if ([managedObject.entity.name isEqualToString:@"Post"]) {
        if ([key isEqualToString:@"created_at"]) {
            NSDate *date = [self dateUsingStringFromAPI:value];
            [managedObject setValue:date forKey:@"createdAt"];
            
        } else if ([key isEqualToString:@"id"]) {
            [managedObject setValue:value forKey:kPostIDKey];
            
        } else if ([key isEqualToString:@"text"]) {
            [managedObject setValue:value forKey:key];
            
        } else if ([key isEqualToString:@"user"]) {
            if ([value isKindOfClass:[NSDictionary class]]) {
                NSManagedObject *user = [self newManagedObjectWithClassName:@"User" forRecord:value];
                [managedObject setValue:user forKey:@"user"];
            }
        }
    } else if ([managedObject.entity.name isEqualToString:@"User"]) {
        if ([key isEqualToString:@"created_at"]) {
            NSDate *date = [self dateUsingStringFromAPI:value];
            [managedObject setValue:date forKey:@"createdAt"];
            
        } else if ([key isEqualToString:@"id"]) {
            [managedObject setValue:value forKey:@"userID"];
            
        } else if ([key isEqualToString:@"username"]) {
            [managedObject setValue:value forKey:key];
            
        } else if ([key isEqualToString:@"avatar_image"]) {
            NSString *imageSrc = [value objectForKey:@"url"];
            [managedObject setValue:imageSrc forKey:@"avatarImageSrc"];
        }
    }
}

- (NSArray *)managedObjectsForClass:(NSString *)className sortedByKey:(NSString *)key usingArrayOfIds:(NSArray *)idArray
                       inArrayOfIds:(BOOL)inIds
{
    NSPredicate *predicate = nil;
    if (inIds) {
        predicate = [NSPredicate predicateWithFormat:@"postID IN %@", idArray];
    } else {
        predicate = [NSPredicate predicateWithFormat:@"NOT (postID IN %@)", idArray];
    }

    NSArray *results = [Post findAllSortedBy:@"postID"
                                   ascending:YES
                               withPredicate:predicate
                                   inContext:self.backgroundMOC];
    return results;
}


#pragma mark - Managed Object Contexts

- (NSManagedObjectContext *)masterMOC
{
    if (_masterMOC != nil) {
        return _masterMOC;
    }
    
    _masterMOC = [NSManagedObjectContext defaultContext];
    return _masterMOC;
}

// Return the NSManagedObjectContext to be used in the background during sync
- (NSManagedObjectContext *)backgroundMOC
{
    if (_backgroundMOC != nil) {
        return _backgroundMOC;
    }
    
    _backgroundMOC = [NSManagedObjectContext contextWithParent:self.masterMOC];
    return _backgroundMOC;
}

- (NSManagedObjectContext *)privateWriterMOC
{
    if (_privateWriterMOC != nil) {
        return _privateWriterMOC;
    }
    
    _privateWriterMOC = [NSManagedObjectContext rootSavingContext];
    return _privateWriterMOC;
}


#pragma mark - Date formatting

- (void)initializeDateFormatter
{
    if (!self.dateFormatter) {
        self.dateFormatter = [[NSDateFormatter alloc] init];
        [self.dateFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss'Z'"];
        [self.dateFormatter setTimeZone:[NSTimeZone timeZoneWithName:@"GMT"]];
    }
}

- (NSDate *)dateUsingStringFromAPI:(NSString *)dateString
{    
    [self initializeDateFormatter];
    
    return [self.dateFormatter dateFromString:dateString];
}

- (NSString *)dateStringForAPIUsingDate:(NSDate *)date
{
    [self initializeDateFormatter];
    NSString *dateString = [self.dateFormatter stringFromDate:date];
    // remove Z
    dateString = [dateString substringWithRange:NSMakeRange(0, [dateString length]-1)];
    // add milliseconds and put Z back on
    dateString = [dateString stringByAppendingFormat:@".000Z"];
    
    return dateString;
}


#pragma mark - File Management

- (NSURL *)applicationCacheDirectory
{
    return [[[NSFileManager defaultManager] URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask] lastObject];
}

- (NSURL *)JSONDataRecordsDirectory
{    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *url = [NSURL URLWithString:@"JSONRecords/" relativeToURL:[self applicationCacheDirectory]];
    NSError *error = nil;
    if (![fileManager fileExistsAtPath:[url path]]) {
        [fileManager createDirectoryAtPath:[url path] withIntermediateDirectories:YES attributes:nil error:&error];
    }
    
    return url;
}

- (void)writeJSONResponse:(id)response toDiskForClassWithName:(NSString *)className
{
    NSURL *fileURL = [NSURL URLWithString:className relativeToURL:[self JSONDataRecordsDirectory]];
    if (![(NSDictionary *)response writeToFile:[fileURL path] atomically:YES]) {
        NSLog(@"Error saving response to disk, will attempt to remove NSNull values and try again.");
        // remove NSNulls and try again...
        NSArray *records = [response objectForKey:@"results"];
        NSMutableArray *nullFreeRecords = [NSMutableArray array];
        for (NSDictionary *record in records) {
            NSMutableDictionary *nullFreeRecord = [NSMutableDictionary dictionaryWithDictionary:record];
            [record enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
                if ([obj isKindOfClass:[NSNull class]]) {
                    [nullFreeRecord setValue:nil forKey:key];
                }
            }];
            [nullFreeRecords addObject:nullFreeRecord];
        }
        
        NSDictionary *nullFreeDictionary = [NSDictionary dictionaryWithObject:nullFreeRecords forKey:@"results"];
        
        if (![nullFreeDictionary writeToFile:[fileURL path] atomically:YES]) {
            NSLog(@"Failed all attempts to save response to disk: %@", response);
        }
    }
}


@end
