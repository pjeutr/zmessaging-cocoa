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

#import "ZMUserSession+Internal.h"
#import "ZMUserSession+Background+Testing.h"
#import "ZMOperationLoop+Background.h"
#import "ZMOperationLoop+Private.h"
#import "ZMLocalNotificationDispatcher.h"

#import "ZMLocalNotification.h"
#import "ZMConversation+Internal.h"
#import "ZMVoiceChannel.h"
#import <zmessaging/NSManagedObjectContext+zmessaging.h>
#import "ZMBackgroundFetchState.h"
#import <zmessaging/zmessaging-Swift.h>
#import "ZMUser+Internal.h"
#import "ZMConnection+Internal.h"
#import "ZMUserSession+UserNotificationCategories.h"
#import "ZMStoredLocalNotification.h"
#import "ZMApplicationLaunchStatus.h"
#import <zmessaging/zmessaging-Swift.h>

static const char *ZMLogTag = "Push";

@interface ZMUserSession (NotificationProcessing)

- (void)ignoreCallForNotification:(UILocalNotification *)notification withCompletionHandler:(void (^)())completionHandler;
- (void)replyToNotification:(UILocalNotification *)notification withReply:(NSString*)reply completionHandler:(void (^)())completionHandler;

@end




@implementation ZMUserSession (PushReceivers)

- (void)receivedPushNotificationWithPayload:(NSDictionary *)payload completionHandler:(ZMPushNotificationCompletionHandler)handler source:(ZMPushNotficationType)source
{
    if(self.authenticationStatus.currentPhase != ZMAuthenticationPhaseAuthenticated ||
       self.application.applicationState != UIApplicationStateBackground)
    {
        if (handler != nil) {
            ZMLogPushKit(@"Not displaying notification because app is not authenticated");
            handler(ZMPushPayloadResultSuccess);
        }
        return;
    }
    [self.operationLoop saveEventsAndSendNotificationForPayload:payload fetchCompletionHandler:handler source:source];
}

- (void)enablePushNotifications
{
    ZM_WEAK(self);
    void (^didReceivePayload)(NSDictionary *userInfo, ZMPushNotficationType source, void (^completionHandler)(ZMPushPayloadResult)) = ^(NSDictionary *userInfo, ZMPushNotficationType source, void (^result)(ZMPushPayloadResult))
    {
        ZM_STRONG(self);
        ZMLogDebug(@"push notification: %@, source %lu", userInfo, (unsigned long)source);
        [self.syncManagedObjectContext performGroupedBlock:^{
            return [self receivedPushNotificationWithPayload:userInfo completionHandler:result source:source];
        }];
    };
    
    [self enableAlertPushNotificationsWithDidReceivePayload:didReceivePayload];
    [self enableVoIPPushNotificationsWithDidReceivePayload:didReceivePayload];
}

- (void)enableAlertPushNotificationsWithDidReceivePayload:(void (^)(NSDictionary *, ZMPushNotficationType, void (^)(ZMPushPayloadResult)))didReceivePayload;
{
    ZM_WEAK(self);
    void (^didInvalidateToken)(void) = ^{
        ZM_STRONG(self);
        [self setPushToken:nil];
    };

    void (^updateCredentials)(NSData *) = ^(NSData *deviceToken){
        NOT_USED(deviceToken);
        ZM_STRONG(self);
         [self setPushToken:deviceToken];
    };
    self.applicationRemoteNotification = [[ZMApplicationRemoteNotification alloc] initWithDidUpdateCredentials:updateCredentials didReceivePayload:didReceivePayload didInvalidateToken:didInvalidateToken];
}


- (void)enableVoIPPushNotificationsWithDidReceivePayload:(void (^)(NSDictionary *, ZMPushNotficationType, void (^)(ZMPushPayloadResult)))didReceivePayload
{
    ZM_WEAK(self);
    void (^didInvalidateToken)(void) = ^{
        ZM_STRONG(self);
        [self.syncManagedObjectContext performGroupedBlock:^{
            [self deletePushKitToken];
        }];
    };

    void (^updatePushKitCredentials)(NSData *) = ^(NSData *deviceToken){
        ZM_STRONG(self);
        [self.syncManagedObjectContext performGroupedBlock:^{
            [self setPushKitToken:deviceToken];
        }];
    };
    self.pushRegistrant = [[ZMPushRegistrant alloc] initWithDidUpdateCredentials:updatePushKitCredentials didReceivePayload:didReceivePayload didInvalidateToken:didInvalidateToken];
}

@end




@implementation ZMUserSession (ZMBackground)

- (void)setupPushNotificationsForApplication:(UIApplication *)application
{
    [application registerForRemoteNotifications];
    NSSet *categories = [NSSet setWithArray:@[self.replyCategory, self.callCategory, self.connectCategory]];
    [application registerUserNotificationSettings:[UIUserNotificationSettings  settingsForTypes:(UIUserNotificationTypeSound |
                                                                                                 UIUserNotificationTypeAlert |
                                                                                                 UIUserNotificationTypeBadge)
                                                                                     categories:categories]];
}


- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken;
{
    [self.applicationRemoteNotification application:application didRegisterForRemoteNotificationsWithDeviceToken:deviceToken];
}

- (void)removeRemoteNotificationTokenIfNeeded;
{
    [self deletePushToken];
}

- (void)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions;
{
    UILocalNotification *notification = launchOptions[UIApplicationLaunchOptionsLocalNotificationKey];
    if (notification != nil) {
        [self application:application didReceiveLocalNotification:notification];
    }
    NSDictionary *payload = launchOptions[UIApplicationLaunchOptionsRemoteNotificationKey];
    if (payload != nil) {
        [self application:application didReceiveRemoteNotification:payload fetchCompletionHandler:^(UIBackgroundFetchResult result) {
            NOT_USED(result);
        }];
    }
    [self.applicationLaunchStatus application:application didFinishLaunchingWithOptions:launchOptions];
}


- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo fetchCompletionHandler:(void (^)(UIBackgroundFetchResult result))completionHandler;
{
    if (self.application.applicationState == UIApplicationStateInactive)
    {
        self.pendingLocalNotification = [[ZMStoredLocalNotification alloc] initWithPushPayload:userInfo
                                                                          managedObjectContext:self.managedObjectContext];
        if (completionHandler != nil) {
            completionHandler(UIBackgroundFetchResultNewData);
        }
    }
    else
    {
        [self.applicationRemoteNotification application:application
                           didReceiveRemoteNotification:userInfo
                                 fetchCompletionHandler:completionHandler];
    }
}


- (void)application:(UIApplication *)application didReceiveLocalNotification:(UILocalNotification *)notification;
{
    if (application.applicationState == UIApplicationStateInactive) {
        self.pendingLocalNotification = [[ZMStoredLocalNotification alloc] initWithNotification:notification
                                                                           managedObjectContext:self.managedObjectContext                                                                                actionIdentifier:nil
                                                                                      textInput:nil];
    }
}

- (void)application:(UIApplication *)application handleActionWithIdentifier:(NSString *)identifier forLocalNotification:(UILocalNotification *)notification responseInfo:(NSDictionary *)responseInfo completionHandler:(void(^)())completionHandler;
{
    if ([identifier isEqualToString:ZMCallIgnoreAction]){
        [self ignoreCallForNotification:notification withCompletionHandler:completionHandler];
    }
    
    NSString *textInput = [responseInfo optionalStringForKey:UIUserNotificationActionResponseTypedTextKey];
    if ([identifier isEqualToString:ZMConversationDirectReplyAction]) {
        [self replyToNotification:notification withReply:textInput completionHandler:completionHandler];

    }
    else {
        if (application.applicationState == UIApplicationStateInactive) {
            self.pendingLocalNotification = [[ZMStoredLocalNotification alloc] initWithNotification:notification
                                                                               managedObjectContext:self.managedObjectContext
                                                                                   actionIdentifier:identifier
                                                                                          textInput:[textInput copy]];
            if (self.didStartInitialSync && !self.isPerformingSync) {
                [self didEnterEventProcessingState:nil];
            }
        }
        if (completionHandler != nil) {
            completionHandler();
        }
    }
}

- (void)application:(UIApplication *)application performFetchWithCompletionHandler:(void (^)(UIBackgroundFetchResult result))completionHandler;
{
    NOT_USED(application);
    // The OS is telling us to fetch new data from the backend.
    // Wrap the handler:
    ZMBackgroundFetchHandler handler = ^(ZMBackgroundFetchResult const result){
        [self.applicationLaunchStatus finishedBackgroundFetch];
        
        dispatch_async(dispatch_get_main_queue(), ^{

            switch (result) {
                case ZMBackgroundFetchResultNewData:
                    completionHandler(UIBackgroundFetchResultNewData);
                    break;
                case ZMBackgroundFetchResultNoData:
                    completionHandler(UIBackgroundFetchResultNoData);
                    break;
                case ZMBackgroundFetchResultFailed:
                    completionHandler(UIBackgroundFetchResultFailed);
                    break;
            }
        });
    };
    
    // Transition into the ZMBackgroundFetchState which will do the fetching:
    [self.applicationLaunchStatus startedBackgroundFetch];
    [self.operationLoop startBackgroundFetchWithCompletionHandler:handler];
}

- (void)application:(UIApplication *)application handleEventsForBackgroundURLSession:(NSString *)identifier completionHandler:(void (^)())completionHandler;
{
    NOT_USED(application);
    NOT_USED(identifier);
    completionHandler(UIBackgroundFetchResultFailed);
}


- (void)applicationDidEnterBackground:(NSNotification *)note;
{
    NOT_USED(note);
    [self notifyThirdPartyServices];
}

