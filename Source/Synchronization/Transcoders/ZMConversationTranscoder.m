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


@import ZMCSystem;
@import ZMUtilities;
@import ZMTransport;

#import "ZMConversationTranscoder.h"
#import "ZMAuthenticationStatus.h"
#import "ZMConversation+Internal.h"
#import "ZMUpdateEvent.h"
#import "ZMConversation.h"
#import "ZMConversation+OTR.h"
#import "ZMUser+internal.h"
#import <zmessaging/NSManagedObjectContext+zmessaging.h>
#import "ZMUpstreamModifiedObjectSync.h"
#import "ZMUpstreamInsertedObjectSync.h"
#import "ZMDownstreamObjectSync.h"
#import "ZMConnection+Internal.h"
#import "ZMSyncStrategy.h"
#import "ZMSingleRequestSync.h"
#import "ZMMessage+Internal.h"
#import "ZMRemoteIdentifierObjectSync.h"
#import "ZMSimpleListRequestPaginator.h"
#import "ZMUpstreamTranscoder.h"
#import "ZMUpstreamRequest.h"

static NSString *const ConversationsPath = @"/conversations";
static NSString *const ConversationIDsPath = @"/conversations/ids";

NSUInteger ZMConversationTranscoderListPageSize = 100;
const NSUInteger ZMConversationTranscoderDefaultConversationPageSize = 32;

static NSString *const UserInfoTypeKey = @"type";
static NSString *const UserInfoUserKey = @"user";
static NSString *const UserInfoAddedValueKey = @"added";
static NSString *const UserInfoRemovedValueKey = @"removed";

static NSString *const ConversationInfoArchivedValueKey = @"archived";

@interface ZMConversationTranscoder () <ZMSimpleListRequestPaginatorSync>

@property (nonatomic) ZMUpstreamModifiedObjectSync *modifiedSync;
@property (nonatomic) ZMUpstreamInsertedObjectSync *insertedSync;

@property (nonatomic) ZMDownstreamObjectSync *downstreamSync;
@property (nonatomic, weak) ZMSyncStrategy *syncStrategy;
@property (nonatomic) ZMRemoteIdentifierObjectSync *remoteIDSync;
@property (nonatomic) ZMSimpleListRequestPaginator *listPaginator;
@property (nonatomic, weak) ZMAuthenticationStatus *authenticationStatus;
@end


@interface ZMConversationTranscoder (DownstreamTranscoder) <ZMDownstreamTranscoder>
@end


@interface ZMConversationTranscoder (UpstreamTranscoder) <ZMUpstreamTranscoder>
@end


@interface ZMConversationTranscoder (PaginatedRequest) <ZMRemoteIdentifierObjectTranscoder>
@end


@implementation ZMConversationTranscoder

- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)moc;
{
    Require(NO);
    self = [super initWithManagedObjectContext:moc];
    NOT_USED(self);
    self = nil;
    return self;
}

- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)moc authenticationStatus:(ZMAuthenticationStatus *)authenticationStatus syncStrategy:(ZMSyncStrategy *)syncStrategy;
{
    self = [super initWithManagedObjectContext:moc];
    if (self) {
        self.authenticationStatus = authenticationStatus;
        
        NSArray<NSString *> *keysToSync = @[ZMConversationUserDefinedNameKey,
                                            ZMConversationUnsyncedInactiveParticipantsKey,
                                            ZMConversationUnsyncedActiveParticipantsKey,
                                            ZMConversationIsSilencedKey,
                                            ZMConversationIsArchivedKey,
                                            ZMConversationIsSelfAnActiveMemberKey,
                                            ZMConversationClearedEventIDDataKey];
        
        self.modifiedSync = [[ZMUpstreamModifiedObjectSync alloc] initWithTranscoder:self entityName:ZMConversation.entityName updatePredicate:nil filter:nil keysToSync:keysToSync managedObjectContext:moc];
        self.insertedSync = [[ZMUpstreamInsertedObjectSync alloc] initWithTranscoder:self entityName:ZMConversation.entityName managedObjectContext:moc];
        NSPredicate *conversationPredicate =
        [NSPredicate predicateWithFormat:@"%K != %@ AND (connection == nil OR (connection.status != %d AND connection.status != %d) ) AND needsToBeUpdatedFromBackend == YES",
         [ZMConversation remoteIdentifierDataKey], nil,
         ZMConnectionStatusPending,  ZMConnectionStatusIgnored
         ];
         
        self.downstreamSync = [[ZMDownstreamObjectSync alloc] initWithTranscoder:self entityName:ZMConversation.entityName predicateForObjectsToDownload:conversationPredicate managedObjectContext:self.managedObjectContext];
        self.listPaginator = [[ZMSimpleListRequestPaginator alloc] initWithBasePath:ConversationIDsPath
                                                                           startKey:@"start"
                                                                           pageSize:ZMConversationTranscoderListPageSize
                                                               managedObjectContext:self.managedObjectContext
                                                                    includeClientID:NO
                                                                         transcoder:self];
        self.syncStrategy = syncStrategy;
        self.conversationPageSize = ZMConversationTranscoderDefaultConversationPageSize;
        self.remoteIDSync = [[ZMRemoteIdentifierObjectSync alloc] initWithTranscoder:self managedObjectContext:self.managedObjectContext];
    }
    return self;
}

