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


#import "ZMBareUser+UserSession.h"
#import "ZMUserImageTranscoder.h"
#import "ZMOperationLoop.h"
#import "ZMUserSession+Internal.h"
#import "ZMAddressBookMatcher.h"

@implementation ZMUser (UserSession)

- (void)requestMediumProfileImageInUserSession:(ZMUserSession *)userSession;
{
    NOT_USED(userSession);
    
    if (self.imageMediumData != nil) {
        return;
    }
    
    if (self.localMediumRemoteIdentifier != nil) {
        self.localMediumRemoteIdentifier = nil;
        [self.managedObjectContext saveOrRollback];
    }
    
    [ZMUserImageTranscoder requestAssetForUserWithObjectID:self.objectID];
    [ZMOperationLoop notifyNewRequestsAvailable:self];
}

- (void)requestSmallProfileImageInUserSession:(ZMUserSession *)userSession;
{
    NOT_USED(userSession);
    
    if (self.imageSmallProfileData != nil) {
        return;
    }
    
    if (self.localSmallProfileRemoteIdentifier != nil) {
        self.localSmallProfileRemoteIdentifier = nil;
        [self.managedObjectContext saveOrRollback];
    }
    
    [ZMUserImageTranscoder requestSmallAssetForUserWithObjectID:self.objectID];
    [ZMOperationLoop notifyNewRequestsAvailable:self];
}

- (id<ZMCommonContactsSearchToken>)searchCommonContactsInUserSession:(ZMUserSession *)session withDelegate:(id<ZMCommonContactsSearchDelegate>)delegate
{
    return [session searchCommonContactsWithUserID:self.remoteIdentifier searchDelegate:delegate];
}

- (ZMAddressBookContact *)contactInUserSession:(ZMUserSession *)userSession
{
    ZMAddressBookMatcher *matcher = [[ZMAddressBookMatcher alloc] initWithUserSession:userSession];
    return [matcher contactForUser:self];
}

@end