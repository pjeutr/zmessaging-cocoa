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


@import Foundation;
@import CoreData;
@import ZMTransport;
@import ZMCDataModel;

#import "MessagingTest.h"
#import "ZMSearchDirectory+Internal.h"
#import "ZMUserSession+Internal.h"
#import "ZMUserIDsForSearchDirectoryTable.h"


@interface TokenAndSearchResult : NSObject

@property (nonatomic, readonly) ZMSearchToken token;
@property (nonatomic, readonly) ZMSearchResult *searchResult;

@end


@implementation TokenAndSearchResult

- (instancetype)initWithToken:(ZMSearchToken)token searchResult:(ZMSearchResult *)result
{
    self = [super init];
    if (self) {
        _token = token;
        _searchResult = result;
    }
    return self;
}

@end



@interface ZMSearchDirectoryTests : MessagingTest <ZMSearchResultObserver, ZMSearchTopConversationsObserver>

@property (nonatomic) ZMSearchDirectory *sut;

@property (nonatomic) NSMutableArray *searchResults;
@property (nonatomic) XCTestExpectation *searchResultExpectation;

@property (nonatomic) OCMockObject *userSession;
@property (nonatomic) OCMockObject *transportSession;

@property (nonatomic) NSInteger numberOfSearchResultUpdates;

@property (nonatomic) NSUInteger topConversationChangeCount;

@property (nonatomic) NSInteger maxTopConversationsCount;

@end

@implementation ZMSearchDirectoryTests

- (void)setUp
{
    [super setUp];
    self.maxTopConversationsCount = 24;
    self.topConversationChangeCount = 0;
    self.userSession = [OCMockObject niceMockForClass:ZMUserSession.class];
    self.transportSession = [OCMockObject niceMockForClass:ZMTransportSession.class];
    (void)[(ZMUserSession *)[[self.userSession stub] andReturn:self.transportSession] transportSession];
    (void)[(ZMUserSession *)[[self.userSession stub] andReturn:self.uiMOC] managedObjectContext];
    [[[self.userSession stub] andReturn:self.syncMOC] syncManagedObjectContext];
    
    self.sut = [[ZMSearchDirectory alloc] initWithUserSession:(ZMUserSession *)self.userSession searchContext:self.searchMOC maxTopConversationsCount:self.maxTopConversationsCount];
    [self.sut addTopConversationsObserver:self];
    self.sut.remoteSearchTimeout = 0.005;
    
    self.numberOfSearchResultUpdates = 0;
    self.searchResults = [@[] mutableCopy];
    [self resetSearchResultExpectation];
    [self.sut addSearchResultObserver:self];

}

- (void)tearDown
{
    WaitForAllGroupsToBeEmpty(0.5);
    [NSManagedObjectContext resetUserInterfaceContext];

    ZMUserIDsForSearchDirectoryTable *table = [ZMSearchDirectory userIDsMissingProfileImage];
    [table clear];
    
    [self.sut tearDown];
    [self.sut removeSearchResultObserver:self];
    [self.sut removeTopConversationsObserver:self];
    self.sut = nil;
    self.searchResults = nil;
    self.searchResultExpectation = nil;
    self.userSession = nil;
    self.transportSession = nil;
    [super tearDown];
}

- (void)recreateSUT;
{
    [self.sut removeSearchResultObserver:self];
    [self.sut removeTopConversationsObserver:self];
    [self.sut tearDown];
    self.sut = [[ZMSearchDirectory alloc] initWithUserSession:(ZMUserSession *)self.userSession searchContext:self.searchMOC maxTopConversationsCount:self.maxTopConversationsCount];
    [self.sut addTopConversationsObserver:self];
}

- (void)didReceiveSearchResult:(ZMSearchResult *)result forToken:(ZMSearchToken)searchToken;
{
    self.numberOfSearchResultUpdates++;
    [self.searchResults addObject:[[TokenAndSearchResult alloc] initWithToken:searchToken searchResult:result] ];
    [self.searchResultExpectation fulfill];
}

- (void)topConversationsDidChange:(NSNotification *)note;
{
    NOT_USED(note);
    self.topConversationChangeCount++;
}


- (NSDictionary *)responseDataForUsers:(NSArray *)users {
    
    NOT_USED(users);
    NSDictionary *responseData = @{
                                   @"buildNumber" : @7029,
                                   @"compares" : @2,
                                   @"description" : @"foo",
                                   @"documents" : users,
                                   @"error" : [NSNull null],
                                   @"found" : @0,
                                   @"friends" : @0,
                                   @"friendsOfFriends" : @0,
                                   @"returned" : @2,
                                   @"time" : @1
                                   };
    return responseData;
}

- (ZMConversation *)createGroupConversationWithName:(NSString *)name
{
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.userDefinedName = name;
    conversation.conversationType = ZMConversationTypeGroup;
    [self.uiMOC saveOrRollback];
    return conversation;
}

- (ZMSearchResult *)firstSearchResultForToken:(ZMSearchToken)token
{
    for (TokenAndSearchResult *result in self.searchResults) {
        if([result.token isEqual:token]) {
            return result.searchResult;
        }
    }
    
    return nil;
}

- (ZMSearchResult *)searchResultAtIndex:(NSUInteger)index
{
    if(index >= self.searchResults.count) {
        return nil;
    }
    
    return [self.searchResults[index] searchResult];
}

- (void)resetSearchResultExpectation
{
    // This is to ensure that we waited for search results before creating a new expectation for them
    NSAssert(self.searchResultExpectation == nil, @"Wrong nesting of search result expectations");
    self.searchResultExpectation = [self expectationWithDescription:@"wait for result"];
}


- (void)waitForSearchResultsWithFailureRecorder:(ZMTFailureRecorder *)failureRecorder shouldFail:(BOOL)shouldFail
{
    if (shouldFail) {
        [self spinMainQueueWithTimeout:0.5];
        FHAssertFalse(failureRecorder, [self verifyAllExpectationsNow]);
    }
    else {
        FHAssertTrue(failureRecorder, [self waitForCustomExpectationsWithTimeout:0.5]);
    }
    self.searchResultExpectation = nil;
}

- (void)finishRequest:(ZMTransportRequest *)request
     withResponseData:(id<ZMTransportData>)responseData
      failureRecorder:(ZMTFailureRecorder *)failureRecorder
{
    FHAssertTrue(failureRecorder, request != nil);
    if (request) {
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:responseData HTTPstatus:200 transportSessionError:nil];
        [request completeWithResponse:response];
    }
}



- (void)testThatItReturnsATokenWhenStartingASearch
{
    ZMSearchToken token = [self.sut searchForUsersAndConversationsMatchingQueryString:@"test"];
    XCTAssertNotNil(token);
}

- (void)testThatItSendsNoResultToTheObserver
{
    // given
    ZMSearchToken token = [self.sut searchForUsersAndConversationsMatchingQueryString:@"Nobody"];
    
    // when
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];

    // then
    ZMSearchResult *result = [self firstSearchResultForToken:token];
    XCTAssertEqual(result.usersInContacts.count, 0u);
    XCTAssertEqual(result.usersInDirectory.count, 0u);
    XCTAssertEqual(result.groupConversations.count, 0u);

}


@end



@implementation ZMSearchDirectoryTests (UserSearch)


- (ZMUser *)createConnectedUserWithName:(NSString *)name
{
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.name = name;
    user.remoteIdentifier = [NSUUID createUUID];

    ZMConnection *connection = [ZMConnection insertNewObjectInManagedObjectContext:self.uiMOC];
    connection.to = user;
    connection.status = ZMConnectionStatusAccepted;

    [self.uiMOC saveOrRollback];

    return user;
}

- (BOOL)isUserFromContacts:(ZMUser *)user equalToSearchUser:(ZMSearchUser *)searchUser
{
    return [searchUser.name isEqualToString:user.name] &&
        [searchUser.displayName isEqualToString:user.displayName] &&
        searchUser.accentColorValue == user.accentColorValue &&
        searchUser.isConnected == YES &&
        searchUser.user == user;
}


- (void)verifyThatResultWithToken:(ZMSearchToken)token containsUsers:(NSArray *)users failureRecorder:(ZMTFailureRecorder *)failureRecorder;
{
    ZMSearchResult *result = [self firstSearchResultForToken:token];
    FHAssertEqual(failureRecorder, result.usersInContacts.count, users.count);
    FHAssertEqual(failureRecorder, result.usersInDirectory.count, 0u);

    for (ZMUser *user in users) {
        if ([result.usersInContacts indexOfObjectPassingTest:^BOOL(ZMSearchUser *searchUser, NSUInteger idx, BOOL *stop) {
            NOT_USED(idx);
            NOT_USED(stop);
            return [self isUserFromContacts:user equalToSearchUser:searchUser];
        }] == NSNotFound) {
            [failureRecorder recordFailure:@"<%@: %p> '%@' not found in result.",
             user.class, user, user.name];
        }
    }
}

- (void)verifyThatResultWithToken:(ZMSearchToken)token doesNotContainUsers:(NSArray *)users failureRecorder:(ZMTFailureRecorder *)failureRecorder;
{
    ZMSearchResult *result = [self firstSearchResultForToken:token];
    
    for (ZMUser *user in users) {
        if ([result.usersInContacts indexOfObjectPassingTest:^BOOL(ZMSearchUser *searchUser, NSUInteger idx, BOOL *stop) {
            NOT_USED(idx);
            NOT_USED(stop);
            return [self isUserFromContacts:user equalToSearchUser:searchUser];
        }] != NSNotFound) {
            [failureRecorder recordFailure:@"<%@: %p> '%@' found in result.",
             user.class, user, user.name];
        }
    }
}


- (void)testThatItFindsASingleUser
{
    // given
    ZMUser *user = [self createConnectedUserWithName:@"Somebody"];
    
    // when
    ZMSearchToken token = [self.sut searchForUsersAndConversationsMatchingQueryString:@"Somebody"];
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];
    // then
    [self verifyThatResultWithToken:token containsUsers:@[user] failureRecorder:NewFailureRecorder()];
}

- (void)testThatItDoesNotFindUsersContainingButNotBeginningWithSearchString
{
    // given
    [self createConnectedUserWithName:@"Somebody"];
    
    // when
    ZMSearchToken token = [self.sut searchForUsersAndConversationsMatchingQueryString:@"mebo"];
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];
    // then
    
    ZMSearchResult *result = [self firstSearchResultForToken:token];
    XCTAssertEqual(result.usersInContacts.count, 0u);
    XCTAssertEqual(result.usersInDirectory.count, 0u);
}

- (void)testThatItFindsUsersBeginningWithSearchString
{
    // given
    ZMUser *user = [self createConnectedUserWithName:@"Somebody"];
    
    // when
    ZMSearchToken token = [self.sut searchForUsersAndConversationsMatchingQueryString:@"Som"];
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];
    // then
    [self verifyThatResultWithToken:token containsUsers:@[user] failureRecorder:NewFailureRecorder()];
}


- (void)testThatItUsesAllQueryComponentsToFindAUser
{
    // given
    ZMUser *user1 = [self createConnectedUserWithName:@"Some Body"];
    [self createConnectedUserWithName:@"Some"];
    [self createConnectedUserWithName:@"Any Body"];

    // when
    ZMSearchToken token = [self.sut searchForUsersAndConversationsMatchingQueryString:@"Some Body"];
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];
    // then
    
    [self verifyThatResultWithToken:token containsUsers:@[user1] failureRecorder:NewFailureRecorder()];
}

- (void)testThatItFindsSeveralUsers
{
    // given
    ZMUser *user1 = [self createConnectedUserWithName:@"Grant"];
    ZMUser *user2 = [self createConnectedUserWithName:@"Greg"];
    [self createConnectedUserWithName:@"Bob"];

    // when
    ZMSearchToken token = [self.sut searchForUsersAndConversationsMatchingQueryString:@"Gr"];
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];

    // then
    [self verifyThatResultWithToken:token containsUsers:@[user1, user2] failureRecorder:NewFailureRecorder()];
}

- (void)testThatTheSearchUserHasTheDirectorysUserSessionSetForResultsFromLocalStore
{
    // given
    (void) [self createConnectedUserWithName:@"Somebody"];
    
    ZMSearchToken token = [self.sut searchForUsersAndConversationsMatchingQueryString:@"Somebody"];
    
    // when
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];

    // then
    ZMSearchResult *result = [self firstSearchResultForToken:token];
    ZMSearchUser *searchUser = result.usersInContacts.firstObject;
    XCTAssertNotNil(searchUser);
}

- (void)testThatUserSearchIsCaseInsensitive
{
    // given
    ZMUser *user = [self createConnectedUserWithName:@"Somebody"];
    
    // when
    ZMSearchToken token = [self.sut searchForUsersAndConversationsMatchingQueryString:@"someBodY"];
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];

    // then
    [self verifyThatResultWithToken:token containsUsers:@[user] failureRecorder:NewFailureRecorder()];
}

