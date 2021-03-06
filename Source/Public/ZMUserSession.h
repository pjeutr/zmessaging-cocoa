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
@import ZMCSystem;

#import <ZMCDataModel/ZMManagedObjectContextProvider.h>
#import <zmessaging/ZMNetworkState.h>

@class ZMTransportSession;
@class ZMSearchDirectory;
@class ZMMessage;
@class ZMConversation;
@class UserClient;

@protocol AVSMediaManager;
@protocol AddressBookUploadObserver;
@protocol ZMNetworkAvailabilityObserver;
@protocol ZMRequestsToOpenViewsDelegate;
@protocol ZMThirdPartyServicesDelegate;

@protocol ZMAVSLogObserver <NSObject>
@required
- (void)logMessage:(NSString *)msg;
@end

@protocol ZMAVSLogObserverToken <NSObject>
@end


/// C.f. -[ZMUserSession trackingIdentifier]
extern NSString * const ZMUserSessionTrackingIdentifierDidChangeNotification;
extern NSString * const ZMLaunchedWithPhoneVerificationCodeNotificationName;
extern NSString * const ZMPhoneVerificationCodeKey;
extern NSString * const ZMUserSessionResetPushTokensNotificationName;

/// The main entry point for the zmessaging API.
///
/// The client app should create this object upon launch and keep a reference to it
@interface ZMUserSession : NSObject <ZMManagedObjectContextProvider>

/**
 Returns YES if data store needs to be migrated.
 */
+ (BOOL)needsToPrepareLocalStore;

/**
 Should be called <b>before</b> using ZMUserSession when applications is started if +needsToPrepareLocalStore returns YES. It will intialize persistent store and perform migration (if needed) on background thread.
 When it's done it will call completionHandler block on main thread. UI is supposed to present some kind of spinner until block is invoked.
 */
+ (void)prepareLocalStore:(void (^)())completionHandler;

/// Whether the local store is ready to be opened. If it returns false, the user session can't be started yet
+ (BOOL)storeIsReady;

/**
 Intended initializer to be used by the UI
 @param mediaManager: the media manager delegate
 @param appVersion: the application version (build number)
*/
- (instancetype)initWithMediaManager:(id<AVSMediaManager>)mediaManager appVersion:(NSString *)appVersion;

@property (nonatomic, weak) id<ZMRequestsToOpenViewsDelegate> requestToOpenViewDelegate;
@property (nonatomic, weak) id<ZMThirdPartyServicesDelegate> thirdPartyServicesDelegate;
@property (atomic, readonly) ZMNetworkState networkState;

/**
 Starts session and checks if client version is not in black list.
 Version should be a build number. blackListedBlock is retained and called only if passed version is black listed. The block is 
 called only once, even if the file is downloaded multiple times.
 */
- (void)startAndCheckClientVersionWithCheckInterval:(NSTimeInterval)interval blackListedBlock:(void (^)())blackListed;

- (void)start;

/// Performs a save in the context
- (void)saveOrRollbackChanges;

/// Performs some changes on the managed object context (in the block) before saving
- (void)performChanges:(dispatch_block_t)block ZM_NON_NULL(1);

/// Enqueue some changes on the managed object context (in the block) before saving
- (void)enqueueChanges:(dispatch_block_t)block ZM_NON_NULL(1);

/// Enqueue some changes on the managed object context (in the block) before saving, then invokes the completion handler
- (void)enqueueChanges:(dispatch_block_t)block completionHandler:(dispatch_block_t)completionHandler ZM_NON_NULL(1);

/// This identifier uniquely identifies the logged in user with 3rd party services such as Localytics.
/// A @c ZMUserSessionTrackingIdentifierDidChangeNotification notification will be sent out when this is updated.
@property (nonatomic, readonly) NSString *trackingIdentifier;


/// Creates new signaling keys  and reregisters the keys and the push tokens with the backend
- (void)resetPushTokens;

/// Initiates the deletion process for the current signed in user
- (void)initiateUserDeletion;

@end



@interface ZMUserSession (Transport)

/// This method should be called from inside @c application(application:handleEventsForBackgroundURLSession identifier:completionHandler:)
/// and passed the NSURLSession and completionHandler to store after recreating the background session with the given identifier.
/// @param identifier The identifier that should be used to recreate the background @c NSURLSession
/// @param handler The completion block from the OS that should be stored
- (void)addCompletionHandlerForBackgroundURLSessionWithIdentifier:(NSString *)identifier handler:(dispatch_block_t)handler;

@end



@interface ZMUserSession (AddressBookUpload)

+ (void)addAddressBookUploadObserver:(id<AddressBookUploadObserver>)observer;
+ (void)removeAddressBookUploadObserver:(id<AddressBookUploadObserver>)observer;

/// Asynchronously uploads the address book.
/// Once the address book has been uploaded, subsequent calls will only cause a re-upload if there are local changes to the address book.
- (void)uploadAddressBook;

@end



@interface ZMUserSession (LaunchOptions)

- (void)didLaunchWithURL:(NSURL *)URL;

@end



@interface ZMUserSession (AVSLogging)

/// Add observer for AVS logging
+ (id<ZMAVSLogObserverToken>)addAVSLogObserver:(id<ZMAVSLogObserver>)observer;
/// Remove observer for AVS logging
+ (void)removeAVSLogObserver:(id<ZMAVSLogObserverToken>)token;

+ (void)appendAVSLogMessageForConversation:(ZMConversation *)conversation withMessage:(NSString *)message;

@end



@protocol AddressBookUploadObserver <NSObject>

/// This method will get called when the app tries to upload the address book, but does not have access to it.
- (void)failedToAccessAddressBook:(NSNotification *)note;

@end



@protocol ZMRequestsToOpenViewsDelegate <NSObject>

/// This will be called when the UI should display a conversation, message or the conversation list.
- (void)showMessage:(ZMMessage *)message inConversation:(ZMConversation *)conversation;
- (void)showConversation:(ZMConversation *)conversation;
- (void)showConversationList;

@end



@protocol ZMThirdPartyServicesDelegate <NSObject>

/// This will get called at a convenient point in time when Hockey and Localytics should upload their data.
/// We try not to have Hockey and Localytics use the network while we're sync'ing.
- (void)userSessionIsReadyToUploadServicesData:(ZMUserSession *)userSession;

@end


@interface ZMUserSession (Giphy)

- (void)giphyRequestWithURL:(NSURL *)url callback:(void (^)(NSData *, NSHTTPURLResponse *, NSError *))callback;

@end


@interface ZMUserSession (SelfUserClient)

- (UserClient *)selfUserClient;
@end
