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

@import ZMCDataModel;

#import "NotificationObservers.h"

@interface ChangeObserver ()
@end



@implementation ChangeObserver

- (instancetype)init
{
    self = [super init];
    if (self) {
        _notifications = [[NSMutableArray alloc] init];
        [self startObservering];
    }
    return self;
}

- (void)dealloc
{
    NSAssert(self.tornDown, @"needs to teardown conversationList token");
    [self stopObservering];
}

- (void)clearNotifications;
{
    [self.notifications removeAllObjects];
}

- (void)startObservering;
{
}

- (void)stopObservering;
{
}

- (void)tearDown;
{
}

@end

@interface ConversationChangeObserver ()
@property (nonatomic, weak) ZMConversation *conversation;
@property (nonatomic) id token;
@end


@implementation ConversationChangeObserver

- (instancetype)initWithConversation:(ZMConversation *)conversation
{
    self = [super init];
    if(self) {
        self.conversation = conversation;
        self.token = [conversation addConversationObserver:self];
    }
    return self;
}

- (void)conversationDidChange:(ConversationChangeInfo *)note;
{
    [self.notifications addObject:note];
    if (self.notificationCallback) {
        self.notificationCallback(note);
    }
}

- (void)tearDown
{
    [ZMConversation removeConversationObserverForToken:self.token];
    self.token = nil;
    self.tornDown = YES;
}

@end



@interface ConversationListChangeObserver ()
@property (nonatomic, weak) ZMConversationList *conversationList;
@property (nonatomic) id token;
@end

@implementation ConversationListChangeObserver

ZM_EMPTY_ASSERTING_INIT()

- (instancetype)initWithConversationList:(ZMConversationList *)conversationList;
{
    self = [super init];
    if(self) {
        self.conversationList = conversationList;
        self.token = [conversationList addConversationListObserver:self];
    }
    return self;
}


- (void)tearDown
{
    [self.conversationList removeConversationListObserverForToken:self.token];
    self.token = nil;
    self.tornDown = YES;
}

- (void)dealloc
{
    NSAssert(self.tornDown, @"needs to teardown conversationList token");
}

- (void)conversationListDidChange:(ConversationListChangeInfo *)note;
{
    [self.notifications addObject:note];
    if (self.notificationCallback) {
        self.notificationCallback(note);
    }

}

@end



@interface UserChangeObserver ()
@property (nonatomic, weak) ZMUser *user;
@property (nonatomic) id token;
@end

@implementation UserChangeObserver

- (instancetype)initWithUser:(ZMUser *)user;
{
    self = [super init];
    if(self) {
        self.user = user;
        self.token = [ZMUser addUserObserver:self forUsers:@[user] managedObjectContext:user.managedObjectContext];
    }
    return self;
}


- (void)startObservering;
{
}

- (void)stopObservering
{
}

- (void)userDidChange:(UserChangeInfo *)info;
{
    [self.notifications addObject:info];
    if (self.notificationCallback) {
        self.notificationCallback(info);
    }
}

-(void)tearDown
{
    [ZMUser removeUserObserverForToken:self.token];
    self.token = nil;
    self.tornDown = YES;
}

- (void)dealloc
{
    [self tearDown];
}

@end



@interface MessageChangeObserver ()
@property (nonatomic, weak) ZMMessage *message;
@property (nonatomic) id token;
@end

@implementation MessageChangeObserver

- (instancetype)initWithMessage:(ZMMessage *)message
{
    self = [super init];
    if(self) {
        self.message = message;
        self.token = [ZMMessageNotification addMessageObserver:self forMessage:message];
    }
    return self;
}


- (void)tearDown
{
    [ZMMessageNotification removeMessageObserverForToken:self.token];
    self.token = nil;
    self.tornDown = YES;
}

- (void)messageDidChange:(MessageChangeInfo *)changeInfo
{
    [self.notifications addObject:changeInfo];
}

@end



@interface MessageWindowChangeObserver ()
@property (nonatomic, weak) ZMConversationMessageWindow *window;
@property (nonatomic) id token;

@end


@implementation MessageWindowChangeObserver

- (instancetype)initWithMessageWindow:(ZMConversationMessageWindow *)window
{
    self = [super init];
    if(self) {
        self.window = window;
        self.token = [window addConversationWindowObserver:self];
    }
    return self;
}

- (void)tearDown
{
    [self.window removeConversationWindowObserverToken:self.token];
    self.token = nil;
    self.tornDown = YES;
}

- (void)conversationWindowDidChange:(MessageWindowChangeInfo *)note
{
    [self.notifications addObject:note];
}

@end




static NSString * const Placeholder = @"Placeholder";

@interface MockConversationWindowObserver ()

@property (nonatomic, readonly) NSMutableOrderedSet *mutableMessages;
@property (nonatomic, readonly) id opaqueToken;
@end


@implementation MockConversationWindowObserver

- (instancetype)initWithConversation:(ZMConversation *)conversation size:(NSUInteger)size
{
    self = [super init];
    if(self) {
        _window = [conversation conversationWindowWithSize:size];
        _mutableMessages = [self.window.messages mutableCopy];
        
        _opaqueToken = [self.window addConversationWindowObserver:self];
    }
    return self;
}

- (void)dealloc
{
    [self.window removeConversationWindowObserverToken:self.opaqueToken];
    _opaqueToken = nil;
}

- (void)conversationWindowDidChange:(MessageWindowChangeInfo *)note
{
    [note.deletedIndexes enumerateIndexesWithOptions:NSEnumerationReverse usingBlock:^(NSUInteger idx, BOOL *stop ZM_UNUSED) {
        [self.mutableMessages removeObjectAtIndex:idx];
    }];
    
    [note.insertedIndexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop ZM_UNUSED) {
        [self.mutableMessages insertObject:Placeholder atIndex:idx];
    }];
    
    [note.movedIndexPairs enumerateObjectsUsingBlock:^(ZMMovedIndex *moved, NSUInteger idx ZM_UNUSED, BOOL *stop ZM_UNUSED) {
        [self.mutableMessages moveObjectsAtIndexes:[NSIndexSet indexSetWithIndex:moved.from] toIndex:moved.to];
    }];
    
    for(NSUInteger i = 0; i < self.mutableMessages.count; ++i) {
        if(self.mutableMessages[i] == Placeholder) {
            [self.mutableMessages replaceObjectAtIndex:i withObject:self.window.messages[i]];
        }
    }
}

- (NSOrderedSet *)computedMessages
{
    return [self.mutableMessages copy];
}

@end