- (void)testThatUserSearchIsInsensitiveToDiacritics
{
    // given
    ZMUser *user = [self createConnectedUserWithName:@"Sömëbodÿ"];
    
    // when
    ZMSearchToken token = [self.sut searchForUsersAndConversationsMatchingQueryString:@"Sømebôdy"];
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];

    // then
    [self verifyThatResultWithToken:token containsUsers:@[user] failureRecorder:NewFailureRecorder()];
}

- (void)testThatUserSearchOnlyReturnsConnectedUsers
{
    // given
    ZMUser *user1 = [self createConnectedUserWithName:@"Somebody Blocked"];
    [user1 block];

    ZMUser *user2 = [self createConnectedUserWithName:@"Somebody"];
    
    ZMUser *user3 = [self createConnectedUserWithName:@"Somebody Unconnected"];
    user3.connection.status = ZMConnectionStatusPending;
    
    XCTAssertTrue([self.uiMOC saveOrRollback]);
    
    // when
    ZMSearchToken token = [self.sut searchForUsersAndConversationsMatchingQueryString:@"Some"];
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];

    // then
    [self verifyThatResultWithToken:token containsUsers:@[user2] failureRecorder:NewFailureRecorder()];
}


- (void)testThatItDoesNotReturnTheSelfUser
{
    // given
    ZMUser *selfUser = [ZMUser selfUserInContext:self.uiMOC];
    selfUser.name = @"Some Self-User";
    ZMUser *user = [self createConnectedUserWithName:@"Somebody"];
    
    // when
    ZMSearchToken token = [self.sut searchForUsersAndConversationsMatchingQueryString:@"Some"];
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];
    
    // then
    [self verifyThatResultWithToken:token containsUsers:@[user] failureRecorder:NewFailureRecorder()];

}

- (void)testThatItReturnsALocalUserWhenSearchingForTheFullEmailAddress
{
    // given
    ZMUser *user1 = [self createConnectedUserWithName:@"User1"];
    user1.emailAddress = @"user1@example.com";
    
    ZMConversation *conversation = [self createGroupConversationWithName:@"Conversation"];
    
    [self.uiMOC saveOrRollback];
    
    // when
    ZMSearchToken token = [self.sut searchForUsersThatCanBeAddedToConversation:conversation queryString:user1.emailAddress];
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];
    
    // then
    [self verifyThatResultWithToken:token containsUsers:@[user1] failureRecorder:NewFailureRecorder()];
    
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItDoesNotReturnALocalUserWhenSearchingForPartsOfTheEmailAddress
{
    // given
    ZMUser *user1 = [self createConnectedUserWithName:@"User1"];
    user1.emailAddress = @"user1@example.com";
    ZMUser *user2 = [self createConnectedUserWithName:@"User2"];
    user2.remoteIdentifier = [NSUUID createUUID];
    
    ZMConversation *conversation = [self createGroupConversationWithName:@"Conversation"];
    [conversation addParticipant:user2];
    
    [self.uiMOC saveOrRollback];
    
    // when
    ZMSearchToken token = [self.sut searchForUsersThatCanBeAddedToConversation:conversation queryString:@"user1@example"];
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];
    
    // then
    [self verifyThatResultWithToken:token doesNotContainUsers:@[user1] failureRecorder:NewFailureRecorder()];
    
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItDoesNotReturnALocalUserWhenTheUserIsNotConnected
{
    // given
    ZMUser *user1 = [self createConnectedUserWithName:@"User1"];
    user1.emailAddress = @"user1@example.com";
    user1.connection.status = ZMConnectionStatusPending;
    
    ZMUser *user2 = [self createConnectedUserWithName:@"User2"];
    user2.remoteIdentifier = [NSUUID createUUID];
    
    ZMConversation *conversation = [self createGroupConversationWithName:@"Conversation"];
    [conversation addParticipant:user2];
    
    [self.uiMOC saveOrRollback];
    
    // when
    ZMSearchToken token = [self.sut searchForUsersThatCanBeAddedToConversation:conversation queryString:user1.emailAddress];
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];
    
    // then
    [self verifyThatResultWithToken:token doesNotContainUsers:@[user1] failureRecorder:NewFailureRecorder()];
    
    WaitForAllGroupsToBeEmpty(0.5);
}

@end




@implementation ZMSearchDirectoryTests (ConversationSearch)


- (void)verifyThatResultWithToken:(ZMSearchToken)token containsConversations:(NSArray *)conversations failureRecorder:(ZMTFailureRecorder *)failureRecorder;
{
    ZMSearchResult *result = [self firstSearchResultForToken:token];
    FHAssertEqual(failureRecorder, result.usersInContacts.count, 0u);
    FHAssertEqual(failureRecorder, result.usersInDirectory.count, 0u);
    FHAssertEqual(failureRecorder, result.groupConversations.count, conversations.count);

    for (ZMConversation *conversation in conversations) {
        FHAssertTrue(failureRecorder, [result.groupConversations containsObject:conversation]);
    }
}


- (void)testThatItFindsASingleConversation
{
    // given
    ZMConversation *conversation = [self createGroupConversationWithName:@"Somebody"];
    //conversation.conversationType = ZMConversationTypeGroup;

    // when
    ZMSearchToken token = [self.sut searchForUsersAndConversationsMatchingQueryString:@"Somebody"];
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];

    // then
    [self verifyThatResultWithToken:token containsConversations:@[conversation] failureRecorder:NewFailureRecorder()];
}



- (void)testThatItDoesNotFindConversationsUsingPartialNames
{
    // given
    ZMConversation *conversation = [self createGroupConversationWithName:@"Somebody"];
    
    // when
    ZMSearchToken token = [self.sut searchForUsersAndConversationsMatchingQueryString:@"mebo"];
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];

    // then
    ZMSearchResult *result = [self firstSearchResultForToken:token];
    XCTAssertFalse([result.groupConversations containsObject:conversation]);
}


- (void)testThatItFindsSeveralConversations
{
    // given
    [self createGroupConversationWithName:@"New Day Rising"];
    ZMConversation *conversation2 = [self createGroupConversationWithName:@"Candy Apple Records"];
    ZMConversation *conversation3 = [self createGroupConversationWithName:@"Landspeed Records"];

    // when
    ZMSearchToken token = [self.sut searchForUsersAndConversationsMatchingQueryString:@"Records"];
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];

    // then
    [self verifyThatResultWithToken:token containsConversations:@[conversation2, conversation3] failureRecorder:NewFailureRecorder()];
}


- (void)testThatConversationSearchIsCaseInsensitive
{
    // given
    ZMConversation *conversation = [self createGroupConversationWithName:@"SoMEBody"];

    // when
    ZMSearchToken token = [self.sut searchForUsersAndConversationsMatchingQueryString:@"someBodY"];
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];

    // then
    [self verifyThatResultWithToken:token containsConversations:@[conversation] failureRecorder:NewFailureRecorder()];
}


- (void)testThatConversationSearchIsInsensitiveToDiacritics
{
    // given
    ZMConversation *conversation = [self createGroupConversationWithName:@"Sömëbodÿ"];

    // when
    ZMSearchToken token = [self.sut searchForUsersAndConversationsMatchingQueryString:@"Sømebôdy"];
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];

    // then
    [self verifyThatResultWithToken:token containsConversations:@[conversation] failureRecorder:NewFailureRecorder()];
}

- (void)testThatItOnlyFindsGroupConversations
{
    // given
    ZMConversation *groupConversation = [self createGroupConversationWithName:@"Group Conversation"];
    groupConversation.conversationType = ZMConversationTypeGroup;

    ZMConversation *oneOnOneConversation = [self createGroupConversationWithName:@"One-on-one Conversation"];
    oneOnOneConversation.conversationType = ZMConversationTypeOneOnOne;

    ZMConversation *selfConversation = [self createGroupConversationWithName:@"Self Conversation"];
    selfConversation.conversationType = ZMConversationTypeSelf;
    [self.uiMOC saveOrRollback];

    ZMConversation *conversationConnection = [self createGroupConversationWithName:@"Connect Conversation"];
    conversationConnection.conversationType = ZMConversationTypeConnection;

    [self.uiMOC saveOrRollback];

    // when
    ZMSearchToken token = [self.sut searchForUsersAndConversationsMatchingQueryString:@"Conversation"];
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];

    // then
    [self verifyThatResultWithToken:token containsConversations:@[groupConversation] failureRecorder:NewFailureRecorder()];
}


- (void)testThatItFindsConversationsThatDoNotHaveAUserDefinedName
{
    // given

    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.conversationType = ZMConversationTypeGroup;

    ZMUser *user1 = [self createConnectedUserWithName:@"Shinji"];
    ZMUser *user2 = [self createConnectedUserWithName:@"Asuka"];
    ZMUser *user3 = [self createConnectedUserWithName:@"Rëï"];

    [conversation addParticipant:user1];
    [conversation addParticipant:user2];
    [conversation addParticipant:user3];

    [self.uiMOC saveOrRollback];

    // when
    ZMSearchToken token = [self.sut searchForUsersAndConversationsMatchingQueryString:@"Rei"];
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];


    // then
    ZMSearchResult *result = [self firstSearchResultForToken:token];
    XCTAssertEqual(result.usersInContacts.count, 1u);
    XCTAssertEqual(result.usersInDirectory.count, 0u);
    XCTAssertEqual(result.groupConversations.count, 1u);

    XCTAssertEqualObjects(conversation, result.groupConversations[0]);
    ZMSearchUser *searchUser = result.usersInContacts[0];
    XCTAssertEqualObjects(user3, searchUser.user);

}

- (void)testThatItFindsConversationsThatContainsSearchTermOnlyInParticipantName
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.conversationType = ZMConversationTypeGroup;
    conversation.userDefinedName = @"Conversation";
    
    ZMUser *user3 = [self createConnectedUserWithName:@"Rëï"];
    [conversation addParticipant:user3];
    
    [self.uiMOC saveOrRollback];
    
    // when
    ZMSearchToken token = [self.sut searchForUsersAndConversationsMatchingQueryString:@"Rei"];
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];
    
    
    // then
    ZMSearchResult *result = [self firstSearchResultForToken:token];
    XCTAssertEqual(result.groupConversations.count, 1u);
    
    XCTAssertEqualObjects(conversation, result.groupConversations[0]);
    
}


- (void)testThatItOrdersConversationsByUserDefinedName
{
    // given
    ZMConversation *conversation1 = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation1.conversationType = ZMConversationTypeGroup;
    conversation1.userDefinedName = @"FooA";
    
    ZMConversation *conversation2 = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation2.userDefinedName = @"FooC";
    conversation2.conversationType = ZMConversationTypeGroup;
    
    ZMConversation *conversation3 = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation3.userDefinedName = @"FooB";
    conversation3.conversationType = ZMConversationTypeGroup;
    
    [self.uiMOC saveOrRollback];
    
    // when
    ZMSearchToken token = [self.sut searchForUsersAndConversationsMatchingQueryString:@"Foo"];
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];
    
    
    // then
    ZMSearchResult *result = [self firstSearchResultForToken:token];
    XCTAssertEqual(result.groupConversations.count, 3u);
    
    NSArray *expectedResult = @[conversation1, conversation3, conversation2];
    XCTAssertEqualObjects(result.groupConversations, expectedResult);
}


- (void)testThatItOrdersConversationsByUserDefinedNameFirstAndByParticipantNameSecond
{
    // given
    ZMUser *user1 = [self createConnectedUserWithName:@"Bla"];
    ZMUser *user2 = [self createConnectedUserWithName:@"FooB"];
    
    
    ZMConversation *conversation1 = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation1.conversationType = ZMConversationTypeGroup;
    conversation1.userDefinedName = @"FooA";
    
    ZMConversation *conversation2 = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation2.userDefinedName = @"Bar";
    [conversation2.mutableOtherActiveParticipants addObject:user1];
    conversation2.conversationType = ZMConversationTypeGroup;
    
    ZMConversation *conversation3 = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation3.userDefinedName = @"FooC";
    conversation3.conversationType = ZMConversationTypeGroup;
    
    ZMConversation *conversation4 = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation4.userDefinedName = @"Bar";
    [conversation4.mutableOtherActiveParticipants addObjectsFromArray:@[user1, user2]];
    conversation4.conversationType = ZMConversationTypeGroup;
    
    [self.uiMOC saveOrRollback];
    
    // when
    ZMSearchToken token = [self.sut searchForUsersAndConversationsMatchingQueryString:@"Foo"];
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];
    
    // then
    ZMSearchResult *result = [self firstSearchResultForToken:token];
    XCTAssertEqual(result.groupConversations.count, 3u);
    
    NSArray *expectedResult = @[conversation1, conversation3, conversation4];
    XCTAssertEqualObjects(result.groupConversations, expectedResult);
}

@end



@implementation ZMSearchDirectoryTests (CombinedSearch)


