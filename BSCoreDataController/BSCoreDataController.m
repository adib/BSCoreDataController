//
//  BSCoreDataController.m
//
//  Created by Sasmito Adibowo on 09-11-13.
//
//  Copyright (c) 2013 Basil Salad Software. All rights reserved.
//  http://basilsalad.com
//
//  Licensed under the BSD License <http://www.opensource.org/licenses/bsd-license>
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY
//  EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
//  OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT
//  SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
//  INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
//  TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
//  BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
//  STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF
//  THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//

#import <CoreData/CoreData.h>
#import "BSCoreDataController.h"

NSString* const BSCoreDataControllerDidMergeFromUbiquitousContentChanges = @"BSCoreDataControllerDidMergeFromUbiquitousContentChanges";
NSString* const BSCoreDataControllerStoresWillChangeNotification = @"BSCoreDataControllerStoresWillChangeNotification";
NSString* const BSCoreDataControllerStoresDidChangeNotification = @"BSCoreDataControllerStoresDidChangeNotification";

@implementation BSCoreDataController {
    NSURL* _filePackageURL;
    NSManagedObjectModel* _managedObjectModel;
    NSPersistentStore* _persistentStore;
    NSManagedObjectContext* _managedObjectContext;
    dispatch_queue_t _backgroundQueue;
}

-(void) setupInitialDataInManagedObjectContext:(NSManagedObjectContext*) objectContext { }


+(NSString*) filePackageName { return @"Default.data"; }

-(id) initWithFilePackageURL:(NSURL *)fileURL
{
    if (self = [super init]) {
        _filePackageURL = fileURL;
        
        NSNotificationCenter* nc = [NSNotificationCenter defaultCenter];
#if TARGET_OS_IPHONE
        UIApplication* app = [UIApplication sharedApplication];
        [nc addObserver:self selector:@selector(applicationDidDeactivate:) name:UIApplicationDidEnterBackgroundNotification object:app];
        [nc addObserver:self selector:@selector(applicationDidDeactivate:) name:UIApplicationWillResignActiveNotification object:app];
        
#else
        NSApplication* app = [NSApplication sharedApplication];
        [nc addObserver:self selector:@selector(applicationDidDeactivate:) name:NSApplicationDidResignActiveNotification object:app];
        [nc addObserver:self selector:@selector(applicationDidDeactivate:) name:NSApplicationDidHideNotification object:app];        
#endif // TARGET_OS_IPHONE
    }
    return self;
}


-(id) init
{
    NSString *executableName = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleExecutable"];
    NSFileManager* fm = [NSFileManager defaultManager];
    NSURL* appSupportURL = [[fm URLsForDirectory:NSApplicationDirectory inDomains:NSUserDomainMask] firstObject];
    NSURL* filePackageURL = [[appSupportURL URLByAppendingPathComponent:executableName] URLByAppendingPathComponent:[[self class] filePackageName]];
    return [self initWithFilePackageURL:filePackageURL];
}


-(void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}


-(dispatch_queue_t) backgroundQueue
{
    if (!_backgroundQueue) {
        // use an internal serial queue for any lengthy operations so that we don't need to synchronize with ourselves.
        _backgroundQueue = dispatch_queue_create("com.basilsalad.CoreDataController",DISPATCH_QUEUE_SERIAL);
    }
    return _backgroundQueue;
}

#pragma mark Notification Handlers

-(void) persistentStoreCoordinatorDidImportUbiquitousContentChanges:(NSNotification*) notification
{
    NSManagedObjectContext* moc = [self managedObjectContext];
    [moc performBlock:^{
        [moc mergeChangesFromContextDidSaveNotification:notification];
        [[NSNotificationCenter defaultCenter] postNotificationName:BSCoreDataControllerDidMergeFromUbiquitousContentChanges object:self userInfo:notification.userInfo];
    }];
}