- (void)applicationWillEnterForeground:(NSNotification *)note;
{
    NOT_USED(note);
    self.didNotifyThirdPartyServices = NO;
    [self.applicationLaunchStatus appWillEnterForeground];
}

@end






@implementation ZMUserSession (NotificationProcessing)

- (void)didEnterEventProcessingState:(NSNotification *)notification
{
    NOT_USED(notification);
    
    if (self.pendingLocalNotification == nil) {
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        ZMStoredLocalNotification *note = self.pendingLocalNotification;
        
        if ([note.category isEqualToString:ZMConnectCategory]) {
            [self handleConnectionRequestCategoryNotification:note];
        }
        else if ([note.category isEqualToString:ZMCallCategory]){
            [self handleCallCategoryNotification:note];
        }
        else {
            [self openConversation:note.conversation atMessage:note.message];
        }
        self.pendingLocalNotification = nil;
    });
    
}

// Foreground Actions

- (void)handleConnectionRequestCategoryNotification:(ZMStoredLocalNotification *)note
{
    ZMConversation *conversation = note.conversation;
    
    ZMUser *sender = [ZMUser fetchObjectWithRemoteIdentifier:note.senderUUID inManagedObjectContext:self.managedObjectContext];
    if (sender != nil) {
        conversation = sender.connection.conversation;
        if ([note.actionIdentifier isEqualToString:ZMConnectAcceptAction]) {
            [sender accept];
            [self.managedObjectContext saveOrRollback];
        }
    }
    
    [self openConversation:conversation atMessage:nil];
}

- (void)handleCallCategoryNotification:(ZMStoredLocalNotification *)note
{
    if (note.actionIdentifier == nil || [note.actionIdentifier isEqualToString:ZMCallAcceptAction]) {
        if ([note.conversation firstOtherConversationWithActiveCall] == nil && note.conversation.callParticipants.count > 0) {
            [note.conversation.voiceChannel join];
            [note.conversation.managedObjectContext saveOrRollback];
        }
    }
    
    [self openConversation:note.conversation atMessage:nil];
}

- (void)openConversation:(ZMConversation *)conversation atMessage:(ZMMessage *)message
{
    id<ZMRequestsToOpenViewsDelegate> strongDelegate = self.requestToOpenViewDelegate;
    if (conversation == nil) {
        [strongDelegate showConversationList];
    }
    else if (message == nil) {
        [strongDelegate showConversation:conversation];
    }
    else {
        [strongDelegate showMessage:message inConversation:conversation];
    }
    
}

// Background Actions

- (void)ignoreCallForNotification:(UILocalNotification *)notification withCompletionHandler:(void (^)())completionHandler;
{
    ZMBackgroundActivity *activity = [ZMBackgroundActivity beginBackgroundActivityWithName:@"IgnoreCall Action Handler"];
    ZMConversation *conversation = [ZMLocalNotification conversationForLocalNotification:notification inManagedObjectContext:self.managedObjectContext];
    [self.managedObjectContext performBlock:^{
        conversation.isIgnoringCall = YES;
        [self.managedObjectContext saveOrRollback];
        
    }];
    [activity endActivity];
    if (completionHandler != nil) {
        completionHandler();
    }
}


- (void)replyToNotification:(UILocalNotification *)notification withReply:(NSString*)reply completionHandler:(void (^)())completionHandler;
{
    if (reply.length == 0) {
        if (completionHandler != nil) {
            completionHandler();
        }
        return;
    }
    ZMBackgroundActivity *activity = [ZMBackgroundActivity beginBackgroundActivityWithName:@"DirectReply Action Handler"];
    ZMConversation *conversation = [ZMLocalNotification conversationForLocalNotification:notification inManagedObjectContext:self.managedObjectContext];
    if (conversation != nil) {
        ZM_WEAK(self);
        [self.operationLoop startBackgroundTaskWithCompletionHandler:^(ZMBackgroundTaskResult result) {
            ZM_STRONG(self);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (result == ZMBackgroundTaskResultFailed) {
                    [self.localNotificationDispatcher didFailToSendMessageInConversation:conversation];
                }
                [activity endActivity];
                if (completionHandler != nil) {
                    completionHandler();
                }
            });
        }];
        [self.managedObjectContext performGroupedBlock:^{
            [conversation appendMessagesWithText:reply];
            [self.managedObjectContext saveOrRollback];
        }];
    }
    else {
        [activity endActivity];
        if (completionHandler != nil) {
            completionHandler();
        }
    }
}


@end





@implementation ZMUserSession (ZMBackgroundFetch)

- (void)enableBackgroundFetch;
{
    // We enable background fetch by setting the minimum interval to something different from UIApplicationBackgroundFetchIntervalNever
    UIApplication *application = self.application;
    Require(application != nil);
    [application setMinimumBackgroundFetchInterval:10. * 60. + arc4random_uniform(5 * 60)];
}

@end



