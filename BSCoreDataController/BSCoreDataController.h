//
//  BSCoreDataController.h
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

#import <Foundation/Foundation.h>

@class NSManagedObjectContext;

/**
 Base class for library-type applications that manages a single Core Data stack inside its Application Support folder. If NSDocument-based implementation gives you too much trouble and you want your CoreData objects to sync with your iOS app, use this instead of basing off NSDocument  / UIManagedDocument.
 
 @author Sasmito Adibowo
 */
@interface BSCoreDataController : NSObject<NSCoding>

/**
 Designated initializer. Will create the container folders if necessary.
 */
-(id) initWithFilePackageURL:(NSURL*) fileURL;

/**
 Creates a default URL.
 */
-(id) init;

/**
 The primary managed object context.
 */
@property (nonatomic,readonly) NSManagedObjectContext* managedObjectContext;

- (BOOL)configurePersistentStoreCoordinatorForURL:(NSURL *)storeURL ofType:(NSString *)fileType modelConfiguration:(NSString *)configuration storeOptions:(NSDictionary *)storeOptions error:(NSError **)error;

@property (nonatomic, copy) NSDictionary *persistentStoreOptions;

@property (nonatomic,copy) NSString* fileType;

/** 
 Override to return YES if you want to sync with iCloud
 */
+ (BOOL) usesUbiquitousStorage;

+ (NSString *) storeContentName;

+ (NSString *) persistentStoreName;

/**
 Override this to return the default file package name.
 */
+ (NSString*) filePackageName;

- (NSString *) persistentStoreTypeForFileType:(NSString *)fileType;

- (void) openWithCompletionHandler:(void (^)(BOOL success))completionHandler;

- (void) closeWithCompletionHandler:(void (^)(BOOL success))completionHandler;

- (void)autosaveWithCompletionHandler:(void (^)(BOOL success))completionHandler;

- (void) handleError:(NSError *)error userInteractionPermitted:(BOOL)userInteractionPermitted;

@end

extern NSString* const BSCoreDataControllerStoresWillChangeNotification;
extern NSString* const BSCoreDataControllerStoresDidChangeNotification;
extern NSString* const BSCoreDataControllerDidMergeFromUbiquitousContentChanges;