- (void)testThatItCanDoSeveralSearchesAtOnce
{
    // given
    ZMConversation *conversation1 = [self createGroupConversationWithName:@"conversation AAAA"];
    ZMConversation *conversation2 = [self createGroupConversationWithName:@"conversation BBBB"];
    ZMConversation *conversation3 = [self createGroupConversationWithName:@"conversation CCCC"];

    [self createConnectedUserWithName:@"user AAAA"];
    ZMUser *user2 = [self createConnectedUserWithName:@"user BBBB"];
    [self createConnectedUserWithName:@"user CCCC"];
    
    // when
    ZMSearchToken token1 = [self.sut searchForUsersAndConversationsMatchingQueryString:@"BBBB"];
    ZMSearchToken token2 = [self.sut searchForUsersAndConversationsMatchingQueryString:@"conversation"];
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];
    WaitForAllGroupsToBeEmpty(0.5);

    // then

    ZMSearchResult *result1 = [self firstSearchResultForToken:token1];
    XCTAssertEqual(result1.usersInContacts.count, 1u);
    XCTAssertEqual(result1.usersInDirectory.count, 0u);
    XCTAssertEqual(result1.groupConversations.count, 1u);

    XCTAssertEqualObjects(conversation2, result1.groupConversations[0]);
    ZMSearchUser *searchUser = result1.usersInContacts[0];
    XCTAssertEqualObjects(user2, searchUser.user);


    [self verifyThatResultWithToken:token2 containsConversations:@[conversation1, conversation2, conversation3] failureRecorder:NewFailureRecorder()];
}


@end



typedef void (^URLSessionCompletionBlock)(NSData *data, NSURLResponse *response, NSError *error);


@implementation ZMSearchDirectoryTests (RemoteSearch)


- (BOOL)isUserDataFromDirectory:(NSDictionary *)userData equalToSearchUser:(ZMSearchUser *)searchUser
{
    BOOL randomColor = [userData numberForKey:@"accent_id"].integerValue == 0;
    
    return [searchUser.displayName isEqualToString:userData[@"name"]] &&
    (randomColor || (searchUser.accentColorValue == [userData[@"accent_id"] integerValue]) ) &&
    searchUser.isConnected == NO &&
    searchUser.user == nil;
}

- (BOOL)isUserDataFromContacts:(NSDictionary *)userData equalToSearchUser:(ZMSearchUser *)searchUser
{
    return [searchUser.displayName isEqualToString:userData[@"name"]] &&
    [searchUser.remoteIdentifier.transportString isEqualToString:userData[@"id"]] &&
    searchUser.accentColorValue == [userData[@"accent_id"] integerValue] &&
    searchUser.isConnected == YES;
}


- (void)verifyThatResultWithToken:(ZMSearchToken)token containsDirectoryUsers:(NSArray *)users failureRecorder:(ZMTFailureRecorder *)failureRecorder
{
    ZMSearchResult *result = [self firstSearchResultForToken:token];
    FHAssertEqual(failureRecorder, result.usersInContacts.count, 0u);
    FHAssertEqual(failureRecorder, result.usersInDirectory.count, users.count);
    FHAssertEqual(failureRecorder, result.groupConversations.count, 0u);

    for (NSDictionary *userData in users) {

        NSUInteger index = [result.usersInDirectory indexOfObjectPassingTest:^BOOL(ZMSearchUser *searchUser, NSUInteger idx, BOOL *stop) {
            NOT_USED(idx);
            NOT_USED(stop);
            return [self isUserDataFromDirectory:userData equalToSearchUser:searchUser];
        }];

        FHAssertTrue(failureRecorder, index != NSNotFound);
    }
}

- (void)testThatItSendsASearchRequest
{
    // given
    NSString *searchURL = @"/search/contacts?q=Steve%20O'Hara%20%26%20S%C3%B6hne&l=3&size=30";
    ZMTransportRequest *expectedRequest = [ZMTransportRequest requestGetFromPath:searchURL];

    // expect
    __block ZMTransportRequest *request;
    [[self.transportSession expect] enqueueSearchRequest:ZM_ARG_SAVE(request)];

    // when
    [self.sut searchForUsersAndConversationsMatchingQueryString:@"Steve O'Hara & Söhne"];

    // then
    [self.transportSession verify];

    XCTAssertNotNil(request);
    XCTAssertEqualObjects(expectedRequest, request);
}

- (void)testThatItEncodesAPlusCharacterInTheSearchURL
{
    // given
    NSString *searchURL = @"/search/contacts?q=foo%2Bbar@example.com&l=3&size=30";
    ZMTransportRequest *expectedRequest = [ZMTransportRequest requestGetFromPath:searchURL];
    
    // expect
    __block ZMTransportRequest *request;
    [[self.transportSession expect] enqueueSearchRequest:ZM_ARG_SAVE(request)];
    
    // when
    [self.sut searchForUsersAndConversationsMatchingQueryString:@"foo+bar@example.com"];
    
    // then
    [self.transportSession verify];
    
    XCTAssertNotNil(request);
    XCTAssertEqualObjects(expectedRequest, request);
}

- (void)testThatItShortensShortQuerysTo200Characters
{
    // given
    NSString *croppedString = [@"f" stringByPaddingToLength:200 withString:@"o" startingAtIndex:0];
    NSString *tooLongString = [@"f" stringByPaddingToLength:400 withString:@"o" startingAtIndex:0];
    
    NSString *searchURL = [NSString stringWithFormat:@"/search/contacts?q=%@&l=3&size=30", croppedString];
    ZMTransportRequest *expectedRequest = [ZMTransportRequest requestGetFromPath:searchURL];
    
    // expect
    __block ZMTransportRequest *request;
    [[self.transportSession expect] enqueueSearchRequest:ZM_ARG_SAVE(request)];
    
    // when
    [self.sut searchForUsersAndConversationsMatchingQueryString:tooLongString];
    
    // then
    [self.transportSession verify];
    
    XCTAssertNotNil(request);
    XCTAssertEqualObjects(expectedRequest, request);
}

- (void)testThatItEncodesUnsafeCharactersInRequest
{
    // RFC 3986 Section 3.4 "Query"
    // <https://tools.ietf.org/html/rfc3986#section-3.4>
    //
    // "The characters slash ("/") and question mark ("?") may represent data within the query component."
    
    // given
    NSString *searchURL = @"/search/contacts?q=$%26%2B,/:;%3D?@&l=3&size=30";
    ZMTransportRequest *expectedRequest = [ZMTransportRequest requestGetFromPath:searchURL];
    
    // expect
    __block ZMTransportRequest *request;
    [[self.transportSession expect] enqueueSearchRequest:ZM_ARG_SAVE(request)];
    
    // when
    [self.sut searchForUsersAndConversationsMatchingQueryString:@"$&+,/:;=?@"];
    
    // then
    [self.transportSession verify];
    
    XCTAssertNotNil(request);
    XCTAssertEqualObjects(expectedRequest, request);
}


- (NSDictionary *)userDataWithName:(NSString *)name id:(NSUUID *)remoteIdentifier connected:(BOOL)isConnected
{
    return @{
             @"blocked" : @NO,
             @"accent_id" : @0,
             @"connected" : @(isConnected),
             @"email" : [NSNull null],
             @"id" : remoteIdentifier.transportString,
             @"level" : @2,
             @"name" : name,
             @"phone" : [NSNull null],
             @"weight" : @1

             };

}


- (void)testThatItCreatesSearchUsersForUnconnectedUsers
{
    // given

    // expect
    __block ZMTransportRequest *request;
    [[self.transportSession expect] enqueueSearchRequest:ZM_ARG_SAVE(request)];
    


    NSArray *searchUsers = @[
                             [self userDataWithName:@"User One" id:[NSUUID createUUID] connected:NO],
                             [self userDataWithName:@"User Two" id:[NSUUID createUUID] connected:NO],
                            ];

    NSDictionary *responseData = [self responseDataForUsers:searchUsers];


    // when
    ZMSearchToken token = [self.sut searchForUsersAndConversationsMatchingQueryString:@"User"];

    XCTAssertNotNil(request);
    if (request) {
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:responseData HTTPstatus:200 transportSessionError:nil];
        [request completeWithResponse:response];
    }
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];

    //then
    [self.transportSession verify];
    [self verifyThatResultWithToken:token containsDirectoryUsers:searchUsers  failureRecorder:NewFailureRecorder()];
    XCTAssertEqual(self.numberOfSearchResultUpdates, 1);
}



- (void)testThatItIncludesGroupConversationsInRemoteSearchResults
{
    
    // given
    ZMConversation *conversation = [self createGroupConversationWithName:@"teenage mutant ninja turtles"];
    ZMConversation *ninjaPenguinConversation = [self createGroupConversationWithName:@"teenage mutant ninja penguins"];
    
    
    __block ZMTransportRequest *request;
    [[self.transportSession expect] enqueueSearchRequest:ZM_ARG_SAVE(request)];
    
    
    NSArray *searchUsers = @[
                             [self userDataWithName:@"Peter Turtles" id:[NSUUID createUUID] connected:NO],
                             [self userDataWithName:@"Bobby Turtles" id:[NSUUID createUUID] connected:NO]
                            ];
    
    NSDictionary *responseData = [self responseDataForUsers:searchUsers];
    
    // when
    ZMSearchToken token = [self.sut searchForUsersAndConversationsMatchingQueryString:@"turtles"];
    
    XCTAssertNotNil(request);
    if (request) {
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:responseData HTTPstatus:200 transportSessionError:nil];
        [request completeWithResponse:response];
    }
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];
    
    //then
    [self.transportSession verify];
    XCTAssertEqual(self.numberOfSearchResultUpdates, 1);
    
    ZMSearchResult *result = [self firstSearchResultForToken:token];
    XCTAssertEqual(result.usersInContacts.count, 0u);
    XCTAssertEqual(result.usersInDirectory.count, searchUsers.count);
    XCTAssertEqual(result.groupConversations.count, 1u);
    
    for (NSDictionary *userData in searchUsers) {
        
        NSUInteger index = [result.usersInDirectory indexOfObjectPassingTest:^BOOL(ZMSearchUser *searchUser, NSUInteger idx, BOOL *stop) {
            NOT_USED(idx);
            NOT_USED(stop);
            return [self isUserDataFromDirectory:userData equalToSearchUser:searchUser];
        }];
        
        XCTAssertTrue(index != NSNotFound);
    }
    
    XCTAssertTrue([result.groupConversations containsObject:conversation]);
    XCTAssertFalse([result.groupConversations containsObject:ninjaPenguinConversation]);
}


- (void)testThatItCreatesSearchUsersForConnectedUsers
{
    // given

    ZMUser *user = [self createConnectedUserWithName:@"User One"];
    user.remoteIdentifier = [NSUUID createUUID];
    [self.uiMOC saveOrRollback];

    NSArray *searchUsers = @[
                             [self userDataWithName:user.name id:user.remoteIdentifier connected:YES], //level 1
                             [self userDataWithName:@"User Two" id:[NSUUID createUUID] connected:NO] // level: 2 ??
                             ];
    NSDictionary *responseData = [self responseDataForUsers:searchUsers];
    
    // expect
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:responseData HTTPstatus:200 transportSessionError:nil];
    [[self.transportSession expect] enqueueSearchRequest:[OCMArg checkWithBlock:^BOOL(ZMTransportRequest *request) {
        [request completeWithResponse:response];
        return YES;
    }]];


    // when
    ZMSearchToken token = [self.sut searchForUsersAndConversationsMatchingQueryString:@"User"];
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];

    //then
    [self.transportSession verify];

    ZMSearchResult *result = [self firstSearchResultForToken:token];
    XCTAssertEqual(result.usersInContacts.count, 1u);
    XCTAssertEqual(result.usersInDirectory.count, 1u);
    XCTAssertEqual(result.groupConversations.count, 0u);

    XCTAssertTrue([self isUserDataFromDirectory:searchUsers[1] equalToSearchUser:result.usersInDirectory[0]]);
    XCTAssertTrue([self isUserFromContacts:user equalToSearchUser:result.usersInContacts[0]]);
    XCTAssertEqual(self.numberOfSearchResultUpdates, 1);
}

- (void)testThatItFiltersOutTheSelfUser
{
    // expect
    ZMUser *selfUser = [ZMUser selfUserInContext:self.uiMOC];
    selfUser.remoteIdentifier = [NSUUID createUUID];
    
    __block ZMTransportRequest *request;
    [[self.transportSession expect] enqueueSearchRequest:ZM_ARG_SAVE(request)];
    
    NSDictionary *firstSearchUser = [self userDataWithName:@"User One" id:[NSUUID createUUID] connected:NO];
    NSDictionary *selfSearchUser = [self userDataWithName:@"User Two" id:selfUser.remoteIdentifier connected:NO];
    
    NSArray *searchUsers = @[
                             firstSearchUser,
                             selfSearchUser
                            ];
    
    NSDictionary *responseData = [self responseDataForUsers:searchUsers];
    
    
    // when
    ZMSearchToken token = [self.sut searchForUsersAndConversationsMatchingQueryString:@"User"];
    
    XCTAssertNotNil(request);
    if (request) {
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:responseData HTTPstatus:200 transportSessionError:nil];
        [request completeWithResponse:response];
    }
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];
    
    //then
    [self.transportSession verify];
    ZMSearchResult *result = [self firstSearchResultForToken:token];
    XCTAssertEqual(result.usersInContacts.count, 0u);
    XCTAssertEqual(result.usersInDirectory.count, 1u);
    XCTAssertEqual(result.groupConversations.count, 0u);
    
    if (result.usersInContacts.count > 1) {
        XCTAssertTrue([self isUserDataFromDirectory:firstSearchUser equalToSearchUser:result.usersInContacts[0]]);
    }
    
    XCTAssertEqual(self.numberOfSearchResultUpdates, 1);
}