- (NSUUID *)nextUUIDFromResponse:(ZMTransportResponse *)response forListPaginator:(ZMSimpleListRequestPaginator *)paginator
{
    NOT_USED(paginator);
    
    NSDictionary *payload = [response.payload asDictionary];
    NSArray *conversationIDStrings = [payload arrayForKey:@"conversations"];
    NSArray *conversationUUIDs = [conversationIDStrings mapWithBlock:^id(NSString *obj) {
        return [obj UUID];
    }];
    NSSet *conversationUUIDSet = [NSSet setWithArray:conversationUUIDs];
    [self.remoteIDSync addRemoteIdentifiersThatNeedDownload:conversationUUIDSet];
    return conversationUUIDs.lastObject;
}

- (void)setNeedsSlowSync
{
    [self.listPaginator resetFetching];
    [self.remoteIDSync setRemoteIdentifiersAsNeedingDownload:[NSSet set]];
}


- (BOOL)isSlowSyncDone
{
    return ( ! self.listPaginator.hasMoreToFetch )  && (self.remoteIDSync.isDone);
}

- (NSArray *)contextChangeTrackers
{
    return @[self.downstreamSync, self.insertedSync, self.modifiedSync];
}

- (NSArray *)requestGenerators;
{
    if (! self.isSlowSyncDone) {
        return  @[self.listPaginator, self.remoteIDSync];
    } else {
        return  @[self.downstreamSync, self.insertedSync, self.modifiedSync];
    }
}

- (ZMConversation *)createConversationFromTransportData:(NSDictionary *)transportData
{
    // If the conversation is not a group conversation, we need to make sure that we check if there's any existing conversation without a remote identifier for that user.
    // If it is a group conversation, we don't need to.
    
    NSNumber *typeNumber = [transportData numberForKey:@"type"];
    VerifyReturnNil(typeNumber != nil);
    ZMConversationType const type = [ZMConversation conversationTypeFromTransportData:typeNumber];
    if (type == ZMConversationTypeGroup || type == ZMConversationTypeSelf) {
        return [self createGroupOrSelfConversationFromTransportData:transportData];
    } else {
        return [self createOneOnOneConversationFromTransportData:transportData type:type];
    }
}

- (ZMConversation *)createGroupOrSelfConversationFromTransportData:(NSDictionary *)transportData
{
    NSUUID * const convRemoteID = [transportData uuidForKey:@"id"];
    if(convRemoteID == nil) {
        ZMLogError(@"Missing ID in conversation payload");
        return nil;
    }
    BOOL conversationCreated = NO;
    ZMConversation *conversation = [ZMConversation conversationWithRemoteID:convRemoteID createIfNeeded:YES inContext:self.managedObjectContext created:&conversationCreated];
    [conversation updateWithTransportData:transportData];
    if (conversation.conversationType != ZMConversationTypeSelf && conversationCreated && ! self.authenticationStatus.registeredOnThisDevice) {
        [conversation appendStartedUsingThisDeviceMessageIfNeeded];
        [self.managedObjectContext enqueueDelayedSave];
    }
    return conversation;
}

- (ZMConversation *)createOneOnOneConversationFromTransportData:(NSDictionary *)transportData type:(ZMConversationType const)type;
{
    NSUUID * const convRemoteID = [transportData uuidForKey:@"id"];
    if(convRemoteID == nil) {
        ZMLogError(@"Missing ID in conversation payload");
        return nil;
    }
    
    // Get the 'other' user:
    NSDictionary *members = [transportData dictionaryForKey:@"members"];
    
    NSArray *others = [members arrayForKey:@"others"];

    if ((type == ZMConversationTypeConnection) && (others.count == 0)) {
        // But be sure to update the conversation if it already exists:
        ZMConversation *conversation = [ZMConversation conversationWithRemoteID:convRemoteID createIfNeeded:NO inContext:self.managedObjectContext];
        if ((conversation.conversationType != ZMConversationTypeOneOnOne) &&
            (conversation.conversationType != ZMConversationTypeConnection))
        {
            conversation.conversationType = type;
        }
        
        // Ignore everything else since we can't find out which connection it belongs to.
        return nil;
    }
    
    VerifyReturnNil(others.count != 0); // No other users? Self conversation?
    VerifyReturnNil(others.count < 2); // More than 1 other user in a conversation that's not a group conversation?
    
    NSUUID *otherUserRemoteID = [[others[0] asDictionary] uuidForKey:@"id"];
    VerifyReturnNil(otherUserRemoteID != nil); // No remote ID for other user?
    
    ZMUser *user = [ZMUser userWithRemoteID:otherUserRemoteID createIfNeeded:YES inContext:self.managedObjectContext];
    ZMConversation *conversation = user.connection.conversation;
    
    BOOL conversationCreated = NO;
    if (conversation == nil) {
        // if the conversation already exist, it will pick it up here and hook it up to the connection
        conversation = [ZMConversation conversationWithRemoteID:convRemoteID createIfNeeded:YES inContext:self.managedObjectContext created:&conversationCreated];
        RequireString(conversation.conversationType != ZMConversationTypeGroup, "Conversation for connection is a group conversation.");
        user.connection.conversation = conversation;
    } else {
        // check if a conversation already exists with that ID
        [conversation mergeWithExistingConversationWithRemoteID:convRemoteID];
        conversationCreated = YES;
    }
    
    conversation.remoteIdentifier = convRemoteID;
    [conversation updateWithTransportData:transportData];
    if (conversationCreated && ! self.authenticationStatus.registeredOnThisDevice) {
        [conversation appendStartedUsingThisDeviceMessageIfNeeded];
        [self.managedObjectContext enqueueDelayedSave];

    }
    return conversation;
}


