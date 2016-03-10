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


@import ZMTransport;

#import "MessagingTest.h"
#import "ZMHotFix.h"
#import "ZMHotFixDirectory.h"
#import "ZMConversation+Internal.h"
#import "ZMConnection+Internal.h"
#import "ZMMessage+Internal.h"
#import "ZMManagedObject+Internal.h"


@interface VersionNumberTests : MessagingTest
@end


@implementation VersionNumberTests

- (void)setUp {
    [super setUp];
}

- (void)tearDown
{
    [super tearDown];
}

- (void)testThatItComparesCorrectly
{
    // given
    NSString *version1String = @"0.1";
    NSString *version2String = @"1.0";
    NSString *version3String = @"1.0";
    NSString *version4String = @"1.0.1";
    NSString *version5String = @"1.1";
    
    ZMVersion *version1 = [[ZMVersion alloc] initWithVersionString:version1String];
    ZMVersion *version2 = [[ZMVersion alloc] initWithVersionString:version2String];
    ZMVersion *version3 = [[ZMVersion alloc] initWithVersionString:version3String];
    ZMVersion *version4 = [[ZMVersion alloc] initWithVersionString:version4String];
    ZMVersion *version5 = [[ZMVersion alloc] initWithVersionString:version5String];

    // then
    XCTAssertEqual([version1 compareWithVersion:version2], NSOrderedAscending);
    XCTAssertEqual([version1 compareWithVersion:version3], NSOrderedAscending);
    XCTAssertEqual([version1 compareWithVersion:version4], NSOrderedAscending);
    XCTAssertEqual([version1 compareWithVersion:version5], NSOrderedAscending);

    XCTAssertEqual([version2 compareWithVersion:version1], NSOrderedDescending);
    XCTAssertEqual([version2 compareWithVersion:version3], NSOrderedSame);
    XCTAssertEqual([version2 compareWithVersion:version4], NSOrderedAscending);
    XCTAssertEqual([version2 compareWithVersion:version5], NSOrderedAscending);

    XCTAssertEqual([version3 compareWithVersion:version1], NSOrderedDescending);
    XCTAssertEqual([version3 compareWithVersion:version2], NSOrderedSame);
    XCTAssertEqual([version3 compareWithVersion:version4], NSOrderedAscending);
    XCTAssertEqual([version3 compareWithVersion:version5], NSOrderedAscending);

    XCTAssertEqual([version4 compareWithVersion:version1], NSOrderedDescending);
    XCTAssertEqual([version4 compareWithVersion:version2], NSOrderedDescending);
    XCTAssertEqual([version4 compareWithVersion:version3], NSOrderedDescending);
    XCTAssertEqual([version4 compareWithVersion:version5], NSOrderedAscending);
    
    XCTAssertEqual([version5 compareWithVersion:version1], NSOrderedDescending);
    XCTAssertEqual([version5 compareWithVersion:version2], NSOrderedDescending);
    XCTAssertEqual([version5 compareWithVersion:version3], NSOrderedDescending);
    XCTAssertEqual([version5 compareWithVersion:version4], NSOrderedDescending);
}

@end




@interface FakeHotFixDirectory : ZMHotFixDirectory
@property (nonatomic) NSUInteger method1CallCount;
@property (nonatomic) NSUInteger method2CallCount;
@property (nonatomic) NSUInteger method3CallCount;

@end

@implementation FakeHotFixDirectory

- (void)methodOne:(NSObject *)object
{
    NOT_USED(object);
    self.method1CallCount++;
}

- (void)methodTwo:(NSObject *)object
{
    NOT_USED(object);
    self.method2CallCount++;
}

- (void)methodThree:(NSObject *)object
{
    NOT_USED(object);
    self.method3CallCount++;
}

- (NSArray *)patches
{
    return @[
             [ZMHotFixPatch patchWithVersion:@"1.0" patchCode:^(NSManagedObjectContext *moc){ [self methodOne:moc]; [self methodThree:moc]; }],
             [ZMHotFixPatch patchWithVersion:@"0.1" patchCode:^(NSManagedObjectContext *moc){ [self methodTwo:moc]; }],
    ];
}

@end



@interface PushTokenNotificationObserver : NSObject
@property (nonatomic) NSUInteger notificationCount;
@end


@implementation PushTokenNotificationObserver

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.notificationCount = 0;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(notificationFired) name:ZMUserSessionResetPushTokensNotificationName object:nil];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)notificationFired
{
    self.notificationCount++;
}

@end



@interface ZMHotFixTests : MessagingTest

@property (nonatomic) FakeHotFixDirectory *fakeHotFixDirectory;
@property (nonatomic) ZMHotFix *sut;

@end


@implementation ZMHotFixTests

- (void)setUp {
    [super setUp];
    
    self.fakeHotFixDirectory = [[FakeHotFixDirectory alloc] init];
    self.sut = [[ZMHotFix alloc] initWithHotFixDirectory:self.fakeHotFixDirectory syncMOC:self.syncMOC];
    }