- (void)testThatItUsesLocalKnowledgeAboutConnectionStatusToMoveUsersIntoResultArrays
{
    // given
    ZMUser *user = [self createConnectedUserWithName:@"User One"];
    user.remoteIdentifier = [NSUUID createUUID];
    [self.uiMOC saveOrRollback];
    
    // expect
    __block ZMTransportRequest *request;
    [[self.transportSession expect] enqueueSearchRequest:ZM_ARG_SAVE(request)];
    NSUUID *otherUserID = [NSUUID createUUID];
    
    NSArray *searchUsers = @[
                             [self userDataWithName:user.name id:user.remoteIdentifier connected:NO],
                             [self userDataWithName:@"User Two" id:otherUserID connected:NO]
                            ];
    
    NSDictionary *responseData = [self responseDataForUsers:searchUsers];
    
    
    // when
    ZMSearchToken token = [self.sut searchForUsersAndConversationsMatchingQueryString:@"User"];
    
    XCTAssertNotNil(request);
    if (request) {
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:responseData HTTPstatus:200 transportSessionError:nil];
        [request completeWithResponse:response];
    }
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];
    
    //then
    [self.transportSession verify];
    
    ZMSearchResult *result = [self firstSearchResultForToken:token];
    XCTAssertEqual(result.usersInContacts.count, 1u);
    XCTAssertEqual(result.usersInDirectory.count, 1u);
    XCTAssertEqual(result.groupConversations.count, 0u);
    
    ZMSearchUser *firstUserInContacts = result.usersInContacts[0];
    ZMSearchUser *firstUserInDirectory = result.usersInDirectory[0];
    XCTAssertTrue([self isUserFromContacts:user equalToSearchUser:firstUserInContacts]);
    XCTAssertEqualObjects(firstUserInDirectory.remoteIdentifier, otherUserID);
    XCTAssertEqual(self.numberOfSearchResultUpdates, 1);
}


- (void)testThatItUsesLocalSearchResultsWhenRemoteSearchReturnsNilResult
{
    // given
    ZMUser *user1 = [self createConnectedUserWithName:@"User One"];
    user1.remoteIdentifier = [NSUUID createUUID];

    [self.uiMOC saveOrRollback];
    
    // expect
    __block ZMTransportRequest *request;
    [[self.transportSession expect] enqueueSearchRequest:ZM_ARG_SAVE(request)];

    // when
    ZMSearchToken token = [self.sut searchForUsersAndConversationsMatchingQueryString:@"User"];
    
    XCTAssertNotNil(request);
    if (request) {
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:nil HTTPstatus:200 transportSessionError:nil];
        [request completeWithResponse:response];
    }
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];
    
    //then
    [self.transportSession verify];
    
    ZMSearchResult *result = [self firstSearchResultForToken:token];
    XCTAssertEqual(result.usersInContacts.count, 1u);
    
    ZMSearchUser *firstUserInContacts = result.usersInContacts[0];
    XCTAssertTrue([self isUserFromContacts:user1 equalToSearchUser:firstUserInContacts]);
}

@end


@implementation ZMSearchDirectoryTests (ConversationParticipantSearch)



- (void)testThatItDoesNotReturnLocalUsersThatAreAlreadyPartOfTheConversation
{
    // given
    ZMUser *user1 = [self createConnectedUserWithName:@"User1"];
    user1.remoteIdentifier = [NSUUID createUUID];
    ZMUser *user2 = [self createConnectedUserWithName:@"Hans"];
    user2.remoteIdentifier = [NSUUID createUUID];
    ZMUser *user3 = [self createConnectedUserWithName:@"User2"];
    user3.remoteIdentifier = [NSUUID createUUID];

    ZMConversation *conversation = [self createGroupConversationWithName:@"Conversation"];
    [conversation addParticipant:user2];

    [self.uiMOC saveOrRollback];
    
    // when
    ZMSearchToken token = [self.sut searchForUsersThatCanBeAddedToConversation:conversation queryString:@"User"];
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];

    // then
    [self verifyThatResultWithToken:token containsUsers:@[user1, user3] failureRecorder:NewFailureRecorder()];

    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItDoesNotReturnRemoteUsers
{
    // given
    ZMUser *user = [self createConnectedUserWithName:@"Hans"];
    user.remoteIdentifier = [NSUUID createUUID];

    ZMConversation *conversation = [self createGroupConversationWithName:@"Conversation"];
    [conversation addParticipant:user];

    [self.uiMOC saveOrRollback];

    [[self.transportSession reject] enqueueSearchRequest:OCMOCK_ANY];

    // when
    ZMSearchToken token = [self.sut searchForUsersThatCanBeAddedToConversation:conversation queryString:@"User"];
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];

    //then
    [self.transportSession verify];
    ZMSearchResult *result = [self firstSearchResultForToken:token];
    XCTAssertEqual(result.usersInContacts.count, 0u);
    XCTAssertEqual(result.usersInDirectory.count, 0u);
    XCTAssertEqual(result.groupConversations.count, 0u);
    
    XCTAssertEqual(self.numberOfSearchResultUpdates, 1);

}


- (void)testThatItReturnsEveryoneWhoCanBeAddedToAConversationWhenSearchingForEmptyString
{
    // given
    ZMUser *user1 = [self createConnectedUserWithName:@"User1"];
    user1.remoteIdentifier = [NSUUID createUUID];
    ZMUser *user2 = [self createConnectedUserWithName:@"User2"];
    user2.remoteIdentifier = [NSUUID createUUID];
    ZMUser *user3 = [self createConnectedUserWithName:@"User3"];
    user3.remoteIdentifier = [NSUUID createUUID];
    
    ZMConversation *conversation = [self createGroupConversationWithName:@"Conversation"];
    [conversation addParticipant:user2];
    
    [self.uiMOC saveOrRollback];

    // when
    ZMSearchToken token = [self.sut searchForUsersThatCanBeAddedToConversation:conversation queryString:@""];
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];
    
    // then
    [self.transportSession verify];
    [self verifyThatResultWithToken:token containsUsers:@[user1, user3] failureRecorder:NewFailureRecorder()];
    
    WaitForAllGroupsToBeEmpty(0.5);
}


@end



@implementation ZMSearchDirectoryTests (RemoteSearchTimeout)



- (void)testThatRemoteSearchTimeoutIsInitializedWithASensibleValue
{
    XCTAssertGreaterThan(self.sut.remoteSearchTimeout, 0);
}


- (NSDictionary *)genericResponseData {
    NSArray *searchUsers = @[
                             [self userDataWithName:@"User Three" id:[NSUUID createUUID] connected:NO],
                             [self userDataWithName:@"User Four" id:[NSUUID createUUID] connected:NO]
                            ];
    
    NSDictionary *responseData = [self responseDataForUsers:searchUsers];
    return responseData;
}

- (void)testThatItTimesOutAndReturnsJustLocalResults
{
    
    // given
    self.sut.remoteSearchTimeout = 0.05;
    
    ZMUser *user1 = [self createConnectedUserWithName:@"User One"];
    ZMUser *user2 = [self createConnectedUserWithName:@"User Two"];
    
    
    // expect
    __block ZMTransportRequest *request;
    [[self.transportSession expect] enqueueSearchRequest:ZM_ARG_SAVE(request)];
    
    
    // when
    ZMSearchToken token = [self.sut searchForUsersAndConversationsMatchingQueryString:@"User"];
    XCTAssertNotNil(request);
    
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];
    
    // Finish request after gathering search results, not before
    if (request) {
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:[self genericResponseData] HTTPstatus:200 transportSessionError:nil];
        [request completeWithResponse:response];
    }
    
    //then
    [self.transportSession verify];
    XCTAssertEqual(self.numberOfSearchResultUpdates, 1);

    ZMSearchResult *result = [self firstSearchResultForToken:token];
    XCTAssertEqual(result.usersInContacts.count, 2u);
    XCTAssertEqual(result.usersInDirectory.count, 0u);
    XCTAssertEqual(result.groupConversations.count, 0u);
    
    XCTAssertNotEqual([result.usersInContacts indexOfObjectPassingTest:^BOOL(ZMUser *obj, NSUInteger idx ZM_UNUSED, BOOL *stop ZM_UNUSED) {
        return [obj.remoteIdentifier isEqual:user1.remoteIdentifier];
    }], (NSUInteger)NSNotFound);
    XCTAssertNotEqual([result.usersInContacts indexOfObjectPassingTest:^BOOL(ZMUser *obj, NSUInteger idx ZM_UNUSED, BOOL *stop ZM_UNUSED) {
        return [obj.remoteIdentifier isEqual:user2.remoteIdentifier];
    }], (NSUInteger)NSNotFound);
    
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItFiresTimeOutWhenRemoteSearchReturnsTryAgainLaterError
{
    
    // given
    self.sut.remoteSearchTimeout = 0.05;
    
    ZMUser *user1 = [self createConnectedUserWithName:@"User One"];
    ZMUser *user2 = [self createConnectedUserWithName:@"User Two"];
    
    
    // expect
    __block ZMTransportRequest *request;
    [[self.transportSession expect] enqueueSearchRequest:ZM_ARG_SAVE(request)];
    
    
    // when
    ZMSearchToken token = [self.sut searchForUsersAndConversationsMatchingQueryString:@"User"];
    XCTAssertNotNil(request);
    
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];
    
    // Finish request after gathering search results, not before
    if (request) {
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:[self genericResponseData] HTTPstatus:420 transportSessionError:nil];
        [request completeWithResponse:response];
    }
    
    //then
    [self.transportSession verify];
    XCTAssertEqual(self.numberOfSearchResultUpdates, 1);
    
    ZMSearchResult *result = [self firstSearchResultForToken:token];
    XCTAssertEqual(result.usersInContacts.count, 2u);
    XCTAssertEqual(result.usersInDirectory.count, 0u);
    XCTAssertEqual(result.groupConversations.count, 0u);
    
    XCTAssertNotEqual([result.usersInContacts indexOfObjectPassingTest:^BOOL(ZMUser *obj, NSUInteger idx ZM_UNUSED, BOOL *stop ZM_UNUSED) {
        return [obj.remoteIdentifier isEqual:user1.remoteIdentifier];
    }], (NSUInteger)NSNotFound);
    XCTAssertNotEqual([result.usersInContacts indexOfObjectPassingTest:^BOOL(ZMUser *obj, NSUInteger idx ZM_UNUSED, BOOL *stop ZM_UNUSED) {
        return [obj.remoteIdentifier isEqual:user2.remoteIdentifier];
    }], (NSUInteger)NSNotFound);
    
    WaitForAllGroupsToBeEmpty(0.5);
}


- (void)testThatItTimesOutAndReturnsLocalResultsIfTimeoutHitsBeforeLocalSearchIsDone
{
    
    // given
    self.sut.remoteSearchTimeout = 0.01;
    
    ZMUser *user1 = [self createConnectedUserWithName:@"User One"];
    ZMUser *user2 = [self createConnectedUserWithName:@"User Two"];
    
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    
    [self.searchMOC performGroupedBlock:^{
        // block search context
        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
        dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC));
    }];
    
    // expect
    __block ZMTransportRequest *request;
    [[self.transportSession expect] enqueueSearchRequest:ZM_ARG_SAVE(request)];
    
    
    // when
    ZMSearchToken token = [self.sut searchForUsersAndConversationsMatchingQueryString:@"User"];
    XCTAssertNotNil(request);
    dispatch_semaphore_signal(semaphore);
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];
    
    
    // Finish request after gathering search results, not before
    if (request) {
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:[self genericResponseData] HTTPstatus:200 transportSessionError:nil];
        [request completeWithResponse:response];
    }
    
    //then
    [self.transportSession verify];
    XCTAssertEqual(self.numberOfSearchResultUpdates, 1);
    
    ZMSearchResult *result = [self firstSearchResultForToken:token];
    XCTAssertEqual(result.usersInContacts.count, 2u);
    XCTAssertEqual(result.usersInDirectory.count, 0u);
    XCTAssertEqual(result.groupConversations.count, 0u);
    
    XCTAssertNotEqual([result.usersInContacts indexOfObjectPassingTest:^BOOL(ZMUser *obj, NSUInteger idx ZM_UNUSED, BOOL *stop ZM_UNUSED) {
        return [obj.remoteIdentifier isEqual:user1.remoteIdentifier];
    }], (NSUInteger)NSNotFound);
    XCTAssertNotEqual([result.usersInContacts indexOfObjectPassingTest:^BOOL(ZMUser *obj, NSUInteger idx ZM_UNUSED, BOOL *stop ZM_UNUSED) {
        return [obj.remoteIdentifier isEqual:user2.remoteIdentifier];
    }], (NSUInteger)NSNotFound);
 
    WaitForAllGroupsToBeEmpty(0.5);
}


