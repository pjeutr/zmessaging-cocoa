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


@import ZMCSystem;
@import ZMTransport;
@import ZMCDataModel;

#import "ZMSearchRequestCodec.h"
#import "ZMSuggestionResult.h"
#import "ZMSearchResult+Internal.h"
#import "ZMUserSession+Internal.h"

static NSString * const ZMSearchEndPoint = @"/search/contacts";
static NSString * const ZMTopSearchEndPoint = @"/search/top";
static NSString * const ZMSuggestedSearchEndPoint = @"/search/suggestions";



@implementation ZMSearchRequestCodec

+ (ZMTransportRequest *)searchRequestForQueryString:(NSString *)queryString levels:(int)levels fetchLimit:(int)fetchLimit;
{
    VerifyAction(queryString != nil, queryString = @"");

    NSMutableCharacterSet *set = [[NSCharacterSet URLQueryAllowedCharacterSet] mutableCopy];
    [set removeCharactersInString:@"=&+"];
    NSString *urlEncodedQuery = [queryString stringByAddingPercentEncodingWithAllowedCharacters:set];
    
    NSString *path = [NSString stringWithFormat:@"%@?q=%@&l=%d&size=%d", ZMSearchEndPoint, urlEncodedQuery, levels, fetchLimit];
    return [ZMTransportRequest requestGetFromPath:path];
    
}

+ (ZMTransportRequest *)searchRequestForTopConversationsWithFetchLimit:(int)fetchLimit;
{
    NSString *path = [NSString stringWithFormat:@"%@?size=%d", ZMTopSearchEndPoint, fetchLimit];
    return [ZMTransportRequest requestGetFromPath:path];
}

+ (ZMTransportRequest *)searchRequestForSuggestedPeopleWithFetchLimit:(int)fetchLimit;
{
    NSString *path = [NSString stringWithFormat:@"%@?size=%d", ZMSuggestedSearchEndPoint, fetchLimit];
    return [ZMTransportRequest requestGetFromPath:path];
}

+ (ZMSearchResult *)searchResultFromTransportResponse:(ZMTransportResponse *)response ignoredIDs:(NSArray *)ignoredIDs userSession:(ZMUserSession *)userSession
{
    NSDictionary *payload = [response.payload asDictionary];
    NSArray *users = [payload optionalArrayForKey:@"documents"];
    if (users == nil) {
        return nil;
    }
    
    ZMUser *selfUser = [ZMUser selfUserInUserSession:userSession];
    
    NSMutableArray *directoryUsers = [NSMutableArray array];
    NSMutableArray *connectedUsers = [NSMutableArray array];
    
    NSMutableArray *payloadArray = [NSMutableArray array];
    
    for (NSDictionary *user in users) {
        NSUUID *identifier = [user optionalUuidForKey:@"id"];
        if (identifier == nil || [ignoredIDs containsObject:identifier] || [selfUser.remoteIdentifier isEqual:identifier]) {
            continue;
        }

        [payloadArray addObject:user];
    }
    
    NSArray <ZMSearchUser *> *searchUsers = [ZMSearchUser usersWithPayloadArray:payloadArray userSession:userSession];
    
    for (ZMSearchUser *searchUser in searchUsers) {
        if ([self canonicalIsUserConnected:searchUser]) {
            [connectedUsers addObject:searchUser];
        }
        else {
            [directoryUsers addObject:searchUser];
        }
    }
    
    ZMSearchResult *searchResult = [[ZMSearchResult alloc] init];
    [searchResult addUsersInDirectory:directoryUsers];
    [searchResult addUsersInContacts:connectedUsers];
    return searchResult;
}

+ (NSOrderedSet *)remoteIdentifiersForSuggestedPeopleSearchResponse:(ZMTransportResponse *)response
{
    if (response.result != ZMTransportResponseStatusSuccess ||
        response.transportSessionError != nil )
    {
        return nil;
    }
    
    NSDictionary *payload = [response.payload asDictionary];
    NSArray *users = [payload optionalArrayForKey:@"documents"];
    if (users == nil) {
        return nil;
    }
    
    NSMutableOrderedSet *suggestedUsers = [NSMutableOrderedSet orderedSetWithCapacity:users.count];
    for (NSDictionary *user in users) {
        ZMSuggestedUserCommonConnections *commonConnections = [[ZMSuggestedUserCommonConnections alloc] initWithPayload:user];
        NSUUID *identifier = [user optionalUuidForKey:@"id"];
        if (identifier != nil && commonConnections != nil) {
            [suggestedUsers addObject:[[ZMSuggestionResult alloc] initWithUserIdentifier:identifier commonConnections:commonConnections]];
        }
    }
    return suggestedUsers;
}


// There is a delay in the search, right after connecting to someone the backend will still say they are unconnected. But this method knows the truth.
+ (BOOL)canonicalIsUserConnected:(ZMSearchUser *)user {
    return user.isConnected;
}

@end
