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
@import zmessaging;
@import ZMCDataModel;

#import "MessagingTest.h"
#import "ZMSyncState.h"
#import "ZMStateMachineDelegate.h"
#import "StateBaseTest.h"
#import "ZMPreBackgroundState.h"
#import "ZMMessageTranscoder.h"

@interface ZMPreBackgroundStateTest : StateBaseTest

@property (nonatomic, readonly) ZMPreBackgroundState* sut;

@end

@implementation ZMPreBackgroundStateTest

- (void)setUp {
    
    [super setUp];
    _sut = [[ZMPreBackgroundState alloc] initWithAuthenticationCenter:self.authenticationStatus clientRegistrationStatus:self.clientRegistrationStatus objectStrategyDirectory:self.objectDirectory stateMachineDelegate:self.stateMachine];
    
}

- (void)tearDown {
    _sut = nil;
    [super tearDown];
}

- (void)testThatThePolicyIsToProcessEvents
{
    XCTAssertEqual(self.sut.updateEventsPolicy, ZMUpdateEventPolicyProcess);
}

- (void)testThatItDoesNotSwitchesToSlowSyncState
{
    // expectation
    [[(id)self.stateMachine reject] startQuickSync];
    
    // when
    [self.sut didRequestSynchronization];
}

- (void)testThatItDoesNotSwitchesToBackgroundState
{
    // expectation
    [[(id)self.stateMachine reject] goToState:OCMOCK_ANY];
    
    // when
    [self.sut didEnterBackground];
}

- (void)testThatItDoesSwitchToQuickSyncOnEnteringForeground
{
    // expectation
    [[(id)self.stateMachine expect] startQuickSync];
    
    // when
    [self.sut didEnterForeground];
}

- (NSArray *)syncObjectsUsedByState
{
    return  @[ /* Note: these must be in the same order as in the class */
              self.objectDirectory.flowTranscoder,
              self.objectDirectory.systemMessageTranscoder,
              self.objectDirectory.textMessageTranscoder,
              self.objectDirectory.clientMessageTranscoder,
              self.objectDirectory.selfTranscoder,
              self.objectDirectory.assetTranscoder,
              ];
}

- (void)testThatItReturnsTheFirstRequestReturnedByASync
{
    /*
     NOTE: a failure here might mean that you either forgot to add a new sync to
     self.syncObjectsUsedByThisState, or that the order of that array doesn't match
     the order used by the state
     */
    
    [self checkThatItCallsRequestGeneratorsOnObjectsOfClass:[self syncObjectsUsedByState] creationOfStateBlock:^ZMSyncState *(id<ZMObjectStrategyDirectory> directory) {
        [[[(id)directory.systemMessageTranscoder stub] andReturnValue:@YES] hasPendingMessages];
        return [[ZMPreBackgroundState alloc] initWithAuthenticationCenter:self.authenticationStatus clientRegistrationStatus:self.clientRegistrationStatus objectStrategyDirectory:directory stateMachineDelegate:self.stateMachine];
    }];
    
}

- (void)testThatItSwitchesToBackgroundStateOnEnterIfThereAreNoPendingMessages
{
    // expect
    [[[(id)self.objectDirectory.clientMessageTranscoder expect] andReturnValue:@NO] hasPendingMessages];
    [[(id)self.stateMachine expect] goToState:[self.stateMachine backgroundState]];
    
    // when
    [self.sut didEnterState];
}

- (void)testThatItDoesNotSwitchToBackgroundStateOnEnterIfThereArePendingMessages
{
    // expect
    [[[(id)self.objectDirectory.clientMessageTranscoder expect] andReturnValue:@YES] hasPendingMessages];
    [[(id)self.stateMachine reject] goToState:OCMOCK_ANY];
    
    // when
    [self.sut didEnterState];
}

- (void)testThatItSwitchesToBackgroundStateOnNextRequestIfThereAreNoPendingMessages
{
    // expect
    [[[(id)self.objectDirectory.clientMessageTranscoder expect] andReturnValue:@NO] hasPendingMessages];
    [[(id)self.stateMachine expect] goToState:[self.stateMachine backgroundState]];
    
    // when
    [self.sut dataDidChange];
}

- (void)testThatItDoesNotSwitchToBackgroundStateOnNextRequestIfThereArePendingMessages
{
    // expect
    [[[(id)self.objectDirectory.clientMessageTranscoder expect] andReturnValue:@YES] hasPendingMessages];
    [[(id)self.stateMachine reject] goToState:OCMOCK_ANY];
    for(id transcoder in self.syncObjectsUsedByState) {
        [[[[transcoder stub] andReturn:nil] requestGenerators] nextRequest];
    }
    
    // when
    [self.sut dataDidChange];
}

- (void)testThatItCreatesABackgroundActivityOnEnterAndItTerminatesItOnLeave
{
    // given
    [[[(id)self.objectDirectory.clientMessageTranscoder expect] andReturnValue:@YES] hasPendingMessages];
    
    // expect
    id mockActivity = [OCMockObject mockForClass:ZMBackgroundActivity.class];
    [[[[mockActivity expect] andReturn:mockActivity] classMethod] beginBackgroundActivityWithName:OCMOCK_ANY];
    [[[[mockActivity reject] andReturn:mockActivity] classMethod] beginBackgroundActivityWithName:OCMOCK_ANY];
    
    // when (1)
    [self.sut didEnterState];
    
    // then
    [mockActivity verify];
    
    // expect
    [[mockActivity expect] endActivity];
    
    // and when (2)
    [self.sut didLeaveState];
    
    // then
    [mockActivity verify];

    
    // after
    [mockActivity stopMocking];
    
    
}
@end