@end



@implementation ZMSearchDirectoryTests (UpdateDelay)

- (void)testThatUpdateDelayIsInitializedWithASensibleValue
{
    XCTAssertGreaterThan(self.sut.updateDelay, 0);
}


- (void)testThatTheSameLocalSearchResultIsReturnedWithinTheUpdateDelay
{
    // given
    self.sut.updateDelay = 999999;
    
    ZMUser *user1 = [self createConnectedUserWithName:@"Initial local user"];
    
    
    // first request
    ZMSearchToken token = [self.sut searchForUsersAndConversationsMatchingQueryString:@"user"];
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];
    
    NOT_USED(token);

    // create additional data
    ZMUser *user2 = [self createConnectedUserWithName:@"Subsequent local user"];
    
    // when
    [self resetSearchResultExpectation];
    ZMSearchToken token2 = [self.sut searchForUsersAndConversationsMatchingQueryString:@"user"];
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];

    
    // then
    [self.transportSession verify];
    XCTAssertEqual(self.numberOfSearchResultUpdates, 2);
    
    ZMSearchResult *result = [self firstSearchResultForToken:token2];
    XCTAssertEqual(result.usersInContacts.count, 1u);
    XCTAssertEqual(result.usersInDirectory.count, 0u);
    XCTAssertEqual(result.groupConversations.count, 0u);
    
    XCTAssertEqualObjects([(ZMUser *)result.usersInContacts.firstObject remoteIdentifier], user1.remoteIdentifier);
    NOT_USED(user2);
}


- (void)testThatTheSameRemoteSearchResultIsReturnedWithinTheUpdateDelay
{
    // given
    self.sut.updateDelay = 999999;
    
    __block ZMTransportRequest *request;
    [[self.transportSession expect] enqueueSearchRequest:ZM_ARG_SAVE(request)];
    
    [[self.transportSession reject] enqueueSearchRequest:OCMOCK_ANY];
    
    
    NSDictionary *userData1 = [self userDataWithName:@"Initial remote user" id:[NSUUID createUUID] connected:NO];
    
    NSDictionary *initialResponseData = [self responseDataForUsers:@[userData1]];
    
    
    // first request
    ZMSearchToken token = [self.sut searchForUsersAndConversationsMatchingQueryString:@"user"];
    
    XCTAssertNotNil(request);
    if (request) {
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:initialResponseData HTTPstatus:200 transportSessionError:nil];
        [request completeWithResponse:response];
    }
    request = nil;
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];
    
    NOT_USED(token);
    
    // when
    [self resetSearchResultExpectation];
    ZMSearchToken token2 = [self.sut searchForUsersAndConversationsMatchingQueryString:@"user"];
    
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];
    
    
    // then
    [self.transportSession verify];
    XCTAssertEqual(self.numberOfSearchResultUpdates, 2);
    
    ZMSearchResult *result = [self firstSearchResultForToken:token2];
    XCTAssertEqual(result.usersInContacts.count, 0u);
    XCTAssertEqual(result.usersInDirectory.count, 1u);
    XCTAssertEqual(result.groupConversations.count, 0u);
    
    XCTAssertTrue([self isUserDataFromDirectory:userData1 equalToSearchUser:result.usersInDirectory.firstObject]);
}


- (void)testThatItDoesNotReturnAResultForARegularSearchWhenSearchingForAddingToConversation
{
    // given
    self.sut.updateDelay = 999999;
    
    ZMUser *user1 = [self createConnectedUserWithName:@"User1"];
    user1.remoteIdentifier = [NSUUID createUUID];
    ZMUser *user2 = [self createConnectedUserWithName:@"User2"];
    user2.remoteIdentifier = [NSUUID createUUID];

    ZMConversation *conversation = [self createGroupConversationWithName:@"Conversation"];
    
    // when

    // first request
    [self.sut searchForUsersAndConversationsMatchingQueryString:@"User"];
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];
    XCTAssertEqual(self.numberOfSearchResultUpdates, 1);
    
    // second request
    ZMUser *user3 = [self createConnectedUserWithName:@"User3"];
    user3.remoteIdentifier = [NSUUID createUUID];
    // TODO: [self.uiMOC updateDisplayNameGeneratorWithInsertedUsers:[NSSet setWithObject:user3]  updatedUsers:nil deletedUsers:nil];
    
    [self resetSearchResultExpectation];
    [self.sut searchForUsersThatCanBeAddedToConversation:conversation queryString:@"User"];
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];
    WaitForAllGroupsToBeEmpty(0.5);
    
    //then
    XCTAssertEqual(self.numberOfSearchResultUpdates, 2);

    ZMSearchResult *result1 = [self searchResultAtIndex:0];
    XCTAssertEqual(result1.usersInContacts.count, 2u);

    ZMSearchResult *result2 = [self searchResultAtIndex:1];
    XCTAssertEqual(result2.usersInContacts.count, 3u);
}


- (void)testThatItDoesNotReturnAResultForAConversationAdditionSearchWhenDoingARegularSearch
{
    // given
    self.sut.updateDelay = 999999;
    
    ZMUser *user1 = [self createConnectedUserWithName:@"User1"];
    user1.remoteIdentifier = [NSUUID createUUID];
    ZMUser *user2 = [self createConnectedUserWithName:@"User2"];
    user2.remoteIdentifier = [NSUUID createUUID];
    
    ZMConversation *conversation = [self createGroupConversationWithName:@"Conversation"];
    
    
    // when
    
    // first request
    [self.sut searchForUsersThatCanBeAddedToConversation:conversation queryString:@"User"];
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];
    XCTAssertEqual(self.numberOfSearchResultUpdates, 1);
    
    // second request
    ZMUser *user3 = [self createConnectedUserWithName:@"User3"];
    user3.remoteIdentifier = [NSUUID createUUID];
    // TODO: [self.uiMOC updateDisplayNameGeneratorWithInsertedUsers:[NSSet setWithObject:user3]  updatedUsers:nil deletedUsers:nil];
    
    [self resetSearchResultExpectation];
    [self.sut searchForUsersAndConversationsMatchingQueryString:@"User"];
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];
    WaitForAllGroupsToBeEmpty(0.5);
    
    //then
    XCTAssertEqual(self.numberOfSearchResultUpdates, 2);
    
    ZMSearchResult *result1 = [self searchResultAtIndex:0];
    XCTAssertEqual(result1.usersInContacts.count, 2u);
    
    ZMSearchResult *result2 = [self searchResultAtIndex:1];
    XCTAssertEqual(result2.usersInContacts.count, 3u);
}


- (void)testThatItItPerformsANewSearchAfterUpdateDelayHasPassed
{
    // given
    self.sut.updateDelay = 0.05;
    
    // expect
    __block ZMTransportRequest *request1;
    __block ZMTransportRequest *request2;
    [[self.transportSession expect] enqueueSearchRequest:ZM_ARG_SAVE(request1)];
    
    [[self.transportSession expect] enqueueSearchRequest:ZM_ARG_SAVE(request2)];
    
    
    NSArray *searchUsers = @[
                             [self userDataWithName:@"User One" id:[NSUUID createUUID] connected:NO],
                             [self userDataWithName:@"User Two" id:[NSUUID createUUID] connected:NO]
                            ];
    
    NSDictionary *responseData = [self responseDataForUsers:searchUsers];
    
    
    // when
    
    // first request
    [self.sut searchForUsersAndConversationsMatchingQueryString:@"User"];
    
    XCTAssertNotNil(request1);
    if (request1) {
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:responseData HTTPstatus:200 transportSessionError:nil];
        [request1 completeWithResponse:response];
    }
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];
    
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssertEqual(self.numberOfSearchResultUpdates, 1);
    
    [self spinMainQueueWithTimeout:0.2];
    
    // second request
    [self resetSearchResultExpectation];
    [self.sut searchForUsersAndConversationsMatchingQueryString:@"User"];
    
    XCTAssertNotNil(request2);
    if (request2) {
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:responseData HTTPstatus:200 transportSessionError:nil];
        [request2 completeWithResponse:response];
    }
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];
    
    WaitForAllGroupsToBeEmpty(0.5);
    
    
    //then
    [self.transportSession verify];
    XCTAssertEqual(self.numberOfSearchResultUpdates, 2);
}



@end




@implementation ZMSearchDirectoryTests (TopConversations)

- (void)testThatItRequests9TopConversations
{
    self.maxTopConversationsCount = 9;
    
    [self recreateSUT];
    
    // expect
    [[self.transportSession expect] enqueueSearchRequest:[OCMArg checkWithBlock:^BOOL(ZMTransportRequest *r) {
        ZMTransportRequest *expectedRequest = [ZMTransportRequest requestGetFromPath:@"/search/top?size=9"];
        XCTAssertEqualObjects(r, expectedRequest);
        [self.searchResultExpectation fulfill];
        return YES;
    }]];
    
    // when
    NSArray *topConversations = self.sut.topConversations;
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
    
    // then
    [self.transportSession verify];
    XCTAssertNotNil(topConversations);
}

- (void)testThatItRequests26TopConversations
{
    self.maxTopConversationsCount = 26;
    
    [self recreateSUT];

    // expect
    [[self.transportSession expect] enqueueSearchRequest:[OCMArg checkWithBlock:^BOOL(ZMTransportRequest *r) {
        ZMTransportRequest *expectedRequest = [ZMTransportRequest requestGetFromPath:@"/search/top?size=26"];
        XCTAssertEqualObjects(r, expectedRequest);
        [self.searchResultExpectation fulfill];
        return YES;
    }]];
    
    // when
    NSArray *topConversations = self.sut.topConversations;
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
    
    // then
    [self.transportSession verify];
    XCTAssertNotNil(topConversations);
}

- (void)testThatItOnlyRequestsTopConversationsOnceIfCalledMultipleTimesInARow;
{
    // expect
    [[self.transportSession expect] enqueueSearchRequest:[OCMArg checkWithBlock:^BOOL(ZMTransportRequest *r) {
        ZMTransportRequest *expectedRequest = [ZMTransportRequest requestGetFromPath:@"/search/top?size=24"];
        XCTAssertEqualObjects(r, expectedRequest);
        [self.searchResultExpectation fulfill];
        return YES;
    }]];
    
    // when
    NSArray *topConversations1 = self.sut.topConversations;
    NSArray *topConversations2 = self.sut.topConversations;
    NSArray *topConversations3 = self.sut.topConversations;
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
    
    // then
    [self.transportSession verify];
    XCTAssertNotNil(topConversations1);
    XCTAssertNotNil(topConversations2);
    XCTAssertNotNil(topConversations3);
}

- (void)testThatItReturnsAnEmptyArrayTheFirstTime;
{
    // when
    NSArray *topConversations = self.sut.topConversations;
    
    // then
    XCTAssertNotNil(topConversations);
    XCTAssertEqualObjects(topConversations, @[]);
}

- (void)testThatItReturnsTheCachedResultTheSecondTime;
{
    // given
    NSArray *users = [self create9Users];
    ZMTransportResponse *successResponse = [self transportResponseForUsers:users];
    
    // expect
    [self expectSearchRequestAndCompleteWithResponse:successResponse expectation:self.searchResultExpectation];
    
    // when
    NSArray *topConversations = self.sut.topConversations;
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
    
    // then
    [self.transportSession verify];
    XCTAssertNotNil(topConversations);
    XCTAssertEqual(topConversations.count, 0u);
    
    // and when
    topConversations = self.sut.topConversations;
    XCTAssertNotNil(topConversations);
    XCTAssertEqual(topConversations.count, 9u);
    
    [topConversations enumerateObjectsUsingBlock:^(ZMConversation *conversation, NSUInteger idx, BOOL *stop) {
        NOT_USED(stop);
        XCTAssertEqual(conversation.connection.to, users[idx]);
    }];
}

- (void)testThatItDoesUpdatesTheCachedTopConversationsResultWhenTheCacheIsStale
{
    // given
    NSArray *users1 = [self create9Users];
    ZMTransportResponse *successResponse1 = [self transportResponseForUsers:users1];
    NSArray *users2 = [users1 reverseObjectEnumerator].allObjects;
    ZMTransportResponse *successResponse2 = [self transportResponseForUsers:users2];
    
    // expect
    [self expectSearchRequestAndCompleteWithResponse:successResponse1 expectation:self.searchResultExpectation];
    
    // when
    __block NSArray *topConversations = self.sut.topConversations;
    
    // then
    [self.transportSession verify];
    XCTAssertNotNil(topConversations);
    XCTAssertEqual(topConversations.count, 0u);
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
    XCTAssertEqual(self.topConversationChangeCount, 1u);
    
    //
    // and expect
    //
    self.searchResultExpectation = [self expectationWithDescription:@"wait for result"];
    [self expectSearchRequestAndCompleteWithResponse:successResponse2 expectation:self.searchResultExpectation];
    
    // when
    [ZMSearchDirectory invalidateCachedTopConversations];
    topConversations = self.sut.topConversations;
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
    XCTAssertEqual(self.topConversationChangeCount, 2u);
    
    // then
    XCTAssertNotNil(topConversations);
    XCTAssertEqual(topConversations.count, 9u);
    [topConversations enumerateObjectsUsingBlock:^(ZMConversation *conversation, NSUInteger idx, BOOL *stop) {
        NOT_USED(stop);
        XCTAssertEqual(conversation.connection.to, users1[idx]);
    }];
    
    // and when
    [ZMSearchDirectory invalidateCachedTopConversations];
    topConversations = self.sut.topConversations;
    
    // then
    // (all still unchanged):
    XCTAssertNotNil(topConversations);
    XCTAssertEqual(topConversations.count, 9u);
    [topConversations enumerateObjectsUsingBlock:^(ZMConversation *conversation, NSUInteger idx, BOOL *stop) {
        NOT_USED(stop);
        XCTAssertEqual(conversation.connection.to, users2[idx]);
    }];
}

