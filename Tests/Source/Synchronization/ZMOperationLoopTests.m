// 
// Wire
// Copyright (C) 2016 Wire Swiss GmbH
// 
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
// 
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <http://www.gnu.org/licenses/>.
// 


@import ZMTransport;
@import Cryptobox;
@import ZMCDataModel;

#import "MessagingTest.h"
#import "ZMSyncStrategy.h"
#import <zmessaging/ZMUserSession.h>
#import "MockModelObjectContextFactory.h"
#import "MockModelObjectContextFactory.h"
#import "ZMAuthenticationStatus.h"
#import "AVSMediaManager.h"
#import "AVSFlowManager.h"
#import "ZMAuthenticationStatus.h"
#import "ZMUserProfileUpdateStatus.h"
#import "CBCryptoBox+UpdateEvents.h"
#import "ZMOperationLoop+Private.h"
#import "ZMSyncStrategy+Internal.h"
#import "ZMLocalNotificationDispatcher.h"
#import "ZMOperationLoop+Background.h"
#import "ZMBadge.h"

@interface ZMOperationLoopTests : MessagingTest

@property (nonatomic) ZMOperationLoop *sut;
@property (nonatomic) id transportSession;
@property (nonatomic) id syncStrategy;
@property (nonatomic) id badge;
@property (nonatomic) id pingBackStatus;
@property (nonatomic) NSMutableArray *pushChannelNotifications;
@end


@implementation ZMOperationLoopTests;

- (void)setUp
{
    [super setUp];
    self.pushChannelNotifications = [NSMutableArray array];
    self.transportSession = [OCMockObject niceMockForClass:[ZMTransportSession class]];
    [[self.transportSession stub] openPushChannelWithConsumer:OCMOCK_ANY groupQueue:OCMOCK_ANY];
    [[self.transportSession stub] closePushChannelAndRemoveConsumer];
    self.syncStrategy = [OCMockObject mockForClass:[ZMSyncStrategy class]];
    
    [self verifyMockLater:self.syncStrategy];
    [self verifyMockLater:self.transportSession];

    self.badge = [[ZMBadge alloc] init];
    
    self.pingBackStatus = [OCMockObject mockForClass:BackgroundAPNSPingBackStatus.class];
    
    // I expect this to be called, at least until we implement the soft sync
    [[[self.syncStrategy stub] andReturn:self.syncMOC] syncMOC];
    
    self.sut = [[ZMOperationLoop alloc] initWithTransportSession:self.transportSession
                                                    syncStrategy:self.syncStrategy
                                                           uiMOC:self.uiMOC
                                                         syncMOC:self.syncMOC
                                    backgroundAPNSPingBackStatus:self.pingBackStatus];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(pushChannelDidChange:) name:ZMPushChannelStateChangeNotificationName object:nil];
}

- (void)tearDown;
{
    self.transportSession = nil;
    self.syncStrategy = nil;
    [self.sut tearDown];
    self.sut = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super tearDown];
    [self.pingBackStatus stopMocking];
    self.pingBackStatus = nil;
}

- (void)pushChannelDidChange:(NSNotification *)note
{
    [self.pushChannelNotifications addObject:note];
}


- (void)testThatItPassesTheMediaManagerDelegateToTheSyncStrategy;
{
    // given
    id mediaManager = [OCMockObject niceMockForClass:NSObject.class];
    ZMAuthenticationStatus *authenticationStatus = [[ZMAuthenticationStatus alloc] initWithManagedObjectContext:self.uiMOC cookie:nil];
    ZMUserProfileUpdateStatus *userProfileStatus = [[ZMUserProfileUpdateStatus alloc] initWithManagedObjectContext:self.uiMOC];
    id transportSession = [OCMockObject niceMockForClass:ZMTransportSession.class];
    
    // expect
    id syncStrategy = [OCMockObject niceMockForClass:ZMSyncStrategy.class];
    [[[[syncStrategy expect] classMethod] andReturn:syncStrategy] alloc];
    (void) [[[syncStrategy expect] andReturn:syncStrategy]
            initWithAuthenticationCenter:authenticationStatus
            userProfileUpdateStatus:userProfileStatus
            clientRegistrationStatus:nil
            clientUpdateStatus:nil
            giphyRequestStatus:nil
            accountStatus:nil
            backgroundAPNSPingBackStatus:nil
            mediaManager:mediaManager
            onDemandFlowManager:nil
            syncMOC:self.syncMOC
            uiMOC:self.uiMOC
            syncStateDelegate:nil
            backgroundableSession:transportSession
            localNotificationsDispatcher:OCMOCK_ANY
            taskCancellationProvider:OCMOCK_ANY
            badge:OCMOCK_ANY];
    
    // when
    ZMOperationLoop *ol = [[ZMOperationLoop alloc] initWithTransportSession:transportSession
                                                       authenticationStatus:authenticationStatus
                                                    userProfileUpdateStatus:userProfileStatus
                                                   clientRegistrationStatus:nil
                                                         clientUpdateStatus:nil
                                                         giphyRequestStatus:nil
                                                              accountStatus:nil
                                               backgroundAPNSPingBackStatus:nil
                                                localNotificationdispatcher:nil
                                                               mediaManager:mediaManager
                                                        onDemandFlowManager:nil
                                                                      uiMOC:self.uiMOC
                                                                    syncMOC:self.syncMOC
                                                          syncStateDelegate:nil];
    XCTAssertNotNil(ol);
    [ol tearDown];
    
    [syncStrategy verify];
    
    [syncStrategy stopMocking];
    [transportSession stopMocking];
}

- (void)testThatItNotifiesTheSyncStrategyWhenThePushChannelIsOpened
{
    // expect
    [[(id) self.syncStrategy expect] didEstablishUpdateEventsStream];
    [[self.syncStrategy stub] dataDidChange];
    
    // when
    [(id<ZMPushChannelConsumer>)self.sut pushChannelDidOpen:nil withResponse:nil];
    
    // then
    [self.syncStrategy verify];
}

- (void)testThatItNotifiesTheSyncStrategyWhenThePushChannelIsClosed
{
    // expect
    [[(id) self.syncStrategy expect] didInterruptUpdateEventsStream];
    [[self.syncStrategy stub] dataDidChange];
    
    // when
    [(id<ZMPushChannelConsumer>)self.sut pushChannelDidClose:nil withResponse:nil];
    
    // then
    [self.syncStrategy verify];
}


