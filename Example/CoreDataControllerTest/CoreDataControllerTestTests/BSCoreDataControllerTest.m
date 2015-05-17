//
//  CoreDataControllerTestTests.m
//  CoreDataControllerTestTests
//
//  Created by Sasmito Adibowo on 17-05-15.
//  Copyright (c) 2015 Basil Salad Software. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <CoreData/CoreData.h>
#import <XCTest/XCTest.h>
#import "BSCoreDataController_TestSurrogate.h"
@interface BSCoreDataControllerTest : XCTestCase

@end

@implementation BSCoreDataControllerTest {
    BSCoreDataController_TestSurrogate* _coreDataController;
}

- (void)setUp {
    [super setUp];
    NSUUID* uuid = [NSUUID UUID];
    NSString *executableName = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleExecutable"];
    NSFileManager* fm = [NSFileManager defaultManager];
    NSURL* appSupportURL = [[fm URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] firstObject];
    NSURL* filePackageURL = [[appSupportURL URLByAppendingPathComponent:executableName] URLByAppendingPathComponent:[uuid UUIDString]];

    _coreDataController = [[BSCoreDataController_TestSurrogate alloc] initWithFilePackageURL:filePackageURL];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    _coreDataController = nil;
    [super tearDown];
}

-(void) testOpenSave {
    XCTestExpectation* openComplete = [self expectationWithDescription:@"Open Completed"];
    [_coreDataController openWithCompletionHandler:^(BOOL success) {
        XCTAssertTrue(success);
        [openComplete fulfill];
    }];

    
    XCTestExpectation* saveComplete = [self expectationWithDescription:@"Save Completed"];
    [_coreDataController autosaveWithCompletionHandler:^(BOOL success) {
        XCTAssertTrue(success);
        
        NSManagedObjectContext* objectContext = [_coreDataController managedObjectContext];
        XCTAssertNotNil(objectContext);
        
        NSPersistentStoreCoordinator* psc = [objectContext persistentStoreCoordinator];
        XCTAssertNotNil(psc);
        
        NSArray* persistentStores = [psc persistentStores];
        XCTAssertNotNil(persistentStores);
        XCTAssertGreaterThan([persistentStores count],0);
        [saveComplete fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:600 handler:nil];
}
@end