- (void)tearDown {
    self.fakeHotFixDirectory = nil;
    [super tearDown];
}

- (void)saveNewVersion
{
    [self.syncMOC setPersistentStoreMetadata:@"0.1" forKey:@"lastSavedVersion"];
}

- (void)testThatItOnlyCallsMethodsForVersionsNewerThanTheLastSavedVersion
{
    // given
    [self saveNewVersion];

    // when
    [self.sut applyPatchesForCurrentVersion:@"1.0"];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.fakeHotFixDirectory.method1CallCount, 1u);
    XCTAssertEqual(self.fakeHotFixDirectory.method3CallCount, 1u);
    XCTAssertEqual(self.fakeHotFixDirectory.method2CallCount, 0u);
}

- (void)testThatItCallsAllMethodsIfThereIsNoLastSavedVersion
{
    // when
    [self.sut applyPatchesForCurrentVersion:@"1.0"];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.fakeHotFixDirectory.method1CallCount, 1u);
    XCTAssertEqual(self.fakeHotFixDirectory.method2CallCount, 1u);
    XCTAssertEqual(self.fakeHotFixDirectory.method3CallCount, 1u);
}

- (void)testThatItRunsFixesOnlyOnce
{
    // given
    [self saveNewVersion];
    
    // when
    [self.sut applyPatchesForCurrentVersion:@"1.0"];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.fakeHotFixDirectory.method1CallCount, 1u);
    
    // and when
    [self.sut applyPatchesForCurrentVersion:@"1.0"];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.fakeHotFixDirectory.method1CallCount, 1u);
}

- (void)testThatItSetsTheCurrentVersionAfterApplyingTheFixes
{
    // given
    [self saveNewVersion];
    
    // when
    [self.sut applyPatchesForCurrentVersion:@"1.2"];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    NSString *newVersion = [self.syncMOC persistentStoreMetadataForKey:@"lastSavedVersion"];
    XCTAssertEqualObjects(newVersion, @"1.2");
}


@end




@implementation ZMHotFixTests (CurrentFixes)