-(void) persistentStoreCoordinatorStoresWillChange:(NSNotification*) notification
{
    void (^saveThenReset)(BOOL)  = ^(BOOL reset) {
        NSManagedObjectContext* moc = [self managedObjectContext];
        [moc performBlockAndWait:^{
            NSError* mocError = nil;
            if ([moc hasChanges]) {
                [moc save:&mocError];
                if (mocError) {
                    NSLog(@"Store change - save error on main context: %@",mocError);
                }
            };
            if (reset) {
                [moc reset];
            }
            
            NSManagedObjectContext* parentMoc = [moc parentContext];
            [parentMoc performBlockAndWait:^{
                if([parentMoc hasChanges]) {
                    NSError* parentError = nil;
                    [parentMoc save:&parentError];
                    if (parentError) {
                        NSLog(@"Store change - save error on parent context: %@",parentError);
                    }
                }
                if (reset) {
                    [parentMoc reset];
                }
            }];
        }];
    };
    
    // First save the contexts first to convert any temporary ID into a permanent ID.
    saveThenReset(NO);
    
    // Notify everyone else first to commit their changes and do whatever is required before we reset the contexts.
    [[NSNotificationCenter defaultCenter] postNotificationName:BSCoreDataControllerStoresWillChangeNotification object:self userInfo:notification.userInfo];
    
    // Then save it again in case the above made any changes to the contexts. This time we reset them afterwards.
    saveThenReset(YES);
}


-(void) persistentStoreCoordinatorStoresDidChange:(NSNotification*) notification
{
    // parallel notification to BSCoreDataControllerStoresWillChangeNotification
    [[NSNotificationCenter defaultCenter] postNotificationName:BSCoreDataControllerStoresDidChangeNotification object:self userInfo:notification.userInfo];
}


-(void) applicationDidDeactivate:(NSNotification*) notification
{
#if TARGET_OS_IPHONE
    UIApplication* app = [UIApplication sharedApplication];
    UIBackgroundTaskIdentifier autosaveTaskID = [app beginBackgroundTaskWithExpirationHandler:nil];
    if (autosaveTaskID != UIBackgroundTaskInvalid) {
        [self autosaveWithCompletionHandler:^(BOOL success) {
            [app endBackgroundTask:autosaveTaskID];
        }];
    }
#else
    [self autosaveWithCompletionHandler:nil];
#endif
}


#pragma mark NSDocument/UIManagedDocument inspired methods

/*
 We copy off some of NSDocument/UIDocument/UIManagedDocument method names and semantics, noting that there are some wisdom in there. But we don't try to clone its entire functionality because we don't support things like Save As, etc.
 */

+ (NSString *)storeContentName { return @"StoreContent"; }

+ (NSString *)persistentStoreName { return @"persistentStore"; }

- (NSString *)persistentStoreTypeForFileType:(NSString *)fileType { return NSSQLiteStoreType; }

+ (BOOL) usesUbiquitousStorage { return NO; }


- (void)openWithCompletionHandler:(void (^)(BOOL success))completionHandler
{
    NSDictionary* storeOptions = self.persistentStoreOptions;
    // ensure context is created
    [self managedObjectContext];
    dispatch_async([self backgroundQueue], ^{
        BOOL __block success = YES;
        void(^returnSuccess)() = ^{
            if (completionHandler) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completionHandler(success);
                });
            }
        };
        if (_persistentStore) {
            returnSuccess();
        }
        NSFileCoordinator* fc = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        NSError* fileCoordinatorError = nil;
        [fc coordinateWritingItemAtURL:_filePackageURL options:NSFileCoordinatorWritingForMerging error:&fileCoordinatorError byAccessor:^(NSURL *newURL) {
            NSFileManager* fm = [NSFileManager defaultManager];
            NSError* fmError = nil;
            
            NSURL* storeContentURL  = [newURL URLByAppendingPathComponent:[[self class] storeContentName]];
            if([fm createDirectoryAtURL:storeContentURL withIntermediateDirectories:YES attributes:nil error:&fmError]) {
                [newURL setResourceValue:@YES forKey:NSURLIsPackageKey error:nil];
                NSURL* persistentStoreURL = [storeContentURL URLByAppendingPathComponent:[[self class] persistentStoreName]];
                NSError* configureError = nil;
                if(![self configurePersistentStoreCoordinatorForURL:persistentStoreURL ofType:nil modelConfiguration:nil storeOptions:storeOptions error:&configureError]) {
                    if (configureError) {
                        [self handleError:configureError userInteractionPermitted:YES];
                    }
                    success = NO;
                    return;
                }

            } else {
                if (fmError) {
                    [self handleError:fmError userInteractionPermitted:YES];
                    success = NO;
                    return;
                }
            }
        }];
        if (fileCoordinatorError) {
            NSLog(@"error coordinating write: %@",fileCoordinatorError);
            [self handleError:fileCoordinatorError userInteractionPermitted:NO];
            success = NO;
        }
        
        returnSuccess();
    });
}


