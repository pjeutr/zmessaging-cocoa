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


#import <zmessaging/ZMManagedObject.h>
#import <zmessaging/ZMUserURLForInvitationToConnect.h>
#import <zmessaging/ZMBareUser.h>

@class ZMUserSession;
@class ZMConversation;
@class UserClient;
@class ZMAddressBookContact;


@interface ZMUser : ZMManagedObject <ZMBareUser>

@property (nonatomic, readonly) NSString *emailAddress;
@property (nonatomic, readonly) NSString *phoneNumber;
@property (nonatomic, readonly) ZMConversation *oneToOneConversation;

///
@property (nonatomic, readonly) NSSet<UserClient *> *clients;

/// New self clients which the self user hasn't been informed about (only valid for the self user)
@property (nonatomic, readonly) NSSet<UserClient *> *clientsRequiringUserAttention;

/// Returns the corresponding address book contact if it exists otherwise nil.
- (ZMAddressBookContact *)contactInUserSession:(ZMUserSession *)userSession;

@end


@protocol ZMEditableUser;

@interface ZMUser (Utilities)

+ (ZMUser<ZMEditableUser, ZMUserURLForInvitationToConnect> *)selfUserInUserSession:(ZMUserSession *)session;

@end



@interface ZMUser (Connections) <ZMBareUserConnection>

@property (nonatomic, readonly) BOOL isBlocked;
@property (nonatomic, readonly) BOOL isIgnored;
@property (nonatomic, readonly) BOOL isPendingApprovalBySelfUser;
//@property (nonatomic, readonly) BOOL isPendingApprovalByOtherUser; // Now part of ZMBareUserConnection

- (void)accept;
- (void)block;
- (void)ignore;
- (void)cancelConnectionRequest;

- (BOOL)trusted;
- (BOOL)untrusted;

@end



@interface ZMUser (KeyValueValidation)

+ (BOOL)validateName:(NSString **)ioName error:(NSError **)outError;
+ (BOOL)validateAccentColorValue:(NSNumber **)ioAccent error:(NSError **)outError;
+ (BOOL)validateEmailAddress:(NSString **)ioEmailAddress error:(NSError **)outError;
+ (BOOL)validatePhoneNumber:(NSString **)ioPhoneNumber error:(NSError **)outError;
+ (BOOL)validatePassword:(NSString **)ioPassword error:(NSError **)outError;
+ (BOOL)validatePhoneVerificationCode:(NSString **)ioVerificationCode error:(NSError **)outError;

@end