- (void)testThatItInitializesThePushChannel
{
    __block id<ZMPushChannelConsumer> receivedConsumer;
    
    // given
    self.transportSession = [OCMockObject mockForClass:[ZMTransportSession class]];
    [[self.transportSession stub] closePushChannelAndRemoveConsumer];
    [[self.transportSession expect] openPushChannelWithConsumer:[OCMArg checkWithBlock:^BOOL(id obj) {
        receivedConsumer = obj;
        return YES;
    }] groupQueue:OCMOCK_ANY];
    
    // when
    ZMOperationLoop *op = [[ZMOperationLoop alloc] initWithTransportSession:self.transportSession
                                                               syncStrategy:self.syncStrategy
                                                                      uiMOC:self.uiMOC
                                                                    syncMOC:self.syncMOC
                                               backgroundAPNSPingBackStatus:nil];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertNotNil(op);
    WaitForAllGroupsToBeEmpty(0.5);
    [op tearDown];

    XCTAssertEqual(op, (id)receivedConsumer);
    
    [self.transportSession verify];
}



- (void)testThatItSendsTheNextOperation
{

    // given
    [[self.syncStrategy stub] dataDidChange];
    ZMTransportEnqueueResult *result = [ZMTransportEnqueueResult resultDidHaveLessRequestsThanMax:NO didGenerateNonNullRequest:NO];
    ZMTransportRequest *request = [[ZMTransportRequest alloc] initWithPath:@"/test"
                                                                   method:ZMMethodPOST
                                                                  payload:@{@"foo": @"bar"}];
    [[[self.syncStrategy stub] andReturn:request] nextRequest];
    [[[self.syncStrategy stub] andReturnValue:@NO] slowSyncInProgress];
    XCTestExpectation *attemptExpectation = [self expectationWithDescription:@"attemptToEnqueue"];
    [[[[self.transportSession expect] andDo:^(NSInvocation *invocation ZM_UNUSED) {
        [attemptExpectation fulfill];
        
    }] andReturn:result] attemptToEnqueueSyncRequestWithGenerator:[OCMArg checkWithBlock:^BOOL(ZMTransportRequestGenerator gen) {
        ZMTransportRequest *generated = gen();
        BOOL equal = [request isEqual:generated];
        return equal;
    }]];
   
    // when
    [ZMOperationLoop notifyNewRequestsAvailable:self];
    
    // then
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
    [self.transportSession verifyWithDelay:0.1];
}

- (void)testThatItDoesNotSendARequestIfThereAreNone
{
    // given
    ZMTransportEnqueueResult *result = [ZMTransportEnqueueResult resultDidHaveLessRequestsThanMax:NO didGenerateNonNullRequest:NO];
    [[[self.syncStrategy stub] andReturn:nil] nextRequest];
    [[[self.syncStrategy stub] andReturnValue:@NO] slowSyncInProgress];
    [[self.syncStrategy stub] dataDidChange];

    [[[self.transportSession expect] andReturn:result] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];
    
    // when
    [ZMOperationLoop notifyNewRequestsAvailable:self];
    
    // then
    [self.transportSession verifyWithDelay:0.15];
}


- (void)testThatItSendsAsManyCallsAsTheTransportSessionCanHandle
{
    // given
    ZMTransportEnqueueResult *resultOK = [ZMTransportEnqueueResult resultDidHaveLessRequestsThanMax:YES didGenerateNonNullRequest:YES];
    ZMTransportEnqueueResult *resultNO = [ZMTransportEnqueueResult resultDidHaveLessRequestsThanMax:NO didGenerateNonNullRequest:NO];
    [[self.syncStrategy stub] dataDidChange];
    
    ZMTransportRequest *request = [[ZMTransportRequest alloc] initWithPath:@"/test" method:ZMMethodPOST payload:@{}];
    int stopAt = 3;
    
    __block int numRequests = 0;
    BOOL(^verifier)(ZMTransportRequestGenerator) = ^BOOL(ZMTransportRequestGenerator generator) {
        ++numRequests;
        if(numRequests < stopAt) {
            // generator will create a new sendRequest
            ZMTransportRequest *generated = generator();
            return [request isEqual:generated];
        }
        else {
            // if I don't call generator, it should not invoke another sendRequest
            return YES;
        }
    };
    
    [[[self.syncStrategy stub] andReturn:request] nextRequest];
    [[[self.syncStrategy stub] andReturnValue:@NO] slowSyncInProgress];


    [[[self.transportSession expect] andReturn:resultOK] attemptToEnqueueSyncRequestWithGenerator:[OCMArg checkWithBlock:verifier]];
    [[[self.transportSession expect] andReturn:resultOK] attemptToEnqueueSyncRequestWithGenerator:[OCMArg checkWithBlock:verifier]];
    
    XCTestExpectation *attemptExpectation = [self expectationWithDescription:@"attemptToEnqueue"];
    [[[[self.transportSession expect] andReturn:resultNO] andDo:^(NSInvocation *invocation ZM_UNUSED) {
        [attemptExpectation fulfill];
    }] attemptToEnqueueSyncRequestWithGenerator:[OCMArg checkWithBlock:verifier]];
    
    [[self.transportSession reject] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];

    // when
    [ZMOperationLoop notifyNewRequestsAvailable:self];

    // then
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.6]);
    [self.transportSession verifyWithDelay:0.2]; //a delay so that the last sendRequest call has a chance to fail
}

- (void)testThatExecuteNextOperationIsCalledWhenThePreviousRequestIsCompleted
{
    // given
    NSManagedObjectContext *moc = [OCMockObject mockForClass:NSManagedObjectContext.class];
    [[[self.syncStrategy stub] andReturn:moc] syncMOC];
    [[self.syncStrategy stub] dataDidChange];
    [[(id)moc stub] saveOrRollback];

    ZMTransportEnqueueResult *resultYES = [ZMTransportEnqueueResult resultDidHaveLessRequestsThanMax:YES didGenerateNonNullRequest:YES];
    ZMTransportEnqueueResult *resultNO = [ZMTransportEnqueueResult resultDidHaveLessRequestsThanMax:NO didGenerateNonNullRequest:NO];
    
    ZMTransportRequest *request = [ZMTransportRequest requestWithPath:@"/boo" method:ZMMethodGET payload:nil];

    [[[self.syncStrategy stub] andReturn:nil] syncMOC];

    // expect
    [[[self.syncStrategy expect] andReturn:request] nextRequest];

    [[[self.syncStrategy stub] andReturnValue:@NO] slowSyncInProgress];
    
    BOOL(^checkGenerator)(ZMTransportRequestGenerator) = ^BOOL(ZMTransportRequestGenerator generator) {
        if(generator) {
            generator();
        }
        return YES;
    };
    
    [[[self.transportSession expect] andReturn:resultYES] attemptToEnqueueSyncRequestWithGenerator:[OCMArg checkWithBlock:checkGenerator]];
    [[[self.transportSession expect] andReturn:resultNO] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];
    [[[self.transportSession expect] andReturn:resultNO] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];
    [[[self.transportSession expect] andReturn:resultNO] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];
    [ZMOperationLoop notifyNewRequestsAvailable:self]; // this will enqueue `request`
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    [request completeWithResponse:[ZMTransportResponse responseWithPayload:@{} HTTPstatus:200 transportSessionError:nil]];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [self.transportSession verifyWithDelay:0.15];
    [self.syncStrategy verifyWithDelay:0.15];

}