- (void)testThatItSetsTheLastReadOfAPendingConnectionRequest
{
    // given
    ZMEventID *lastReadEventID = self.createEventID;
    ZMEventID *lastEventID = self.createEventID;
    XCTAssertEqual([lastEventID compare:lastReadEventID], NSOrderedDescending);
    
    __block ZMConversation *conversation;
    
    [self.syncMOC performGroupedBlockAndWait:^{
        conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.connection = [ZMConnection insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.connection.status = ZMConnectionStatusPending;
        conversation.remoteIdentifier = [NSUUID UUID];
        conversation.conversationType = ZMConversationTypeConnection;
        
        conversation.lastReadEventID = lastReadEventID;
        conversation.lastEventID = lastEventID;
        
        [self.syncMOC saveOrRollback];
        XCTAssertNotEqualObjects(conversation.lastReadEventID, lastEventID);
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    self.sut = [[ZMHotFix alloc] initWithSyncMOC:self.syncMOC];
    [self.sut applyPatchesForCurrentVersion:@"1.0"];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqualObjects(conversation.lastReadEventID, lastEventID);
}

- (void)testThatItSetsTheLastReadOfClearedConversationsWithZeroMessages
{
    // given
    ZMEventID *lastReadEventID = self.createEventID;
    ZMEventID *lastEventID = self.createEventID;
    XCTAssertEqual([lastEventID compare:lastReadEventID], NSOrderedDescending);
    
    __block ZMConversation *conversation;
    
    [self.syncMOC performGroupedBlockAndWait:^{
        conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.remoteIdentifier = [NSUUID UUID];
        conversation.conversationType = ZMConversationTypeOneOnOne;
        
        conversation.clearedEventID = lastReadEventID;
        conversation.lastReadEventID = lastReadEventID;
        conversation.lastEventID = lastEventID;
        
        [self.syncMOC saveOrRollback];
        XCTAssertNotEqualObjects(conversation.lastReadEventID, lastEventID);
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    self.sut = [[ZMHotFix alloc] initWithSyncMOC:self.syncMOC];
    [self.sut applyPatchesForCurrentVersion:@"1.0"];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqualObjects(conversation.lastReadEventID, lastEventID);
}

- (void)testThatItRemovesTheFirstAddedSystemMessagesWhenUpdatingTo1_26
{
    // given
    __block ZMConversation *conversation;
    __block ZMSystemMessage *addedMessage;
    __block NSOrderedSet <ZMMessage *>*messages;
    NSString *text = @"Some Text";
    
    [self.syncMOC performGroupedBlockAndWait:^{
        conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.conversationType = ZMConversationTypeGroup;
    
        addedMessage = [ZMSystemMessage insertNewObjectInManagedObjectContext:self.syncMOC];
        addedMessage.systemMessageType = ZMSystemMessageTypeParticipantsAdded;
        addedMessage.eventID = [ZMEventID eventIDWithMajor:1 minor:3];
        [conversation sortedAppendMessage:addedMessage];
        
        [conversation appendMessagesWithText:text];
        ZMSystemMessage *secondAddedMessage = [ZMSystemMessage insertNewObjectInManagedObjectContext:self.syncMOC];
        secondAddedMessage.systemMessageType = ZMSystemMessageTypeParticipantsAdded;
        secondAddedMessage.eventID = [ZMEventID eventIDWithMajor:3 minor:3];
        [conversation sortedAppendMessage:secondAddedMessage];
        
        messages = conversation.messages;
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertEqual(messages.count, 3lu);
    XCTAssertEqualObjects(messages.firstObject, addedMessage);
    XCTAssertEqualObjects(messages.lastObject.class, ZMSystemMessage.class);
    
    // when
    self.sut = [[ZMHotFix alloc] initWithSyncMOC:self.syncMOC];
    [self.sut applyPatchesForCurrentVersion:@"38.58"];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(conversation.messages.count, 2lu);
    XCTAssertEqualObjects(messages.firstObject.messageText, text);
    XCTAssertEqualObjects(messages.lastObject.class, ZMSystemMessage.class);
}

- (void)testThatItRemovesConnectionRequestSystemMessagesWhenUpdatingTo1_26
{
    // given
    __block ZMConversation *conversation;
    __block ZMSystemMessage *addedMessage;
    __block NSOrderedSet <ZMMessage *>*messages;
    NSString *text = @"Some Text";
    
    [self.syncMOC performGroupedBlockAndWait:^{
        conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.conversationType = ZMConversationTypeOneOnOne;
        
        addedMessage = [ZMSystemMessage insertNewObjectInManagedObjectContext:self.syncMOC];
        addedMessage.systemMessageType = ZMSystemMessageTypeConnectionRequest;
        [conversation sortedAppendMessage:addedMessage];
        
        [conversation appendMessagesWithText:text];
        messages = conversation.messages;
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertEqual(messages.count, 2lu);
    XCTAssertEqual(messages.firstObject.systemMessageData.systemMessageType, ZMSystemMessageTypeConnectionRequest);
    XCTAssertEqualObjects(messages.firstObject, addedMessage);
    XCTAssertEqualObjects(messages.lastObject.messageText, text);
    
    // when
    self.sut = [[ZMHotFix alloc] initWithSyncMOC:self.syncMOC];
    [self.sut applyPatchesForCurrentVersion:@"38.58"];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(conversation.messages.count, 1lu);
    XCTAssertEqualObjects(messages.firstObject.messageText, text);
}

- (void)testThatItSetsTheLastReadOfALeftConversation
{
    // given
    ZMEventID *lastReadEventID = self.createEventID;
    ZMEventID *lastEventID = self.createEventID;
    XCTAssertEqual([lastEventID compare:lastReadEventID], NSOrderedDescending);
    
    __block ZMConversation *conversation;
    
    [self.syncMOC performGroupedBlockAndWait:^{
        conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.remoteIdentifier = [NSUUID UUID];
        conversation.conversationType = ZMConversationTypeGroup;
        [conversation appendMessagesWithText:@"foo"];
        [conversation appendMessagesWithText:@"bar"];
        conversation.isSelfAnActiveMember = NO;
        
        conversation.clearedEventID = lastReadEventID;
        conversation.lastReadEventID = lastReadEventID;
        conversation.lastEventID = lastEventID;
        
        [self.syncMOC saveOrRollback];
        XCTAssertNotEqualObjects(conversation.lastReadEventID, lastEventID);
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    self.sut = [[ZMHotFix alloc] initWithSyncMOC:self.syncMOC];
    [self.sut applyPatchesForCurrentVersion:@"1.0"];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqualObjects(conversation.lastReadEventID, lastEventID);
}

- (void)testThatItSendsOutResetPushTokenNotificationVersion_40_4
{
    // given
    PushTokenNotificationObserver *observer = [[PushTokenNotificationObserver alloc] init];
    
    // when
    self.sut = [[ZMHotFix alloc] initWithSyncMOC:self.syncMOC];
    [self.sut applyPatchesForCurrentVersion:@"40.4"];
    WaitForAllGroupsToBeEmpty(0.5);

    NSString *newVersion = [self.syncMOC persistentStoreMetadataForKey:@"lastSavedVersion"];
    XCTAssertEqualObjects(newVersion, @"40.4");
    
    [self.sut applyPatchesForCurrentVersion:@"40.4"];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(observer.notificationCount, 1lu);
    
    // when
    [self.sut applyPatchesForCurrentVersion:@"40.5"];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(observer.notificationCount, 1lu);
}


@end
