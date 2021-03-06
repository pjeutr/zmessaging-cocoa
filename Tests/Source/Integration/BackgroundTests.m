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


@import UIKit;
@import ZMCMockTransport;
@import ZMCDataModel;

#import "IntegrationTestBase.h"
#import "ZMUserSession.h"
#import "ZMUserSession+Internal.h"

// needed to override very long timers
#import "ZMLocalNotificationDispatcher+Testing.h"
// -----------------------------------

@class BackgroundTests;

static BackgroundTests *zmCurrentBackgroundTest;
static NSTimeInterval zmMessageExpirationTimer = 0.3;



@interface BackgroundTests : IntegrationTestBase

@property (nonatomic) NSMutableArray *firedNotifications;

@end


@implementation BackgroundTests

- (BOOL)scheduleLocalNotification:(UILocalNotification *)notification;
{
    [zmCurrentBackgroundTest.firedNotifications addObject:notification];
    return YES;
}

- (BOOL)cancelLocalNotification:(UILocalNotification *)notification;
{
    [zmCurrentBackgroundTest.firedNotifications removeObject:notification];
    return YES;
}

- (void)setUp {
    [super setUp];
    [(UIApplication *)[(id)self.userSession.application stub] scheduleLocalNotification:[OCMArg checkWithSelector:@selector(scheduleLocalNotification:) onObject:self]];
    [(UIApplication *)[(id)self.userSession.application stub] cancelLocalNotification:[OCMArg checkWithSelector:@selector(cancelLocalNotification:) onObject:self]];

    zmCurrentBackgroundTest = self;
    self.firedNotifications = [NSMutableArray array];
}

- (void)tearDown {
    
    self.firedNotifications = nil;
    zmCurrentBackgroundTest = nil;
    self.mockTransportSession.disableEnqueueRequests = NO;
    [ZMMessage resetDefaultExpirationTime];
    [super tearDown];
}


- (void)testThatItSendsUILocalNotificationsForExpiredMessageRequestsWhenGoingToTheBackground
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request) {
        (void)request;
        return ResponseGenerator.ResponseNotCompleted;
    };
    
    ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
    
    // when
    [self.userSession performChanges:^{
        [conversation appendMessageWithText:@"foo"];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // background
    [[NSNotificationCenter defaultCenter] postNotificationName:UIApplicationDidEnterBackgroundNotification object:nil];
    
    [self.mockTransportSession expireAllBlockedRequests];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertEqual(self.firedNotifications.count, 1u);
}

- (void)testThatItSendsUILocalNotificationsForExpiredMessageNotPickedUpForRequestWhenGoingToTheBackground
{
    // given
    [ZMMessage setDefaultExpirationTime:zmMessageExpirationTimer];
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
    self.mockTransportSession.disableEnqueueRequests = YES;
    ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
    
    // when
    [self.userSession performChanges:^{
        [conversation appendMessageWithText:@"foo"];
    }];
    
    // background
    [[NSNotificationCenter defaultCenter] postNotificationName:UIApplicationDidEnterBackgroundNotification object:nil];
    [self spinMainQueueWithTimeout:zmMessageExpirationTimer + 0.1];
    
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.firedNotifications.count, 1u);
}

- (void)testThatItDoesNotCreateNotificationsForMessagesInTheSelfConversation
{
    // given
    [ZMMessage setDefaultExpirationTime:zmMessageExpirationTimer];
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
    self.mockTransportSession.disableEnqueueRequests = YES;
    ZMConversation *conversation = [self conversationForMockConversation:self.selfConversation];
    
    // when
    [self.userSession performChanges:^{
        [conversation appendMessageWithText:@"foo"];
    }];
    
    // background
    [[NSNotificationCenter defaultCenter] postNotificationName:UIApplicationDidEnterBackgroundNotification object:nil];
    [self spinMainQueueWithTimeout:zmMessageExpirationTimer + 0.1];
    
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.firedNotifications.count, 0u);

}


@end