- (BOOL)shouldProcessUpdateEvent:(ZMUpdateEvent *)event
{
    switch (event.type) {
        case ZMUpdateEventConversationMessageAdd:
        case ZMUpdateEventConversationClientMessageAdd:
        case ZMUpdateEventConversationOtrMessageAdd:
        case ZMUpdateEventConversationOtrAssetAdd:
        case ZMUpdateEventConversationKnock:
        case ZMUpdateEventConversationAssetAdd:
        case ZMUpdateEventConversationMemberJoin:
        case ZMUpdateEventConversationMemberLeave:
        case ZMUpdateEventConversationRename:
        case ZMUpdateEventConversationMemberUpdate:
        case ZMUpdateEventConversationVoiceChannelActivate:
        case ZMUpdateEventConversationVoiceChannelDeactivate:
        case ZMUpdateEventConversationVoiceChannel:
        case ZMUpdateEventConversationCreate:
        case ZMUpdateEventConversationConnectRequest:
        case ZMUpdateEventCallState:
            return YES;
        default:
            return NO;
    }
}

- (ZMConversation *)conversationFromEventPayload:(ZMUpdateEvent *)event conversationMap:(ZMConversationMapping *)prefetchedMapping
{
    NSUUID * const conversationID = [event.payload optionalUuidForKey:@"conversation"];
    
    if (nil == conversationID) {
        return nil;
    }
    
    if (nil != prefetchedMapping[conversationID]) {
        return prefetchedMapping[conversationID];
    }
    
    ZMConversation *conversation = [ZMConversation conversationWithRemoteID:conversationID createIfNeeded:NO inContext:self.managedObjectContext];
    if (conversation == nil) {
        conversation = [ZMConversation conversationWithRemoteID:conversationID createIfNeeded:YES inContext:self.managedObjectContext];
        // if we did not have this conversation before, refetch it
        conversation.needsToBeUpdatedFromBackend = YES;
    }
    return conversation;
}

- (void)updatePropertiesOfConversation:(ZMConversation *)conversation fromEvent:(ZMUpdateEvent *)event
{
    // Update last event-id
    NSDate *oldLastTimeStamp = conversation.lastServerTimeStamp;
    ZMEventID *oldLastEventID = conversation.lastEventID;

    NSDate *timeStamp = event.timeStamp;
    ZMEventID *eventId = event.eventID;
    
    if (timeStamp != nil) {
        [conversation updateLastServerTimeStampIfNeeded:timeStamp];
        if (event.type != ZMUpdateEventConversationMemberUpdate) {
            conversation.lastModifiedDate = [NSDate lastestOfDate:conversation.lastModifiedDate and:timeStamp];
        }
    }
    [conversation updateLastEventIDIfNeededWithEventID:eventId];

    
    BOOL eventIsCompletedVoiceCall = NO;
    if (event.type == ZMUpdateEventConversationVoiceChannelDeactivate) {
        NSString *reason = [[event.payload optionalDictionaryForKey:@"data"] optionalStringForKey:@"reason"];
        eventIsCompletedVoiceCall = ! [reason isEqualToString:@"missed"];
    }
    
    if ((! [ZMMessage doesEventTypeGenerateMessage:event.type]) || eventIsCompletedVoiceCall) {
        [self updateLastReadForInvisibleEventInConversation:conversation
                                                  timeStamp:timeStamp
                                           oldLastTimeStamp:oldLastTimeStamp
                                                    eventID:eventId
                                             oldLastEventID:oldLastEventID];
    }
    
    // Unarchive conversations when applicable
    [conversation unarchiveConversationFromEvent:event];
}

- (void)updateLastReadForInvisibleEventInConversation:(ZMConversation *)conversation
                                            timeStamp:(NSDate *)timeStamp
                                     oldLastTimeStamp:(NSDate *)oldLastTimeStamp
                                              eventID:(ZMEventID *)eventID
                                       oldLastEventID:(ZMEventID *)oldLastEventID
{

    if (timeStamp != nil && oldLastTimeStamp != nil && [oldLastTimeStamp isEqualToDate:conversation.lastReadServerTimeStamp]) {
        [conversation updateLastReadServerTimeStampIfNeededWithTimeStamp:timeStamp andSync:YES];
    }
    
    if (eventID != nil && oldLastEventID != nil && [oldLastEventID isEqualToEventID:conversation.lastReadEventID]) {
        [conversation updateLastReadEventIDIfNeededWithEventID:eventID];
    }
}

