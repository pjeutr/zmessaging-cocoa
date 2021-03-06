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
@import ZMCMockTransport;
@import ZMCDataModel;

#import <zmessaging/zmessaging-Swift.h>

#import "MessagingTest+EventFactory.h"
#import "IntegrationTestBase.h"
#import "ZMUserSession+Internal.h"

@interface TestWindowObserver : NSObject <ZMConversationMessageWindowObserver>

@property (nonatomic, copy) void (^notificationHandler)(MessageWindowChangeInfo *note);
@property (nonatomic) NSMutableArray *notifications;
@property (nonatomic) id observerToken;
@property (nonatomic) ZMConversationMessageWindow *window;

- (void)registerOnConversation:(ZMConversation *)conversation;

@end


@interface CallingTests : IntegrationTestBase <ZMVoiceChannelStateObserver, ZMVoiceChannelParticipantsObserver>

@property (nonatomic) NSMutableArray *voiceChannelStateDidChangeNotes;
@property (nonatomic) NSMutableArray *voiceChannelParticipantStateDidChangeNotes;
@property (nonatomic) TestWindowObserver *windowObserver;
@property (nonatomic) BOOL useGroupConversation;
@property (nonatomic) MockConversation *mockConversationUnderTest;
@property (nonatomic) ZMConversation *conversationUnderTest;


- (void)tearDownVoiceChannelForConversation:(ZMConversation *)conversation;
- (BOOL)lastRequestContainsSelfStateJoined;
- (BOOL)lastRequestContainsSelfStateIdle;

- (void)selfJoinCall;
- (void)otherJoinCall;

- (void)selfDropCall;
- (void)otherDropsCall;
- (void)otherLeavesUnansweredCall;

- (void)selfLeavesConversation;

- (ZMTransportRequest *)selfJoinCallButDelayRequest;

- (void)usersJoinGroupCall:(NSOrderedSet *)users;
- (void)usersLeaveGroupCall:(NSOrderedSet *)users;

@end




@interface CallingTests (VideoCalling)

- (void)selfJoinVideoCall;
- (void)otherJoinVideoCall;

@end