- (void)testThatMOCIsSavedOnSuccessfulRequest
{
    // given
    id mockObserver = [OCMockObject observerMock];
    [[NSNotificationCenter defaultCenter] addMockObserver:mockObserver name:NSManagedObjectContextDidSaveNotification object:self.syncMOC];
    [[self.syncStrategy stub] dataDidChange];

    ZMTransportEnqueueResult *resultYES = [ZMTransportEnqueueResult resultDidHaveLessRequestsThanMax:YES didGenerateNonNullRequest:YES];
    ZMTransportEnqueueResult *resultNO = [ZMTransportEnqueueResult resultDidHaveLessRequestsThanMax:NO didGenerateNonNullRequest:NO];

    ZMTransportRequest *request = [ZMTransportRequest requestWithPath:@"/boo" method:ZMMethodGET payload:nil];

    // expect
    [[mockObserver expect] notificationWithName:NSManagedObjectContextDidSaveNotification object:OCMOCK_ANY userInfo:OCMOCK_ANY];
    [[[self.syncStrategy expect] andReturn:request] nextRequest];

    [[[self.syncStrategy stub] andReturnValue:@NO] slowSyncInProgress];

    BOOL(^checkGenerator)(ZMTransportRequestGenerator) = ^BOOL(ZMTransportRequestGenerator generator) {
        if(generator) {
            generator();
        }
        return YES;
    };

    [[[self.transportSession expect] andReturn:resultYES] attemptToEnqueueSyncRequestWithGenerator:[OCMArg checkWithBlock:checkGenerator]];
    [[[self.transportSession stub] andReturn:resultNO] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];
    [[self.syncStrategy stub] processSaveWithInsertedObjects:OCMOCK_ANY updateObjects:OCMOCK_ANY];

    [ZMOperationLoop notifyNewRequestsAvailable:self]; // this will enqueue `request`
    WaitForAllGroupsToBeEmpty(0.5);
    
    [request addCompletionHandler:[ZMCompletionHandler handlerOnGroupQueue:self.syncMOC block:^(ZMTransportResponse *resp ZM_UNUSED) {
        [ZMClientMessage insertNewObjectInManagedObjectContext:self.syncMOC];
    }]];
    
    // when
    [request completeWithResponse:[ZMTransportResponse responseWithPayload:@{} HTTPstatus:200 transportSessionError:nil]];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [self.transportSession verifyWithDelay:0.15];
    [self.syncStrategy verifyWithDelay:0.15];
    
    WaitForAllGroupsToBeEmpty(0.5);
    [mockObserver verify];
    
    [[NSNotificationCenter defaultCenter] removeObserver:mockObserver];

}

- (void)testThatMOCIsSavedOnFailedRequest
{
    // given
    id mockObserver = [OCMockObject observerMock];
    [[NSNotificationCenter defaultCenter] addMockObserver:mockObserver name:NSManagedObjectContextDidSaveNotification object:self.syncMOC];
    [[self.syncStrategy stub] dataDidChange];
    
    ZMTransportEnqueueResult *resultYES = [ZMTransportEnqueueResult resultDidHaveLessRequestsThanMax:YES didGenerateNonNullRequest:YES];
    ZMTransportEnqueueResult *resultNO = [ZMTransportEnqueueResult resultDidHaveLessRequestsThanMax:NO didGenerateNonNullRequest:NO];
    
    ZMTransportRequest *request = [ZMTransportRequest requestWithPath:@"/boo" method:ZMMethodGET payload:nil];
    
    // expect
    [[mockObserver expect] notificationWithName:NSManagedObjectContextDidSaveNotification object:OCMOCK_ANY userInfo:OCMOCK_ANY];
    [[[self.syncStrategy expect] andReturn:request] nextRequest];
    
    [[[self.syncStrategy stub] andReturnValue:@NO] slowSyncInProgress];
    
    BOOL(^checkGenerator)(ZMTransportRequestGenerator) = ^BOOL(ZMTransportRequestGenerator generator) {
        if(generator) {
            generator();
        }
        return YES;
    };
    
    [[[self.transportSession expect] andReturn:resultYES] attemptToEnqueueSyncRequestWithGenerator:[OCMArg checkWithBlock:checkGenerator]];
    [[[self.transportSession stub] andReturn:resultNO] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];
    [[self.syncStrategy stub] processSaveWithInsertedObjects:OCMOCK_ANY updateObjects:OCMOCK_ANY];
    [ZMOperationLoop notifyNewRequestsAvailable:self]; // this will enqueue `request`
    WaitForAllGroupsToBeEmpty(0.5);
    
    [request addCompletionHandler:[ZMCompletionHandler handlerOnGroupQueue:self.syncMOC block:^(ZMTransportResponse *resp ZM_UNUSED) {
        [ZMClientMessage insertNewObjectInManagedObjectContext:self.syncMOC];
    }]];
    
    // when
    [request completeWithResponse:[ZMTransportResponse responseWithPayload:@{} HTTPstatus:400 transportSessionError:nil]];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [self.transportSession verifyWithDelay:0.15];
    [self.syncStrategy verifyWithDelay:0.15];
    WaitForAllGroupsToBeEmpty(0.5);
    [mockObserver verify];
    
    [[NSNotificationCenter defaultCenter] removeObserver:mockObserver];
    
}