- (void)updatePropertiesOfConversation:(ZMConversation *)conversation withPostPayloadEvent:(ZMUpdateEvent *)event
{
    // Clear self user leave event if conversation was previously cleared
    BOOL conversationWasCleared = conversation.clearedEventID != nil || conversation.clearedTimeStamp != nil;
    BOOL selfUserLeft = (event.type == ZMUpdateEventConversationMemberLeave) &&
                        ([event.senderUUID isEqual:[ZMUser selfUserInContext:self.managedObjectContext].remoteIdentifier]);
    
    if(conversationWasCleared && selfUserLeft) {
        BOOL isResponseToClearEvent = [conversation.clearedEventID isEqual:conversation.lastEventID] ||
        [conversation.clearedTimeStamp isEqualToDate:conversation.lastServerTimeStamp];
        if (isResponseToClearEvent) {
            [conversation updateClearedFromPostPayloadEvent:event];
        }
    }
    
    // Self generated messages shouldn't generate unread dots
    [conversation updateLastReadFromPostPayloadEvent:event];
}

- (BOOL)isSelfConversationEvent:(ZMUpdateEvent *)event;
{
    NSUUID * const conversationID = event.conversationUUID;
    return [conversationID isSelfConversationRemoteIdentifierInContext:self.managedObjectContext];
}

- (void)createConversationFromEvent:(ZMUpdateEvent *)event {
    NSDictionary *payloadData = [event.payload dictionaryForKey:@"data"];
    if(payloadData == nil) {
        ZMLogError(@"Missing conversation payload in ZMUpdateEventConversationCreate");
        return;
    }
    [self createConversationFromTransportData:payloadData];
}

- (void)processEvents:(NSArray<ZMUpdateEvent *> *)events
           liveEvents:(BOOL)liveEvents
       prefetchResult:(ZMFetchRequestBatchResult *)prefetchResult;
{
    for(ZMUpdateEvent *event in events) {
        
        if (event.type == ZMUpdateEventConversationCreate) {
            [self createConversationFromEvent:event];
            continue;
        }
        
        if ([self isSelfConversationEvent:event]) {
            continue;
        }
        
        ZMConversation *conversation = [self conversationFromEventPayload:event
                                                          conversationMap:prefetchResult.conversationsByRemoteIdentifier];
        if(conversation == nil) {
            continue;
        }
        [self markConversationForDownloadIfNeeded:conversation afterEvent:event];
        
        if(![self shouldProcessUpdateEvent:event]) {
            continue;
        }
        [self updatePropertiesOfConversation:conversation fromEvent:event];
        
        if(liveEvents) {
            [self processUpdateEvent:event forConversation:conversation];
        }
    }
}

- (NSSet<NSUUID *> *)conversationRemoteIdentifiersToPrefetchToProcessEvents:(NSArray<ZMUpdateEvent *> *)events
{
    return [NSSet setWithArray:[events mapWithBlock:^NSUUID *(ZMUpdateEvent *event) {
        return [event.payload optionalUuidForKey:@"conversation"];
    }]];
}


- (void)markConversationForDownloadIfNeeded:(ZMConversation *)conversation afterEvent:(ZMUpdateEvent *)event {
    
    switch(event.type) {
        case ZMUpdateEventConversationOtrAssetAdd:
        case ZMUpdateEventConversationOtrMessageAdd:
        case ZMUpdateEventConversationRename:
        case ZMUpdateEventConversationMemberLeave:
        case ZMUpdateEventConversationKnock:
        case ZMUpdateEventConversationMessageAdd:
        case ZMUpdateEventConversationTyping:
        case ZMUpdateEventConversationAssetAdd:
        case ZMUpdateEventConversationClientMessageAdd:
        case ZMUpdateEventCallState:
        case ZMUpdateEventConversationVoiceChannelActivate:
        case ZMUpdateEventConversationVoiceChannelDeactivate:
            break;
        default:
            return;
    }
    
    BOOL isConnection = conversation.connection.status == ZMConnectionStatusPending
        || conversation.connection.status == ZMConnectionStatusSent
        || conversation.conversationType == ZMConversationTypeConnection; // the last OR should be covered by the
                                                                      // previous cases already, but just in case..
    if(isConnection || conversation.conversationType == ZMConversationTypeInvalid) {
        conversation.needsToBeUpdatedFromBackend = YES;
        conversation.connection.needsToBeUpdatedFromBackend = YES;
    }
}