- (void)testThatItDoesNotSendAnUpdateNotificationWhenTopConversationsRemainTheSame;
{
    // given
    NSArray *users = [self create9Users];
    ZMTransportResponse *successResponse = [self transportResponseForUsers:users];
    
    // expect
    [self expectSearchRequestAndCompleteWithResponse:successResponse expectation:self.searchResultExpectation];
    
    // when
    __block NSArray *topConversations = self.sut.topConversations;
    
    // then
    [self.transportSession verify];
    XCTAssertNotNil(topConversations);
    XCTAssertEqual(topConversations.count, 0u);
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
    XCTAssertEqual(self.topConversationChangeCount, 1u);
    
    //
    // and expect
    //
    self.searchResultExpectation = [self expectationWithDescription:@"wait for result"];
    [self expectSearchRequestAndCompleteWithResponse:successResponse expectation:self.searchResultExpectation];
    
    // when
    [ZMSearchDirectory invalidateCachedTopConversations];
    topConversations = self.sut.topConversations;
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
    XCTAssertEqual(self.topConversationChangeCount, 1u);
    
    // then
    XCTAssertNotNil(topConversations);
    XCTAssertEqual(topConversations.count, 9u);
    [topConversations enumerateObjectsUsingBlock:^(ZMConversation *conversation, NSUInteger idx, BOOL *stop) {
        NOT_USED(stop);
        XCTAssertEqual(conversation.connection.to, users[idx]);
    }];
    
    // and when
    [ZMSearchDirectory invalidateCachedTopConversations];

    topConversations = self.sut.topConversations;
    
    // then
    // (all still unchanged):
    XCTAssertNotNil(topConversations);
    XCTAssertEqual(topConversations.count, 9u);
    [topConversations enumerateObjectsUsingBlock:^(ZMConversation *conversation, NSUInteger idx, BOOL *stop) {
        NOT_USED(stop);
        XCTAssertEqual(conversation.connection.to, users[idx]);
    }];
}

- (void)testThatItDoesNotChangeTheCachedTopConversationsResultIfTheRequestFails;
{
    // given
    NSArray *users = [self create9Users];
    ZMTransportResponse *successResponse = [self transportResponseForUsers:users];
    ZMTransportResponse *failureResponse = [ZMTransportResponse responseWithPayload:nil HTTPstatus:0 transportSessionError:[NSError errorWithDomain:ZMTransportSessionErrorDomain code:ZMTransportSessionErrorCodeTryAgainLater userInfo:nil]];
    
    // expect
    [self expectSearchRequestAndCompleteWithResponse:successResponse expectation:self.searchResultExpectation];
    
    // when
    __block NSArray *topConversations = self.sut.topConversations;
    
    // then
    [self.transportSession verify];
    XCTAssertNotNil(topConversations);
    XCTAssertEqual(topConversations.count, 0u);
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
    XCTAssertEqual(self.topConversationChangeCount, 1u);
    
    //
    // and expect
    //
    [self performIgnoringZMLogError:^{
        self.searchResultExpectation = [self expectationWithDescription:@"wait for result"];
        [self expectSearchRequestAndCompleteWithResponse:failureResponse expectation:self.searchResultExpectation];
        
        // when
        [ZMSearchDirectory invalidateCachedTopConversations];
        topConversations = self.sut.topConversations;
        WaitForAllGroupsToBeEmpty(0.5);
        XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
        XCTAssertEqual(self.topConversationChangeCount, 1u, @"Should not receive a notification, since it didn't change.");
        
        // then
        XCTAssertNotNil(topConversations);
        XCTAssertEqual(topConversations.count, 9u);
        [topConversations enumerateObjectsUsingBlock:^(ZMConversation *conversation, NSUInteger idx, BOOL *stop) {
            NOT_USED(stop);
            XCTAssertEqual(conversation.connection.to, users[idx]);
        }];
        
        // and when
        [ZMSearchDirectory invalidateCachedTopConversations];
        topConversations = self.sut.topConversations;
        
        // then
        // (all still unchanged):
        XCTAssertNotNil(topConversations);
        XCTAssertEqual(topConversations.count, 9u);
        [topConversations enumerateObjectsUsingBlock:^(ZMConversation *conversation, NSUInteger idx, BOOL *stop) {
            NOT_USED(stop);
            XCTAssertEqual(conversation.connection.to, users[idx]);
        }];
    }];
}

- (void)testThatItPersistsTheTopConversations;
{
    // given
    NSArray *users = [self create9Users];
    ZMTransportResponse *successResponse = [self transportResponseForUsers:users];
    
    // expect
    [self expectSearchRequestAndCompleteWithResponse:successResponse expectation:self.searchResultExpectation];
    
    // when (1)
    NSArray *topConversations = self.sut.topConversations;
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
    topConversations = self.sut.topConversations;
    
    // then (1)
    XCTAssertEqual(topConversations.count, 9u);
    
    [self recreateSUT];
    
    // when (2)
    topConversations = self.sut.topConversations;
    
    // then (2)
    XCTAssertEqual(topConversations.count, 9u);
    [topConversations enumerateObjectsUsingBlock:^(ZMConversation *conversation, NSUInteger idx, BOOL *stop) {
        NOT_USED(stop);
        XCTAssertEqual(conversation.connection.to, users[idx]);
    }];
}

- (NSArray *)create9Users;
{
    NSMutableArray *users = [NSMutableArray array];
    for (int i = 0; i < 9; ++i) {
        ZMUser *user = [self createConnectedUserWithName:[NSString stringWithFormat:@"User %d", i]];
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
        conversation.conversationType = ZMConversationTypeOneOnOne;
        user.connection.conversation = conversation;
        [users addObject:user];
    }
    [self.uiMOC saveOrRollback];
    return users;
}

- (ZMTransportResponse *)transportResponseForUsers:(NSArray *)users;
{
    NSMutableArray *searchUsers = [NSMutableArray array];
    for (ZMUser *user in users) {
        NSMutableDictionary *userData = [[self userDataWithName:user.name id:user.remoteIdentifier connected:YES] mutableCopy];
        userData[@"accent_id"] = @(user.accentColorValue);
        [searchUsers addObject:userData];
    }
    NSDictionary *responsePayload = [self responseDataForUsers:searchUsers];
    return [ZMTransportResponse responseWithPayload:responsePayload HTTPstatus:200 transportSessionError:nil];
}

- (void)expectSearchRequestAndCompleteWithResponse:(ZMTransportResponse *)response expectation:(XCTestExpectation *)expectation;
{
    [[self.transportSession expect] enqueueSearchRequest:[OCMArg checkWithBlock:^BOOL(ZMTransportRequest *r) {
        XCTAssertTrue([r.path hasPrefix:@"/search/top"]);
        [expectation fulfill];
        [self.syncMOC performGroupedBlock:^{
            [r completeWithResponse:response];
        }];
        return YES;
    }]];
}


@end






@implementation ZMSearchDirectoryTests (Observer)

- (id<ZMSearchResultObserver>)makeObserver
{
    id<ZMSearchResultObserver> observer = (id<ZMSearchResultObserver>)[OCMockObject mockForProtocol:@protocol(ZMSearchResultObserver)];
    [self.sut addSearchResultObserver:observer];
    return observer;
}



- (void)testThatItNotifiesSeveralObservers
{
    // given
    id<ZMSearchResultObserver> observer1 = [self makeObserver];
    [[(OCMockObject *)observer1 expect] didReceiveSearchResult:OCMOCK_ANY forToken:OCMOCK_ANY];

    id<ZMSearchResultObserver> observer2 = [self makeObserver];
    [[(OCMockObject *)observer2 expect] didReceiveSearchResult:OCMOCK_ANY forToken:OCMOCK_ANY];

    // when
    [self.sut searchForUsersAndConversationsMatchingQueryString:@"Nobody"];
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];

    // then
    XCTAssertTrue(self.searchResults.count > 0);
    [(OCMockObject *)observer1 verify];
    [(OCMockObject *)observer2 verify];
}


- (void)testThatItDoesNotNotifyObserversAfterRemoval
{
    // given
    id<ZMSearchResultObserver> observer1 = [self makeObserver];
    id<ZMSearchResultObserver> observer2 = [self makeObserver];
    [self.sut removeSearchResultObserver:observer1];

    [[(OCMockObject *)observer1 reject] didReceiveSearchResult:OCMOCK_ANY forToken:OCMOCK_ANY];
    [[(OCMockObject *)observer2 expect] didReceiveSearchResult:OCMOCK_ANY forToken:OCMOCK_ANY];
    
    // when
    [self.sut searchForUsersAndConversationsMatchingQueryString:@"Nobody"];
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];

    // then
    XCTAssertTrue(self.searchResults.count > 0);
    [(OCMockObject *)observer1 verify];
    [(OCMockObject *)observer2 verify];
}

@end



@implementation ZMSearchDirectoryTests (SuggestedPeople)

- (NSDictionary *)createUsersForSuggestedPeopleSearch;
{
    // given
    NSArray *remoteIDs = @[NSUUID.createUUID, NSUUID.createUUID, NSUUID.createUUID, NSUUID.createUUID, NSUUID.createUUID];
    
    self.uiMOC.suggestedUsersForUser = [NSOrderedSet orderedSetWithArray:remoteIDs];

    // Existing blocked local user for remoteIDs[1] (should be filtered out):
    ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user1.remoteIdentifier = remoteIDs[1];
    user1.name = @"Günter";
    user1.accentColorValue = ZMAccentColorStrongBlue;
    user1.connection = [ZMConnection insertNewObjectInManagedObjectContext:self.uiMOC];
    user1.connection.status = ZMConnectionStatusBlocked;
    
    // No local user for remoteIDs[2]
    
    // Existing connected local user for remoteIDs[3] (should be filtered out):
    ZMUser *user3 = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user3.remoteIdentifier = remoteIDs[3];
    user3.name = @"Hans";
    user3.accentColorValue = ZMAccentColorBrightYellow;
    user3.connection = [ZMConnection insertNewObjectInManagedObjectContext:self.uiMOC];
    user3.connection.status = ZMConnectionStatusAccepted;
    
    XCTAssert([self.uiMOC saveOrRollback]);

    ZMSearchUser *searchUser0 = [[ZMSearchUser alloc] initWithName:@"Sophie" accentColor:ZMAccentColorSoftPink remoteID:remoteIDs[0] user:nil syncManagedObjectContext: self.syncMOC uiManagedObjectContext:self.uiMOC];

    // ZMSearchUser *searchUser1 = [[ZMSearchUser alloc] initWithName:nil accentColor:ZMAccentColorUndefined isConnected:NO remoteID:nil user:user1];
    ZMSearchUser *searchUser2 = [[ZMSearchUser alloc] initWithName:@"Max" accentColor:ZMAccentColorStrongBlue remoteID:remoteIDs[2] user:nil syncManagedObjectContext: self.syncMOC uiManagedObjectContext:self.uiMOC];

    // ZMSearchUser *searchUser3 = [[ZMSearchUser alloc] initWithName:nil accentColor:ZMAccentColorUndefined isConnected:NO remoteID:nil user:user3];
    ZMSearchUser *searchUser4 = [[ZMSearchUser alloc] initWithName:@"Maria" accentColor:ZMAccentColorStrongLimeGreen remoteID:remoteIDs[4] user:nil syncManagedObjectContext: self.syncMOC uiManagedObjectContext:self.uiMOC];
    
    NSArray *responsePayload = @[@{@"accent_id": @(ZMAccentColorSoftPink),
                                   @"name": @"Sophie",
                                   @"id": ((NSUUID *)remoteIDs[0]).transportString},
                                 @{@"accent_id": @(ZMAccentColorStrongBlue),
                                   @"name": @"Max",
                                   @"id": ((NSUUID *)remoteIDs[2]).transportString},
                                 @{@"accent_id": @(ZMAccentColorStrongLimeGreen),
                                   @"name": @"Maria",
                                   @"id": ((NSUUID *)remoteIDs[4]).transportString},
                                 ];
    return @{@"u": @[searchUser0, searchUser2, searchUser4], @"p": responsePayload, @"r": remoteIDs};
}