- (void)testThatWhenThereIsAnInsertionItAsksForNextRequest
{
    // given
    [ZMClientMessage insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMTransportEnqueueResult *resultNO = [ZMTransportEnqueueResult resultDidHaveLessRequestsThanMax:NO didGenerateNonNullRequest:NO];

    [[[self.syncStrategy stub] andReturnValue:@NO] slowSyncInProgress];
    [[self.syncStrategy stub] dataDidChange];


    BOOL(^checkGenerator)(ZMTransportRequestGenerator) = ^BOOL(ZMTransportRequestGenerator generator) {
        if(generator) {
            generator();
        }
        return YES;
    };


    // expect
    [[[self.syncStrategy expect] andReturnValue:@YES]
     processSaveWithInsertedObjects:OCMOCK_ANY updateObjects:OCMOCK_ANY];
    [[[self.syncStrategy expect] andReturn:nil] nextRequest];
    [[[self.transportSession expect] andReturn:resultNO] attemptToEnqueueSyncRequestWithGenerator:[OCMArg checkWithBlock:checkGenerator]];

    [self verifyMockLater:self.syncStrategy];
    [self verifyMockLater:self.transportSession];

    // when
    NSError *error;
    XCTAssertTrue([self.uiMOC save:&error]);
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatWhenThereIsAnUpdateItAsksForNextRequest
{
    ZMClientMessage *entity = [ZMClientMessage insertNewObjectInManagedObjectContext:self.uiMOC];

    [[[self.syncStrategy expect] andReturnValue:@YES]
     processSaveWithInsertedObjects:OCMOCK_ANY updateObjects:OCMOCK_ANY];
    [[[self.syncStrategy stub] andReturnValue:@NO] slowSyncInProgress];
    ZMTransportEnqueueResult *resultNO = [ZMTransportEnqueueResult resultDidHaveLessRequestsThanMax:NO didGenerateNonNullRequest:NO];
    [[[self.transportSession expect] andReturn:resultNO] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];
    [[self.syncStrategy stub] dataDidChange];
    
    NSError *error;
    XCTAssertTrue([self.uiMOC save:&error]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    entity.nonce = NSUUID.createUUID;

    BOOL(^checkGenerator)(ZMTransportRequestGenerator) = ^BOOL(ZMTransportRequestGenerator generator) {
        if(generator) {
            generator();
        }
        return YES;
    };

    // expect
    [[[self.syncStrategy expect] andReturn:nil] nextRequest];
    [[[self.syncStrategy expect] andReturnValue:@YES]
     processSaveWithInsertedObjects:OCMOCK_ANY updateObjects:OCMOCK_ANY];
    [[[self.transportSession expect] andReturn:resultNO] attemptToEnqueueSyncRequestWithGenerator:[OCMArg checkWithBlock:checkGenerator]];

    [self verifyMockLater:self.syncStrategy];
    [self verifyMockLater:self.transportSession];

    // when
    XCTAssertTrue([self.uiMOC save:&error]);
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItCallsProcessSaveOnSyncStrategyEvenIfThereAreNoChanges
{
    // given
    [[[self.syncStrategy stub] andReturnValue:@NO] slowSyncInProgress];
    ZMTransportEnqueueResult *resultNO = [ZMTransportEnqueueResult resultDidHaveLessRequestsThanMax:NO didGenerateNonNullRequest:NO];
    [[[self.transportSession stub] andReturn:resultNO] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];
    [[self.syncStrategy stub] dataDidChange];
    
    // expect
    [[self.syncStrategy expect] processSaveWithInsertedObjects:OCMOCK_ANY updateObjects:OCMOCK_ANY];
    
    // when
    NSError *error;
    XCTAssertTrue([self.uiMOC save:&error]);
    WaitForAllGroupsToBeEmpty(0.5);
}


- (void)testThatItCallsSyncStrategyDidRegisterWithInsertedObjects
{
    // given
    [[self.syncStrategy stub] dataDidChange];
    
    ZMClientMessage *entity1 = [ZMClientMessage insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMClientMessage *entity2 = [ZMClientMessage insertNewObjectInManagedObjectContext:self.uiMOC];
    
    NSSet *insertSet = [NSSet setWithObjects:entity1, entity2, nil];

    [[[self.syncStrategy expect] andReturnValue:@NO]
     processSaveWithInsertedObjects:[OCMArg checkWithBlock:^BOOL(NSSet *inserted) {
        [self checkThatObjectIDs:insertSet match:inserted];

        return YES;
    }] updateObjects:OCMOCK_ANY];
    [[[self.syncStrategy stub] andReturnValue:OCMOCK_VALUE(NO)] slowSyncInProgress];
    [[self.transportSession stub] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];
    
    // expect
    [self verifyMockLater:self.syncStrategy];
    
    // when
    NSError *error;
    XCTAssertTrue([self.uiMOC save:&error]);
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItCallsSyncStrategyDidRegisterWithUpdatedObjects
{
    // given
    [[self.syncStrategy stub] dataDidChange];
    
    [ZMClientMessage insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMClientMessage *entity2 = [ZMClientMessage insertNewObjectInManagedObjectContext:self.uiMOC];

    [[[self.syncStrategy expect] andReturnValue:@NO]
     processSaveWithInsertedObjects:OCMOCK_ANY updateObjects:OCMOCK_ANY];
    
    __block NSError *error;
    XCTAssertTrue([self.uiMOC save:&error]);

    entity2.nonce = NSUUID.createUUID;
    
    NSSet *updatedSet = [NSSet setWithObjects:entity2, nil];

    [[[self.syncStrategy expect] andReturnValue:@NO]
     processSaveWithInsertedObjects:OCMOCK_ANY updateObjects:[OCMArg checkWithBlock:^BOOL(NSSet *updated) {
        [self checkThatObjectIDs:updatedSet match:updated];

        return YES;
    }]];
    [[[self.syncStrategy stub] andReturnValue:OCMOCK_VALUE(NO)] slowSyncInProgress];
    [[self.transportSession stub] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];

    
    // expect
    [self verifyMockLater:self.syncStrategy];
    
    // when
    XCTAssertTrue([self.uiMOC save:&error]);
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatSyncStrategyDidRegisterIsCalledWithInsertedObjectsFromTheSyncContext
{
    // given
    [[self.syncStrategy stub] dataDidChange];
    
    ZMClientMessage *entity1 = [ZMClientMessage insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMClientMessage *entity2 = [ZMClientMessage insertNewObjectInManagedObjectContext:self.uiMOC];
    
    NSSet *insertSet = [NSSet setWithObjects:entity1, entity2, nil];

    [[[self.syncStrategy expect] andReturnValue:@NO]
     processSaveWithInsertedObjects:[OCMArg checkWithBlock:^BOOL(NSSet *inserted) {
        [self checkThatObjectIDs:insertSet match:inserted];

        return YES;
    }] updateObjects:OCMOCK_ANY];
    [[[self.syncStrategy stub] andReturnValue:OCMOCK_VALUE(NO)] slowSyncInProgress];
    [[self.transportSession stub] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];

    
    // expect
    [self verifyMockLater:self.syncStrategy];
    
    // when
    NSError *error;
    XCTAssertTrue([self.uiMOC save:&error], @"Error in saving %@", error);
    WaitForAllGroupsToBeEmpty(0.5);
}


- (void)checkThatObjectIDs:(NSSet *)expected match:(NSSet *)actualObjects {
    
    XCTAssertEqual(expected.count, actualObjects.count);
    for(NSManagedObject *obj in actualObjects){
        XCTAssertEqualObjects(obj.managedObjectContext, self.syncMOC);
        NSSet *matches = [expected objectsPassingTest:^BOOL(NSManagedObject *expectedObj, BOOL *stop) {
            NOT_USED(stop);
            return [expectedObj.objectID isEqual:obj.objectID];
        }];
        XCTAssertEqual(1u, matches.count);
    }
}

- (void)testThatSyncStrategyDidRegisterIsCalledWithUpdatedObjectsFromTheSyncContext
{
    // given
    [[self.syncStrategy stub] dataDidChange];
    
    [ZMClientMessage insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMClientMessage *entity2 = [ZMClientMessage insertNewObjectInManagedObjectContext:self.uiMOC];

    [[[self.syncStrategy expect] andReturnValue:@NO]
     processSaveWithInsertedObjects:OCMOCK_ANY updateObjects:OCMOCK_ANY];
    
    __block NSError *error;
    XCTAssertTrue([self.uiMOC save:&error]);
    
    entity2.nonce = NSUUID.createUUID;

    [[[self.syncStrategy expect] andReturnValue:@NO]
     processSaveWithInsertedObjects:OCMOCK_ANY updateObjects:[OCMArg checkWithBlock:^BOOL(NSSet *updated) {

        XCTAssertEqual(1u, updated.count);
        NSManagedObject *obj = [updated anyObject];
        XCTAssertEqualObjects(obj.managedObjectContext, self.syncMOC);
        XCTAssertEqualObjects(obj.objectID, entity2.objectID);

        return YES;
    }]];
    [[[self.syncStrategy stub] andReturnValue:OCMOCK_VALUE(NO)] slowSyncInProgress];
    [[self.transportSession stub] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];

    
    // expect
    [self verifyMockLater:self.syncStrategy];
    
    // when
    [self.uiMOC performBlockAndWait:^{
        XCTAssertTrue([self.uiMOC save:&error]);
    }];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItAsksSyncStrategyForNextOperationOnZMOperationLoopNewRequestAvailableNotification
{
    // given
    [[[self.syncStrategy stub] andReturnValue:@NO] slowSyncInProgress];
    [[self.syncStrategy stub] dataDidChange];
    
     
    ZMTransportEnqueueResult *resultNO = [ZMTransportEnqueueResult resultDidHaveLessRequestsThanMax:NO didGenerateNonNullRequest:NO];

    BOOL(^checkGenerator)(ZMTransportRequestGenerator) = ^BOOL(ZMTransportRequestGenerator generator) {
        if(generator) {
            generator();
        }
        return YES;
    };
    
    [[[self.transportSession stub] andReturn:resultNO] attemptToEnqueueSyncRequestWithGenerator:[OCMArg checkWithBlock:checkGenerator]];

    
    // expect
    [[[self.syncStrategy expect] andReturn:nil] nextRequest];
    [self verifyMockLater:self.syncStrategy];
    
    // when
    [ZMOperationLoop notifyNewRequestsAvailable:self];
    WaitForAllGroupsToBeEmpty(0.5);
    
}


- (void)testThatPushChannelDataIsSplitAndForwardedToAllIndividualObjects
{
    // given
    NSString *eventType = @"user.update";
    
    NSDictionary *payload1 = @{
                               @"type" : eventType,
                               @"foo" : @"bar"
                               };
    NSDictionary *payload2 = @{
                               @"type" : eventType,
                               @"bar" : @"xxxxxxx"
                               };
    NSDictionary *payload3 = @{
                               @"type" : eventType,
                               @"baz" : @"barbar"
                               };
    
    NSDictionary *eventData = @{
                                @"id" : @"5cc1ab91-45f4-49ec-bb7a-a5517b7a4173",
                                @"payload" : @[payload1, payload2, payload3],
                                };
    
    NSMutableArray *expectedEvents = [NSMutableArray array];
    [expectedEvents addObjectsFromArray:[ZMUpdateEvent eventsArrayFromPushChannelData:eventData]];
    XCTAssertGreaterThan(expectedEvents.count, 0u);
    
    // expect
    [[self.syncStrategy expect] processUpdateEvents:expectedEvents ignoreBuffer:NO];
    
    // when
    [(id<ZMPushChannelConsumer>)self.sut pushChannel:nil didReceiveTransportData:eventData];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatProcessSyncDataIsNotForwardedToAllSyncObjectsIfItIsNotAnArray
{
    // given
    NSDictionary *eventdata = @{
                                @"id" : @"16be010d-c284-4fc0-b636-837bcebed654",
                                @"payload" : @{
                                        @"type" : @"yyy",
                                        @"cat" : @"dog"
                                        },
                                };
    
    // expect
    [[self.syncStrategy reject] processUpdateEvents:OCMOCK_ANY ignoreBuffer:NO];
    [[self.syncStrategy reject] processUpdateEvents:OCMOCK_ANY ignoreBuffer:YES];
    
    // when
    [self performIgnoringZMLogError:^{
        [(id<ZMPushChannelConsumer>)self.sut pushChannel:nil didReceiveTransportData:eventdata];
        WaitForAllGroupsToBeEmpty(0.5);
    }];
}

- (void)testThatProcessSyncDataIsNotForwardedToAllSyncObjectsIfEventsAreInvalid
{
    // given
    NSArray *eventdata = @[ @{ @"id" : @"16be010d-c284-4fc0-b636-837bcebed654" } ];
    
    // expect
    [[self.syncStrategy reject] processUpdateEvents:OCMOCK_ANY ignoreBuffer:NO];
    [[self.syncStrategy reject] processUpdateEvents:OCMOCK_ANY ignoreBuffer:YES];
    
    // when
    [self performIgnoringZMLogError:^{
        [(id<ZMPushChannelConsumer>)self.sut pushChannel:nil didReceiveTransportData:eventdata];
        WaitForAllGroupsToBeEmpty(0.5);
    }];
}


- (void)testThatItClosesThePushChannelOnTearDown
{
    
    // given
    ZMTransportSession *transportSession = [OCMockObject mockForClass:[ZMTransportSession class]];
    [[(id) transportSession stub] openPushChannelWithConsumer:OCMOCK_ANY groupQueue:OCMOCK_ANY];
    
    ZMOperationLoop *sut = [[ZMOperationLoop alloc] initWithTransportSession:transportSession
                                                                syncStrategy:self.syncStrategy
                                                                       uiMOC:self.uiMOC
                                                                     syncMOC:self.syncMOC
                                                backgroundAPNSPingBackStatus:nil];
    
    // expect
    [[(id) transportSession expect] closePushChannelAndRemoveConsumer];
    
    // when
    [sut tearDown];
    
    // then
    [(id) transportSession verify];
}


- (void)testThatItCalls_DataDidChange_OnSyncStrategyWhenThereIsANewRequest
{
    // given
    ZMTransportEnqueueResult *result = [ZMTransportEnqueueResult resultDidHaveLessRequestsThanMax:NO didGenerateNonNullRequest:NO];
    [[[self.syncStrategy stub] andReturn:nil] nextRequest];
    [[[self.syncStrategy stub] andReturnValue:@NO] slowSyncInProgress];
    [[[self.transportSession stub] andReturn:result] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];
    
    // expect
    [[self.syncStrategy expect] dataDidChange];
    
    // when
    [ZMOperationLoop notifyNewRequestsAvailable:nil];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItSendsANotificationWhenClosingThePushChannelAndRemovingConsumers
{
    // given
    id fakeResponse = [OCMockObject niceMockForClass:[NSHTTPURLResponse class]];
    [[[fakeResponse stub] andReturnValue:@(100l)] statusCode];
    [[self.syncStrategy stub] didInterruptUpdateEventsStream];
    [[self.syncStrategy stub] dataDidChange];
    
    // when
    [(id<ZMPushChannelConsumer>)self.sut pushChannelDidClose:nil withResponse:fakeResponse];
    
    // then
    XCTAssertEqual(self.pushChannelNotifications.count, 1u);
    NSNotification *note = self.pushChannelNotifications.firstObject;
    XCTAssertFalse([note.userInfo[ZMPushChannelIsOpenKey] boolValue]);
    XCTAssertEqualObjects(note.userInfo[ZMPushChannelResponseStatusKey], @(100));
}

- (void)testThatItSendsANotificationWhenOpeningThePushChannel
{
    // given
    id fakeResponse = [OCMockObject niceMockForClass:[NSHTTPURLResponse class]];
    [[[fakeResponse stub] andReturnValue:@(100l)] statusCode];
    [[self.syncStrategy stub] didEstablishUpdateEventsStream];
    [[self.syncStrategy stub] dataDidChange];

    // when
    [(id<ZMPushChannelConsumer>)self.sut pushChannelDidOpen:nil withResponse:fakeResponse];
    
    // then
    XCTAssertEqual(self.pushChannelNotifications.count, 1u);
    NSNotification *note = self.pushChannelNotifications.firstObject;
    XCTAssertTrue([note.userInfo[ZMPushChannelIsOpenKey] boolValue]);
    XCTAssertEqualObjects(note.userInfo[ZMPushChannelResponseStatusKey], @(100));
}


@end



#if TARGET_OS_IPHONE

@implementation ZMOperationLoopTests (Background)

- (APSSignalingKeysStore *)prepareSelfClientForAPSSignalingStore
{
    [[self.syncStrategy stub] processSaveWithInsertedObjects:OCMOCK_ANY updateObjects:OCMOCK_ANY];
    [[self.syncStrategy stub] dataDidChange];
    
    NSString *macKey = @"OnuLUsjZT5ix8mebzewnNH7kVuLNYvDTxVFe8xiZ1u0=";
    NSString *encryptionKey = @"eiISyl78bYnFZaXsjvZh4v7d/mnNLDQNB+vRcsapovA=";
    
    NSData *macKeyData = [[NSData alloc] initWithBase64EncodedString:macKey options:0];
    NSData *encryptionKeyData = [[NSData alloc] initWithBase64EncodedString:encryptionKey options:0];
    
    UserClient *selfClient = [self createSelfClient];
    selfClient.apsDecryptionKey = encryptionKeyData;
    selfClient.apsVerificationKey = macKeyData;

    return [[APSSignalingKeysStore alloc] initWithUserClient:selfClient];
}

-(void)clearKeyChainData
{
    [ZMKeychain deleteAllKeychainItemsWithAccountName: @"APSVerificationKey"];
    [ZMKeychain deleteAllKeychainItemsWithAccountName: @"APSDecryptionKey"];
}

- (NSDictionary *)pushPayloadForEventPayload:(NSArray *)eventPayloads identifier:(NSUUID *)identifier
{
    return @{
             @"aps": @{@"content-available": @1},
             @"data": @{
                     @"id": identifier.transportString,
                     @"payload": eventPayloads
                     }
             };
}

- (NSDictionary *)pushPayloadForEventPayload:(NSArray *)eventPayloads
{
    return [self pushPayloadForEventPayload:eventPayloads identifier:NSUUID.createUUID];
}

- (NSDictionary *)alertPushPayloadForEventPayload:(NSArray *)eventPayloads
{
    return @{
             @"aps": @{@"content-available": @1,
                       @"alert": @{@"foo": @"bar"}
                       },
             @"data": @{
                     @"id": [[NSUUID createUUID] transportString],
                     @"payload": eventPayloads
                     }
             };
}

- (NSDictionary *)fallbackAPNSPayloadWithIdentifier:(NSUUID *)uuid
{
    return @{
             @"aps": @{
                     @"content-available": @1,
                     @"alert": @{ @"foo": @"bar" }
                     },
             @"data": @{
                     @"data": @{ @"id": uuid.transportString },
                     @"type": @"notice"
                     }
             };
}

- (NSDictionary *)payLoadForMessageAddEvent
{
    return [self payLoadForMessageAddEventWithNonce:NSUUID.createUUID];
}

- (NSDictionary *)payLoadForMessageAddEventWithNonce:(NSUUID *)uuid
{
    return @{
            @"conversation": [[NSUUID createUUID] transportString],
            @"time": [NSDate date],
            @"data": @{
                    @"content": @"saf",
                    @"nonce": [uuid transportString],
                    },
            @"from": [[NSUUID createUUID] transportString],
            @"type": @"conversation.message-add"
            };
}

- (NSDictionary *)encryptedPushPayload
{
    return @{
             @"aps" : @{@"alert": @{@"loc-args": @[],
                                    @"loc-key": @"push.notification.new_message"}
                        },
             @"data": @{@"data" : @"70XpQ4qri2D4YCU7lvSjaqk+SgN/s4dDv/J8uMUel0xY8quNetPF8cMXskAZwBI9EArjMY/NupWo8Bar14GHi9ISzlOswDsoQ6BQiFsEdnv4shT+ZpJ+wghmPF+sxWhys9048ny6WiSqywUNzsUPjDrudAAiG4bPjS2FjMou2/o7FpCg7+6p8fcSYCcvQllv6P8oidVbMlpnT1Bs7fK6fz9ceq6H3L+BKZai82H7gc6nxSS5Gjf56qvDqdc3J9jTowpdjyqHGO26YahMQtDf4tn6KuTSp4OG1qLPk6jFf4xO2q/WrxV2dnoXGXWbIZ4cnohkeA85QxMhpM9pIGAbZ58fRUt9fPXm6PmX3rqQY7MSv4TV1fLyb5Zqo/yqQbcE2qS/dJKRrzwW5MWlKVWfacuNRZnansMMGUYyt7iRpD/E8PdtSfW7QO/02Evureor7MqQ8AYf6Ivt3Ksf1wplXne0zl8CT5GMeExB7DLfyr8T1xK6H+u3y29FmI9/T01la5cbIq/E83Yh2LTNo3X4eOfZ6mhC0EIC8YEyo/0x2IHsLyCAjzvIFfTSD8tOpa1yQTBSQ3mGGDWiPJ3f6OypQFj+vY13Bq9WZoL9Q+UbYbxdzkaYILaX2UakZ5OafQ7nH0WslvfzjRsdYoruTGDV+E8mXB2JOZh9ij2PT8fWsyJJ9DqKg5Iw2EPfUlXBv3pXIpZuL6+g8c2von092bV2pHTWkPE4A2yvw3LTzI8e9puOr5K87JUQHdR7mfXYifErW+9TRrmBibF5wKZtVl97UOFOps4/ZXU9i6Lr0qKKMdX3iruo7o3fYcbJTajb+sZLttDPsKnJHnnMxJUB3D+I1UuA35hL6Fy2wLj2mRNAzWuitNj9MSDUhDHU42+bZnap",
                        @"mac": @"ZGe7fjgAEvTjfSSv2MuDHQe7BCRj2NT7qg8OAm8JZyI=",
                        @"type": @"cipher"
                        }
             };
}

- (void)testThatItForwardsEventsFromSilentPushesToTheTransportSessionAndBackgroundAPNSPingBackStatus
{
    // given
    NSUUID *identifier = NSUUID.createUUID;
    NSDictionary *eventPayload = [self payLoadForMessageAddEvent];
    NSDictionary *pushPayload = [self pushPayloadForEventPayload:@[eventPayload] identifier:identifier];
    NSArray *events = [ZMUpdateEvent eventsArrayFromPushChannelData:pushPayload[@"data"]];
    XCTAssertNotNil(events);
    
    // expect
    [(ZMSyncStrategy *)[self.syncStrategy expect] consumeUpdateEvents:events];
    [(ZMSyncStrategy *)[self.syncStrategy expect] updateBadgeCount];
    [[self.pingBackStatus expect] didReceiveVoIPNotification:OCMOCK_ANY handler:[OCMArg checkWithBlock:^BOOL((void(^handler)(ZMPushPayloadResult))) {
        handler(ZMPushPayloadResultSuccess);
        return YES;
    }]];

    // when
    [self.sut saveEventsAndSendNotificationForPayload:pushPayload fetchCompletionHandler:^(ZMPushPayloadResult result) {
        NOT_USED(result);
    } source:ZMPushNotficationTypeVoIP];
    WaitForAllGroupsToBeEmpty(1.0);
    
    // then
    [self.pingBackStatus verify];
    [self.syncStrategy verify];
}


- (void)testThatItForwardsEventsFromEncryptedPushesToTheTransportSessionAndPingBackStatus
{
    // given
    self.sut.apsSignalKeyStore = [self prepareSelfClientForAPSSignalingStore];
    id mockCryptoBox = [OCMockObject niceMockForClass:[CBCryptoBox class]];
    self.sut.cryptoBox = mockCryptoBox;
    
    NSUUID *nonce = NSUUID.createUUID;
    ZMGenericMessageBuilder *builder = [[ZMGenericMessageBuilder alloc] init];
    builder.messageId = nonce.transportString;
    ZMGenericMessage *genericMessage = builder.build;

    NSDictionary *pushPayload = [self encryptedPushPayload];
    NSDictionary *eventPayload = @{
                                   @"payload": @[
                                           @{
                                               @"conversation": @"164756de-7768-4cb8-9161-17879013994c",
                                               @"time": @"2015-10-05T15:23:42.159Z",
                                               @"data": @{
                                                   @"text": genericMessage.data.base64String,
                                                   @"sender": @"2867e165364b3b2f",
                                                   @"recipient": @"25667f739870989a"
                                               },
                                               @"from": @"f23aea6d-b7c6-4cfc-8df4-61905f5b71dc",
                                               @"type": @"conversation.otr-message-add"
                                               }
                                           ],
                                   @"id": NSUUID.createUUID.transportString
                                   };
    ZMUpdateEvent *event = [[ZMUpdateEvent eventsArrayFromPushChannelData:eventPayload] firstObject];
    [[[mockCryptoBox stub] andReturn:event] decryptUpdateEventAndAddClient:OCMOCK_ANY managedObjectContext:OCMOCK_ANY];
    
    // expect
    [[self.syncStrategy expect] updateBadgeCount];
    [[self.syncStrategy expect] consumeUpdateEvents:OCMOCK_ANY];
    [[self.pingBackStatus expect] didReceiveVoIPNotification:OCMOCK_ANY handler:[OCMArg checkWithBlock:^BOOL((void(^handler)(ZMPushPayloadResult))) {
        handler(ZMPushPayloadResultSuccess);
        return YES;
    }]];

    // when
    [self.sut saveEventsAndSendNotificationForPayload:pushPayload fetchCompletionHandler:^(ZMPushPayloadResult result) {
        NOT_USED(result);
    } source:ZMPushNotficationTypeVoIP];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [self.syncStrategy verify];
    [self.pingBackStatus verify];
    [mockCryptoBox verify];
    [self clearKeyChainData];
}

- (void)testThatCallsThePingBackStatusOnceForAVoIPNotificationToCancelFallBackAPNS
{
    // given
    NSString *eventType = @"user.update";
    
    NSDictionary *payload1 = @{
                               @"type" : eventType,
                               @"foo" : @"bar"
                               };
    NSDictionary *payload2 = @{
                               @"type" : eventType,
                               @"bar" : @"baz"
                               };
    
    // expect
    [[self.syncStrategy expect] updateBadgeCount];
    [[self.syncStrategy expect] consumeUpdateEvents:OCMOCK_ANY];
    [[self.pingBackStatus expect] didReceiveVoIPNotification:OCMOCK_ANY handler:[OCMArg checkWithBlock:^BOOL((void(^handler)(ZMPushPayloadResult))) {
        handler(ZMPushPayloadResultSuccess);
        return YES;
    }]];
    
    // when
    [self.sut saveEventsAndSendNotificationForPayload:[self pushPayloadForEventPayload:@[payload1, payload2]] fetchCompletionHandler:^(ZMPushPayloadResult result) {
        NOT_USED(result);
    } source:ZMPushNotficationTypeVoIP];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [self.pingBackStatus verify];
}

- (void)testThatItDoesNotCreateUpdateEventsOrForwardsAPNSWithTypeNoticeToTheSyncStrategyAndLocalNotificationDispatcher
{
    // given
    NSDictionary *payload = [self fallbackAPNSPayloadWithIdentifier:NSUUID.createUUID];
    
    // reject
    [[self.syncStrategy reject] updateBadgeCount];
    [[self.pingBackStatus reject] didReceiveVoIPNotification:OCMOCK_ANY handler:OCMOCK_ANY];
    
    // when
    [self.sut saveEventsAndSendNotificationForPayload:payload fetchCompletionHandler:nil source:ZMPushNotficationTypeAlert];
    
    // then
    [self.pingBackStatus verify];
}


- (void)testThatItDoesNotForwardEventsFromAlertPushesToTheTransportSessionAndLocalNotificationDispatcher
{
    // given
    NSDictionary *eventPayload = [self payLoadForMessageAddEvent];
    NSDictionary *pushPayload = [self alertPushPayloadForEventPayload:@[eventPayload]];
    NSArray *events = [ZMUpdateEvent eventsArrayFromPushChannelData:pushPayload[@"data"]];
    XCTAssertNotNil(events);
    
    // expect
    [(ZMSyncStrategy *)[self.syncStrategy expect] consumeUpdateEvents:events];
    [(ZMSyncStrategy *)[self.syncStrategy expect] updateBadgeCount];

    // when
    [self.sut saveEventsAndSendNotificationForPayload:pushPayload fetchCompletionHandler:nil source:ZMPushNotficationTypeAlert];
    WaitForAllGroupsToBeEmpty(1.0);
    
    // then
    [self.syncStrategy verify];
}

- (void)testThatItForwardsTheBackgroundFetchRequestToTheSyncStrategy
{
    // given
    XCTestExpectation *expectation = [self expectationWithDescription:@"Background fetch completed"];
    ZMBackgroundFetchHandler handler = ^(ZMBackgroundFetchResult result) {
        XCTAssertEqual(result, ZMBackgroundFetchResultNewData);
        [expectation fulfill];
    };
    
    // expect
    [(ZMSyncStrategy *)[[(id) self.syncStrategy expect] andCall:@selector(forward_startBackgroundFetchWithCompletionHandler:) onObject:self] startBackgroundFetchWithCompletionHandler:OCMOCK_ANY];
    
    // when
    [self.sut startBackgroundFetchWithCompletionHandler:handler];
    // then
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
    [(id) self.syncStrategy verify];
}

- (void)forward_startBackgroundFetchWithCompletionHandler:(ZMBackgroundFetchHandler)handler;
{
    handler(ZMBackgroundFetchResultNewData);
}

- (void)testThatItFiltersOutPreexisingMessageEventsAndForwardsTheEventsToTheSyncStrategyAndFilteredEventsToThePingBackStatus
{
    // given
    NSUUID *notificationID = NSUUID.createUUID;
    NSUUID *newNonce = NSUUID.createUUID;
    NSUUID *preexistingNonce = NSUUID.createUUID;
    
    // We need to stub these for the inserting
    [[self.syncStrategy stub] processSaveWithInsertedObjects:OCMOCK_ANY updateObjects:OCMOCK_ANY];
    [[self.syncStrategy stub] dataDidChange];
    
    ZMClientMessage *preexistingMessage = [ZMClientMessage insertNewObjectInManagedObjectContext:self.syncMOC];
    preexistingMessage.nonce = preexistingNonce;
    
    XCTAssertTrue([self.syncMOC saveOrRollback]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    NSArray *updateEventPayload = [self messageAddPayloadWithNonces:@[newNonce, preexistingNonce]];
    NSDictionary *pushPayload = [self pushPayloadForEventPayload:updateEventPayload identifier:notificationID];
    NSArray *events = [ZMUpdateEvent eventsArrayFromPushChannelData:@{ @"payload": updateEventPayload, @"id": notificationID.transportString }];
    
    NSArray *filteredEvents = [events filterWithBlock:^BOOL(ZMUpdateEvent *event) {
        if ([event.messageNonce isEqual:preexistingNonce]) {
            return NO;
        }
        return YES;
    }];
    
    XCTAssertNotNil(events);
    XCTAssertEqual(filteredEvents.count, 1lu);
    
    // expect
    [(ZMSyncStrategy *)[self.syncStrategy expect] consumeUpdateEvents:events];
    [(ZMSyncStrategy *)[self.syncStrategy expect] updateBadgeCount];
    [[self.pingBackStatus expect] didReceiveVoIPNotification:[OCMArg checkWithBlock:^BOOL(EventsWithIdentifier *eventsWithID) {
        XCTAssertEqualObjects(eventsWithID.events, filteredEvents);
        return YES;
    }] handler:OCMOCK_ANY];
    
    
    // when
    [self.sut saveEventsAndSendNotificationForPayload:pushPayload fetchCompletionHandler:nil source:ZMPushNotficationTypeVoIP];
    WaitForAllGroupsToBeEmpty(1.0);
    
    // then
    [self.syncStrategy verify];
    [self.pingBackStatus verify];
}

- (void)testThatItForwardsNoticeNotificationsToTheSyncStrategyAndPingBackStatus
{
    // given
    NSUUID *notificationID = NSUUID.createUUID;
    
    // We need to stub these for the inserting
    [[self.syncStrategy stub] processSaveWithInsertedObjects:OCMOCK_ANY updateObjects:OCMOCK_ANY];
    [[self.syncStrategy stub] dataDidChange];
    
    XCTAssertTrue([self.syncMOC saveOrRollback]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    NSDictionary *pushPayload =  @{@"aps" : @{},
                                   @"data" : @{
                                           @"data" : @{ @"id" : notificationID.transportString },
                                           @"type" : @"notice"
                                           }
                                   };
    
    // expect
    [[self.pingBackStatus expect] didReceiveVoIPNotification:[OCMArg checkWithBlock:^BOOL(EventsWithIdentifier *eventsWithID) {
        XCTAssertEqualObjects(eventsWithID.identifier, notificationID);
        XCTAssertTrue(eventsWithID.isNotice);
        return YES;
    }] handler:OCMOCK_ANY];
    
    
    // when
    [self.sut saveEventsAndSendNotificationForPayload:pushPayload fetchCompletionHandler:nil source:ZMPushNotficationTypeVoIP];
    WaitForAllGroupsToBeEmpty(1.0);
    
    // then
    [self.pingBackStatus verify];
}

- (NSArray *)messageAddPayloadWithNonces:(NSArray <NSUUID *>*)nonces
{
    return [nonces mapWithBlock:^NSDictionary *(NSUUID *nonce) {
        return [self payLoadForMessageAddEventWithNonce:nonce];
    }];
}

@end

#endif