- (void)processUpdateEvent:(ZMUpdateEvent *)event forConversation:(ZMConversation *)conversation
{
    switch (event.type) {
        case ZMUpdateEventConversationRename: {
            NSDictionary *data = [event.payload dictionaryForKey:@"data"];
            NSString *newName = [data stringForKey:@"name"];
            conversation.userDefinedName = newName;
            break;
        }
        case ZMUpdateEventConversationMemberJoin:
        {
            [self processMemberJoinEvent:event forConversation:conversation];
            break;
        }
        case ZMUpdateEventConversationMemberLeave:
        {
            [self processMemberLeaveEvent:event forConversation:conversation];
            break;
        }
        case ZMUpdateEventConversationMemberUpdate:
        {
            [self processMemberUpdateEvent:event forConversation:conversation];
            break;
        }
        default: {
            break;
        }
    }
}

- (void)processMemberJoinEvent:(ZMUpdateEvent *)event forConversation:(ZMConversation *)conversation
{
    NSSet *users = [event usersFromUserIDsInManagedObjectContext:self.managedObjectContext createIfNeeded:YES];
    for (ZMUser *user in users) {
        [conversation internalAddParticipant:user isAuthoritative:YES];
        [conversation synchronizeAddedUser:user];
    }
}

- (void)processMemberLeaveEvent:(ZMUpdateEvent *)event forConversation:(ZMConversation *)conversation
{
    NSUUID *senderUUID = event.senderUUID;
    ZMUser *sender = [ZMUser userWithRemoteID:senderUUID createIfNeeded:YES inContext:self.managedObjectContext];
    
    NSSet *users = [event usersFromUserIDsInManagedObjectContext:self.managedObjectContext createIfNeeded:YES];
    for (ZMUser *user in users) {
        [conversation internalRemoveParticipant:user sender:sender];
        [conversation synchronizeRemovedUser:user];
    }
}

- (void)processMemberUpdateEvent:(ZMUpdateEvent *)event forConversation:(ZMConversation *)conversation
{
    NSDictionary *dataPayload = [event.payload.asDictionary dictionaryForKey:@"data"];
 
    if(dataPayload) {
        [conversation updateSelfStatusFromDictionary:dataPayload timeStamp:event.timeStamp];
    }
}

@end



@implementation ZMConversationTranscoder (UpstreamTranscoder)

- (BOOL)shouldProcessUpdatesBeforeInserts;
{
    return NO;
}

- (ZMUpstreamRequest *)requestForUpdatingObject:(ZMConversation *)updatedConversation forKeys:(NSSet *)keys;
{
    ZMUpstreamRequest *request = nil;
    if([keys containsObject:ZMConversationUserDefinedNameKey]) {
        request = [self requestForUpdatingUserDefinedNameInConversation:updatedConversation];
    }
    if (request == nil && [keys containsObject:ZMConversationUnsyncedInactiveParticipantsKey]) {
        request = [self requestForUpdatingUnsyncedInactiveParticipantsInConversation:updatedConversation];
    }
    if (request == nil && [keys containsObject:ZMConversationUnsyncedActiveParticipantsKey]) {
        request = [self requestForUpdatingUnsyncedActiveParticipantsInConversation:updatedConversation];
    }
    if (request == nil && (   [keys containsObject:ZMConversationIsSilencedKey]
                           || [keys containsObject:ZMConversationIsArchivedKey]
                           || [keys containsObject:ZMConversationClearedEventIDDataKey]) )
    {
        request = [self requestForUpdatingConversationSelfInfo:updatedConversation];
    }
    if (request == nil && [keys containsObject:ZMConversationIsSelfAnActiveMemberKey] && ! updatedConversation.isSelfAnActiveMember) {
        request = [self requestForLeavingConversation:updatedConversation];
    }
    if (request == nil) {
        ZMTrapUnableToGenerateRequest(keys, self);
    }
    return request;
}

- (ZMUpstreamRequest *)requestForLeavingConversation:(ZMConversation *)conversation
{
    ZMUser *selfUser = [ZMUser selfUserInContext:self.managedObjectContext];

    if (conversation.remoteIdentifier == nil) {
        return nil;
    }
    
    NSString *path = [NSString pathWithComponents:@[ ConversationsPath, conversation.remoteIdentifier.transportString, @"members", selfUser.remoteIdentifier.transportString]];
    ZMTransportRequest *request = [ZMTransportRequest requestWithPath:path method:ZMMethodDELETE payload:nil];
    return [[ZMUpstreamRequest alloc] initWithKeys:[NSSet setWithObject:ZMConversationIsSelfAnActiveMemberKey] transportRequest:request userInfo:nil];
}

- (ZMUpstreamRequest *)requestForUpdatingUnsyncedActiveParticipantsInConversation:(ZMConversation *)conversation
{
    NSOrderedSet *unsyncedUserIDs = [conversation.unsyncedActiveParticipants mapWithBlock:^NSString*(ZMUser *unsyncedUser) {
        return unsyncedUser.remoteIdentifier.transportString;
    }];
    
    if (unsyncedUserIDs.count == 0) {
        return nil;
    }
    
    NSString *path = [NSString pathWithComponents:@[ ConversationsPath, conversation.remoteIdentifier.transportString, @"members" ]];
    NSDictionary *payload = @{
                              @"users": unsyncedUserIDs.array,
                              };
    
    ZMTransportRequest *request = [ZMTransportRequest requestWithPath:path method:ZMMethodPOST payload:payload];
    [request expireAfterInterval:ZMTransportRequestDefaultExpirationInterval];
    NSDictionary *userInfo = @{ UserInfoTypeKey : UserInfoAddedValueKey, UserInfoUserKey : conversation.unsyncedActiveParticipants };
    return [[ZMUpstreamRequest alloc] initWithKeys:[NSSet setWithObject:ZMConversationUnsyncedActiveParticipantsKey] transportRequest:request userInfo:userInfo];
}