- (void)autosaveWithCompletionHandler:(void (^)(BOOL success))completionHandler
{
    dispatch_queue_t callbackQueue = [NSThread isMainThread] ? dispatch_get_main_queue() : [self backgroundQueue];
    BOOL __block success = YES;
    void(^returnSuccess)() = ^{
        if (completionHandler) {
            dispatch_async(callbackQueue, ^{
                completionHandler(success);
            });
        }
    };

    NSManagedObjectContext* context = self.managedObjectContext;
    [context performBlock:^{
        NSError* mainContextSaveError = nil;
        if([context hasChanges]) {
            [context save:&mainContextSaveError];
        }
        if (!mainContextSaveError) {
            NSManagedObjectContext* parentContext = [context parentContext];
            [parentContext performBlock:^{
                if ([parentContext hasChanges]) {
                    NSFileCoordinator* fc = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
                    [fc coordinateWritingItemAtURL:_filePackageURL options:NSFileCoordinatorWritingForMerging error:nil byAccessor:^(NSURL *newURL) {
                        NSError* parentSaveError = nil;
                        success = [parentContext save:&parentSaveError];
                        if (parentSaveError) {
                            [self handleError:parentSaveError userInteractionPermitted:NO];
                        }
                    }];
                }
                returnSuccess();
            }];
            // call completion handler in the above performBlock.
            return;
        } else {
            [self handleError:mainContextSaveError userInteractionPermitted:YES];
            success = NO;
        }
        returnSuccess();
    }];
}


- (void)closeWithCompletionHandler:(void (^)(BOOL success))completionHandler
{
    BOOL __block success = YES;
    void(^returnSuccess)() = ^{
        if (completionHandler) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completionHandler(success);
            });
        }
    };

    dispatch_async([self backgroundQueue], ^{
        [self autosaveWithCompletionHandler:^(BOOL autosaveSuccess) {
            if(autosaveSuccess) {
                NSPersistentStoreCoordinator* coordinator = [self.managedObjectContext persistentStoreCoordinator];
                if (_persistentStore) {
                    NSError* removeError  = nil;
                    [coordinator removePersistentStore:_persistentStore error:&removeError];
                    if (removeError) {
                        [self handleError:removeError userInteractionPermitted:YES];
                        success = NO;
                    } else {
                        _persistentStore = nil;
                    }
                }
            } else {
                success = NO;
            }
            returnSuccess();
        }];
    });
}


- (void)handleError:(NSError *)error userInteractionPermitted:(BOOL)userInteractionPermitted
{
    // TODO
    NSLog(@"Error: %@",error);
    [self finishedHandlingError:error recovered:NO];
}


- (void)finishedHandlingError:(NSError *)error recovered:(BOOL)recovered
{
    // nothing yet
}

- (void)userInteractionNoLongerPermittedForError:(NSError *)error
{
    // nothing yet
}



- (NSManagedObjectModel *)managedObjectModel;
{
    if (!_managedObjectModel) {
        _managedObjectModel = [NSManagedObjectModel mergedModelFromBundles:[NSArray arrayWithObject:[NSBundle mainBundle]]];
    }
    return _managedObjectModel;
}