- (void)testSearchingForSuggestedPeople;
{
    // given
    NSDictionary *setup = [self createUsersForSuggestedPeopleSearch];
    ZMSearchUser *searchUser0 = setup[@"u"][0];
    ZMSearchUser *searchUser2 = setup[@"u"][1];
    ZMSearchUser *searchUser4 = setup[@"u"][2];
    NSArray *responsePayload = setup[@"p"];
    NSArray *remoteIDs = setup[@"r"];
    
    // expect
    [[self.transportSession expect] enqueueSearchRequest:OCMOCK_ANY];
        
    ZMTransportResponse *response2 = [ZMTransportResponse responseWithPayload:responsePayload HTTPstatus:200 transportSessionError:nil];
    NSString *expectedPath2 = [NSString stringWithFormat:@"/users?ids=%@,%@,%@",
                              [remoteIDs[0] transportString],
                              [remoteIDs[2] transportString],
                              [remoteIDs[4] transportString]];
    [[self.transportSession expect] enqueueSearchRequest:[OCMArg checkWithBlock:^BOOL(ZMTransportRequest *req) {
        XCTAssertEqualObjects(req.path, expectedPath2);
        XCTAssertEqual(req.method, ZMMethodGET);
        [req completeWithResponse:response2];
        return YES;
    }]];
    
    
    // when
    id token = [self.sut searchForSuggestedPeople];
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];
    
    // then
    XCTAssertEqual(self.searchResults.count, 1u);
    TokenAndSearchResult *result = self.searchResults.firstObject;
    XCTAssertEqualObjects(result.token, token);
    XCTAssertEqual(result.searchResult.usersInContacts.count, 0u);
    XCTAssertEqual(result.searchResult.groupConversations.count, 0u);
    XCTAssertEqual(result.searchResult.usersInDirectory.count, 3u);
    NSArray *expectedUsers = @[searchUser0, searchUser2, searchUser4];
    XCTAssertEqualObjects(result.searchResult.usersInDirectory, expectedUsers);
}

- (void)testThatTheSuggestedPeopleSearchResultIsUpdatedWhenPeopleAreRemoved;
{
    // given (1)
    NSDictionary *setup = [self createUsersForSuggestedPeopleSearch];
    ZMSearchUser *searchUser0 = setup[@"u"][0];
    ZMSearchUser *searchUser2 = setup[@"u"][1];
    ZMSearchUser *searchUser4 = setup[@"u"][2];
    NSArray *responsePayload = setup[@"p"];
    NSArray *remoteIDs = setup[@"r"];
    
    // expect (1)
    [[self.transportSession expect] enqueueSearchRequest:OCMOCK_ANY];
    
    ZMTransportResponse *response2 = [ZMTransportResponse responseWithPayload:responsePayload HTTPstatus:200 transportSessionError:nil];
    NSString *expectedPath2 = [NSString stringWithFormat:@"/users?ids=%@,%@,%@",
                               [remoteIDs[0] transportString],
                               [remoteIDs[2] transportString],
                               [remoteIDs[4] transportString]];
    [[self.transportSession expect] enqueueSearchRequest:[OCMArg checkWithBlock:^BOOL(ZMTransportRequest *req) {
        XCTAssertEqualObjects(req.path, expectedPath2);
        XCTAssertEqual(req.method, ZMMethodGET);
        [req completeWithResponse:response2];
        return YES;
    }]];
    
    
    // when (1)
    id token = [self.sut searchForSuggestedPeople];
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];
    
    // First time we get all 3 users:
    XCTAssertEqual(self.searchResults.count, 1u);
    TokenAndSearchResult *result1 = self.searchResults.firstObject;
    XCTAssertEqual(result1.searchResult.usersInDirectory.count, 3u);
    
    // when (2)
    XCTAssertEqualObjects(result1.searchResult.usersInDirectory[1], searchUser2);
    [self.sut removeSearchUserFromSuggestedPeople:searchUser2];
    
    [self resetSearchResultExpectation];
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];
    
    // then (2)
    XCTAssertEqual(self.searchResults.count, 2u);
    TokenAndSearchResult *result2 = self.searchResults.lastObject;
    XCTAssertEqualObjects(result2.token, token);
    XCTAssertEqual(result2.searchResult.usersInContacts.count, 0u);
    XCTAssertEqual(result2.searchResult.groupConversations.count, 0u);
    XCTAssertEqual(result2.searchResult.usersInDirectory.count, 2u);
    NSArray *expectedUsers = @[searchUser0, searchUser4];
    XCTAssertEqualObjects(result2.searchResult.usersInDirectory, expectedUsers);
}

- (void)testThatANewSearchForSuggestedPeopleDoesNotIncludePreviouslyRemovedPeople;
{
    // given (1)
    NSDictionary *setup = [self createUsersForSuggestedPeopleSearch];
    ZMSearchUser *searchUser0 = setup[@"u"][0];
    ZMSearchUser *searchUser2 = setup[@"u"][1];
    ZMSearchUser *searchUser4 = setup[@"u"][2];
    NSArray *responsePayload = setup[@"p"];
    NSArray *remoteIDs = setup[@"r"];
    
    // expect (1)
    [[self.transportSession expect] enqueueSearchRequest:OCMOCK_ANY];
    
    ZMTransportResponse *response2 = [ZMTransportResponse responseWithPayload:responsePayload HTTPstatus:200 transportSessionError:nil];
    NSString *expectedPath2 = [NSString stringWithFormat:@"/users?ids=%@,%@,%@",
                               [remoteIDs[0] transportString],
                               [remoteIDs[2] transportString],
                               [remoteIDs[4] transportString]];
    [[self.transportSession expect] enqueueSearchRequest:[OCMArg checkWithBlock:^BOOL(ZMTransportRequest *req) {
        XCTAssertEqualObjects(req.path, expectedPath2);
        XCTAssertEqual(req.method, ZMMethodGET);
        [req completeWithResponse:response2];
        return YES;
    }]];
    
    
    // when (1)
    id token = [self.sut searchForSuggestedPeople];
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];
    
    // First time we get all 3 users:
    XCTAssertEqual(self.searchResults.count, 1u);
    TokenAndSearchResult *result1 = self.searchResults.firstObject;
    XCTAssertEqual(result1.searchResult.usersInDirectory.count, 3u);
    
    // when (2)
    XCTAssertEqualObjects(result1.searchResult.usersInDirectory[1], searchUser2);
    [self.sut removeSearchUserFromSuggestedPeople:searchUser2];

    [self resetSearchResultExpectation];
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];
    
    // new search
    [self.searchResults removeAllObjects];
    token = [self.sut searchForSuggestedPeople];
    [self resetSearchResultExpectation];
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];
    
    // then (2)
    XCTAssertEqual(self.searchResults.count, 1u);
    TokenAndSearchResult *result2 = self.searchResults.firstObject;
    XCTAssertEqualObjects(result2.token, token);
    XCTAssertEqual(result2.searchResult.usersInContacts.count, 0u);
    XCTAssertEqual(result2.searchResult.groupConversations.count, 0u);
    XCTAssertEqual(result2.searchResult.usersInDirectory.count, 2u);
    NSArray *expectedUsers = @[searchUser0, searchUser4];
    XCTAssertEqualObjects(result2.searchResult.usersInDirectory, expectedUsers);
}

- (void)testSearchingForSuggestedPeopleUpdatesRemoteIdentifier;
{
    // given
    NSArray *remoteIDs = @[NSUUID.createUUID, NSUUID.createUUID, NSUUID.createUUID, NSUUID.createUUID, NSUUID.createUUID];
    
    self.uiMOC.suggestedUsersForUser = [NSOrderedSet orderedSetWithArray:remoteIDs];
    
    // Existing blocked local user for remoteIDs[1] (should be filtered out):
    ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user1.remoteIdentifier = remoteIDs[1];
    user1.name = @"Günter";
    user1.accentColorValue = ZMAccentColorStrongBlue;
    user1.connection = [ZMConnection insertNewObjectInManagedObjectContext:self.uiMOC];
    user1.connection.status = ZMConnectionStatusBlocked;
    
    // No local user for remoteIDs[2]
    
    // Existing connected local user for remoteIDs[3] (should be filtered out):
    ZMUser *user3 = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user3.remoteIdentifier = remoteIDs[3];
    user3.name = @"Hans";
    user3.accentColorValue = ZMAccentColorBrightYellow;
    user3.connection = [ZMConnection insertNewObjectInManagedObjectContext:self.uiMOC];
    user3.connection.status = ZMConnectionStatusAccepted;
    
    XCTAssert([self.uiMOC saveOrRollback]);
    XCTAssertEqualObjects(self.uiMOC.suggestedUsersForUser.array, remoteIDs);
    
    
    NSArray *responsePayload = @[@{@"accent_id": @(ZMAccentColorSoftPink),
                                   @"name": @"Sophie",
                                   @"id": ((NSUUID *)remoteIDs[0]).transportString},
                                 @{@"accent_id": @(ZMAccentColorStrongBlue),
                                   @"name": @"Max",
                                   @"id": ((NSUUID *)remoteIDs[2]).transportString},
                                 @{@"accent_id": @(ZMAccentColorStrongLimeGreen),
                                   @"name": @"Maria",
                                   @"id": ((NSUUID *)remoteIDs[4]).transportString},
                                 ];
    
    // expect
    ZMTransportResponse *response1 = [ZMTransportResponse responseWithPayload:@{@"documents": responsePayload} HTTPstatus:200 transportSessionError:nil];
    NSString *expectedPath1 = @"/search/suggestions?size=30";
    [[self.transportSession expect] enqueueSearchRequest:[OCMArg checkWithBlock:^BOOL(ZMTransportRequest *req) {
        XCTAssertEqualObjects(req.path, expectedPath1);
        XCTAssertEqual(req.method, ZMMethodGET);
        [req completeWithResponse:response1];
        return YES;
    }]];

    [[self.transportSession expect] enqueueSearchRequest:OCMOCK_ANY];
    
    // when
    [self.sut searchForSuggestedPeople];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    NSArray *expectedUserIDs = @[remoteIDs[0], remoteIDs[2], remoteIDs[4]];
    XCTAssertEqualObjects(self.uiMOC.suggestedUsersForUser.array, expectedUserIDs);
}

- (void)testSearchingForSuggestedPeopleDoesNotUpdateRemoteIdentifiersIfTheyDidNotChange;
{
    // given
    NSArray *remoteIDs = @[NSUUID.createUUID, NSUUID.createUUID, NSUUID.createUUID, NSUUID.createUUID, NSUUID.createUUID];
    
    self.uiMOC.suggestedUsersForUser = [NSOrderedSet orderedSetWithArray:remoteIDs];
    
    XCTAssert([self.uiMOC saveOrRollback]);
    XCTAssertEqualObjects(self.uiMOC.suggestedUsersForUser.array, remoteIDs);
    
    // expect
    [[self.transportSession expect] enqueueSearchRequest:[OCMArg checkWithBlock:^BOOL(ZMTransportRequest *req) {
        if ([req.path isEqualToString:@"/search/suggestions?size=9"]) {
            return NO;
        }
        return YES;
    }]];
    
    // when
    [self.sut searchForSuggestedPeople];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqualObjects(self.uiMOC.suggestedUsersForUser.array, remoteIDs);
}

- (void)testSearchingForSuggestedPeopleExcludesContactsIgnoredAndBlocked;
{
    // given
    NSMutableArray *remoteIDs = [NSMutableArray array];
    
    ZMConnectionStatus ignored[] = {
        ZMConnectionStatusAccepted,
        ZMConnectionStatusPending,
        ZMConnectionStatusIgnored,
        ZMConnectionStatusBlocked,
        ZMConnectionStatusSent,
    };
    for (size_t i = 0; i < (sizeof(ignored)/sizeof(*ignored)); ++i) {
        NSUUID *remoteID = NSUUID.createUUID;
        [remoteIDs addObject:remoteID];
    
        ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
        user.remoteIdentifier = remoteID;
        user.connection = [ZMConnection insertNewObjectInManagedObjectContext:self.uiMOC];
        user.connection.status = ignored[i];
        user.name = [NSString stringWithFormat:@"Sophie %d", (int) user.connection.status];
        user.accentColorValue = ZMAccentColorSoftPink;
    }
    self.uiMOC.suggestedUsersForUser = [NSOrderedSet orderedSetWithArray:remoteIDs];
    XCTAssert([self.uiMOC saveOrRollback]);
    
    // reject
    [[self.transportSession expect] enqueueSearchRequest:OCMOCK_ANY];
    [[self.transportSession reject] enqueueSearchRequest:OCMOCK_ANY];
    
    // when
    id token = [self.sut searchForSuggestedPeople];
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];
    
    XCTAssertEqual(self.searchResults.count, 1u);
    TokenAndSearchResult *result = self.searchResults.firstObject;
    XCTAssertEqualObjects(result.token, token);
    XCTAssertEqual(result.searchResult.usersInContacts.count, 0u);
    XCTAssertEqual(result.searchResult.groupConversations.count, 0u);
    XCTAssertEqual(result.searchResult.usersInDirectory.count, 0u);
}