- (ZMUpstreamRequest *)requestForUpdatingUnsyncedInactiveParticipantsInConversation:(ZMConversation *)conversation
{
    ZMUser *unsyncedUser = conversation.unsyncedInactiveParticipants.firstObject;
    
    if (unsyncedUser == nil) {
        return nil;
    }
    
    NSString *path = [NSString pathWithComponents:@[ ConversationsPath, conversation.remoteIdentifier.transportString, @"members", unsyncedUser.remoteIdentifier.transportString ]];
    
    ZMTransportRequest *request = [ZMTransportRequest requestWithPath:path method:ZMMethodDELETE payload:nil];
    [request expireAfterInterval:ZMTransportRequestDefaultExpirationInterval];
    NSDictionary *userInfo = @{ UserInfoTypeKey : UserInfoRemovedValueKey, UserInfoUserKey : unsyncedUser };
    return [[ZMUpstreamRequest alloc] initWithKeys:[NSSet setWithObject:ZMConversationUnsyncedInactiveParticipantsKey] transportRequest:request userInfo:userInfo];
}


- (ZMUpstreamRequest *)requestForUpdatingUserDefinedNameInConversation:(ZMConversation *)conversation
{
    NSDictionary *payload = @{ @"name" : conversation.userDefinedName };
    NSString *lastComponent = conversation.remoteIdentifier.transportString;
    Require(lastComponent != nil);
    NSString *path = [NSString pathWithComponents:@[ConversationsPath, lastComponent]];
    ZMTransportRequest *request = [ZMTransportRequest requestWithPath:path method:ZMMethodPUT payload:payload];

    [request expireAfterInterval:ZMTransportRequestDefaultExpirationInterval];
    return [[ZMUpstreamRequest alloc] initWithKeys:[NSSet setWithObject:ZMConversationUserDefinedNameKey] transportRequest:request userInfo:nil];
}

- (ZMUpstreamRequest *)requestForUpdatingConversationSelfInfo:(ZMConversation *)conversation
{
    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    NSMutableSet *updatedKeys = [NSMutableSet set];
    
    if ([conversation hasLocalModificationsForKey:ZMConversationIsSilencedKey]) {
        payload[@"muted"] = @(conversation.isSilenced);
        [updatedKeys addObject:ZMConversationIsSilencedKey];
    }
    
    if ([conversation hasLocalModificationsForKey:ZMConversationClearedEventIDDataKey]) {
        payload[@"cleared"] = conversation.clearedEventID == nil ? [NSNull null] : conversation.clearedEventID.transportString;
        [updatedKeys addObject:ZMConversationClearedEventIDDataKey];
    }
    
    if ([conversation hasLocalModificationsForKey:ZMConversationIsArchivedKey]) {
        
        if (conversation.isArchived) {
            
            if( conversation.archivedEventID == nil) {
                ZMLogError(@"Unable to push isArchive, because archivedEventID is not set. Conversation: %@", conversation);
                [conversation resetLocallyModifiedKeys:[NSSet setWithObject:ZMConversationIsArchivedKey]];
                [self.managedObjectContext enqueueDelayedSave];
            } else {
                payload[ConversationInfoArchivedValueKey] = conversation.archivedEventID.transportString;
                [updatedKeys addObject:ZMConversationIsArchivedKey];
            }
        }
        else {
            payload[ConversationInfoArchivedValueKey] = @"false";
            [updatedKeys addObject:ZMConversationIsArchivedKey];
        }
    }
    
    if (updatedKeys.count == 0) {
        return nil;
    }
    
    NSString *path = [NSString pathWithComponents:@[ConversationsPath, conversation.remoteIdentifier.transportString, @"self"]];
    ZMTransportRequest *request = [ZMTransportRequest requestWithPath:path method:ZMMethodPUT payload:payload];
    return [[ZMUpstreamRequest alloc] initWithKeys:updatedKeys transportRequest:request userInfo:nil];
}


- (ZMUpstreamRequest *)requestForInsertingObject:(ZMManagedObject *)managedObject forKeys:(NSSet *)keys;
{
    NOT_USED(keys);
    
    ZMTransportRequest *request = nil;
    ZMConversation *insertedConversation = (ZMConversation *) managedObject;
    
    NSArray *participantUUIDs = [[insertedConversation.otherActiveParticipants array] mapWithBlock:^id(ZMUser *user) {
        return [user.remoteIdentifier transportString];
    }];
    
    NSMutableDictionary *payload = [@{ @"users" : participantUUIDs } mutableCopy];
    if(insertedConversation.userDefinedName != nil) {
        payload[@"name"] = insertedConversation.userDefinedName;
    }
    
    request = [ZMTransportRequest requestWithPath:ConversationsPath method:ZMMethodPOST payload:payload];
    return [[ZMUpstreamRequest alloc] initWithTransportRequest:request];
}