-(NSManagedObjectContext *)managedObjectContext
{
    if (!_managedObjectContext) {
        [self setManagedObjectContext:[[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType]];
    }
    return _managedObjectContext;
}


-(void)setManagedObjectContext:(NSManagedObjectContext *)managedObjectContext
{
    BOOL isUbiquitous = [[self class] usesUbiquitousStorage];
    NSNotificationCenter* nc = [NSNotificationCenter defaultCenter];
    if (isUbiquitous) {
        [nc removeObserver:self name:NSPersistentStoreDidImportUbiquitousContentChangesNotification object:nil];
        [nc removeObserver:self name:NSPersistentStoreCoordinatorStoresWillChangeNotification object:nil];
        [nc removeObserver:self name:NSPersistentStoreCoordinatorStoresDidChangeNotification object:nil];
    }
    NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:[self managedObjectModel]];
    if (isUbiquitous) {
        [nc addObserver:self selector:@selector(persistentStoreCoordinatorDidImportUbiquitousContentChanges:) name:NSPersistentStoreDidImportUbiquitousContentChangesNotification object:coordinator];
        [nc addObserver:self selector:@selector(persistentStoreCoordinatorStoresWillChange:) name:NSPersistentStoreCoordinatorStoresWillChangeNotification object:coordinator];
        [nc addObserver:self selector:@selector(persistentStoreCoordinatorStoresDidChange:) name:NSPersistentStoreCoordinatorStoresDidChangeNotification object:coordinator];
    }
    
    NSManagedObjectContext* parentContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    [parentContext performBlockAndWait:^{
        [parentContext setUndoManager:nil];
        [parentContext setPersistentStoreCoordinator:coordinator];
    }];

    [managedObjectContext setParentContext:parentContext];
    _managedObjectContext = managedObjectContext;
}


- (BOOL)configurePersistentStoreCoordinatorForURL:(NSURL *)storeURL
                                           ofType:(NSString *)fileType
                               modelConfiguration:(NSString *)configuration
                                     storeOptions:(NSDictionary *)storeOptions
                                            error:(NSError **)error
{
    BOOL shouldSetupInitialData = NO;
    NSString* ubSetupKey = nil;
    NSString* ubName = storeOptions[NSPersistentStoreUbiquitousContentNameKey];
    if (ubName) {
        // on iCloud, use the key-value store to mark whether this store has been pre-populated
        NSUbiquitousKeyValueStore* ubStore = [NSUbiquitousKeyValueStore defaultStore];
        ubSetupKey = [NSString stringWithFormat:@"storeSetupDone/%@/%@/%@",[self class],storeOptions[NSPersistentStoreUbiquitousContainerIdentifierKey],ubName];
        BOOL setupDone = [ubStore boolForKey:ubSetupKey];
        if (!setupDone) {
            shouldSetupInitialData = YES;
        }
    } else {
        // not on iCloud, detect whether the file exists or not. If it doesn't exists yet, then setup afterwards.
        NSError* urlCheckError = nil;
        BOOL fileExists = [storeURL checkResourceIsReachableAndReturnError:&urlCheckError];
        if (!urlCheckError) {
            shouldSetupInitialData = !fileExists;
        }
    }

    NSManagedObjectContext* objectContext = [self managedObjectContext];
    NSPersistentStoreCoordinator *storeCoordinator = [objectContext persistentStoreCoordinator];
    _persistentStore = [storeCoordinator addPersistentStoreWithType:[self persistentStoreTypeForFileType:fileType]
                                                      configuration:configuration
                                                                URL:storeURL
                                                            options:storeOptions
                                                              error:error];

    if (shouldSetupInitialData && _persistentStore) {
        NSManagedObjectContext* parentContext = [objectContext parentContext];
        [parentContext performBlock:^{
            [self setupInitialDataInManagedObjectContext:parentContext];
            if (ubSetupKey) {
                // on iCloud, mark setup done on the key-value pair.
                NSUbiquitousKeyValueStore* ubStore = [NSUbiquitousKeyValueStore defaultStore];
                [ubStore setBool:YES forKey:ubSetupKey];
            }
        }];
    }
    return (_persistentStore != nil);
}


@end
