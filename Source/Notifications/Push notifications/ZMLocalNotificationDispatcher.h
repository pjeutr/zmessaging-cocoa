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
#import "ZMPushRegistrant.h"

@class ZMUpdateEvent;
@class ZMConversation;
@class ZMBadge;
@class ZMLocalNotificationForEvent;
@class ZMLocalNotificationForExpiredMessage;
@class ZMMessage;

extern NSString * _Null_unspecified const ZMConversationCancelNotificationForIncomingCallNotificationName;

@interface ZMLocalNotificationDispatcher : NSObject

- (nullable instancetype)initWithManagedObjectContext:(nonnull NSManagedObjectContext *)moc sharedApplication:(nonnull UIApplication *)sharedApplication;

- (void)tearDown;

@property (nonatomic, readonly, nonnull, copy) NSArray *eventsNotifications;

- (void)didFailToSentMessage:(nonnull ZMMessage *)message;
- (void)didFailToSendMessageInConversation:(nonnull ZMConversation *)conversation;

- (void)didReceiveUpdateEvents:(nullable NSArray <ZMUpdateEvent *>*)events;
- (nullable ZMLocalNotificationForEvent *)notificationForEvent:(nullable ZMUpdateEvent *)event;


// Can be used for cancelling all conversations if need
// Notifications for a specific conversation are otherwise deleted automatically when the message window changes and
// ZMConversationDidChangeVisibleWindowNotification is called
- (void)cancelAllNotifications;
- (void)cancelNotificationForConversation:(nonnull ZMConversation *)conversation;

@end