- (void)updateInsertedObject:(ZMManagedObject *)managedObject request:(ZMUpstreamRequest *__unused)upstreamRequest response:(ZMTransportResponse *)response
{
    ZMConversation *insertedConversation = (ZMConversation *)managedObject;
    NSUUID *remoteID = [response.payload.asDictionary uuidForKey:@"id"];
    ZMEventID *lastEventID = [response.payload.asDictionary eventForKey:@"last_event"];
    
    // check if there is another with the same conversation ID
    if(remoteID != nil)
    {
        ZMConversation *existingConversation = [ZMConversation conversationWithRemoteID:remoteID createIfNeeded:NO inContext:self.managedObjectContext];
        
        if( existingConversation != nil )
        {
            [self.managedObjectContext deleteObject:existingConversation];
            if( ! [existingConversation.lastEventID isEqualToEventID:lastEventID] )
            {
                insertedConversation.needsToBeUpdatedFromBackend = YES;
            }
        }
    }
    insertedConversation.remoteIdentifier = remoteID;
    [insertedConversation updateWithTransportData:response.payload.asDictionary];
    [insertedConversation startFetchingMessages];
}

- (ZMUpdateEvent *)conversationEventWithKeys:(NSSet *)keys responsePayload:(id<ZMTransportData>)payload;
{
    NSSet *keysThatGenerateEvents = [NSSet setWithObjects:ZMConversationUserDefinedNameKey,
                                     ZMConversationUnsyncedInactiveParticipantsKey,
                                     ZMConversationUnsyncedActiveParticipantsKey,
                                     ZMConversationIsSelfAnActiveMemberKey,
                                     nil];
    if (! [keys intersectsSet:keysThatGenerateEvents]) {
        return nil;
        
    }
    ZMUpdateEvent *event = [ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil];
    return event;
}


- (BOOL)updateUpdatedObject:(ZMConversation *)conversation
            requestUserInfo:(NSDictionary *)userInfo
                   response:(ZMTransportResponse *)response
                keysToParse:(NSSet *)keysToParse
{
    ZMUpdateEvent *event = [self conversationEventWithKeys:keysToParse responsePayload:response.payload];
    if (event != nil) {
        [self.syncStrategy processDownloadedEvents:@[event]];
        [self updatePropertiesOfConversation:conversation withPostPayloadEvent:event];
    }
    
    if ([keysToParse isEqualToSet:[NSSet setWithObject:ZMConversationUserDefinedNameKey]]) {
        return NO;
    }
    
    // When participants change, we need to update them based on userInfo, not 'keysToParse'.
    // 'keysToParse' will not contain the participants if they've changed in the meantime, but
    // we need to parse the result anyway.
    NSString * const changeType = userInfo[UserInfoTypeKey];
    BOOL const addedUsers = ([changeType isEqualToString:UserInfoAddedValueKey]);
    BOOL const removedUsers = ([changeType isEqualToString:UserInfoRemovedValueKey]);
    
    if (addedUsers || removedUsers) {
        BOOL needsAnotherRequest;
        if (removedUsers) {
            ZMUser *syncedUser = userInfo[UserInfoUserKey];
            [conversation synchronizeRemovedUser:syncedUser];
            
            needsAnotherRequest = conversation.unsyncedInactiveParticipants.count > 0;
        }
        else if (addedUsers) {
            NSMutableOrderedSet *syncedUsers = userInfo[UserInfoUserKey];
            
            for (ZMUser *syncedUser in syncedUsers) {
                [conversation synchronizeAddedUser:syncedUser];
            }
            
            needsAnotherRequest = NO; // 1 TODO What happens if participants are changed while being updated?
        }
        
        // Reset keys
        if (! needsAnotherRequest && [keysToParse containsObject:ZMConversationUnsyncedInactiveParticipantsKey]) {
            [conversation resetLocallyModifiedKeys:[NSSet setWithObject:ZMConversationUnsyncedInactiveParticipantsKey]];
        }
        if (! needsAnotherRequest && [keysToParse containsObject:ZMConversationUnsyncedActiveParticipantsKey]) {
            [conversation resetLocallyModifiedKeys:[NSSet setWithObject:ZMConversationUnsyncedActiveParticipantsKey]];
        }
        
        return needsAnotherRequest;
    }
    if( keysToParse == nil ||
       [keysToParse isEmpty] ||
       [keysToParse containsObject:ZMConversationLastReadEventIDDataKey] ||
       [keysToParse containsObject:ZMConversationIsSilencedKey] ||
       [keysToParse containsObject:ZMConversationIsArchivedKey] ||
       [keysToParse containsObject:ZMConversationClearedEventIDDataKey] ||
       [keysToParse containsObject:ZMConversationIsSelfAnActiveMemberKey])
    {
        return NO;
    }
    ZMLogError(@"Unknown changed keys in request. keys: %@  payload: %@  userInfo: %@", keysToParse, response.payload, userInfo);
    return NO;
}