- (void)testThatItUsesTheCacheForSuggestedPeopleTheSecondsTime;
{
    // given
    NSArray *remoteIDs = @[NSUUID.createUUID];
    self.uiMOC.suggestedUsersForUser = [NSOrderedSet orderedSetWithArray:remoteIDs];

    XCTAssert([self.uiMOC save:nil]);
    
    ZMSearchUser *searchUser = [[ZMSearchUser alloc] initWithName:@"Maria" accentColor:ZMAccentColorStrongLimeGreen remoteID:remoteIDs[0] user:nil syncManagedObjectContext: self.syncMOC uiManagedObjectContext:self.uiMOC];

    
    NSArray *responsePayload = @[@{@"accent_id": @(ZMAccentColorStrongLimeGreen),
                                   @"name": @"Maria",
                                   @"id": ((NSUUID *)remoteIDs[0]).transportString},
                                 ];
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:responsePayload HTTPstatus:200 transportSessionError:nil];
    
    // expect
    [[self.transportSession expect] enqueueSearchRequest:OCMOCK_ANY];

    NSString *expectedPath = [@"/users?ids=" stringByAppendingString:[remoteIDs[0] transportString]];
    [[self.transportSession expect] enqueueSearchRequest:[OCMArg checkWithBlock:^BOOL(ZMTransportRequest *req) {
        XCTAssertEqualObjects(req.path, expectedPath);
        XCTAssertEqual(req.method, ZMMethodGET);
        [req completeWithResponse:response];
        return YES;
    }]];
    
    // when
    (void) [self.sut searchForSuggestedPeople];
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];
    
    XCTAssertEqual(self.searchResults.count, 1u);
    TokenAndSearchResult *result1 = self.searchResults.firstObject;
    XCTAssertEqual(result1.searchResult.usersInDirectory.count, 1u);
    XCTAssertEqualObjects(result1.searchResult.usersInDirectory, @[searchUser]);
    [self.searchResults removeAllObjects];
    [self resetSearchResultExpectation];
    
    // expect
    // (nothing to be called)
    
    // when
    (void) [self.sut searchForSuggestedPeople];
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];
    
    XCTAssertEqual(self.searchResults.count, 1u);
    TokenAndSearchResult *result2 = self.searchResults.firstObject;
    XCTAssertEqual(result2.searchResult.usersInDirectory.count, 1u);
    XCTAssertEqualObjects(result2.searchResult.usersInDirectory, @[searchUser]);
}

- (void)testThatItRefetchesTheResultsWhenTheRemoteIDsChange;
{
    {
        // given
        NSArray *originalRemoteIDs = @[NSUUID.createUUID];
        self.uiMOC.suggestedUsersForUser = [NSOrderedSet orderedSetWithArray:originalRemoteIDs];

        XCTAssert([self.uiMOC save:nil]);
        
        ZMSearchUser *searchUser = [[ZMSearchUser alloc] initWithName:@"Maria" accentColor:ZMAccentColorStrongLimeGreen remoteID:originalRemoteIDs[0] user:nil syncManagedObjectContext: self.syncMOC uiManagedObjectContext:self.uiMOC];

        
        NSArray *responsePayload = @[@{@"accent_id": @(ZMAccentColorStrongLimeGreen),
                                       @"name": @"Maria",
                                       @"id": ((NSUUID *)originalRemoteIDs[0]).transportString},
                                     ];
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:responsePayload HTTPstatus:200 transportSessionError:nil];
        
        // expect
        [[self.transportSession expect] enqueueSearchRequest:OCMOCK_ANY];
        
        NSString *expectedPath = [@"/users?ids=" stringByAppendingString:[originalRemoteIDs[0] transportString]];
        [[self.transportSession expect] enqueueSearchRequest:[OCMArg checkWithBlock:^BOOL(ZMTransportRequest *req) {
            XCTAssertEqualObjects(req.path, expectedPath);
            XCTAssertEqual(req.method, ZMMethodGET);
            [req completeWithResponse:response];
            return YES;
        }]];
        
        // when
        (void) [self.sut searchForSuggestedPeople];
        [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];
        
        XCTAssertEqual(self.searchResults.count, 1u);
        TokenAndSearchResult *result1 = self.searchResults.firstObject;
        XCTAssertEqual(result1.searchResult.usersInDirectory.count, 1u);
        XCTAssertEqualObjects(result1.searchResult.usersInDirectory, @[searchUser]);
    }
    [self.searchResults removeAllObjects];
    [self resetSearchResultExpectation];
    
    //
    // Remote IDs changing
    //
    
    {
        NSArray *newRemoteIDs = @[NSUUID.createUUID];
        ZMSearchUser *searchUser = [[ZMSearchUser alloc] initWithName:@"Hans" accentColor:ZMAccentColorBrightOrange remoteID:newRemoteIDs[0] user:nil syncManagedObjectContext: self.syncMOC uiManagedObjectContext:self.uiMOC];
        
        NSArray *responsePayload = @[@{@"accent_id": @(ZMAccentColorBrightOrange),
                                       @"name": @"Maria",
                                       @"id": ((NSUUID *)newRemoteIDs[0]).transportString},
                                     ];
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:responsePayload HTTPstatus:200 transportSessionError:nil];
        
        // expect
        NSString *expectedPath = [@"/users?ids=" stringByAppendingString:[newRemoteIDs[0] transportString]];
        [[self.transportSession expect] enqueueSearchRequest:[OCMArg checkWithBlock:^BOOL(ZMTransportRequest *req) {
            XCTAssertEqualObjects(req.path, expectedPath);
            XCTAssertEqual(req.method, ZMMethodGET);
            [req completeWithResponse:response];
            return YES;
        }]];
        
        self.uiMOC.suggestedUsersForUser = [NSOrderedSet orderedSetWithArray:newRemoteIDs];
        XCTAssert([self.uiMOC save:nil]);
        
        // when
        [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];
        
        XCTAssertEqual(self.searchResults.count, 1u);
        TokenAndSearchResult *result1 = self.searchResults.firstObject;
        XCTAssertEqual(result1.searchResult.usersInDirectory.count, 1u);
        XCTAssertEqualObjects(result1.searchResult.usersInDirectory, @[searchUser]);
    }
}

- (void)testThatItCompletesTheSearchIfThereAreNoResults
{
    
    // given
    NSOrderedSet *originalRemoteIDs = nil;
    self.uiMOC.suggestedUsersForUser = originalRemoteIDs;
    XCTAssert([self.uiMOC save:nil]);
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:@{@"documents":@[]} HTTPstatus:200 transportSessionError:nil];
    
    // expect
    [[self.transportSession expect] enqueueSearchRequest:[OCMArg checkWithBlock:^BOOL(ZMTransportRequest *request) {
        [request completeWithResponse:response];
        return YES;
    }]];
    
    // when
    (void) [self.sut searchForSuggestedPeople];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [self.transportSession verify];
    XCTAssertEqual(self.searchResults.count, 1u);
    TokenAndSearchResult *result1 = self.searchResults.firstObject;
    XCTAssertNotNil(result1);
    XCTAssertEqual(result1.searchResult.usersInDirectory.count, 0u);
    XCTAssertEqualObjects(result1.searchResult.usersInDirectory, @[]);

}

- (void)testItDoesNotStartSearchIfRemoteIdentifiersAreNil
{
    // given
    XCTAssertNil(self.uiMOC.suggestedUsersForUser);
    [[self.transportSession stub] enqueueSearchRequest:OCMOCK_ANY];

    // when
    [self.sut searchForSuggestedPeople];
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:YES];
}


@end



@implementation ZMSearchDirectoryTests (SearchUserImages)

- (void)testThatWhenReceivingSearchUsersWeAddTheIDsToTheTable
{
    // given
    NSUUID *userID1 = [NSUUID createUUID];
    NSUUID *userID2 = [NSUUID createUUID];
    
    // expect
    __block ZMTransportRequest *request;
    [[self.transportSession expect] enqueueSearchRequest:ZM_ARG_SAVE(request)];
    
    
    NSArray *searchUsers = @[
                             [self userDataWithName:@"User one" id:userID1 connected:NO],
                             [self userDataWithName:@"User Two" id:userID2 connected:NO]
                             ];
    
    NSDictionary *responseData = [self responseDataForUsers:searchUsers];
    
    // when
    [self.sut searchForUsersAndConversationsMatchingQueryString:@"User"];
    
    XCTAssertNotNil(request);
    if (request) {
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:responseData HTTPstatus:200 transportSessionError:nil];
        [request completeWithResponse:response];
    }
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];
    
    //then
    ZMUserIDsForSearchDirectoryTable *table = [ZMSearchDirectory userIDsMissingProfileImage];
    NSSet *expectedIDs = [NSSet setWithObjects:userID1, userID2, nil];
    XCTAssertEqualObjects(table.allUserIDs, expectedIDs);
}

- (void)testThatWhenReceivingSearchUsersWeDoNotAddTheIDsToTheTableIfThereIsACorrespondingZMUser
{
    // given
    NSUUID *userID1 = [NSUUID createUUID];
    NSUUID *userID2 = [NSUUID createUUID];
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.remoteIdentifier = userID1;
    
    // expect
    __block ZMTransportRequest *request;
    [[self.transportSession expect] enqueueSearchRequest:ZM_ARG_SAVE(request)];
    
    
    NSArray *searchUsers = @[
                             [self userDataWithName:@"User one" id:userID1 connected:YES],
                             [self userDataWithName:@"User Two" id:userID2 connected:NO]
                             ];
    
    NSDictionary *responseData = [self responseDataForUsers:searchUsers];
    
    // when
    [self.sut searchForUsersAndConversationsMatchingQueryString:@"User"];
    
    XCTAssertNotNil(request);
    if (request) {
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:responseData HTTPstatus:200 transportSessionError:nil];
        [request completeWithResponse:response];
    }
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];
    
    //then
    ZMUserIDsForSearchDirectoryTable *table = [ZMSearchDirectory userIDsMissingProfileImage];
    NSSet *expectedIDs = [NSSet setWithObject: userID2];
    XCTAssertEqualObjects(table.allUserIDs, expectedIDs);
}

- (void)testThatItDoesNotAddIDsToTheTableIfTheCacheHasAnImageForThatUser;
{
    // given
    NSUUID *userID1 = [NSUUID createUUID];
    NSUUID *userID2 = [NSUUID createUUID];
    
    NSCache *imageDataCache = [ZMSearchUser searchUserToSmallProfileImageCache];
    [imageDataCache setObject:[NSData dataWithBytes:"ab" length:2] forKey:userID1];
    NSCache *mediumImageCache = [ZMSearchUser searchUserToMediumImageCache];
    [mediumImageCache setObject:[NSData dataWithBytes:"foo" length:2] forKey:userID1];
    
    // expect
    __block ZMTransportRequest *request;
    [[self.transportSession expect] enqueueSearchRequest:ZM_ARG_SAVE(request)];
    
    NSArray *searchUsers = @[[self userDataWithName:@"User one" id:userID1 connected:NO],
                             [self userDataWithName:@"User Two" id:userID2 connected:NO],];
    
    NSDictionary *responseData = [self responseDataForUsers:searchUsers];
    
    // when
    [self.sut searchForUsersAndConversationsMatchingQueryString:@"User"];
    
    XCTAssertNotNil(request);
    if (request) {
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:responseData HTTPstatus:200 transportSessionError:nil];
        [request completeWithResponse:response];
    }
    [self waitForSearchResultsWithFailureRecorder:NewFailureRecorder() shouldFail:NO];
    
    //then
    ZMUserIDsForSearchDirectoryTable *table = [ZMSearchDirectory userIDsMissingProfileImage];
    NSSet *expectedIDs = [NSSet setWithObject:userID2];
    XCTAssertEqualObjects(table.allUserIDs, expectedIDs);
}

- (void)testThatItEmptiesTheMediumImageCacheOnTeardown
{
    // given
    NSUUID *userID = [NSUUID createUUID];
    NSCache *imageDataCache = [ZMSearchUser searchUserToMediumImageCache];
    [imageDataCache setObject:[NSData dataWithBytes:"ab" length:2] forKey:userID];
    XCTAssertNotNil([imageDataCache objectForKey:userID]);

    // when
    [self.sut tearDown];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertNil([imageDataCache objectForKey:userID]);
}

- (void)testThatItRemovesItselfFromTheTableOnTearDown
{
    // expect
    id mockTable = [OCMockObject mockForClass:ZMUserIDsForSearchDirectoryTable.class];
    [[mockTable expect] removeSearchDirectory:self.sut];
    
    id mockSearch = [OCMockObject mockForClass:ZMSearchDirectory.class];
    [[[[mockSearch stub] classMethod] andReturn:mockTable] userIDsMissingProfileImage];
    
    // when
    [self.sut tearDown];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [mockTable verify];
    [mockSearch verify];
    [mockSearch stopMocking];
}

@end
