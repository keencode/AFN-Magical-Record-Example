//
//  SDSyncEngine.h
//  SignificantDates
//
//  Created by Yee Peng Chia on 12/20/12.
//
//

#import <Foundation/Foundation.h>

typedef enum {
    AFNObjectSynced = 0,
    AFNObjectCreated,
    AFNObjectDeleted,
} AFNObjectSyncStatus;


extern NSString * const kAFNSyncEngineInitialCompleteKey;
extern NSString * const kAFNSyncEngineSyncCompletedNotificationName;

@interface AFNSyncEngine : NSObject

@property (atomic, readonly) BOOL syncInProgress;

+ (AFNSyncEngine *)sharedEngine;

- (void)registerNSManagedObjectClassToSync:(Class)aClass;

- (void)startSync;


@end