- (ZMManagedObject *)objectToRefetchForFailedUpdateOfObject:(ZMManagedObject *)managedObject;
{
    if([managedObject isKindOfClass:ZMConversation.class]) {
        return managedObject;
    }
    return nil;
}

- (void)requestExpiredForObject:(ZMConversation *)conversation forKeys:(NSSet *)keys
{
    if ([keys containsObject:ZMConversationUserDefinedNameKey]) {
        conversation.needsToBeUpdatedFromBackend = YES;
        [conversation resetLocallyModifiedKeys:[NSSet setWithObject:ZMConversationUserDefinedNameKey]];
    }
    if ([keys containsObject:ZMConversationUnsyncedActiveParticipantsKey] ||
             [keys containsObject:ZMConversationUnsyncedInactiveParticipantsKey]) {
        conversation.needsToBeUpdatedFromBackend = YES;
        [conversation resetParticipantsBackToLastServerSync];
    }
}

- (BOOL)shouldCreateRequestToSyncObject:(ZMManagedObject *)managedObject withSync:(id __unused)sync;
{
    ZMConversation *conversation = (ZMConversation *)managedObject;
    if ([conversation hasLocalModificationsForKey:ZMConversationUserDefinedNameKey] && !conversation.userDefinedName) {
        [conversation resetLocallyModifiedKeys:[NSSet setWithObject:ZMConversationUserDefinedNameKey]];
        [self.modifiedSync objectsDidChange:[NSSet setWithObject:conversation]];
        [self.managedObjectContext enqueueDelayedSave];
        return NO;
    }
    return YES;
}

- (BOOL)failedToUpdateInsertedObject:(ZMConversation *)conversation request:(ZMUpstreamRequest *__unused)upstreamRequest response:(ZMTransportResponse *__unused)response keysToParse:(NSSet * __unused)keys
{
    if (conversation.remoteIdentifier) {
        conversation.needsToBeUpdatedFromBackend = YES;
        [conversation resetParticipantsBackToLastServerSync];
        return YES;
    }
    else {
        return NO;
    }
}

@end



@implementation ZMConversationTranscoder (DownstreamTranscoder)

- (ZMTransportRequest *)requestForFetchingObject:(ZMConversation *)conversation downstreamSync:(ZMDownstreamObjectSync *)downstreamSync;
{
    NOT_USED(downstreamSync);
    if (conversation.remoteIdentifier == nil) {
        return nil;
    }
    
    NSString *path = [NSString pathWithComponents:@[ConversationsPath, conversation.remoteIdentifier.transportString]];
    ZMTransportRequest *request = [[ZMTransportRequest alloc] initWithPath:path method:ZMMethodGET payload:nil];
    return request;
}

- (void)updateObject:(ZMConversation *)conversation withResponse:(ZMTransportResponse *)response downstreamSync:(ZMDownstreamObjectSync *)downstreamSync;
{
    NOT_USED(downstreamSync);
    conversation.needsToBeUpdatedFromBackend = NO;
    
    NSDictionary *dictionaryPayload = [response.payload asDictionary];
    VerifyReturn(dictionaryPayload != nil);
    [conversation updateWithTransportData:dictionaryPayload];
}

- (void)deleteObject:(ZMConversation *)conversation downstreamSync:(ZMDownstreamObjectSync *)downstreamSync;
{
    NOT_USED(downstreamSync);
    NOT_USED(conversation);
}

@end


@implementation ZMConversationTranscoder (PaginatedRequest)

- (NSUInteger)maximumRemoteIdentifiersPerRequestForObjectSync:(ZMRemoteIdentifierObjectSync *)sync;
{
    NOT_USED(sync);
    return self.conversationPageSize;
}


- (ZMTransportRequest *)requestForObjectSync:(ZMRemoteIdentifierObjectSync *)sync remoteIdentifiers:(NSSet *)identifiers;
{
    NOT_USED(sync);
    
    NSArray *currentBatchOfConversationIDs = [[identifiers allObjects] mapWithBlock:^id(NSUUID *obj) {
        return obj.transportString;
    }];
    NSString *path = [NSString stringWithFormat:@"%@?ids=%@", ConversationsPath, [currentBatchOfConversationIDs componentsJoinedByString:@","]];

    return [[ZMTransportRequest alloc] initWithPath:path method:ZMMethodGET payload:nil];
}


- (void)didReceiveResponse:(ZMTransportResponse *)response remoteIdentifierObjectSync:(ZMRemoteIdentifierObjectSync *)sync forRemoteIdentifiers:(NSSet *)remoteIdentifiers;
{
    NOT_USED(sync);
    NOT_USED(remoteIdentifiers);
    NSDictionary *payload = [response.payload asDictionary];
    NSArray *conversations = [payload arrayForKey:@"conversations"];
    
    for (NSDictionary *rawConversation in [conversations asDictionaries]) {
        ZMConversation *conv = [self createConversationFromTransportData:rawConversation];
        conv.needsToBeUpdatedFromBackend = NO;
    }
}

@end